# Evaluation Engine for SMA-English Projection
# Self-contained, deterministic, no regex, no JSON.

class ProjectionConfig {
    [string]$Prefix = "none"         # none, qmark (¿ ), slash (// ), spade (♠ )
    [string]$Apostrophe = "none"     # none, backtick (`), modifier (ʼ), escaped (`')
    [string]$Hash = "none"           # none, fullwidth (＃)
    [string]$Semicolon = "none"      # none, fullwidth (；)
    [string]$TermPunct = "none"      # none, space ( .), nbsp (\u00A0.)
    [string]$Hyphen = "none"         # none, unicode (‐)
    [string]$Quote = "none"          # none, guillemets (« »)

    [int] GetMutationCount() {
        $c = 0
        if ($this.Prefix -ne "none") { $c++ }
        if ($this.Apostrophe -ne "none") { $c++ }
        if ($this.Hash -ne "none") { $c++ }
        if ($this.Semicolon -ne "none") { $c++ }
        if ($this.TermPunct -ne "none") { $c++ }
        if ($this.Hyphen -ne "none") { $c++ }
        if ($this.Quote -ne "none") { $c++ }
        return $c
    }

    [string] GetKey() {
        return "pre=$($this.Prefix)|apos=$($this.Apostrophe)|hash=$($this.Hash)|semi=$($this.Semicolon)|term=$($this.TermPunct)|hyph=$($this.Hyphen)|quot=$($this.Quote)"
    }
}

class EvalResult {
    [int]$SentenceCount = 0
    [int]$TotalErrors = 0
    [int]$FailingSentences = 0
    [int]$UsefulAstScore = 0
    [int]$BoundaryDisagreements = 0
    [int]$MutationCount = 0
    [bool]$FidelityPassed = $true
    [string]$ConfigKey = ""

    [string] FormatScore() {
        return "Errors=$($this.TotalErrors) FailSent=$($this.FailingSentences) UsefulAST=$($this.UsefulAstScore) BoundDiff=$($this.BoundaryDisagreements) Muts=$($this.MutationCount)"
    }
}

function ProjectSentence([string]$sent, [ProjectionConfig]$config) {
    $s = $sent

    # Double quote
    if ($config.Quote -eq "guillemets") {
        $inQuote = $false
        $chars = $s.ToCharArray()
        for ($i = 0; $i -lt $chars.Length; $i++) {
            if ($chars[$i] -eq [char]34) {
                if (-not $inQuote) {
                    $chars[$i] = [char]0x00AB # «
                    $inQuote = $true
                } else {
                    $chars[$i] = [char]0x00BB # »
                    $inQuote = $false
                }
            }
        }
        $s = [string]::new($chars)
    }

    # Hyphen
    if ($config.Hyphen -eq "unicode") {
        $s = $s.Replace([char]0x002D, [char]0x2010)
    }

    # Semicolon
    if ($config.Semicolon -eq "fullwidth") {
        $s = $s.Replace([char]0x003B, [char]0xFF1B)
    }

    # Hash
    if ($config.Hash -eq "fullwidth") {
        $s = $s.Replace([char]0x0023, [char]0xFF03)
    }

    # Apostrophe
    if ($config.Apostrophe -eq "backtick") {
        $s = $s.Replace([char]0x0027, [char]0x0060)
    } elseif ($config.Apostrophe -eq "modifier") {
        $s = $s.Replace([char]0x0027, [char]0x02BC)
    } elseif ($config.Apostrophe -eq "escaped") {
        $escaped = [string][char]0x0060 + [string][char]0x0027
        $s = $s.Replace([string][char]0x0027, $escaped)
    }

    # Terminal punctuation spacing
    if ($config.TermPunct -eq "space") {
        if ($s.EndsWith(".") -or $s.EndsWith("?") -or $s.EndsWith("!")) {
            $last = $s.Substring($s.Length - 1)
            $s = $s.Substring(0, $s.Length - 1) + " " + $last
        }
    } elseif ($config.TermPunct -eq "nbsp") {
        if ($s.EndsWith(".") -or $s.EndsWith("?") -or $s.EndsWith("!")) {
            $last = $s.Substring($s.Length - 1)
            $s = $s.Substring(0, $s.Length - 1) + [char]0x00A0 + $last
        }
    }

    # Prefix sentinel
    if ($config.Prefix -eq "qmark") {
        $s = [char]0x00BF + " " + $s
    } elseif ($config.Prefix -eq "slash") {
        $s = "// " + $s
    } elseif ($config.Prefix -eq "spade") {
        $s = [char]0x2660 + " " + $s
    }

    return $s
}

