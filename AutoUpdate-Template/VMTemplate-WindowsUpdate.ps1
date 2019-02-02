<#
    .SYNOPSIS
        Run Windows updates on a converted templated to virtual machine.
    .Description
        Send the function the name of the template to convert from a templae to a virtual machine.  Power on
        the converted virtual machine and run Windows Updates on the image. After Windows Updates have been installed,
        power off the VM and convert it back into a template.

    .NOTES Author:  Aaron Strong
    .NOTES Site:    www.theaaronstrong.com
    .NOTES Twitter  @theaaronstrong

    .PARAMETER vCenter
        Name or IP address of the vCenter
    .PARAMETER vCenterUser
        Username to log into the vCenter
    .PARAMETER vCenterPass
        Password to use with the username to log into vCenter
    .PARAMETER template
        Name of the template to convert and run Windows Updates
    .PARAMETER GuestUser
        Local account for the template
    .PARAMETER GuestPwd
        Local account password for the template
    .PARAMETER WSLog
        Log name
#>


#cd $PSScriptRoot  # Change directory from which script is running


Param(
    [string]$vCenterInstance = "192.168.2.200",
    [string]$vCenterUser = "administrator@vsphere.local",
    [string]$vCenterPasss = "VMware1!",
    [string]$template = "T-2016",
    [string]$GuestUser = "Administrator",
    [string]$GuestPwd  = "VMware1!",
    [string]$WSLog = "C:\PSWindowsupdate.log",
    [int]$vCPU = 4
)
$StartDTM = (Get-date)

find-module -name vmware.powercli
Connect-VIServer $vCenterInstance  -User $vCenterUser -Password $vCenterPass -WarningAction SilentlyContinue

# Convert Template
Write-host "Converting $template template to VM" -ForegroundColor Green
$task = Set-Template -Template $template -ToVM
Wait-Task -Task $task

# Add additional hardware
Write-Host "Adding $vCPU CPU to $template" -ForegroundColor Green
Set-VM $template -NumCpu $vCPU -Confirm:$false


# Start VM
Write-host "Powering on $template" -ForegroundColor Green
Start-VM $template -Confirm:$false

.\RebootFunction.ps1 -hostname $template

Write-host "Wait for VM to settle" -ForegroundColor Green
sleep 60

#Write-host "Set Repository" -ForegroundColor Green
#Invoke-VMScript -ScriptType PowerShell -ScriptText "Set-PSRepository -name PSGallery -InstallationPolicy Trusted -force" -VM $template -GuestUser $GuestUser -GuestPassword $GuestPwd -Verbose | Out-File $WSLog -Append
#cls

Write-host "Installing NuGet package" -ForegroundColor Green
Invoke-VMScript -ScriptType PowerShell -ScriptText "Install-PackageProvider Nuget -force" -VM $template -GuestUser $GuestUser -GuestPassword $GuestPwd -Verbose | Out-File $WSLog -Append
#cls

Write-host "Installing PSWindowsUpdate" -ForegroundColor Green
Invoke-VMScript -ScriptType PowerShell -ScriptText "Import-Module PowerShellGet; Sleep 10; Install-Module -Name PSWindowsUpdate -force" -VM $template -GuestUser $GuestUser -GuestPassword $GuestPwd -Verbose | Out-File $WSLog -Append
#cls

Write-Host "Installing Windows Updates" -ForegroundColor Green
Invoke-VMScript -ScriptType Powershell -ScriptText "Get-WindowsUpdate -MicrosoftUpdate -install -acceptall -autoreboot" -VM $template -GuestUser $GuestUser -GuestPassword $GuestPwd -Verbose | Out-File $WSLog -Append
#Cls

Write-Host "$template is up and will wait 2 hours for updates to be installed." -ForegroundColor Green

#long timer here
Start-sleep -Seconds 300

#Restart VMGuest one more time in case Windows Update requires it and for whatever reason the –AutoReboot switch didn’t complete it.  
  
Write-Output "Performing final reboot of $template"  
  
Restart-VMGuest -VM $template -Confirm:$false  

#Shutdown the server, reset vCPU count and convert it back to Template.
write-host "30 minutes have passed. We will shutdown the  server, and take back a vCPU." -foregroundcolor green
shutdown-VMGuest –VM $template -Confirm:$false
Wait-VMPowerState -VMName $template -Operation Down | Out-Null
write-host "Server powered off. Will reset vCPU count to 1" -foregroundcolor green
Set-VM $templates -NumCpu 1 -Confirm:$false
Start-Sleep -Seconds 15
Write-Host "vCPU count reset. Now converting to template" -ForegroundColor Green
Set-VM –VM $template -ToTemplate -Confirm:$false
write-host "job done!" -ForegroundColor Green


$EndDTM = (Get-date)
Write-Verbose "Elapse time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapse time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose