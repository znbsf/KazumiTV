param(
    [Parameter(Mandatory=$true)][string]$FlutterRoot,
    [Parameter(Mandatory=$true)][string]$PubCache,
    [Parameter(Mandatory=$true)][string]$GradleHome,
    [Parameter(Mandatory=$true)][string]$JavaHome,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Python = 'python',
    [string]$BuildName = '0.4.5-parserqa.1',
    [int]$BuildNumber = 20570,
    [ValidateSet('android-x64','android-arm','android-arm64')]
    [string]$TargetPlatform = 'android-x64',
    [switch]$LaunchOnly,
    [string]$AndroidSdkRoot = "$env:LOCALAPPDATA/Android/Sdk"
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
Set-Location -LiteralPath $repo
$androidRegistrant = 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
if (-not (Test-Path -LiteralPath (Join-Path $repo $androidRegistrant) -PathType Leaf)) {
    throw "Missing Android GeneratedPluginRegistrant: $androidRegistrant. Run the pinned Flutter Android-only injectPlugins preparation first (see tools/qa/source_batch/README.md). Dependency metadata alone is insufficient; refusing --no-pub QA build."
}
New-Item -ItemType Directory -Force -Path $Output | Out-Null
& $Python -X utf8 tools/qa/source_batch/prepare.py
if ($LASTEXITCODE -ne 0) { throw 'Parser generation failed' }
function Source-Digests {
    $paths = @(& git ls-files --cached --others --exclude-standard -- android lib tools/qa/source_batch)
    $paths += 'android/app/src/parserQa/assets/parserqa/parser.generated.js'
    $paths += $androidRegistrant
    $map = [ordered]@{}
    foreach ($path in ($paths | Sort-Object -Unique)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $map[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return ($map | ConvertTo-Json -Compress)
}
$before = Source-Digests
$env:PUB_CACHE = $PubCache
$env:GRADLE_USER_HOME = $GradleHome
$env:JAVA_HOME = $JavaHome
$env:GRADLE_OPTS = '-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false'
$qaFlavor = if ($LaunchOnly) { 'parserQaOffline' } else { 'parserQa' }
$qaExtraArgs = if ($LaunchOnly) { @('--android-project-arg=kazumiQaLaunchOnly=true', '--dart-define=KAZUMI_QA_LAUNCH_ONLY=true') } else { @() }
& "$FlutterRoot/bin/flutter.bat" --no-version-check build apk --debug --no-pub --flavor $qaFlavor --android-project-arg=kazumiParserQa=true @qaExtraArgs --target-platform $TargetPlatform --target tools/qa/source_batch/main.dart "--build-name=$BuildName" "--build-number=$BuildNumber" *> "$Output/build.log"
if ($LASTEXITCODE -ne 0) { Get-Content "$Output/build.log" -Tail 40; throw 'QA build failed' }
if ($before -ne (Source-Digests)) { throw 'Sources changed during build; refusing artifact identity' }
$apk = Join-Path $repo "build/app/outputs/flutter-apk/app-$($qaFlavor.ToLowerInvariant())-debug.apk"
Copy-Item -LiteralPath $apk -Destination "$Output/parserqa.apk"
if ($LaunchOnly) {
    $qaMerged = Join-Path $repo 'build/app/intermediates/merged_manifests/parserQaOfflineDebug/processParserQaOfflineDebugManifest/AndroidManifest.xml'
    [xml]$qaManifest = Get-Content -LiteralPath $qaMerged -Raw
    $qaPermissions = @($qaManifest.manifest.ChildNodes | Where-Object { $_.Name -like 'uses-permission*' } | ForEach-Object { $_.GetAttribute('name','http://schemas.android.com/apk/res/android') })
    if ('android.permission.INTERNET' -in $qaPermissions) { throw 'Offline merged manifest still requests INTERNET' }
    Copy-Item -LiteralPath $qaMerged -Destination "$Output/merged-manifest.xml"
    $qaAapt = Join-Path $AndroidSdkRoot 'build-tools/36.0.0/aapt.exe'
    $qaApkPermissions = & $qaAapt dump permissions "$Output/parserqa.apk"
    if ($LASTEXITCODE -ne 0 -or $qaApkPermissions -match "android.permission.INTERNET") { throw 'Offline APK permission check failed' }
    $qaApkPermissions | Set-Content -Encoding utf8NoBOM "$Output/apk-permissions.txt"
}
$before | Set-Content -Encoding utf8NoBOM "$Output/source-digests.json"
@{
    code_sha = (& git rev-parse HEAD).Trim()
    branch = (& git branch --show-current).Trim()
    dirty = [bool](& git status --porcelain)
    apk_sha256 = (Get-FileHash "$Output/parserqa.apk").Hash.ToLowerInvariant()
    source_digests_sha256 = (Get-FileHash "$Output/source-digests.json").Hash.ToLowerInvariant()
    gecko = '146.0.20251217121356'
    target_platform = $TargetPlatform
    launch_only_build = [bool]$LaunchOnly
    no_internet_permission = if ($LaunchOnly) { $true } else { $null }
    built_utc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content -Encoding utf8NoBOM "$Output/artifact.json"
Get-Content "$Output/artifact.json"
