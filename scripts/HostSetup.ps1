$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

function Load {
    param([scriptblock]$function,
        [string]$Label)
    $job = Start-Job  -ScriptBlock $function

    $symbols = @("⣾⣿", "⣽⣿", "⣻⣿", "⢿⣿", "⡿⣿", "⣟⣿", "⣯⣿", "⣷⣿",
                 "⣿⣾", "⣿⣽", "⣿⣻", "⣿⢿", "⣿⡿", "⣿⣟", "⣿⣯", "⣿⣷")
    $i = 0;
    while ($job.State -eq "Running") {
        $symbol =  $symbols[$i]
        Write-Host -NoNewLine "`r$symbol $Label" -ForegroundColor Green
        Start-Sleep -Milliseconds 100
        $i++
        if ($i -eq $symbols.Count){
            $i = 0;
        }   
    }
    Write-Host -NoNewLine "`r                                                       "
}

#Disable Password Complexity
secedit /export /cfg c:\secpol.cfg | Out-Null
(Get-Content C:\secpol.cfg).replace("PasswordComplexity = 1", "PasswordComplexity = 0") | Out-File C:\secpol.cfg
secedit /configure /db c:\windows\security\local.sdb /cfg c:\secpol.cfg /areas SECURITYPOLICY | Out-Null
Remove-Item -Force c:\secpol.cfg -Confirm:$False

# Disable Local User Access control
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLUA -Value 0 -Force

# Audio fix
New-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "ServicesPipeTimeout" -Value 600000 -PropertyType "DWord" | Out-Null
Set-Service -Name Audiosrv -StartupType Automatic

# Disable Shutdown Tracker
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability" | New-ItemProperty -Name ShutdownReasonOn -Value 0

