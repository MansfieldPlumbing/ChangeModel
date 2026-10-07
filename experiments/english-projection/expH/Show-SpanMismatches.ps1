#requires -Version 7.4
# List homograph rows whose [start,end) span does not equal the homograph text.
$data = Join-Path $PSScriptRoot '..\inputs\WikipediaHomographData\data'
$unquote = { param([string]$f) if ($f.Length -ge 2 -and $f[0] -eq '"' -and $f[-1] -eq '"') { $f.Substring(1, $f.Length - 2).Replace('""', '"') } else { $f } }
$n = 0
foreach ($dir in 'train', 'eval') {
    foreach ($file in (Get-ChildItem (Join-Path $data $dir) -Filter *.tsv)) {
        $lines = [IO.File]::ReadAllLines($file.FullName)
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $f = $lines[$i].Split("`t"); $h = & $unquote $f[0]; $s = & $unquote $f[2]; $a = [int](& $unquote $f[3]); $b = [int](& $unquote $f[4])
            $got = if ($b -le $s.Length) { $s.Substring($a, $b - $a) } else { '<past end>' }
            if (-not $got.Equals($h, [StringComparison]::OrdinalIgnoreCase)) {
                $n++
                if ($n -le 8) { "{0}/{1}:{2} want '{3}' got '{4}' | text has '{5}' at {6}" -f $dir, $file.Name, $i, $h, $got, $h, $s.IndexOf($h, [StringComparison]::OrdinalIgnoreCase) }
            }
        }
    }
}
"total $n"
