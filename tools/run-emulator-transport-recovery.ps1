param(
    [Parameter(Mandatory=$true)][string]$Adb,
    [string]$Serial = 'emulator-5560',
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
if ($Serial -notmatch '^emulator-[0-9]+$') { throw 'Transport controls are limited to an emulator.' }
if (!(Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw 'Output directory must already exist.' }
function Assert-NetworkRestored {
    $status = (& $Adb -s $Serial emu network status) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $status -notmatch 'download speed:\s+0 bits/s' -or
        $status -notmatch 'upload speed:\s+0 bits/s' -or $status -notmatch 'minimum latency:\s+0 ms' -or
        $status -notmatch 'maximum latency:\s+0 ms') { throw 'Emulator network is not confirmed unlimited with zero delay.' }
}
function Get-DeviceUptimeMilliseconds {
    $uptime = (& $Adb -s $Serial shell cat /proc/uptime) -join ''
    if ($LASTEXITCODE -ne 0 -or $uptime -notmatch '^([0-9]+\.[0-9]+)\s') { throw 'Could not read emulator monotonic uptime.' }
    return [long][Math]::Floor([double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture) * 1000)
}
Assert-NetworkRestored
$remoteRoot = '/sdcard/Android/data/com.znbsf.kazumi.compose.tv/files'
$commandPath = Join-Path $OutputDirectory 'transport-command.txt'
$startedDeviceMs = Get-DeviceUptimeMilliseconds
$activeCheckpoint = $null
$deadline = [DateTime]::UtcNow.AddSeconds(400)
$impaired = $false
$restored = $false
$secondImpaired = $false
$secondRestored = $false
$finished = $false
$lastPhase = ''
function Set-TransportCommand([string]$Value) {
    [IO.File]::WriteAllText($commandPath,$Value,[Text.UTF8Encoding]::new($false))
    & $Adb -s $Serial push $commandPath "$remoteRoot/transport-recovery-command.txt.tmp" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Transport command upload failed.' }
    & $Adb -s $Serial shell mv "$remoteRoot/transport-recovery-command.txt.tmp" "$remoteRoot/transport-recovery-command.txt" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Transport command publish failed.' }
}
function Set-Network([string]$Kind,[string]$Value) {
    $reply = & $Adb -s $Serial emu network $Kind $Value
    if ($LASTEXITCODE -ne 0 -or ($reply -join "`n") -match '(?m)^KO') { throw "Emulator rejected network $Kind." }
}
try {
    while ([DateTime]::UtcNow -lt $deadline) {
        $raw = & $Adb -s $Serial shell "if [ -f '$remoteRoot/transport-recovery-phase.json' ]; then cat '$remoteRoot/transport-recovery-phase.json'; fi"
        $state = try { $raw -join "`n" | ConvertFrom-Json } catch { $null }
        if ($state -and $state.checkpoint -match '^transport-recovery-[0-9]+$' -and
            $null -ne $state.elapsedRealtimeMs -and [long]$state.elapsedRealtimeMs -ge $startedDeviceMs -and
            (!$activeCheckpoint -or $state.checkpoint -eq $activeCheckpoint)) {
            if (!$activeCheckpoint) { $activeCheckpoint = $state.checkpoint }
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
                Assert-NetworkRestored
                # /proc/uptime is sampled after both commands and status readback: an upper bound,
                # on the device monotonic clock, for when restoration was confirmed.
                $restoreConfirmedDeviceMs = Get-DeviceUptimeMilliseconds
                @{ event = 'network_restore_confirmed'; deviceElapsedRealtimeMs = $restoreConfirmedDeviceMs;
                   hostStopwatchTicks = [Diagnostics.Stopwatch]::GetTimestamp();
                   hostStopwatchFrequency = [Diagnostics.Stopwatch]::Frequency } | ConvertTo-Json -Compress
                $restored = $true
                Set-TransportCommand "restored:$restoreConfirmedDeviceMs"
            }
            if ($state.phase -eq 'ready_again' -and $restored -and !$secondImpaired) {
                Set-Network 'speed' '1'
                Set-Network 'delay' '60000'
                & $Adb -s $Serial emu network status
                $secondImpaired = $true
                Set-TransportCommand 'impaired'
            }
            if ($state.phase -eq 'restore_requested_again' -and $secondImpaired -and !$secondRestored) {
                Set-Network 'speed' 'full'
                Set-Network 'delay' 'none'
                Assert-NetworkRestored
                $restoreConfirmedDeviceMs = Get-DeviceUptimeMilliseconds
                @{ event = 'network_restore_confirmed_again'; deviceElapsedRealtimeMs = $restoreConfirmedDeviceMs;
                   hostStopwatchTicks = [Diagnostics.Stopwatch]::GetTimestamp();
                   hostStopwatchFrequency = [Diagnostics.Stopwatch]::Frequency } | ConvertTo-Json -Compress
                $secondRestored = $true
                Set-TransportCommand "restored:$restoreConfirmedDeviceMs"
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
    Assert-NetworkRestored
    @{ event = 'network_finally_restored'; deviceElapsedRealtimeMs = Get-DeviceUptimeMilliseconds } | ConvertTo-Json -Compress
}
