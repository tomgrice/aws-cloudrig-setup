$WarningPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

Set-ExecutionPolicy Unrestricted -Confirm:$false -Force


Start-Process ".\utils\alacritty-portable.exe" -ArgumentList "--config-file utils\alacritty.yml -e pwsh -ExecutionPolicy Unrestricted -File .\scripts\Start.ps1"