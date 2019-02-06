Param(
    [Parameter(Mandatory=$true)][string]$hostname,
    [int]$timeToWait = 5
)


# +------------------------------------------------------+
# |        Load VMware modules if not loaded             |
# +------------------------------------------------------+

if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
    if (Test-Path -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI' ) {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI'
       
    } else {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\VMware, Inc.\VMware vSphere PowerCLI'
    }
    . (join-path -path (Get-ItemProperty  $Regkey).InstallPath -childpath 'Scripts\Initialize-PowerCLIEnvironment.ps1')
}
if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
    Write-Host "VMware modules not loaded/unable to load"
    Exit 99
}



    write-host “Waiting for VM Tools to stop” -ForegroundColor Yellow
    do {
    $toolsStatus = (Get-VM $hostname | Get-View).Guest.ToolsStatus
    write-host $toolsStatus
    sleep $timeToWait
    } until ( $toolsStatus -ne ‘toolsOk’ )

    # ---- Wait for computer to come back ---#
    write-host “Waiting for VM to Start” -ForegroundColor Yellow
    do {
    $vmCheck = get-view -ViewType VirtualMachine -property Name,Guest -Filter @{"name"="$hostname"}
    write-host $vmCheck.Guest.GuestOperationsReady
    sleep $timeToWait
    } until ( $vmCheck.Guest.GuestOperationsReady -eq ‘False’ )

