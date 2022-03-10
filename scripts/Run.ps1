$WarningPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

Start-Process ".\utils\alacritty-portable.exe" -ArgumentList "--config-file utils\alacritty.yml -e pwsh -ExecutionPolicy Bypass -File .\scripts\Start.ps1"