#requires -Version 7.4
# Run isolated misaki (Python 3.11, fba12365) to label all occurrences of the 671
# multi-pronunciation words in the 40 Gutenberg books.
param(
    [string] $BooksDir = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\gutenberg'),
    [string] $GoldPath = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\misaki\us_gold.json'),
    [string] $OutDir = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\gutenberg_labeled'),
    [string] $PythonExe = (Join-Path $env:LOCALAPPDATA 'Build\Kokoro-Hexagon\misaki-ref-fba12365\src\.venv\Scripts\python.exe')
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PythonExe)) {
    throw "Isolated Python environment not found: $PythonExe"
}

$pyScript = Join-Path $PSScriptRoot 'Label-GutenbergSnapshot.py'
Write-Host "Starting misaki Gutenberg labeling using isolated Python: $PythonExe"
& $PythonExe $pyScript $BooksDir $GoldPath $OutDir
Write-Host "Labeling completed."
