# Compare apostrophe strategies across 500 sentences
$baseDir = "C:\temp\sma-english-projection"
$trainPath = [System.IO.Path]::Combine($baseDir, "inputs", "train_500.tsv")
$trainLines = [System.IO.File]::ReadAllLines($trainPath)

function TestStrategy([string]$name, [scriptblock]$mutFn) {
    $failing = 0
    $totalErr = 0
    for ($i = 1; $i -lt $trainLines.Length; $i++) {
        $line = $trainLines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $sent = $line.Split([char]9)[5]
        $mut = & $mutFn $sent
        $errs = [System.Management.Automation.Language.ParseError[]]@()
        $toks = [System.Management.Automation.Language.Token[]]@()
        $null = [System.Management.Automation.Language.Parser]::ParseInput($mut, [ref]$toks, [ref]$errs)
        if ($errs.Length -gt 0) {
            $failing++
            $totalErr += $errs.Length
        }
    }
    Write-Output "Strategy: ${name} -> Failing: ${failing}/500, Errors: ${totalErr}"
}

# 1. ¿ prefix + U+02BC
TestStrategy "Prefix ¿ + U+02BC" {
    param($s)
    [char]0x00BF + " " + $s.Replace([char]0x0027, [char]0x02BC).Replace([char]0x0023, [char]0xFF03)
}

# 2. ¿ prefix + Backtick substitution
TestStrategy "Prefix ¿ + Backtick substitution" {
    param($s)
    [char]0x00BF + " " + $s.Replace([char]0x0027, [char]0x0060).Replace([char]0x0023, [char]0xFF03)
}

# 3. ¿ prefix + Escaped apostrophe
TestStrategy "Prefix ¿ + Escaped apostrophe" {
    param($s)
    $escaped = [string][char]0x0060 + [string][char]0x0027
    [char]0x00BF + " " + $s.Replace([string][char]0x0027, $escaped).Replace([char]0x0023, [char]0xFF03)
}
