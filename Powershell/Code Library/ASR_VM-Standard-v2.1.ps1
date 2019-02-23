################################Vm standardization Script ################

##    Created by: Mohammad Zafar Khan, mohammk@microsoft.com 
##    Summary: This script enables below standards things: 
##             Apply standards to NICs, OS Disk, Data disk, Enable HUB, Managed disk conversion

##    Input Required: Resource Group, VM Name, Storage details, Subscriptions

##    Note: Please ensure that VMs are backed up before running this script

# V 2.1: Fixed the multiple nic issues, Enabled the cleanup activities for the old resources


########################################################################



param(
        
    [Parameter(mandatory = $True, HelpMessage="Enter the Azure subscription Id")]
    [String] $SubID,

    [Parameter(Mandatory=$True, HelpMessage="Enter an existing resource group name.")]
    [String] $ResourceGroupName,

    [Parameter(Mandatory=$True, HelpMessage="Enter Vm Name.")]
    [String] $vmName,

    [Parameter(mandatory = $True, HelpMessage="Enter the Storage Type. StandardLRS / PremiumLRS")]
    [ValidateSet("Standard_LRS", "Premium_LRS")]
    [String] $storageType = 'Premium_LRS',

    [Parameter(mandatory = $True, HelpMessage="Please confirm if old resources should be cleaned after being converted or corrected.")]
    [Boolean] $Cleanup = $False,

    [Parameter(Mandatory=$True, HelpMessage="Enter New Vm Name.")]
    [String] $vmNamenew

    )


Login-AzureRmAccount -SubscriptionId $SubId



#region Log the runbook initiator
Write-Output "[$(get-date -Format HH:mm:ss)] Script initiated" 
$starttime = get-date
#endregion


#region Retrieving Variables

write-output "[$(get-date -Format HH:mm:ss)] Retrieving variables"
$location = (get-azurermresourcegroup -Name $ResourceGroupName).location

#endregion


#region Retrieve current Virtual Machine information

write-output "[$(get-date -Format HH:mm:ss)] Retrieving information about VM [$vmName]"
try {
$currentvm = Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $vmname
} catch {
    write-error $_
    break
}

$nicids = $currentvm.NetworkProfile.NetworkInterfaces.id
$osdisk = $currentvm.StorageProfile.OsDisk
$datadisks = $currentvm.StorageProfile.Datadisks
$vmSize = $currentvm.HardwareProfile.VmSize


if ($currentvm.StorageProfile.OsDisk.OsType -eq 'Windows') { 
    write-output "[$(get-date -Format HH:mm:ss)] Windows Virtual Machine [$VmName] detected with VM size [$Vmsize]"
    $OStype = 'Windows' 
}
else { 
    write-output "[$(get-date -Format HH:mm:ss)] Linux Virtual Machine detected [$($currentvm.StorageProfile.OsDisk.OsType)]"
    $OStype = 'Linux' 
}

#endregion


#region Validate the existing VM for standards

$VMstandard = $true

# check osdisk
if ($osdisk.ManagedDisk -eq $null) {
    write-output "[$(get-date -Format HH:mm:ss)] [Verify] No Managed Disk - OS-Disk will be converted"
    $VMstandard = $false
}
elseif ($osdisk.Name -ne "$vmname-osdisk") {
    write-output "[$(get-date -Format HH:mm:ss)] [Verify] Incorrect Managed Disk Name - OS-Disk will be converted"
    $VMstandard = $false
}
if ($osdisk.ManagedDisk.StorageAccountType -ne $storageType) {
    Write-output "[$(get-date -Format HH:mm:ss)] [Verify] Incorrect Storage Type - OS-disk [$($osdisk.Name)] will be converted to [$storageType] Storage"
    $VMstandard = $false
}

