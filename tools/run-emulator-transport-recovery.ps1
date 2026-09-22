param(
    [Parameter(Mandatory=$true)][string]$Adb,
    [string]$Serial = 'emulator-5560',
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
if ($Serial -notmatch '^emulator-[0-9]+$') { throw 'Transport controls are limited to an emulator.' }
if (!(Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw 'Output directory must already exist.' }
$initialStatus = (& $Adb -s $Serial emu network status) -join "`n"
if ($LASTEXITCODE -ne 0 -or $initialStatus -notmatch 'download speed:\s+0 bits/s' -or
    $initialStatus -notmatch 'upload speed:\s+0 bits/s' -or $initialStatus -notmatch 'minimum latency:\s+0 ms' -or
    $initialStatus -notmatch 'maximum latency:\s+0 ms') { throw 'Requires an initially unlimited, zero-delay emulator network.' }
$remoteRoot = '/sdcard/Android/data/com.znbsf.kazumi.compose.tv/files'
$commandPath = Join-Path $OutputDirectory 'transport-command.txt'
$started = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 30000
$deadline = [DateTime]::UtcNow.AddSeconds(400)
$impaired = $false
$restored = $false
$finished = $false
$lastPhase = ''
function Set-TransportCommand([string]$Value) {
    [IO.File]::WriteAllText($commandPath,$Value,[Text.UTF8Encoding]::new($false))
    & $Adb -s $Serial push $commandPath "$remoteRoot/transport-recovery-command.txt" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Transport command upload failed.' }
}
function Set-Network([string]$Kind,[string]$Value) {
    $reply = & $Adb -s $Serial emu network $Kind $Value
    if ($LASTEXITCODE -ne 0 -or ($reply -join "`n") -match '(?m)^KO') { throw "Emulator rejected network $Kind." }
}
try {
    while ([DateTime]::UtcNow -lt $deadline) {
        $raw = & $Adb -s $Serial shell cat "$remoteRoot/transport-recovery-phase.json" 2>$null
        $state = try { $raw -join "`n" | ConvertFrom-Json } catch { $null }
        if ($state -and $state.checkpoint -match '^transport-recovery-([0-9]+)$' -and [long]$Matches[1] -ge $started) {
            if ($state.phase -ne $lastPhase) { $state | ConvertTo-Json -Compress; $lastPhase = $state.phase }
            if ($state.phase -eq 'ready' -and !$impaired) {
                Set-Network 'speed' '1'
                Set-Network 'delay' '60000'
                & $Adb -s $Serial emu network status
                $impaired = $true
                Set-TransportCommand 'impaired'
            }
            if ($state.phase -eq 'restore_requested' -and !$restored) {
                Set-Network 'speed' 'full'
                Set-Network 'delay' 'none'
                $restored = $true
                Set-TransportCommand 'restored'
            }
            if ($state.phase -eq 'finished') { $finished = $true; break }
        }
        Start-Sleep -Seconds 2
    }
    if (!$finished) { throw 'Transport test did not finish within the host deadline.' }
} finally {
    # Always restore the emulator, including invalid commands, test crashes and observation failure.
    try { Set-Network 'speed' 'full' } finally { Set-Network 'delay' 'none' }
    if (!$finished) { Set-TransportCommand 'abort' }
    & $Adb -s $Serial emu network status
}
