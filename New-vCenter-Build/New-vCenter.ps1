Function Add_License_to_vCenter {
 
    # Get value passed to function
    $LicKey = $args[0]
     
    # add PowerCLI snapins
    add-PSSnapin VMware.VimAutomation.Core
    add-PSSnapin VMware.VimAutomation.License
     
    # Connect to vCenter
    Connect-VIServer $DefaultVIServer -user $vcuser -password $vcpass
     
    #Add Licenses
    $VcLicMgr=$DefaultVIServer
    $LicMgr = Get-View $VcLicMgr
    $AddLic= Get-View $LicMgr.Content.LicenseManager
     
    $AddLic.AddLicense($LicKey,$null)
     
    # Disconnect from vCenter
    Disconnect-VIServer -Confirm:$false
     
    }

# ------vSphere Targeting Variables tracked below------#
$vCenterInstance = "192.168.2.200"            # vCenter address
$vCenterUser = "administrator@vsphere.local"   # vCenter Username
$vCenterPass = "VMware1!" # vCenter Password
$esxHosts = @("192.168.2.205","192.168.2.206") # ESXi Hosts separate with comma if multiples
$dataCenter = "MyDatacenter"  #Name of the new Datacneter
$clusterName = "HomeCluster"  #Name of the new Cluster
$vcenterName = "VMware vCenter Server Appliance"
$license = "3N48N-JYH0N-D8V81-0T182-2NU36"

# This section logs on to the defined vCenter instance above
find-module -name vmware.powercli
Connect-VIServer $vCenterInstance -User $vCenterUser -Password $vCenterPass -WarningAction SilentlyContinue

$location = Get-Folder -NoRecursion
$esxcred = Get-Credential

# Create new Datacenter and Cluster
New-Datacenter -Location $location -Name $dataCenter
New-Cluster -Location $dataCenter -Name $clusterName

# Add ESXi hosts to new Cluster
foreach ($esx in $esxHosts){
    Write-Host "Adding ESXi Host $esx to cluster $clusterName" -ForegroundColor Green
    Add-VMHost -Name $esx -Location (get-cluster $clusterName) -Credential $esxcred -RunAsync -Confirm:$false -force -WarningAction Ignore
}

# Set the Startup Policy for vCenter
$vmstartpolicy = Get-VMStartPolicy -VM $vcenterName
if($vmstartpolicy.StartAction -ne "PowerOn"){
    $vmhost = Get-VM -name "$vcenterName"
    Get-VMHostStartPolicy -VMHost ($vmhost.VMHost) | Set-VMHostStartPolicy -Enabled $true
    Set-VMStartPolicy -StartPolicy $vmstartpolicy -StartAction PowerOn -StartOrder 1
}

# Rename local datastore
foreach ($esxHost in $esxHosts){
    $dsName = "$esxHost-local"
    Get-vmhost -name $esxHost | Get-Datastore -Name datastore* | Set-Datastore -Name $dsName
}

Add_License_to_vCenter ($license)

# Create Distributed Switch and Port Groups
#  Variables for the vDSwitch
$vdsName = "VDS-01"
$mtu = "9000"
$numUplinks = "2" # Number of uplinks associated to host
#  Variables for PortGroups
$storage_pg1 = "VPG-100-iSCSI-1"
$storage_pg2 = "VPG-100-iSCSI-2"
$lab_pg = "VPG-110-LAB"
$mgmt_pg = "VPG-Management"
$vmotion_pg = "VPG-90-vMotion"
# Set the iSCSI target. Separate by command enclosed with quotes.
$iscsiTargets = "192.168.100.99"


#  Create new vDSwitch
Write-Host "Creating new Virtual Distributed Switch"
New-VDSwitch -Name $vdsName -Location (Get-Datacenter -Name $dataCenter) -Mtu $mtu -LinkDiscoveryProtocol LLDP -LinkDiscoveryProtocolOperation Listen -NumUplinkPorts $numUplinks | Out-Null
#   Create new Port Groups
Write-Host "Create Portgroup $storage_pg1"
Get-VDSwitch -Name $vdsName | New-VDPortgroup -Name $storage_pg1 -VlanId 100 | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort "dvUplink1" -UnusedUplinkPort "dvUplink2" | Out-Null

Write-Host "Create Portgroup $storage_pg2"
Get-VDSwitch -Name $vdsName | New-VDPortgroup -Name $storage_pg2 -VlanId 100 | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort "dvUplink2" -UnusedUplinkPort "dvUplink1" | Out-Null

