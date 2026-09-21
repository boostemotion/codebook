$ErrorActionPreference = 'Stop'

$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$defaultTarget = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Cipherbook'
$registryPath = 'HKCU:\Software\Cipherbook'
$startMenuShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Cipherbook.lnk'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Cipherbook.lnk'

Add-Type -AssemblyName System.Windows.Forms

function Show-InstallerMessage {
    param(
        [string]$Message,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        'Cipherbook Installer',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    ) | Out-Null
}

function Get-ShortcutTargetDirectory {
    param([string]$ShortcutPath)

    if (-not (Test-Path -LiteralPath $ShortcutPath)) {
        return $null
    }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        if ([string]::IsNullOrWhiteSpace($shortcut.TargetPath)) {
            return $null
        }
        return Split-Path -Parent $shortcut.TargetPath
    } catch {
        return $null
    }
}

function Get-ExistingInstallDirectory {
    $candidates = [System.Collections.Generic.List[string]]::new()

    if (Test-Path -LiteralPath $registryPath) {
        try {
            $registered = (Get-ItemProperty -LiteralPath $registryPath -Name InstallLocation).InstallLocation
            if (-not [string]::IsNullOrWhiteSpace($registered)) {
                $candidates.Add($registered)
            }
        } catch {
            # The registry record may be absent or incomplete; use shortcuts below.
        }
    }

    foreach ($shortcutPath in @($startMenuShortcut, $desktopShortcut)) {
        $shortcutDirectory = Get-ShortcutTargetDirectory $shortcutPath
        if (-not [string]::IsNullOrWhiteSpace($shortcutDirectory)) {
            $candidates.Add($shortcutDirectory)
        }
    }

    $candidates.Add($defaultTarget)
    foreach ($candidate in $candidates | Select-Object -Unique) {
        try {
            $fullCandidate = [IO.Path]::GetFullPath($candidate)
            if (Test-Path -LiteralPath (Join-Path $fullCandidate 'cipherbook.exe')) {
                return $fullCandidate
            }
        } catch {
            continue
        }
    }
    return $null
}

if (Get-Process -Name 'cipherbook' -ErrorAction SilentlyContinue) {
    Show-InstallerMessage `
        'Cipherbook is currently running. Save your work, close Cipherbook, and run the installer again.' `
        ([System.Windows.Forms.MessageBoxIcon]::Warning)
    exit 1
}

$target = $env:CIPHERBOOK_INSTALL_DIR
if ([string]::IsNullOrWhiteSpace($target)) {
    $target = Get-ExistingInstallDirectory
}
if ([string]::IsNullOrWhiteSpace($target)) {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the Cipherbook installation folder (first install)'
    $dialog.SelectedPath = $defaultTarget
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        exit 0
    }
    $target = $dialog.SelectedPath
}
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

New-Item -ItemType Directory -Path $target -Force | Out-Null

$archive = Join-Path $source 'cipherbook-payload.zip'
if (-not (Test-Path -LiteralPath $archive)) {
    throw 'Installer payload is missing cipherbook-payload.zip.'
}
Expand-Archive -LiteralPath $archive -DestinationPath $target -Force
$iconSource = Join-Path $source 'cipherbook.ico'
$iconTarget = Join-Path $target 'cipherbook.ico'
if (Test-Path -LiteralPath $iconSource) {
    Copy-Item -LiteralPath $iconSource -Destination $iconTarget -Force
}

New-Item -Path $registryPath -Force | Out-Null
Set-ItemProperty -Path $registryPath -Name InstallLocation -Value $target
Set-ItemProperty -Path $registryPath -Name DisplayName -Value 'Cipherbook'
Set-ItemProperty -Path $registryPath -Name InstalledAt -Value (Get-Date).ToUniversalTime().ToString('o')

New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
$executable = Join-Path $target 'cipherbook.exe'

foreach ($shortcutPath in @(
    (Join-Path $startMenu 'Cipherbook.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Cipherbook.lnk')
)) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $executable
    $shortcut.WorkingDirectory = $target
    $shortcut.IconLocation = "$iconTarget,0"
    $shortcut.Description = 'Cipherbook password vault'
    $shortcut.Save()
}

Start-Process -FilePath $env:ComSpec -ArgumentList @('/c', 'start', '""', "`"$executable`"") `
    -WorkingDirectory $target -WindowStyle Hidden

Write-Host "Cipherbook installed to $target"
