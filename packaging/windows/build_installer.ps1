param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepositoryRoot 'dist\Cipherbook-Setup.exe'
}

$buildReleasePath = Join-Path $RepositoryRoot 'build\windows\x64\runner\Release'
$fallbackReleasePath = Join-Path $RepositoryRoot 'release\windows\x64\runner\Release'
$releasePath = if (Test-Path -LiteralPath (Join-Path $buildReleasePath 'cipherbook.exe')) {
    $buildReleasePath
} else {
    $fallbackReleasePath
}
$installScriptPath = Join-Path $PSScriptRoot 'install.ps1'
$installCommandPath = Join-Path $PSScriptRoot 'install.cmd'
$iconPath = Join-Path $RepositoryRoot 'windows\runner\resources\app_icon.ico'
$iexpressPath = Join-Path $env:WINDIR 'System32\iexpress.exe'
$cmdPath = Join-Path $env:WINDIR 'System32\cmd.exe'

if (-not (Test-Path -LiteralPath (Join-Path $releasePath 'cipherbook.exe'))) {
    throw "找不到 Windows Release 产物: $buildReleasePath 或 $fallbackReleasePath"
}
if (-not (Test-Path -LiteralPath $iexpressPath)) {
    throw "找不到 Windows IExpress: $iexpressPath"
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}
$stagingPath = Join-Path ([IO.Path]::GetTempPath()) `
    ("cipherbook-iexpress-" + [Guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null
try {
    $payloadArchive = Join-Path $stagingPath 'cipherbook-payload.zip'
    Compress-Archive -Path (Join-Path $releasePath '*') `
        -DestinationPath $payloadArchive -CompressionLevel Optimal -Force
    Copy-Item -LiteralPath $installScriptPath -Destination $stagingPath -Force
    Copy-Item -LiteralPath $installCommandPath -Destination $stagingPath -Force
    Copy-Item -LiteralPath $iconPath -Destination (Join-Path $stagingPath 'cipherbook.ico') -Force

    $sedPath = Join-Path $stagingPath 'cipherbook.sed'
    $sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=1
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles

[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=Cipherbook installation completed.
TargetName=$OutputPath
FriendlyName=Cipherbook
AppLaunched=$cmdPath /c install.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="cipherbook-payload.zip"
FILE1="install.cmd"
FILE2="install.ps1"
FILE3="cipherbook.ico"

[SourceFiles]
SourceFiles0=$stagingPath

[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
"@
    Set-Content -LiteralPath $sedPath -Value $sed -Encoding ASCII

    & $iexpressPath /N /Q $sedPath
    $deadline = (Get-Date).AddMinutes(2)
    $lastLength = -1L
    $stableChecks = 0
    do {
        if (Test-Path -LiteralPath $OutputPath) {
            $currentLength = (Get-Item -LiteralPath $OutputPath).Length
            if ($currentLength -gt 1MB -and $currentLength -eq $lastLength) {
                $stableChecks++
            } else {
                $stableChecks = 0
            }
            $lastLength = $currentLength
            if ($stableChecks -ge 2) {
                break
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    if (-not (Test-Path -LiteralPath $OutputPath) -or
        (Get-Item -LiteralPath $OutputPath).Length -le 1MB) {
        throw "IExpress 未生成完整目标文件: $OutputPath"
    }

    $package = Get-Item -LiteralPath $OutputPath
    Write-Host "已生成: $($package.FullName)"
    Write-Host "大小: $([math]::Round($package.Length / 1MB, 2)) MB"
}
finally {
    if ($env:KEEP_CIPHERBOOK_STAGING -eq '1') {
        Write-Host "保留打包临时目录: $stagingPath"
    } elseif (Test-Path -LiteralPath $stagingPath) {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
}