function ReverseProjectSentence([string]$projected, [ProjectionConfig]$config) {
    $s = $projected

    if ($config.Prefix -eq "qmark") {
        if ($s.StartsWith([char]0x00BF + " ")) { $s = $s.Substring(2) }
    } elseif ($config.Prefix -eq "slash") {
        if ($s.StartsWith("// ")) { $s = $s.Substring(3) }
    } elseif ($config.Prefix -eq "spade") {
        if ($s.StartsWith([char]0x2660 + " ")) { $s = $s.Substring(2) }
    }

    if ($config.TermPunct -eq "space") {
        if ($s.EndsWith(" .") -or $s.EndsWith(" ?") -or $s.EndsWith(" !")) {
            $last = $s.Substring($s.Length - 1)
            $s = $s.Substring(0, $s.Length - 2) + $last
        }
    } elseif ($config.TermPunct -eq "nbsp") {
        $nbspStr = [string][char]0x00A0
        if ($s.EndsWith($nbspStr + ".") -or $s.EndsWith($nbspStr + "?") -or $s.EndsWith($nbspStr + "!")) {
            $last = $s.Substring($s.Length - 1)
            $s = $s.Substring(0, $s.Length - 2) + $last
        }
    }

    if ($config.Apostrophe -eq "backtick") {
        $s = $s.Replace([char]0x0060, [char]0x0027)
    } elseif ($config.Apostrophe -eq "modifier") {
        $s = $s.Replace([char]0x02BC, [char]0x0027)
    } elseif ($config.Apostrophe -eq "escaped") {
        $escaped = [string][char]0x0060 + [string][char]0x0027
        $s = $s.Replace($escaped, [string][char]0x0027)
    }

    if ($config.Hash -eq "fullwidth") {
        $s = $s.Replace([char]0xFF03, [char]0x0023)
    }

    if ($config.Semicolon -eq "fullwidth") {
        $s = $s.Replace([char]0xFF1B, [char]0x003B)
    }

    if ($config.Hyphen -eq "unicode") {
        $s = $s.Replace([char]0x2010, [char]0x002D)
    }

    if ($config.Quote -eq "guillemets") {
        $s = $s.Replace([char]0x00AB, [char]0x0022).Replace([char]0x00BB, [char]0x0022)
    }

    return $s
}

function EvaluateDataset([string[]]$sentences, [System.Collections.Generic.Dictionary[int, object]]$spacyMap, [ProjectionConfig]$config) {
    $res = [EvalResult]::new()
    $res.SentenceCount = $sentences.Length
    $res.MutationCount = $config.GetMutationCount()
    $res.ConfigKey = $config.GetKey()

    $prefixOffset = 0
    if ($config.Prefix -eq "qmark" -or $config.Prefix -eq "spade") { $prefixOffset = 2 }
    elseif ($config.Prefix -eq "slash") { $prefixOffset = 3 }

    for ($idx = 0; $idx -lt $sentences.Length; $idx++) {
        $raw = $sentences[$idx]
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        $projected = ProjectSentence $raw $config

        # Check fidelity
        $recovered = ReverseProjectSentence $projected $config
        if ($recovered -ne $raw) {
            $res.FidelityPassed = $false
        }

        # Parse with SMA
        $errors = [System.Management.Automation.Language.ParseError[]]@()
        $tokens = [System.Management.Automation.Language.Token[]]@()
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($projected, [ref]$tokens, [ref]$errors)

        if ($errors.Length -gt 0) {
            $res.FailingSentences++
            $res.TotalErrors += $errors.Length
        }

        # Useful AST structures
        # 1. ParenExpressionAst
        $parens = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParenExpressionAst] }, $true)
        $res.UsefulAstScore += ($parens.Count * 2)

        # 2. ArrayLiteralAst
        $arrays = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ArrayLiteralAst] }, $true)
        $res.UsefulAstScore += $arrays.Count

        # 3. CommandElements count (discrete words in commands)
        $commands = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($cmd in $commands) {
            if ($cmd.CommandElements.Count -ge 2) {
                $res.UsefulAstScore += ($cmd.CommandElements.Count - 1)
            }
        }

        # 4. Token kind semantic distinctions (e.g. Kind=In)
        foreach ($tok in $tokens) {
            if ($tok.Kind -eq "In") {
                $res.UsefulAstScore += 1
            }
        }

        # Boundary disagreement against spaCy
        if ($spacyMap -and $spacyMap.ContainsKey($idx)) {
            $spToks = $spacyMap[$idx]
            foreach ($st in $spToks) {
                # Skip punctuation tokens from boundary penalty
                if ($st.Pos -eq "PUNCT") { continue }
                $targetStart = $st.Start + $prefixOffset
                $targetEnd = $st.End + $prefixOffset
                $matched = $false
                foreach ($t in $tokens) {
                    if ($t.Kind -eq "EndOfInput") { continue }
                    if ($t.Extent.StartOffset -eq $targetStart -and $t.Extent.EndOffset -eq $targetEnd) {
                        $matched = $true
                        break
                    }
                }
                if (-not $matched) {
                    $res.BoundaryDisagreements++
                }
            }
        }
    }

    return $res
}

# Compare two results:
# Returns >0 if NewResult is strictly better than BaselineResult
# Returns <0 if NewResult is worse
# Returns 0 if Neutral
function CompareResults([EvalResult]$newRes, [EvalResult]$baseRes) {
    # 1. Fewer parse errors
    if ($newRes.TotalErrors -lt $baseRes.TotalErrors) { return 1 }
    if ($newRes.TotalErrors -gt $baseRes.TotalErrors) { return -1 }

    # 2. Fidelity
    if ($newRes.FidelityPassed -and -not $baseRes.FidelityPassed) { return 1 }
    if (-not $newRes.FidelityPassed -and $baseRes.FidelityPassed) { return -1 }

    # 3. Useful AST structure score (higher is better)
    if ($newRes.UsefulAstScore -gt $baseRes.UsefulAstScore) { return 1 }
    if ($newRes.UsefulAstScore -lt $baseRes.UsefulAstScore) { return -1 }

    # 4. Token boundary disagreements (fewer is better)
    if ($newRes.BoundaryDisagreements -lt $baseRes.BoundaryDisagreements) { return 1 }
    if ($newRes.BoundaryDisagreements -gt $baseRes.BoundaryDisagreements) { return -1 }

    # 5. Mutation count (smaller is better)
    if ($newRes.MutationCount -lt $baseRes.MutationCount) { return 1 }
    if ($newRes.MutationCount -gt $baseRes.MutationCount) { return -1 }

    return 0
}