# check datadisk
foreach ($ddisk in $datadisks) { 
    if ($ddisk.ManagedDisk -eq $null) {
        write-output "[$(get-date -Format HH:mm:ss)] [Verify] No Managed Disk - Data-disk [$($ddisk.Name)] attached to LUN [$($ddisk.LUN)] will be converted"
        $VMstandard = $false
    }
    elseif ($ddisk.Name -notlike "$vmname-datadisk*") {
        write-output "[$(get-date -Format HH:mm:ss)] [Verify] Incorrect Managed Disk Name -  Data-disk [$($ddisk.Name)] attached to LUN [$($ddisk.LUN)] will be converted"
        $VMstandard = $false
    }
    if ($ddisk.ManagedDisk.StorageAccountType -ne $storageType) {
        Write-output "[$(get-date -Format HH:mm:ss)] [Verify] Incorrect Storage Type - Data-disk [$($ddisk.Name)] will be converted to [$storageType] Storage"
        $VMstandard = $false
    }
}

# check HUB licensing benefits for Windows Servers (Windows_Server)
if (($currentvm.LicenseType -eq $null) -and ($OStype -eq 'Windows')) {
    write-output "[$(get-date -Format HH:mm:ss)] [Verify] HUB license benefits are not enabled - and will be enabled"
    $VMstandard = $false
}

#endregion Validate