Write-Host "Create Portgroup $lab_pg"
Get-VDSwitch -Name $vdsName | New-VDPortgroup -Name $lab_pg -VlanId 110 | Out-Null

Write-Host "Create Portgroup $mgmt_pg"
Get-VDSwitch -Name $vdsName | New-VDPortgroup -Name $mgmt_pg | Out-Null

Write-Host "Create Portgroup $vmotion_pg"
Get-VDSwitch -Name $vdsName | New-VDPortgroup -Name $vmotion_pg | Out-Null


foreach($esxHost in $esxHosts){
    # Create the new VDS and first swing one leg and the the second leg
    $vs = Get-VDSwitch -Name $vdsName
    # Add ESXi host to vDS
    Write-host "Adding host $esxHost to $vdsName"
    Get-VDSwitch -Name $vdsName | Add-VDSwitchVMHost -VMHost $esxHost | Out-Null

    <#
    #  Swing first pNic leg
    $pNic1 = get-vmhost $esxHost | Get-VMHostNetworkAdapter -Physical -Name vmnic1
    $vmk0 = Get-VMHostNetworkAdapter -VMHost $esxHost -name vmk0
    $vdPortgroupManagement = Get-VDPortgroup -VDSwitch $vdsName -Name $mgmt_pg
    Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vdsName -VMHostPhysicalNic $pNic1 -VMHostVirtualNic $vmk0 -VirtualNicPortgroup $vdPortgroupManagement -Confirm:$false

    #  Migrate any guest VMs and set their network
    foreach($vm in (get-vmhost -Name $esxHost | get-vm)){
        Get-NetworkAdapter $vm | %{ Write-Host "Setting adapter" $_.NetworkName on $vm $_ | Set-NetworkAdapter -PortGroup (Get-VDPortGroup -Name $mgmt_pg -VDSwitch $vdsName) -Confirm:$false
        }
    }

    #  Swin second pNic leg
    $pNic1 = get-vmhost $esxHost | Get-VMHostNetworkAdapter -Physical -Name vmnic0
    Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vdsName -VMHostPhysicalNic $pNic1 -VMHostVirtualNic $vmk0 -VirtualNicPortgroup $vdPortgroupManagement -Confirm:$false
    #>

    # Migrate vmk0 to VDS
    #$dvportgroup = Get-VDPortgroup -name $mgmt_portgroup -VDSwitch $vdsName
   # $vmk = Get-VMHostNetworkAdapter -Name vmk0
    #Set-VMHostNetworkAdapter -PortGroup $dvportgroup -VirtualNic $vmk -confirm:$false | Out-Null

    # Create VMKernel
    $iscsiIP1 = "192.168.100.10"
    $iscsiIP2 = "192.168.100.11"
    $subnetMask = "255.255.255.0"
    $vmotionIP = "192.168.90.10"
    $labIP = "192.168.110.10"
    $vmhost = $esxHosts

    $vs = Get-VDSwitch -Name $vdsName
    New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $storage_pg1 -VirtualSwitch $vs -ip $iscsiIP1 -SubnetMask $subnetMask -Mtu 9000
    New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $storage_pg2 -VirtualSwitch $vs -ip $iscsiIP2 -SubnetMask $subnetMask -Mtu 9000
    New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup $vmotion_pg -VirtualSwitch $vs -ip $vmotionIP -SubnetMask $subnetMask
    New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup $lab_pg -VirtualSwitch $vs -ip $labIP -SubnetMask $subnetMask

    # Enable iSCSI Software
    $vmHost = Get-vmhost -Name $esxHost
    Write-Host "Enable Software iSCSI Adapater on host $esxHost"
    Get-VMHostStorage -VMHost $esxHost | Set-VMHostStorage -SoftwareIScsiEnabled $true
    Start-sleep 30  # Give host time to add new adapter
    $vmHost | Get-VMHostStorage -RescanAllHba
    Start-Sleep 30
    $hba = Get-VMHostHba -VMHost $esxHost -Type IScsi
    New-IScsiHbaTarget -IScsiHba $hba -Address $target

    # Add pNic2 to iSCSI PG 1
    $pNic = get-vmhost $esxHost | Get-VMHostNetworkAdapter -Physical -Name vmnic2
    $vmk1 = Get-VMHostNetworkAdapter -VMHost $esxHost -name vmk1
    $vdPortgroupIscsi1 = Get-VDPortgroup -VDSwitch $vdsName -Name $storage_pg1
    Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vdsName -VMHostNetworkAdapter $pNic -VMHostVirtualNic $vmk1 -VirtualNicPortgroup $vdPortgroupIscsi1 -Confirm:$false

    # Add pNic3 to iSCSI PG 2
    $pNic = get-vmhost $esxHost | Get-VMHostNetworkAdapter -Physical -Name vmnic3
    $vmk2 = Get-VMHostNetworkAdapter -VMHost $esxHost -name vmk2
    $vdPortgroupIscsi2 = Get-VDPortgroup -VDSwitch $vdsName -Name $storage_pg2
    Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vdsName -VMHostNetworkAdapter $pNic -VMHostVirtualNic $vmk2 -VirtualNicPortgroup $vdPortgroupIscsi2 -Confirm:$false


}


<#

# Create VMKernel
$iscsiIP1 = "192.168.100.10"
$iscsiIP2 = "192.168.100.11"
$iscsiMask = "255.255.255.0"
$vmotionIP = "192.168.90.10"
$labIP = "192.168.110.10"
$vmhost = $esxHosts

$vs = Get-VDSwitch -Name $vdsName
New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $storage_pg1 -VirtualSwitch $vs -ip $iscsiIP1 -SubnetMask $iscsiMask -Mtu 9000
New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $storage_pg2 -VirtualSwitch $vs -ip $iscsiIP2 -SubnetMask $iscsiMask -Mtu 9000
New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup $vmotion_pg -VirtualSwitch $vs -ip $vmotionIP -SubnetMask $iscsiMask
New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup $lab_pg -VirtualSwitch $vs -ip $labIP -SubnetMask $iscsiMask

# Get the physical adapters to migrate
$pNics = Get-VMHostNetworkAdapter -VMHost $vmhost -Physical
# Get the virtual network adapters to migrate
$vNicManagement = Get-VMHostNetworkAdapter -VMHost $vmhost -Name vmk0
$vNicIscsi1 = Get-VMHostNetworkAdapter -VMHost $vmhost  -Name vmk1
$vNicIscsi2 = Get-VMHostNetworkAdapter -VMHost $vmhost  -Name vmk2
$vNicvMotion = Get-VMHostNetworkAdapter -VMHost $vmhost -Name vmk3
$vNicVMNetwork = Get-VMHostNetworkAdapter -VMHost $vmhost -Name vmk4

# Get the port groups corresponding to the virtual network adapters that you want to migrate to the distributed switch
$vdPortgroupIsci1 = Get-VDPortgroup -VDSwitch $vs -VMHostNetworkAdapter 








foreach ($esxHost in $esxHosts){
    $dvPG = Get-VDPortgroup -Name $mgmt_pg -VDSwitch $vdsName
    $vmk = Get-VMHostNetworkAdapter -Name vmk0
    Set-VMHostNetworkAdapter -PortGroup $dvPG -VirtualNic $vmk -Confirm:$false | Out-Null
}

# Move vmnic0 from VSS to VDS and remove vswitch0
foreach ($vmhost in $esxHosts) {
    $vmhostNetworkAdapter = Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic0
    Get-VDSwitch -Name $vds_name | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
    $vswitch = Get-VirtualSwitch -VMHost $vmhost -Name vSwitch0
    #Remove-VirtualSwitch -VirtualSwitch $vswitch -Confirm:$false
}


# Create iSCSI VMKernel Ports
foreach ($vmhost in $esxHosts) {
    $vs = Get-VDSwitch -Name $vdsName
    #New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $vmotion_portgroup -VirtualSwitch $vs -VMotionEnabled $true
    New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $storage_pg1 -VirtualSwitch $vs -ip $iscsiIP1 -SubnetMask $iscsiMask -Mtu 9000
    New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $storage_pg2 -VirtualSwitch $vs -ip $iscsiIP2 -SubnetMask $iscsiMask -Mtu 9000
    New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup 
    #New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $vsan_portgroup -VirtualSwitch $vs -VsanTrafficEnabled $true
}



# Set the iSCSI target. Separate by command enclosed with quotes.
$iscsiTargets = "192.168.100.99"

# Enable Software iSCSI adapter
foreach ($esxHost in $esxHosts){
    $vmHost = Get-vmhost -Name $esxHost
    Write-Host "Enable Software iSCSI Adapater on host $esxHost"
    Get-VMHostStorage -VMHost $esxHost | Set-VMHostStorage -SoftwareIScsiEnabled $true
    Start-sleep 30  # Give host time to add new adapter
    $vmHost | Get-VMHostStorage -RescanAllHba
    Start-Sleep 30
    $hba = Get-VMHostHba -VMHost $esxHost -Type IScsi

    foreach ($target in $iscsiTargets){
        New-IScsiHbaTarget -IScsiHba $hba -Address $target
    }
}

#>
