<#
    .SYNOPSIS
        Run Windows updates on a converted templated and converts back to a template.
    .Description
        Send the function the name of the template to convert from a template to a virtual machine. Pass key vSphere
        information like the vCenter and credentials. This function will require the local administrator account name
        and password. This is to log into the VM and run the necessary scripts to launch Windows Updates. The $longtimer
        value is how long to keep the VM up and running to download updaes.After Windows Updates have been installed,
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
        Log name and location
    .PARAMETER vCPU
        Number of vCPUs to assign to the VM
    .PARAMETER longtimer
        The number of seconds to keep the VM up to download updates
        The default is 3600 seconds which is 1 hour
#>
Param(
    [string]$vCenterInstance = "192.168.2.200",
    [string]$vCenterUser = "administrator@vsphere.local",
    [string]$vCenterPasss = "VMware1!",
    [string]$template,
    [string]$GuestUser = "Administrator",
    [string]$GuestPwd  = "VMware1!",
    [string]$WSLog = "C:\PSWindowsupdate.log",
    [int]$vCPU = 4,
    [int]$longtimer = 3600 # time to leave VM up to download Windows Updates
)

$StartDTM = (Get-date)

cd $PSScriptRoot  # Change directory from which script is running

find-module -name vmware.powercli
$password = $vCenterPasss | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object -TypeName pscredential -ArgumentList $vCenterUser,$password
Connect-VIServer -Server $vCenterInstance -Credential $credential

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
sleep 15

Write-host "Installing NuGet package" -ForegroundColor Green
Invoke-VMScript -ScriptType PowerShell -ScriptText "Install-PackageProvider Nuget -force" -VM $template -GuestUser $GuestUser -GuestPassword $GuestPwd -Verbose | Out-File $WSLog -Append
cls

Write-host "Installing PSWindowsUpdate" -ForegroundColor Green
Invoke-VMScript -ScriptType PowerShell -ScriptText "Import-Module PowerShellGet; Sleep 10; Install-Module -Name PSWindowsUpdate -force" -VM $template -GuestUser $GuestUser -GuestPassword $GuestPwd -Verbose | Out-File $WSLog -Append
cls

Write-Host "Installing Windows Updates" -ForegroundColor Green
Invoke-VMScript -ScriptType Powershell -ScriptText "Get-WindowsUpdate -MicrosoftUpdate -install -acceptall -autoreboot" -VM $template -GuestUser $GuestUser -GuestPassword $GuestPwd -Verbose | Out-File $WSLog -Append
cls

Write-Host "$template is up and will wait 2 hours for updates to be installed." -ForegroundColor Green

#long timer here
#Start-sleep -Seconds 3600

$longtimer..0 | foreach { echo $_ | Out-File $WSLog -Append; start-sleep -seconds 1; cls; }
  
Write-Output "Performing final reboot of $template"    
Restart-VMGuest -VM $template -Confirm:$false

.\RebootFunction.ps1 -hostname $template

# Record when Windows Update Ran in the Notes field
Write-host "Recording in Notes field the date this template was updated." -ForegroundColor Green
$today = (get-date).tostring('M/d/y')
set-vm -vm "Windows 2016" -Notes "Windows Update last ran on $today." -Confirm:$false | Out-File $WSLog -Append

#Shutdown the server, reset vCPU count and convert it back to Template.
write-host "Shutdown the  server and take back vCPU." -foregroundcolor green
shutdown-VMGuest –VM $template -Confirm:$false
do { $vmstatus = (get-vm $template).PowerState ; Start-Sleep -Seconds 5} while ($vmstatus -ne "PoweredOff")
write-host "Server powered off. Will reset vCPU count to 1" -foregroundcolor green
Set-VM -VM $template -NumCpu 1 -Confirm:$false
Start-Sleep -Seconds 15
Write-Host "vCPU count reset. Now converting to template" -ForegroundColor Green
Set-VM –VM $template -ToTemplate -Confirm:$false
write-host "Job Completed!" -ForegroundColor Green

$EndDTM = (Get-date)
Write-Verbose "Elapse time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapse time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose