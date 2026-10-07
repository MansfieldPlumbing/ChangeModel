# Dedicated Numeric Morphology Probe for SMA
# Probes ~100 numeric forms across bare and command-argument contexts.
# Records token kinds, AST topology, and emergent categories.
# Governed by NIST SP 800-218 and prompt specifications (no regex, no JSON).

$baseDir = "C:\temp\sma-english-projection"
$outTsv = "$baseDir\results\inventory_numeric_morphology.tsv"
$outReport = "$baseDir\results\numeric_morphology_report.md"

$testForms = @(
    # Cardinal integers
    "0", "1", "7", "42", "01", "007", "100", "911", "747", "1000", "2026", "1000000",
    # Grouped digits
    "1,000", "1,234", "10,000", "100,000", "1,000,000", "1,234,567",
    # Decimals and reals
    "1.0", "1.00", "0.5", ".5", "3.14", "3.14159", "0.001", "99.99",
    # Grouped decimals
    "1,234.56", "10,000.00", "1,000,000.50",
    # Signed values
    "-5", "+5", "-12", "+100", "-0.5", "-1.23", "-1,000",
    # Scientific / exponent notation
    "1e3", "1e6", "1.5e3", "2.4E4", "1e-3", "2.5e-5", "1.0e+6",
    # Hex and binary
    "0xFF", "0x10", "0xABCD", "0b1010", "0b11110000",
    # Range expressions
    "1..5", "1..10", "3..5", "10..20", "3-5", "10-20", "1990-2000", "1990-95",
    # Ratios and fractions
    "1/2", "3/4", "5/8", "1:1", "1:2", "16:9", "4:3",
    # Time forms
    "10:30", "12:00", "08:15", "12:00:00", "10:30am", "5:00pm", "10:30AM",
    # Date forms
    "2026-10-07", "10-07-2026", "2026/10/07", "10/07/2026", "1999-12-31",
    # Currency forms
    "`$5", "`$12", "`$12.50", "`$100", "`$1,000", "`$1,234.56", "`$100M", "`$50k",
    [char]0x00A3 + "50",   # £50
    [char]0x20AC + "100",  # €100
    [char]0x00A5 + "1000", # ¥1000
    # Percentages
    "12%", "50%", "100%", "0.5%", "99.9%", "3.5%",
    # Ordinals
    "1st", "2nd", "3rd", "4th", "5th", "21st", "22nd", "23rd", "31st", "100th", "21ST",
    # Multipliers and units
    "10kb", "10mb", "1gb", "10TB", "12kg", "50g", "100m", "5km", "50mph", "100km/h",
    "35mm", "60s", "120min", "24h", "200hp", "5V", "12V", "220V", "50Hz", "60Hz"
)

$tsvRows = [System.Collections.Generic.List[string]]::new()
$tsvRows.Add("form`tcontext`terrors`terror_ids`ttoken_kinds`ttoken_texts`tast_root_type`tnode_types`temergent_category")

foreach ($rawForm in $testForms) {
    # Test in two contexts: bare and command argument
    $contexts = @("bare", "cmd_arg")
    foreach ($ctx in $contexts) {
        $inputText = if ($ctx -eq "cmd_arg") { "// " + $rawForm } else { $rawForm }
        
        $errors = [System.Management.Automation.Language.ParseError[]]@()
        $tokens = [System.Management.Automation.Language.Token[]]@()
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($inputText, [ref]$tokens, [ref]$errors)

        $errCount = $errors.Length
        $errIds = ($errors | ForEach-Object { $_.ErrorId }) -join ","
        if ([string]::IsNullOrEmpty($errIds)) { $errIds = "NONE" }

        # Filter out EndOfInput and leading //
        $filteredTokens = [System.Collections.Generic.List[object]]::new()
        foreach ($t in $tokens) {
            if ($t.Kind -eq "EndOfInput") { continue }
            if ($ctx -eq "cmd_arg" -and $t.Extent.StartOffset -eq 0 -and $t.Text -eq "//") { continue }
            $filteredTokens.Add($t)
        }

        $tokenKinds = ($filteredTokens | ForEach-Object { $_.Kind.ToString() }) -join "|"
        $tokenTexts = ($filteredTokens | ForEach-Object { $_.Text }) -join "|"

        # Collect distinct AST node types
        $nodeTypes = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($node in $ast.FindAll({ $true }, $true)) {
            $nName = $node.GetType().Name
            if ($nName -ne "ScriptBlockAst" -and $nName -ne "NamedBlockAst" -and $nName -ne "PipelineAst") {
                [void]$nodeTypes.Add($nName)
            }
        }
        $nodeTypesStr = ($nodeTypes) -join "|"

        # Determine emergent category
        $cat = "Unknown"
        if ($errCount -gt 0) {
            $cat = "SyntaxError"
        } elseif ($tokenKinds -eq "Number") {
            $cat = "PureNumericLiteral"
        } elseif ($tokenKinds.Contains("Variable")) {
            $cat = "VariableSyntax"
        } elseif ($tokenKinds.Contains("Comma") -or $nodeTypesStr.Contains("ArrayLiteralAst")) {
            $cat = "CommaSeparatedCompound"
        } elseif ($nodeTypesStr.Contains("BinaryExpressionAst") -or $tokenKinds.Contains("DotDot")) {
            $cat = "RangeOrBinaryExpression"
        } elseif ($tokenKinds -eq "Generic") {
            $cat = "GenericWordToken"
        } elseif ($tokenKinds -eq "Identifier") {
            $cat = "IdentifierToken"
        } elseif ($tokenKinds.Contains("Parameter") -or $nodeTypesStr.Contains("CommandParameterAst")) {
            $cat = "ParameterSwitch"
        } elseif ($filteredTokens.Count -gt 1) {
            $cat = "MultiTokenCompound"
        }

        $tsvRows.Add("${rawForm}`t${ctx}`t${errCount}`t${errIds}`t${tokenKinds}`t${tokenTexts}`t$($ast.GetType().Name)`t${nodeTypesStr}`t${cat}")
    }
}

[System.IO.File]::WriteAllLines($outTsv, $tsvRows)
Write-Output "Probe completed: tested $($testForms.Length) forms across 2 contexts (total $( $testForms.Length * 2 ) parses)."
Write-Output "Results saved to $outTsv"
