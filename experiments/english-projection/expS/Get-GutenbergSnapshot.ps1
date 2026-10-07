#requires -Version 7.4
# Fetch a fixed list of public-domain Project Gutenberg books as plain text, strip the Project
# Gutenberg header and footer, and record each file's SHA-256 in a manifest. Polite: one request
# every 2 seconds, existing files are not re-fetched.
param([string] $OutDir = (Join-Path $PSScriptRoot '..\inputs\gutenberg'))
$ErrorActionPreference = 'Stop'
$books = @(1342, 84, 11, 2701, 1661, 98, 345, 174, 76, 74, 1260, 768, 2600, 5200, 1080, 4300, 135, 1400, 46, 120,
           215, 36, 35, 43, 1184, 2554, 28054, 3207, 1232, 205, 2814, 158, 161, 105, 1952, 64317, 2591, 1497, 3600, 23)
[void][IO.Directory]::CreateDirectory($OutDir)
$manifest = [Collections.Generic.List[string]]::new(); $manifest.Add("id`tbytes`tsha256`tsource")
foreach ($id in $books) {
    $raw = Join-Path $OutDir "pg$id.raw.txt"; $clean = Join-Path $OutDir "pg$id.txt"
    $url = "https://www.gutenberg.org/cache/epub/$id/pg$id.txt"
    if (-not (Test-Path $raw)) {
        try { Invoke-WebRequest $url -OutFile $raw -UserAgent 'Kokoro-Hexagon research (polite fetch)'; Start-Sleep -Seconds 2 }
        catch { "skip $id ($($_.Exception.Message))"; continue }
    }
    $text = [IO.File]::ReadAllText($raw)
    $a = $text.IndexOf('*** START OF', [StringComparison]::Ordinal); $b = $text.IndexOf('*** END OF', [StringComparison]::Ordinal)
    if ($a -lt 0 -or $b -le $a) { "skip $id (no START/END markers)"; continue }
    $a = $text.IndexOf("`n", $a) + 1
    [IO.File]::WriteAllText($clean, $text.Substring($a, $b - $a))
    $manifest.Add("$id`t$((Get-Item $clean).Length)`t$((Get-FileHash $clean).Hash)`t$url")
}
[IO.File]::WriteAllLines((Join-Path $OutDir 'MANIFEST.tsv'), $manifest)
"books kept: $($manifest.Count - 1)"