#region Rebuild Virtual Machine
if ($VMstandard -eq $false) {

    #region Stop and Remove Virtual Machine

    # Stop Azure-VM
    write-output "[$(get-date -Format HH:mm:ss)] Deallocating (stopping) Virtual Machine [$vmName]"
    $null = Stop-AzureRmVM -Name $vmname -ResourceGroupName $ResourceGroupName -Force

    # Remove Current VM
    write-output "[$(get-date -Format HH:mm:ss)] Removing Virtual Machine [$vmName]"
    $null = Remove-AzureRmVM -Name $vmname -ResourceGroupName $ResourceGroupName -Force

    #endregion

    #region Build New Virtual Machine

    $vmName= $vmNamenew
    # Build New Virtual Machine Configuration
    write-output "[$(get-date -Format HH:mm:ss)] Rebuilding Configuration of Virtual Machine [$vmName] with size [$vmSize]"
    $vmConfig = New-AzureRmVMConfig -VMName $vmname -VMSize $vmsize

        
    # Rename / Rebuild / Add NIC's to the Virtual Machine
     $niccount = 0
     $i = 1
    foreach ($nicid in $nicids) {
        $NICName = $nicid.Split('/') | select -last 1
        if ($NICname -notlike "$vmname-nic-0$($i)") {
            $IPConfiguration = (Get-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName).IpConfigurations
            $NICIPAddress = $IPConfiguration.privateIpAddress
             
            # Remove incorrectly named NIC
            write-output "[$(get-date -Format HH:mm:ss)] Removing NIC with name [$NICname]"
            Remove-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Force

            # Rebuild NIC with correct name
            write-output "[$(get-date -Format HH:mm:ss)] Creating NIC with name [$vmname-nic-0$i] using the same settings as [$NICname]"
            $newnic = New-AzureRmNetworkInterface -Name "$vmname-nic-0$($i)" -ResourceGroupName $ResourceGroupName -Location $location -IpConfiguration $IPConfiguration -Force -Confirm:$false
            $newnic.IpConfigurations[0].PrivateIpAllocationMethod = 'Static'
            $newnic.IpConfigurations[0].PrivateIpAddress = $NICIPAddress
            $null = Set-AzureRmNetworkInterface -NetworkInterface $newnic
            $nicid = $newnic.Id
        }
        
        # Add NIC's back to the Virtual Machine
        write-output "[$(get-date -Format HH:mm:ss)] Attaching NIC [$($nicid.split('/') | select -last 1)] to Virtual Machine [$vmname]"
        $vmConfig = Add-AzureRmVMNetworkInterface -VM $vmConfig -Id $nicid
        $niccount++
        $i++
    }


     if ($niccount -gt 1) { 
    write-output "[$(get-date -Format HH:mm:ss)] Detected multiple Nics. Setting NIC [$($nicids[0].split('/') |select -last 1) ] as Primary]"
    $vmConfig.NetworkProfile.NetworkInterfaces.Item(0).Primary = $true 
    
    }
    
    
  #region Correct or Rebuild the OS Disk

    # Not Managed Disks
    if ($osdisk.ManagedDisk -eq $null) {
        # convert os disk to managed disks
        write-output "[$(get-date -Format HH:mm:ss)] Converting OS-disk [$($osdisk.Name)] to Managed disk [$vmname-osdisk]"
        $newOsDisk = New-AzureRmDisk -DiskName "$Vmname-osdisk" `
                                  -Disk (New-AzureRmDiskConfig -AccountType $storagetype -Location $location -CreateOption Import -SourceUri $osdisk.Vhd.Uri) `
                                  -ResourceGroupName $resourceGroupName

        # attach os disk to new VM
        write-output "[$(get-date -Format HH:mm:ss)] Attaching OS-disk [$($newOsDisk.name)] to Virtual Machine [$vmname]"
        if ($OStype -eq 'Windows') {
            $vmConfig = Set-AzureRmVMOSDisk -VM $vmConfig -ManagedDiskId $newOsDisk.Id -StorageAccountType $storagetype -CreateOption Attach -Windows
        }
        if ($OStype -eq 'Linux') {
            $vmConfig = Set-AzureRmVMOSDisk -VM $vmConfig -ManagedDiskId $newOsDisk.Id -StorageAccountType $storagetype -CreateOption Attach -Linux
        }
    }
    # Managed Disks
    else {
        # Naming convention correct
        if ($osdisk.Name -eq "$Vmname-osdisk") {
            # Check if StorageType is correct, if not correct it
            if ($osdisk.ManagedDisk.StorageAccountType -ne $storageType) {
                write-output "[$(get-date -Format HH:mm:ss)] Converting OS-disk [$($osdisk.Name)] to storage type [$storageType]"
                $osdiskconfig = New-AzureRmDiskUpdateConfig -AccountType $storageType
                $null = Update-AzureRmDisk -ResourceGroupName $ResourceGroupName -DiskName $osdisk.Name -DiskUpdate $osdiskconfig
            }       
            
            # attach os disk to new VM
            write-output "[$(get-date -Format HH:mm:ss)] Attaching OS-disk [$($osdisk.Name)] to Virtual Machine [$vmname]"
            $attachosdisk = get-azurermdisk -ResourceGroupName $resourceGroupName -DiskName $osdisk.Name
            if ($OStype -eq 'Windows') {
                $vmConfig = Set-AzureRmVMOSDisk -VM $vmConfig -ManagedDiskId $attachosdisk.Id -StorageAccountType $storagetype -CreateOption Attach -Windows
            }
            if ($OStype -eq 'Linux') {
                $vmConfig = Set-AzureRmVMOSDisk -VM $vmConfig -ManagedDiskId $attachosdisk.Id -StorageAccountType $storagetype -CreateOption Attach -Linux
            }
        }
        # Naming convention not correct
        else {
            write-output "[$(get-date -Format HH:mm:ss)] Rebuilding OS-disk [$($osdisk.Name)] to the use the correct name [$Vmname-osdisk]"
            $newOsDisk = New-AzureRmDisk -DiskName "$Vmname-osdisk" `
                                         -Disk (New-AzureRmDiskConfig -AccountType $storagetype -Location $location -CreateOption Copy -SourceResourceId $osdisk.manageddisk.id) `
                                         -ResourceGroupName $resourceGroupName
            write-output "[$(get-date -Format HH:mm:ss)] Attaching OS-disk [$($newOsDisk.name)] to Virtual Machine [$vmname]"
            if ($OStype -eq 'Windows') {
                $vmConfig = Set-AzureRmVMOSDisk -VM $vmConfig -ManagedDiskId $newOsDisk.Id -StorageAccountType $storagetype -CreateOption Attach -Windows
            }
            if ($OStype -eq 'Linux') {
                $vmConfig = Set-AzureRmVMOSDisk -VM $vmConfig -ManagedDiskId $newOsDisk.Id -StorageAccountType $storagetype -CreateOption Attach -Linux
            }
        }
    }

    #endregion

  #region Correct or Rebuid the Data Disk(s)

    $i = 1
    foreach ($ddisk in $datadisks) {
        # Not Managed Disks
        if ($ddisk.ManagedDisk -eq $null) {
            # convert data disks to managed disks
            write-output "[$(get-date -Format HH:mm:ss)] Converting Data-disk [$($ddisk.Name)] to Managed disk [$vmname-datadisk$($i)]"    
            $NewDataDisk = New-AzureRmDisk -DiskName "$vmname-datadisk$($i)" `
                                           -Disk (New-AzureRmDiskConfig -AccountType $storagetype -Location $location -CreateOption Import -SourceUri ($ddisk.Vhd.Uri)) `
                                           -ResourceGroupName $resourceGroupName

            # attach data disks to new VM
            write-output "[$(get-date -Format HH:mm:ss)] Attaching Data-disk [$($NewDataDisk.Name)] to LUN [$($ddisk.LUN)] on Virtual Machine [$vmname]"
            $vmConfig = Add-AzureRmVMDataDisk -VM $vmConfig -Name "$vmname-datadisk$($i)" -CreateOption Attach -ManagedDiskId $NewDataDisk.Id -Lun $ddisk.LUN

            $i++
        }
        # Managed Disks
        else {
            # Naming convention correct
            if ($ddisk.Name -like "$Vmname-datadisk*") {
                # Check if StorageType is correct, if not correct it
                if ($ddisk.ManagedDisk.StorageAccountType -ne $storageType) {
                    write-output "[$(get-date -Format HH:mm:ss)] Converting Data-disk [$($ddisk.Name)] to storage type [$storageType]"
                    $datadiskconfig = New-AzureRmDiskUpdateConfig -AccountType $storageType
                    $null = Update-AzureRmDisk -ResourceGroupName $ResourceGroupName -DiskName $ddisk.Name -DiskUpdate $datadiskconfig
                }   

                # attach data disk to new VM
                write-output "[$(get-date -Format HH:mm:ss)] Attaching Data-disk [$($ddisk.Name)] to LUN [$($ddisk.LUN)] on Virtual Machine [$vmname]"
                $attachdataDisk = get-azurermdisk -ResourceGroupName $resourceGroupName -DiskName $ddisk.Name
                $vmConfig = Add-AzureRmVMDataDisk -VM $vmConfig -Name $ddisk.Name -CreateOption Attach -ManagedDiskId $attachdataDisk.Id -Lun $ddisk.LUN
            }
            # Naming convention not correct
            else {
                do {
                    try {
                        $checkdatadisk = $null
                        $checkdatadisk = get-azurermdisk -ResourceGroupName $resourceGroupName -DiskName "$vmname-datadisk$($i)" -ErrorAction SilentlyContinue 
                    } catch {}
                    if ($checkdatadisk -ne $null) {$i++}
                } until ($checkdatadisk -eq $null)
                write-output "[$(get-date -Format HH:mm:ss)] Rebuilding Data-disk [$($ddisk.Name)] to the use the correct name [$vmname-datadisk$($i)]"
                $NewDataDisk = New-AzureRmDisk -DiskName "$vmname-datadisk$($i)" `
                                               -Disk (New-AzureRmDiskConfig -AccountType $storagetype -Location $location -CreateOption Copy -SourceResourceId ($ddisk.manageddisk.id)) `
                                               -ResourceGroupName $resourceGroupName
                write-output "[$(get-date -Format HH:mm:ss)] Attaching Data-disk [$($NewDataDisk.Name)] to LUN [$($ddisk.LUN)] on Virtual Machine [$vmname]"
                $vmConfig = Add-AzureRmVMDataDisk -VM $vmConfig -Name "$vmname-datadisk$($i)" -CreateOption Attach -ManagedDiskId $NewDataDisk.Id -Lun $ddisk.LUN          
            }
        }
    }

    #endregion


    # Create the new Virtual Machine
    write-output "[$(get-date -Format HH:mm:ss)] Re-building Virtual Machine [$vmname]"
    try {
        if ($OStype -eq 'Windows') {
            $null = New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $location -VM $vmConfig #-LicenseType 'Windows_Server'
        }
        if ($OStype -eq 'Linux') {
            $null = New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $location -VM $vmConfig -ErrorAction Stop
        }
    } catch {
        Write-Error $_
        Write-Output $vmConfig
        Break
    }

    #endregion
}

