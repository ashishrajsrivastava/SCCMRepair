﻿# ================================================================================================
# NAME: SCCMRepair.ps1
# AUTHOR: Ashish Raj, azuredevopspro.com
# VERSION: 1906
# COMMENTS: This script repair uninstall the SCCM Client, Repair the WMI Repository 
# and notify to admin via email
# Don't forget to download WMIRepair and configure the script (see above)
# PowerShell 3.0 require
# The WMIRepair.exe require .NET Framework 3.5
# LICENSE: MIT License
# ================================================================================================

# Relaunch as an elevated process
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-File", ('"{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
    exit
}

# ================================================================================================
#
# Parameters - Must match your infrastructure
#
$PathScript = Split-Path -Parent $PSCommandPath # Path of the current script
$LocalSCCMClient = "C:\Windows\ccmsetup\ccmsetup.exe" # Path of the Source of SCCM Client (on local computer)
$RemoteSCCMClient = "C:\Windows\ccmsetup\ccmsetup.exe" # Path of the Source of SCCM Client (from Server)
$NewSCCMClientLocation = "C:\NewccmsetupMedia"
$SCCMSiteCode = "LAB" # SCCM Site Code
$wmiRepair = "$PathScript\wmirepair.exe"

$smtpServer = "smtp.office365.com"
$smtpusername = "yoursmtpusername@abc.com"
$smtppassword = "YourSMTPPassword" | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object pscredential($smtpusername, $smtppassword)
$smtpFrom = "from@abc.com"
$smtpTo = "to@abc.com"
$messageSubject = "SCCM Uninstalled on $env:COMPUTERNAME"
#
# Please put WMIRepair.exe and WMIRepair.exe.config in the same folder of this script
# It can be downloaded from https://sourceforge.net/projects/smsclictr/files/latest/download
# The files are under <ZIP File>\Program Files\Common Files\SMSCliCtr
# The sources was from SCCM Client Center by Roger Zander (Grüezi Roger !)
#
# ================================================================================================

# Get the current ccmsetup.exe to diffenerent location 
Write-Host "Copy ccmsetup.exe from $LocalSCCMClient to $NewSCCMClientLocation"
Copy-Item -Path $RemoteSCCMClient -Destination (New-Item -Path $NewSCCMClientLocation -ItemType Directory -Force) -ErrorAction SilentlyContinue


If (Test-Path $LocalSCCMClient -ErrorAction SilentlyContinue) {
    # Uninstall the SCCM Client
    Write-Host "Removing SCCM Client..."
    Start-Process -FilePath $LocalSCCMClient -ArgumentList "/uninstall" -Wait
}
 
# Stop Winmgmt
Write-Host "Stopping WMI Service..."
Set-Service Winmgmt -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service Winmgmt -Force -ErrorAction SilentlyContinue
 
# Sleep 10 for WMI Stop
Write-Host "Waiting 10 seconds..."
Sleep -Seconds 10
 
# Remove old backup
If (Test-Path C:\Windows\System32\wbem\repository.old -ErrorAction SilentlyContinue) {
    Write-Host "Removing old Repository backup..."
    Remove-Item -Path C:\Windows\System32\wbem\repository.old -Recurse -Force -ErrorAction SilentlyContinue
}
 
# Rename the existing repository directory.
Write-Host "Renaming the Repository..."
Rename-Item -Path C:\Windows\System32\wbem\repository -NewName 'Repository.old' -Force -ErrorAction SilentlyContinue

# Start WMI Service, this action reconstruct the WMi Repository
Write-Host "Starting WMI Service..."
Set-Service Winmgmt -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service Winmgmt -ErrorAction SilentlyContinue
 
# Sleep 10 for WMI Startup
Write-Host "Waiting 10 seconds..."
Sleep -Seconds 10

# Start other services
Write-Host "Starting IP Helper Service..."
Start-Service iphlpsvc -ErrorAction SilentlyContinue
Write-Host "Starting WMI Service..."
Start-Service Winmgmt -ErrorAction SilentlyContinue
 
# Sleep 1 Minute to allow the WMI Repository to Rebuild
Write-Host "Waiting 1 Minute for rebuild the Repository..."
Sleep -Seconds 60
 
# Run WMIRepair.exe
Write-Host "Starting WMIRepair..."
Start-Process -FilePath $wmiRepair -ArgumentList "/CMD" -Wait
 
# Clear ccmsetup folder
Write-Host "Clean local ccmsetup folder..."
Remove-Item -Path C:\Windows\ccmsetup\* -Recurse -ErrorAction SilentlyContinue

# Get the current ccmsetup.exe from the Site Server
#Write-Host "Copy a fresh copy of ccmsetup.exe from Site Server..."
#Copy-Item -Path $RemoteSCCMClient -Destination (New-Item -Path $NewSCCMClientLocation -ItemType Directory -Force) -ErrorAction SilentlyContinue

# Sleep 10 seconds to allow the WMI Repository to Rebuild
Write-Host "Waiting 10 seconds for rebuild the Repository..."
Sleep -Seconds 10

#Notify with email
if (Test-Path -Path $NewSCCMClientLocation) {
    Write-Host "Successfully copied ccmsetup.exe to $NewSCCMClientLocation and uninstalled ccm client"
    $htmlbody = @" 
<html> 
<body style="font-family:verdana;font-size:13"> 
Hello Team<br> 
<span style="color:red;font-family:calibri;font-size:15">SCCM Client on machine $env:COMPUTERNAME has been uninstalled!</span> <br> <br> 
Thanks, <br> 
Exchange Team. 
</body> 
</html> 
"@ 

    Send-MailMessage -Body $htmlbody -Subject $messagesubject -To $smtpTo -From $smtpFrom -SmtpServer $smtpServer -Credential $cred -UseSsl -BodyAsHtml
    # $smtp = New-Object Net.Mail.SmtpClient($smtpServer)
    # $smtp.Send($smtpFrom,$smtpTo,$messagesubject,$htmlbody)
}

# Install the client
Write-Host "Install SCCM Client on Site Code:$SCCMSiteCode..." 
Start-Process -FilePath $$NewSCCMClientLocation = "C:\NewccmsetupMedia\ccmsetup.exe" -ArgumentList "smssitecode=$SCCMSiteCode" -Wait

$SCCMInstallTime = Get-Item -Path C:\Windows\ccmsetup\ccmsetup.cab | Select-Object -Property CreationTime
Write-Host "SCCM Client Installed on $SCCMInstallTime"
#Notify with email for install
if (Test-Path -Path $LocalSCCMClient) {
    Write-Host "Successfully copied ccmsetup.exe to $LocalSCCMClient and installed ccm client"
    $htmlbody = @" 
<html> 
<body style="font-family:verdana;font-size:13"> 
Hello Team<br> 
<span style="color:red;font-family:calibri;font-size:15">SCCM Client on machine $env:COMPUTERNAME has been installed!</span> <br> <br> 
Thanks, <br> 
Exchange Team. 
</body> 
</html> 
"@ 

    Send-MailMessage -Body $htmlbody -Subject $messagesubject -To $smtpTo -From $smtpFrom -SmtpServer $smtpServer -Credential $cred -UseSsl -BodyAsHtml
    # $smtp = New-Object Net.Mail.SmtpClient($smtpServer)
    # $smtp.Send($smtpFrom,$smtpTo,$messagesubject,$htmlbody)
}