Set-ExecutionPolicy Unrestricted -Confirm:$false -Force
$WarningPreference = 'SilentlyContinue'


<# Import Configuration File #>
$Config = Import-PowerShellDataFile .\Config.psd1

<# Install required AWS Tools Modules 
if(!(Get-Module AWS.Tools.Installer -ListAvailable)) {
  Install-Module -Name AWS.Tools.Installer -Confirm:$false -Force -Scope AllUsers -Wait
}

Install-AWSToolsModule AWS.Tools.EC2,AWS.Tools.SimpleSystemsManagement -Confirm:$false -Scope AllUsers

Clear-Host

<# Function to display cool loading spinner whilst a command is running. #>
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
    Write-Host -NoNewLine "`r"
}

Write-Host "👋 Welcome to Cloud Rig setup tool."
Write-Host "created by @tomgrice: https://github.com/tomgrice"
Write-Host "____________________________________________________`n"

$InstanceName = ""
while($InstanceName -eq "") {
    Write-Host "🏷️  Please specify a name for your cloud rig: " -ForegroundColor Cyan -NoNewline
    $InstanceName = (Read-Host).Trim().Replace(" ","")
}
<# Try creating a new keypair or return error message. #>
try {
    (New-EC2KeyPair -KeyName "$($InstanceName)Key" -AccessKey $Config['AWS_AccessKey'] -SecretKey $Config['AWS_SecretKey'] -Region $Config['AWS_Region']).KeyMaterial | Out-File -Encoding ascii -FilePath ".\$($InstanceName)Key.pem"
}
catch {
    Write-Host "Could not generate keypair: "
    Write-Host $_
}

<# Instance Volume Settings #>
$Image_ebsBlock = @{VolumeSize=256;VolumeType='gp3'}

<# Instance Tag Settings #>
$InstanceTags = @(
    @{key="Name";value="$($InstanceName)"}
)

$TagSpec = @(@{ResourceType="Instance";Tags=$InstanceTags},@{ResourceType="Volume";Tags=$InstanceTags})

$SecGroup = New-EC2SecurityGroup -AccessKey $Config['AWS_AccessKey'] -SecretKey $Config['AWS_SecretKey'] -Region $Config['AWS_Region'] `
    -Description "Security group for CloudRig" -GroupName "$($InstanceName)-SG" -Force

Grant-EC2SecurityGroupIngress -AccessKey $Config['AWS_AccessKey'] -SecretKey $Config['AWS_SecretKey'] -Region $Config['AWS_Region'] `
    -GroupId $($SecGroup) -IpPermission @{'IpProtocol' = '-1'; 'IpRanges' = '0.0.0.0/0'}

<# Get AMI image id #>
$AMI_ImageId = Get-SSMLatestEC2Image -AccessKey $Config['AWS_AccessKey'] -SecretKey $Config['AWS_SecretKey'] -Region $Config['AWS_Region'] `
    -Path ami-windows-latest -ImageName $($Config.AMI_ImageName)

<# Create new instance #>
$NewInstance = New-EC2Instance -AccessKey $Config['AWS_AccessKey'] -SecretKey $Config['AWS_SecretKey'] -Region $Config['AWS_Region'] `
    -ImageId $AMI_ImageId `
    -UserDataFile ".\scripts\Launch_UserData.txt" -EncodeUserData `
    -BlockDeviceMapping @( @{DeviceName="/dev/sda1";Ebs=$Image_ebsBlock} ) `
    -InstanceType 'g4dn.xlarge' `
    -KeyName "$($InstanceName)Key" `
    -SecurityGroupId "$($SecGroup)" `
    -TagSpecification $TagSpec `
    -MaxCount 1

<# Get new instance IP, store and display it. #>
Write-Host "Getting Instance Public IP"

do {
    $InstanceIP = (Get-EC2Instance -AccessKey $Config['AWS_AccessKey'] -SecretKey $Config['AWS_SecretKey'] -Region $Config['AWS_Region'] -InstanceId $($NewInstance.Instances[0].InstanceId)).Instances[0].PublicIpAddress
} while ($Null -eq $InstanceIP)

Write-Host "New Instance IP: $($InstanceIP)`n"

$InstanceIP | Out-File -Encoding ascii -FilePath ".\InstanceIP.txt" -Force

<# ScriptBlock to test port 22 on the new instance and loop if unsuccessful. #>
$TestSSH = {
    $InstanceIP = Get-Content -Path ".\InstanceIP.txt" | Select-Object -First 1
    while ((Test-NetConnection $InstanceIP -Port 22).TcpTestSucceeded -ne $True) {
        Write-Host "Waiting for host SSH."
        Start-Sleep -Seconds 5
    }
}

Load $TestSSH "Waiting for host SSH"

<# Get Administrator password from AWS #>
$SSHPass = Get-EC2PasswordData -AccessKey $Config['AWS_AccessKey'] -SecretKey $Config['AWS_SecretKey'] -Region $Config['AWS_Region'] `
    -InstanceId $NewInstance.Instances[0].InstanceId `
    -PemFile ".\$($InstanceName)Key.pem"

$SSHPass | Out-File -Encoding ascii -FilePath ".\SSHPass.txt" -Force

Write-Host "Administrator Password: $($SSHPass)`n"

Write-Host "Uploading setup script to new instance."
Start-Process ".\utils\kscp.exe" "-pw $($SSHPass) -auto-store-sshkey .\scripts\HostSetup.ps1 Administrator@$($InstanceIP):C:" -NoNewWindow -Wait

Write-Host "Connecting to new instance via SSH in 5 seconds."
Start-Sleep -Seconds 5
.\utils\ssh.exe -o "StrictHostKeyChecking=no" -o "PermitLocalCommand=yes" -o "LocalCommand=cls" -l Administrator -i .\$($InstanceName)Key.pem $($InstanceIP) -t pwsh C:\HostSetup.ps1

Write-Host "`nCloud Rig setup complete."
Write-Host "Connect via Instance IP: $InstanceIP"

cmd /c pause | Out-Null