if (-Not (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability')) {
    New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT' -Name Reliability -Force
}

(Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' -Name ShutdownReasonOn -Value 0) | Out-Null
(Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' -Name ShutdownReasonUI -Value 0) | Out-Null

Clear-Host

Write-Host "Welcome, let's set up your cloud desktop!"
Write-Host " "
Write-Host " "
Write-Host "🔐 Please set a password for the Administrator account" -ForegroundColor White
$AdminPassword = $null
do {
    if ($null -ne $AdminPassword) { Write-Host "Passwords do not match." -ForegroundColor Red }
    Write-Host "Enter Administrator password: " -NoNewLine
    $AdminPassword = Read-Host -MaskInput
    Write-Host "Re-enter Administrator password: " -NoNewLine
    $AdminPasswordConfirm = Read-Host -MaskInput
} while (($AdminPassword -ne $AdminPasswordConfirm) -And ($null -ne $AdminPassword))

net user Administrator $($AdminPassword) | Out-Null

$install_steam = $Host.UI.PromptForChoice("🕹  Steam", "Would you like to install Steam?", ('&Yes', '&No'), 0)
$install_parsec = $Host.UI.PromptForChoice("👾  Parsec", "Would you like to install Parsec? (high-fidelity remote desktop)", ('&Yes', '&No'), 0)
$install_7zip = $Host.UI.PromptForChoice("📁  7zip", "Would you like to install 7zip?", ('&Yes', '&No'), 0)
$install_nicedcv = $Host.UI.PromptForChoice("🖥️  NICE DCV Server", "Would you like to install NICE DCV? (recommended - high quality desktop access using your Admin login)", ('&Yes', '&No'), 0)
$install_nvdrivers = $Host.UI.PromptForChoice("📺  NVIDIA GPU Drivers", "Would you like to install NVIDIA Graphics Drivers?", ('&Yes', '&No'), 0)
$set_res = $Host.UI.PromptForChoice("🖥️  Set Resolution", "Would you like to set the screen resolution?", ("720p", "1080p", "1440p", "4K", "&No"), 1)

Clear-Host

Write-Host "Setting host resolution...`n"
switch ($set_res) {
    0 { reg add HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /v SetResolution /f /d "pwsh -WindowStyle Hidden -Command Set-DisplayResolution -Width 1280 -Height 720 -Force" | Out-Null ; Write-Host "Resolution will change to 720p on startup." }
    1 { reg add HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /v SetResolution /f /d "pwsh -WindowStyle Hidden -Command Set-DisplayResolution -Width 1920 -Height 1080 -Force" | Out-Null ; Write-Host "Resolution will change to 1080p on startup." }
    2 { reg add HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /v SetResolution /f /d "pwsh -WindowStyle Hidden -Command Set-DisplayResolution -Width 2560 -Height 1440 -Force" | Out-Null ; Write-Host "Resolution will change to 1440p on startup." }
    3 { reg add HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /v SetResolution /f /d "pwsh -WindowStyle Hidden -Command Set-DisplayResolution -Width 3840 -Height 2160 -Force" | Out-Null ; Write-Host "Resolution will change to 4K on startup." }
    4 { Write-Host "Resolution not changed." }
}

Write-Host "`nInstalling selected packages...`n"

if ($install_steam -eq 0) {
    $Command = { choco install steam -y --limit-output }
    Load $Command "Installing Steam"
}

if ($install_parsec -eq 0) {
    $Command = { choco install parsec -y --limit-output }
    Load $Command "Installing Parsec"
}

if ($install_7zip -eq 0) {
    $Command = { choco install 7zip -y --limit-output }
    Load $Command "Installing 7zip"
}

if ($install_nicedcv -eq 0) {
    $Command = { "https://d1uj6qtbmh3dt5.cloudfront.net/" | Set-Variable BucketURL -Scope Private ; Set-Variable DCVUrl -Value ("$BucketURL" + ((Invoke-RestMethod "$BucketURL").ListBucketResult.Contents | Where-Object { $_.Key -like "*/Servers/*.msi" } | Sort-Object { $_.LastModified } -Descending | Select-Object -First 1).Key)
    Write-Host "Installing NICE-DCV from $DCVUrl"
    Invoke-WebRequest -Uri "$DCVUrl" -OutFile "$InstallDir\NiceDCV.msi"

    Start-Process -FilePath "C:\Windows\System32\msiexec.exe" -ArgumentList "/i $InstallDir\NiceDCV.msi ADDLOCAL=ALL AUTOMATIC_SESSION_OWNER=Administrator /quiet /norestart" -Wait
    New-Item -Path "Microsoft.PowerShell.Core\Registry::\HKEY_USERS\S-1-5-18\Software\GSettings\com\nicesoftware\dcv\" -Name security -Force | Set-ItemProperty -Name os-auto-lock -Value 0
    netsh advfirewall firewall add rule name="DCV Server" dir=in action=allow protocol=TCP localport=8443
    Set-Service dcvserver -StartupType Automatic }

    Load $Command "Installing NICE DCV Server"
}

if ($install_nvdrivers -eq 0) {
    $Command = { Write-Host "Installing NVIDIA vGaming Drivers" -ForegroundColor Cyan
    $NVDriverURL = "https://nvidia-gaming.s3.amazonaws.com/" + (Invoke-RestMethod "https://nvidia-gaming.s3.amazonaws.com/?prefix=windows/latest").ListBucketResult.Contents.Key[1]
    Invoke-WebRequest $NVDriverURL -OutFile "$InstallDir\NVDriver.zip"
    Expand-Archive -Path "$InstallDir\NVDriver.zip" -DestinationPath "$InstallDir\NVDriver" -Force
    Start-Process "$InstallDir\NVDriver\Windows\*vgaming*.exe" -ArgumentList "-s" -NoNewWindow -Wait
    New-ItemProperty -Path "HKLM:\SOFTWARE\NVIDIA Corporation\Global" -Name "vGamingMarketplace" -PropertyType "DWord" -Value "2"
    Invoke-WebRequest -Uri "https://nvidia-gaming.s3.amazonaws.com/GridSwCert-Archive/GridSwCertWindows_2021_10_2.cert" -OutFile "$Env:PUBLIC\Documents\GridSwCert.txt" }

    Load $Command "Installing NVIDIA Graphics Drivers (takes a while)"
}

$do_restart = $Host.UI.PromptForChoice("🔁 Restart required", "Would you like to restart your Windows instance now?", ('&Yes', '&No'), 0)
if ($do_restart -eq 0) {
    shutdown /r /t 0
} else {
    shutdown /a
}



Write-Host "Setup complete." -ForegroundColor Green