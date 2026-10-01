# Creates or removes a Start Menu shortcut for Spectrum Strategy.
# Run without arguments to create the shortcut.
# Run with -Remove to remove it.
# Uses WScript.Shell COM object - no admin rights required.

param(
  [switch]$Remove
)

$shortcutName = "Spectrum Strategy.lnk"
$programsDir = [Environment]::GetFolderPath("Programs")
$shortcutPath = Join-Path $programsDir $shortcutName

if ($Remove) {
  if (Test-Path $shortcutPath) {
    try {
      Remove-Item $shortcutPath -ErrorAction Stop
    } catch {
      Write-Warning "Could not remove the shortcut at ${shortcutPath}: $($_.Exception.Message)"
      exit 1
    }
    Write-Host "Removed Start Menu shortcut: $shortcutPath"
  } else {
    Write-Host "Start Menu shortcut not found: $shortcutPath"
  }
  exit 0
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exePath = Join-Path $scriptDir "spectrumstrategy.exe"

if (-not (Test-Path $exePath -PathType Leaf)) {
  Write-Warning "spectrumstrategy.exe not found next to the script at: $exePath"
  Write-Warning "Place the script in the same directory as the unzipped build and retry."
  Write-Host "No shortcut created."
  exit 1
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $exePath
$shortcut.WorkingDirectory = $scriptDir
$shortcut.Description = "Spectrum Strategy"
$shortcut.Save()

Write-Host "Created Start Menu shortcut: $shortcutPath"
