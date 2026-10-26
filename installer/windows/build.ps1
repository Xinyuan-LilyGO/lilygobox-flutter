param(
    [string]$IsccPath,
    [string]$FlutterPath = 'flutter',
    [ValidateSet('alpha', 'beta', 'stable')]
    [string]$ReleaseChannel = 'stable',
    [string]$ReleaseVersion,
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Push-Location $projectRoot
try {
    if (-not $IsccPath) {
        $compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($compiler) { $IsccPath = $compiler.Source }
        else {
            $candidates = @(
                "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
                "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
            )
            $IsccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        }
    }
    if (-not $IsccPath -or -not (Test-Path -LiteralPath $IsccPath)) {
        throw 'Install Inno Setup 6 or pass -IsccPath with the path to ISCC.exe.'
    }
    $versionLine = Get-Content -LiteralPath 'pubspec.yaml' | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
    $baseVersion = ($versionLine -replace '^version:\s*', '').Trim() -replace '\+.*$', ''
    if ($baseVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected a numeric major.minor.patch version in pubspec.yaml.' }
    $appVersion = $ReleaseVersion
    if (-not $appVersion) {
        $appVersion = if ($ReleaseChannel -eq 'stable') { $baseVersion } else { "$baseVersion-$ReleaseChannel.1" }
    }
    $versionMatch = [regex]::Match($appVersion, '^\d+\.\d+\.\d+(?:-(alpha|beta)\.\d+)?$')
    if (-not $versionMatch.Success) { throw 'ReleaseVersion must follow major.minor.patch[-alpha.N|-beta.N].' }
    $versionChannel = if ($versionMatch.Groups[1].Success) { $versionMatch.Groups[1].Value } else { 'stable' }
    if ($versionChannel -ne $ReleaseChannel) { throw 'ReleaseVersion suffix must match ReleaseChannel.' }
    if (-not $SkipFlutterBuild) {
        & $FlutterPath build windows --release `
            "--dart-define=LILYGOBOX_RELEASE_CHANNEL=$ReleaseChannel" `
            "--dart-define=LILYGOBOX_RELEASE_VERSION=$appVersion"
        if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
    }
    $releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    foreach ($required in @('lilygobox-windows-x64.exe', 'flutter_windows.dll', 'data\icudtl.dat', 'data\flutter_assets')) {
        if (-not (Test-Path -LiteralPath (Join-Path $releaseDir $required))) {
            throw "Release output is incomplete: $required"
        }
    }
    $licenseText = Get-Content -LiteralPath 'LICENSE' -Raw
    $licenseParagraphs = [regex]::Split($licenseText.Trim(), '\r?\n\s*\r?\n')
    $rtfParagraphs = foreach ($paragraph in $licenseParagraphs) {
        $text = ($paragraph.Trim() -replace '\s+', ' ')
        $escapedText = $text.Replace('\', '\\').Replace('{', '\{').Replace('}', '\}')
        if ($text -eq 'GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007') {
            '\pard\qc\sb0\sa180\b GNU GENERAL PUBLIC LICENSE\b0\line Version 3, 29 June 2007\par'
        } elseif ($text -in @('Preamble', 'TERMS AND CONDITIONS', 'END OF TERMS AND CONDITIONS', 'How to Apply These Terms to Your New Programs')) {
            "\pard\qc\sb180\sa180\b $escapedText\b0\par"
        } else {
            "\pard\ql\sb0\sa140 $escapedText\par"
        }
    }
    $installerDir = Join-Path $projectRoot 'build\installer'
    New-Item -ItemType Directory -Path $installerDir -Force | Out-Null
    $licenseRtf = '{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}}\f0\fs20 ' + ($rtfParagraphs -join "`r`n") + '}'
    Set-Content -LiteralPath (Join-Path $installerDir 'LICENSE.rtf') -Value $licenseRtf -Encoding ascii
    & $IsccPath "/DAppVersion=$appVersion" "/DReleaseDir=$releaseDir" (Join-Path $PSScriptRoot 'lilygobox.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
} finally {
    Pop-Location
}
