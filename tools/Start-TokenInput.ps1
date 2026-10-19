param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [int]$Port = 18769,
    [string]$AdbPath = 'adb'
)
$ErrorActionPreference = 'Stop'
$pythonPath = (Get-Command python -ErrorAction Stop).Source
$resolvedAdb = (Get-Command $AdbPath -ErrorAction Stop).Source
& $pythonPath (Join-Path $PSScriptRoot 'local_token_input.py') --adb $resolvedAdb --serial $Serial --port $Port
exit $LASTEXITCODE