if ($VMstandard -eq $true) {
    Write-Warning -Message "[$(get-date -Format HH:mm:ss)] Virtual Machine Configuration already complies, No VM Configuration changes will be made."
}

#endregion


#region Cleanup the old resources
if (($Cleanup -eq $true) -and ($VMstandard -eq $false)) {

     # Cleanup old OS Disk
    if ($osdisk.ManagedDisk -eq $null) {
        # Cleanup old VHD
        $vhdstorageaccount = ($osdisk.Vhd.Uri).split('/').split('.')[2]
        $vhdblob = ($osdisk.Vhd.Uri).split('/') | select -last 1
        $vhdcontainer = (($osdisk.Vhd.Uri).split('/') | select -last 2)[0]
        $vhdresourcegroup = (Find-AzureRmResource -ResourceNameContains $vhdstorageaccount).ResourceGroupName
        $Storagekey = (Get-AzureRmStorageAccountKey -ResourceGroupName $vhdresourcegroup -Name $vhdstorageaccount).Value[0]
        $Storagecontext = New-AzureStorageContext -StorageAccountName $vhdstorageaccount -StorageAccountKey $Storagekey

        write-output "[$(get-date -Format HH:mm:ss)] [Cleanup] Removing old OS Disk [$vhdblob] from Storage Account [$vhdstorageaccount]"
        $Null = Remove-AzureStorageBlob -Blob $vhdblob -Container $vhdcontainer -Context $Storagecontext -Force
    }
    else {
        if ($osdisk.Name -ne "$vmname-osdisk") {
            # Cleanup old Disk
            write-output "[$(get-date -Format HH:mm:ss)] [Cleanup] Removing old Managed OS Disk [$($osdisk.Name)]"
            $Null = Remove-AzureRmDisk -ResourceGroupName $ResourceGroupName -DiskName $osdisk.Name -Force -Confirm:$false
        }
    }

    # Cleanup old Data Disks
    foreach ($ddisk in $datadisks) {
        if ($ddisk.ManagedDisk -eq $null) {
            # Cleanup old VHD
            if ($Cleanup) {
                $vhdstorageaccount = ($ddisk.Vhd.Uri).split('/').split('.')[2]
                $vhdblob = ($ddisk.Vhd.Uri).split('/') | select -last 1
                $vhdcontainer = (($ddisk.Vhd.Uri).split('/') | select -last 2)[0]
                $vhdresourcegroup = (Find-AzureRmResource -ResourceNameContains $vhdstorageaccount).ResourceGroupName
                $Storagekey = (Get-AzureRmStorageAccountKey -ResourceGroupName $vhdresourcegroup -Name $vhdstorageaccount).Value[0]
                $Storagecontext = New-AzureStorageContext -StorageAccountName $vhdstorageaccount -StorageAccountKey $Storagekey

                write-output "[$(get-date -Format HH:mm:ss)] [Cleanup] Removing old OS Disk [$vhdblob] from Storage Account [$vhdstorageaccount]"
                $Null = Remove-AzureStorageBlob -Blob $vhdblob -Container $vhdcontainer -Context $Storagecontext -Force
            }
        }
        else {
            if ($ddisk.Name -notlike "$vmname-datadisk*") {
                # Cleanup old Disk
                write-output "[$(get-date -Format HH:mm:ss)] [Cleanup] Removing old Managed Data Disk [$($ddisk.Name)]"
                $Null = Remove-AzureRmDisk -ResourceGroupName $ResourceGroupName -DiskName $ddisk.Name -Force -Confirm:$false
            }
        }
    }

}
#endregion


#region Completed
$Completed = (get-date) - $starttime
$Output =  "[$(get-date -Format HH:mm:ss)] Script Completed in {0:g}" -f $Completed
Write-Output $Output
#endregion