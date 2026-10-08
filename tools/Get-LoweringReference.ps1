[CmdletBinding()]
param([string]$OutDir=(Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\pslowering-1afabe056235a570da29e268824784557d4f6cdd'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$commit='1afabe056235a570da29e268824784557d4f6cdd'
$tree=Invoke-RestMethod -Uri "https://api.github.com/repos/MansfieldPlumbing/PSLowering/git/trees/${commit}?recursive=1" -Headers @{'User-Agent'='PSPerception-pinned-dependency'}
[void][IO.Directory]::CreateDirectory($OutDir)
$manifest=[Collections.Generic.List[object]]::new()
foreach($entry in ($tree.tree|Where-Object {$_.type -ceq 'blob' -and $_.path.StartsWith('src/')}|Sort-Object path)){
    $target=Join-Path $OutDir $entry.path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    if(-not(Test-Path -LiteralPath $target)){Invoke-WebRequest -Uri "https://raw.githubusercontent.com/MansfieldPlumbing/PSLowering/$commit/$($entry.path)" -OutFile $target}
    $bytes=[IO.File]::ReadAllBytes($target)
    $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA1)
    try{$hash.AppendData([Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0"));$hash.AppendData($bytes);$blob=[Convert]::ToHexString($hash.GetHashAndReset()).ToLowerInvariant()}finally{$hash.Dispose()}
    if($blob -cne $entry.sha){throw 'Pinned lowering dependency blob mismatch; existing files preserved.'}
    $manifest.Add([pscustomobject]@{Commit=$commit;Path=$entry.path;GitBlob=$entry.sha;Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash})
}
$manifest|Export-Csv -LiteralPath (Join-Path $OutDir 'verified-source.tsv') -Delimiter "`t"
'LOWERING_REFERENCE=VERIFIED commit={0} files={1}' -f $commit,$manifest.Count
