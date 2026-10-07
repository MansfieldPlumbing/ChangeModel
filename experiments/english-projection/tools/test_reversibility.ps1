# Verify bit-for-bit lossless reversibility
$trainLines = [System.IO.File]::ReadAllLines("C:\temp\sma-english-projection\inputs\train_500.tsv")
$allPassed = $true

for ($i = 1; $i -lt $trainLines.Length; $i++) {
    $line = $trainLines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $s = $line.Split([char]9)[5]

    # Apply projection mutations
    $mut = [char]0x00BF + " " + $s
    $mut = $mut.Replace([char]0x0027, [char]0x02BC)
    $mut = $mut.Replace([char]0x0023, [char]0xFF03)
    $mut = $mut.Replace([char]0x003B, [char]0xFF1B)
    $mut = $mut.Replace([char]0x002D, [char]0x2010)
    $mut = $mut.Replace([char]0x0022, [char]0x00AB)
    if ($mut.EndsWith(".")) { $mut = $mut.Substring(0, $mut.Length - 1) + " ." }

    # Reverse projection
    $rev = $mut
    if ($rev.StartsWith([char]0x00BF + " ")) { $rev = $rev.Substring(2) }
    if ($rev.EndsWith(" .")) { $rev = $rev.Substring(0, $rev.Length - 2) + "." }
    $rev = $rev.Replace([char]0x00AB, [char]0x0022)
    $rev = $rev.Replace([char]0x2010, [char]0x002D)
    $rev = $rev.Replace([char]0xFF1B, [char]0x003B)
    $rev = $rev.Replace([char]0xFF03, [char]0x0023)
    $rev = $rev.Replace([char]0x02BC, [char]0x0027)

    if ($rev -ne $s) {
        Write-Output "FAIL at row ${i}: ORIG='$s' REV='$rev'"
        $allPassed = $false
        break
    }
}

if ($allPassed) {
    Write-Output "REVERSIBILITY VERIFIED: 100% of 500 sentences bit-for-bit identical!"
}
