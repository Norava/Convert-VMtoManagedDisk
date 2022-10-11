
    <#
    .SYNOPSIS
        Converts all disks on a Azure Stack Hub Virtual machine from Unmanaged Disks to Managed Disks and automates VM deletion and recreation

    .PARAMETER AADTenantName
        AAD Tenant Name for Stamp. Exclusive from flag -ADFS

    .PARAMETER ADFS
        Indicates the Stamp is an ADFS authentication based stamp. Exclusive from flag -AADTenantName

    .PARAMETER FQDN
        Fullly qualified domain name for a Stack Hub stamp

    .PARAMETER OutReport
        Folder to save VM Report to

    .PARAMETER VMName
        The VM's name in the Azure Stack Portal

    .EXAMPLE
        PS> Convert-VMtoManagedDisks.ps1

    .EXAMPLE
        PS> Get-AZSSupportVM

    #>

    [CmdletBinding(DefaultParameterSetName="Default")]
param(

     
    [Parameter(Mandatory=$True, ValueFromPipeline=$false, ParameterSetName="AAD")]
    $AADTenantName,

    [Parameter(Mandatory=$True, ValueFromPipeline=$false, ParameterSetName="ADFS")]
    [Switch]$ADFS,

    [Parameter(Mandatory=$True, ValueFromPipeline=$false)]
    [string]$FQDN,

    [Parameter(Mandatory=$True, ValueFromPipeline=$false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    $OutReport = "$env:USERPROFILE\Documents",

    [Parameter(Mandatory=$True, ValueFromPipeline=$false)]
    $VMName
        

)

#Check Prereqs are installed
try{Import-Module az -ErrorAction Stop}
Catch [System.IO.FileNotFoundException]{
        Write-Host -ForegroundColor Red -BackgroundColor Black "Az Module for Azure Stack Hub not detected.Please install via https://learn.microsoft.com/en-us/azure-stack/operator/powershell-install-az-module and restart Powershell to continue"
        exit
        }
Catch {
        Write-Warning "Az module failed to load, exiting processing"
        Write-Host -ForegroundColor Red -BackgroundColor Black $Error[0]
        exit
        }
if ($(Get-Module -Name az) -notlike $null ){write-host "Azure az module loaded successfully"}

##Worth checking if AzureRM is installed?

if($(get-module -ListAvailable azurerm*) -notlike $null){
Do{
Write-Warning "AzureRM Module detected as installed on system, issues may occur if module is used alongside az module. Advise removing module before continuning"
$AzureRMContinue = Read-Host -Prompt "Continue Migration Anyway (Y/N)?"
switch -wildcard ($AzureRMContinue){
N*{write "Stopping" ; $Go = $true ; exit}
Y*{write "Continuing" ; $Go = $true ; continue}
default {"Invalid Response"
          $Go = $false
          [console]::Beep(1000,300)  
        }
                                   }
                                                        
  }Until($Go -eq $true)#Check if an AzureStackUser enviornment exists and prompt user if it doesn't match what we'd want to use
  }
#! Check Azure Stack Connects successfully
Try {
Write-Host -BackgroundColor Gray -ForegroundColor Green "Connecting to Azure Stack..."
Add-AzEnvironment –Name ‘AzureStackUser’ -ArmEndpoint "https://management.$FQDN" | Out-Null
# Set your AAD tenant name
$AuthEndpoint = (Get-AzEnvironment -Name "AzureStackUser").ActiveDirectoryAuthority.TrimEnd('/')
$TenantId = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]
# Signing into Azure Stack
Connect-AzAccount -EnvironmentName "AzureStackUser" -TenantId $TenantId -ErrorAction Stop | Out-Null
}
Catch {
$Error[0]
Write-Warning "Cannot connect to Azure Stack environment. Please check your credentials. Exiting!"
Break
}

# Define recovery function in case errors occur later on
function Revert-VM{do{$Recover = Read-Host -Prompt "Attempt to recover VM? (Y/N)"
                    switch -Wildcard ($Recover){
                                    #Show data lost and so VM can be manually triaged
                                    N*{write-host "Ending Script, Note both managed and unmanaged disks for the following still exist:"
                                    $DisksCreated

                                    Write-host "
                                                The Following Disks were not Created"
                                                $DisksMissed
                                    }
                                    #Attempt to Recover VM
                                    Y*{            Write-Host "Attempting to recover VM"
                                        $VMRebuild = $azsVM
                                        $VMRebuild.StorageProfile.OsDisk.CreateOption = "Attach"
                                        $VMRebuild.StorageProfile.DataDisks | %{$_.CreateOption = "Attach"}
                                        $VMRebuild.StorageProfile.ImageReference = $null
                                        $VMRebuild.OSProfile = $null
                                        New-AzVM -VM $VMRebuild -ResourceGroupName $azsVM.ResourceGroupName -Location $azsVM.Location
                                    return
                                    }
                                    #Default
                                    default {"Invalid Response"}
                                    }
        }until ($Recover -like "Y*" -or $Recover -like "N*")

                    }
# Get all Azure Stack Tenant Subscriptions and look for the VM that you want to convert
# The source and target VM will be created
Write-Host -BackgroundColor Gray -ForegroundColor Green "Get all Azure Stack Tenant Subscriptions..."
$azsSubs = Get-AzSubscription

Write-Host -BackgroundColor Gray -ForegroundColor Green "Locate Azure Stack VM ($VMName)..."
$azsVMs = $azsSubs | ForEach-Object {Select-AzSubscription $_ | Out-Null; Get-AzVM | Where-Object {$_.Name -eq $VMName -and $_.StorageProfile.OsDisk.ManagedDisk -like $null} }


#Check if $azsVM returns more than 1 VM, if so ask user which VM to convert
do{
if($azsVMs.count -eq 0)
    {Write-Warning "No Unmanaged VMs found with name of $VMName . Exiting script"
    return}
if($azsVMs.count -ne 1)
    {##TODO: MAKE TAGS DISPLAY PRETTY
    $VMCount = $azsVMs.Count
    Write-Warning "$VMCount VMs found with name $VMName . Please select the VM you wish to convert and press OK"
    $azsVM = $azsVMs | select -Property  VMID,`
                                         Name,`
                                         @{Name='OsType';Expression={if($_.OSProfile.LinuxConfiguration -ne $null){'Linux'}
                                                                     if($_.OSProfile.WindowsConfiguration -ne $null){'Windows'}}
                                                                     },`
                                         ResourceGroupName,`
                                         @{Name="VMSize";Expression={$_.HardwareProfile.VMSize}},`
                                         @{Name="NICs";Expression={$($_.NetworkProfile.NetworkInterfaces| %{$_.Id.split('/')[-1]}) | Out-String}},`
                                         @{Name="Disks";Expression={$($_.StorageProfile.OSDisk.Name ; $_.StorageProfile.DataDisks.Name) | Out-String}},`
                                         @{Name="Tags";Expression={$_.Tags | Out-String}},`
                                         @{Name="ParentSubscription";Expression={$_.Id.Split('/')[2]}} | Out-GridView -PassThru -Title "$VMCount VMs found with name $VMName . Please select the VM you wish to convert and press OK"
    
# Retrieve virtual machine details
    Select-AzSubscription $azsVM.ParentSubscription  | Out-Null
    $azsVM = Get-AzVM | Where-Object{$_.VMID -like $azsVM.VMID}
    }
if($azsVMs.count -eq 1) 
   {
   Select-AzSubscription $azsVMs.Id.Split('/')[2]  | Out-Null
   $azsVM = $azsVMs[0]}
   }until($azsVM.count -eq 1)


######Compute#####
#Get VM Size
$VMSize = Get-AzVMSize -Location $azsVM.Location |?{$_.Name -like $azsVM.HardwareProfile.VmSize}


#####NETWORK#####
#Get All NIC configs
$NICs = $azsVM.NetworkProfile.NetworkInterfaces.Id |%{
$NicName = $_.split('/')[-1] 
Get-AzNetworkInterface -Name $NicName -ResourceGroupName $azsVM.ResourceGroupName}

#Prep Section

#####STORAGE#####
$azsdisks = @($azsvm.StorageProfile.OsDisk)
if ($azsvm.StorageProfile.DataDisks.Vhd.Uri) {
$azsdisks += $azsvm.StorageProfile.DataDisks
}

#Get Boot Diagnostics Storage Account
If ($azsVM.DiagnosticsProfile.BootDiagnostics.Enabled -eq $true) {
$azsVMstoragediag = $azsVM.DiagnosticsProfile.BootDiagnostics.StorageUri.Split("//")[2]
$azsVMstoragediag = $azsVMstoragediag.Split('.')[0]
}

#####Availability Set#####
#Get Availability Set to add new VM to
If ($azsVM.AvailabilitySetReference.Id -ne $null) {
Write-Host -BackgroundColor Gray -ForegroundColor Green "Check if the VM that you want to convert is a member of an AvailabilitySet..."
$avSetName = $azsVM.AvailabilitySetReference.Id.Split('/')[-1]
$avSet = Get-AzAvailabilitySet -ResourceGroupName $azsVM.ResourceGroupName -Name $avSetName
}

#####Misc#####
#Get VM Extensions in progress to re run on boot (Might not be possible? 
$azExtensions = Get-AzVMExtension -VmName $azsVM.Name -ResourceGroupName $azsVM.ResourceGroupName

#Get VM Tags
$azTags = $azsVM.Tags

#Set the report full path
$ReportPath = $OutReport + "\AzSVM-" + $VMName + "Report" + $([datetime]::Now.ToUniversalTime().ToString("yyyyMMdd-HH-mm-ss")) + ".html"

######Generate Report#####
#Create "Report friendly" data

#Clean up Tags
$azTagsReport = $aztags.GetEnumerator() | % { "(<b>$($_.Key)</b>=$($_.Value))" }
$azTagsReport = $azTagsReport -join ","

#Clean up VM Sizing data
$VMSizeReport = $VMSize  | Select -Property Name,`
                                             @{Name="vCPU Cores";Expression={$_.NumberOfCores}},`
                                             @{Name="Memory in MB";Expression={$_.MemoryInMB}},`
                                             @{Name="OS SKU";Expression={$azsVM.StorageProfile.ImageReference.Sku}}
#Get NSGs per NIC

$VMNetworkSummary = $NICs | Select -Property Name,`
                                             ResourceGroupName,`
                                             Location,`
                                             @{Name="PrivateIP";Expression={$_.IpConfigurations.PrivateIpAddress}},`
                                             @{Name="PublicIP";Expression={(get-azpublicipaddress -Name $_.IpConfigurations.PublicIpAddress.Id.Split('/')[-1] -ResourceGroupName $azsVM.ResourceGroupName).IpAddress}},`
                                             @{Name="PublicIPObject";Expression={(get-azpublicipaddress -Name $_.IpConfigurations.PublicIpAddress.Id.Split('/')[-1] -ResourceGroupName $azsVM.ResourceGroupName).Name}},`
                                             @{Name="PublicFQDN";Expression={(get-azpublicipaddress -Name $_.IpConfigurations.PublicIpAddress.Id.Split('/')[-1] -ResourceGroupName $azsVM.ResourceGroupName).DnsSettings.Fqdn}},`
                                             @{Name="NSGName";Expression={($_.NetworkSecurityGroup.Id).Split('/')[-1]}}

#Clean up Storage
$azsDisksReport = $azsdisks | select -Property @{Name="Lun";Expression={if($_.Lun -notlike $null){$_.Lun} else{"OS Disk for "+$_.OSType}}},`
                                                Name,`
                                                DiskSizeGB,`
                                                Caching,`
                                                WriteAcceleratorEnabled,`
                                                CreateOption,`
                                                @{Name="Disk Location";Expression={$_.vhd.uri}}
#Clean up Availability Group listing
$avSetReport = $avSet  | Select -Property Name,`
                                           Sku,`
                                             @{Name="Tags";Expression={$_.Tags.GetEnumerator() | % { "(<b>$($_.Key)</b>=$($_.Value))" }}},`
                                             @{Name="Virtual Machines in Group";Expression={$avSet.VirtualMachinesReferences | %{$_.Id.split('/')[-1]}}}

#Clean up Extensions
$azExtensionsReport = $azExtensions | select Name,Publisher,ExtensionType,PublicSettings

#Output file with VM configuration for review
$ReportBase = "<head>
<style>
h1 {
background-color : #060298;
color : #FFFFFF
}

p,div{
font-family:Calibri
}	  

table{
width: 100%;
table-layout: fixed;
border-collapse:collapse
}

tr{
    border:2px solid; 
}

td{
width: 100%;
border:1px solid;
word-wrap: break-word;
}

th{
text-align:left;
border:1px dotted;
}

p.Grid tr:nth-child(odd) {background-color: #aaaabb;}

p.Grid tr:first-child {
                        background-color : #060298;
                        color : #FFFFFF
}

p.List table td:first-child {
  width: 10%;
  font-weight: bold
}
</style>
</head>
<body>
<div>
<table>
 <tr>
  <td>
    <p><b>VM Name</b>:" + $azsVM.Name + "</p>
  </td>
  <td>
    <p>Stamp:" + $azsVM.Location + "</p>
  </td>
 </tr>

 <tr>
  <td>
    <p><b>Resource Group</b>: " + $azsVM.ResourceGroupName + " <b><o:p></o:p></b></p>
  </td>
  <td>
    <p><b>VMID</b>: " + $azsVm.VmId + " </p>
  </td>

 </tr>

 <tr>
  <td>
    <p><b>Subscription</b>:" + $azsVM.Id.Split('/')[2] + " </p>
  </td>
 </tr>

 <tr>
  <td colspan=4 valign=top >
    <p><b>ID: </b>" + $azsVM.Id + "</p>
  </td>
 </tr>

 <tr>
  <td colspan=4 valign=top >
    <p><b>Tags:</b> " + $azTagsReport + "</p>
  </td>
 </tr>

 <tr>
  <td colspan=4 valign=top >
    <h1 align=center ><b>VM Compute<o:p></o:p></b></h1>
  </td>
 </tr>

 <tr>
  <td colspan=4 valign=top >
    <p class=Grid>" + $($VMSizeReport|ConvertTo-Html -Fragment) + "</p>
  </td>
 </tr>

 <tr >
  <td colspan=4 valign=top >
    <h1 align=center ><b>VM Networking<o:p></o:p></b></h1>
  </td>
 </tr>

 <tr >
  <td colspan=4 valign=top >
    <p class=Grid>" + $($VMNetworkSummary | ConvertTo-Html -Fragment) + "</p>
  </td>
 </tr>

 <tr >
  <td colspan=4 valign=top >
    <h1 align=center><b>VM Storage<o:p></o:p></b></h1>
  </td>
 </tr>

 <tr >
  <td colspan=4 valign=top >
    <p class=grid>" + $($azsDisksReport | ConvertTo-Html -Fragment) + "</p>
  </td>
 </tr>

 <tr >
  <td colspan=4 valign=top>
    <h1 align=center ><b>VM Availability Group<o:p></o:p></b></1>
  </td>
 </tr>

 <tr >
  <td colspan=4 valign=top >
    <p class=Grid>" + $($avSetReport | ConvertTo-Html -Fragment ).replace("&lt;b&gt;","<b>").replace("&lt;/b&gt;","</b>") + "</p>
  </td>
 </tr>
 <tr>
  <td colspan=4 valign=top 
    <h1 align=center ><b>VM Extensions<o:p></o:p></b></h1>
  </td>
 </tr>

 <tr>
  <td width=876 colspan=4 valign=top >
    <p class=List >" + $($azExtensionsReport | ConvertTo-Html -Fragment -As List) + "</p>
  </td>
 </tr>
</table>
</div>
</body>
</html>
"

$ReportBase |  Out-File $ReportPath

#Pause processing for user to review VM data gathered
Write-Warning $("VM Data for " + $Azsvm.Name + " has been saved at $(gci $ReportPath)
Please review this report to validate VM settings are correct before continuing
NOTE: Upon moving to the next step VM WILL BE DELETED and ALL DISKS UNMOUNTED to
start migration from Unmanaged to Managed Disks this process must be completed in one pass
Would you like to continue to the next phase of Migration?:")

#####LAST CHANCE FOR CX TO STOP PROCESS IN CASE OF ERROR#####
$Continue = Read-Host -Prompt "Continue Migration (Y/N)"
switch -wildcard ($Continue){
N*{write "Stopping" ; return}
Y*{write "Continuing" ; continue}
default {"Invalid Response"
            }
}

$Starttime = Get-Date
# Remove the VM, keeping the disks 
Write-Output -InputObject "Removing old virtual machine"
Remove-AzVM -Name $VMName -ResourceGroupName $azsVM.ResourceGroupName -Force

######Create Disks and VM Config#####
$DisksCreated = @()
$DisksMissed =@()
##TODO: Change delete process to happen out of band ONLY if all disks successfully create
##TODO: Add rollback script if disks do not successfully create
foreach ($azsdisk in $azsdisks) { 

# The size of the new disk in GB. It should be greater than the existing VHD file size.
$NewDiskSize = ($azsdisk.DiskSizeGB)+1

#Get VM Storage account location for Unmanaged Disk
$storageacc = ([System.Uri]$azsdisk.Vhd.Uri).Host.Split('.')[0]
$azsStorage = Get-AzStorageAccount -ResourceGroupName $azsVM.ResourceGroupName -Name $storageacc
Set-AzCurrentStorageAccount -Name $storageacc -ResourceGroupName $azsVM.ResourceGroupName | Out-Null
$storageContainerName = (Get-AzStorageContainer).Name

# Create the managed disk configuration.
$DiskConfig = New-AzDiskConfig -AccountType $azsStorage.Sku.Name -Location $azsVM.Location -DiskSizeGB $NewDiskSize -SourceUri $azsdisk.Vhd.Uri -CreateOption Import -StorageAccountId $azsStorage.Id

if ($azsdisk.OsType -ne $null) { 
   
    # Create one of 2 possible VM configs, adding tags here 
    Write-Host -BackgroundColor Gray -ForegroundColor Green "Creating virtual machine configuration..."
    #Make sure to add VM to the Availability Set if it's already part of one

    If ($avSetName) {
    Write-Host -BackgroundColor Gray -ForegroundColor Green "Configuring the VM $($azsVM.Name) to be added to managed availability set ($avSetName)"
    $VirtualMachine = New-AzVMConfig -VMName $azsVM.Name -VMSize $azsVM.HardwareProfile.VmSize -Tags $azTags -AvailabilitySetId $avSet.Id 
    }

    #If it's not in an availibility set, continue creation without this information
    Else {
    $VirtualMachine = New-AzVMConfig -VMName $azsVM.Name -VMSize $azsVM.HardwareProfile.VmSize -Tags $azTags
    }

    # Create OS managed disk.
    #TODO: ADD PROPER ERROR HANDLING IN CASE DISK DOESN'T GET CREATED
    #TODO: Specific Error for duplicate disk ErrorMessage: Changing property 'sourceUri' is not allowed for existing disk 'Diskname'. Change Disk name to include a GUID and output name
    Write-Host -BackgroundColor Gray -ForegroundColor Green "Creating OS managed disk with name: $($azsVM.Name)-$($azsdisk.Name)"
    $OsDisk = New-AzDisk -DiskName "$($azsVM.Name)-$($azsdisk.Name)" -Disk $DiskConfig -ResourceGroupName $azsVM.ResourceGroupName
    if(!$OsDisk){Write-Error "OS DISK CREATION FAILED, EXITING"
                return}
    # Use the managed disk resource ID from the Disk above to attach the disk to the new VM config
    # The OS type will be set according to the exisitng VM OsType (Windows/Linux)
    If ($azsdisk.ostype -eq "Windows") {
    $VirtualMachine = Set-AzVMOSDisk -VM $VirtualMachine -ManagedDiskId $OsDisk.Id -CreateOption Attach -Windows -Caching $azsdisk.Caching 
    }
    If ($azsdisk.ostype -eq "Linux") {
    $VirtualMachine = Set-AzVMOSDisk -VM $VirtualMachine -ManagedDiskId $OsDisk.Id -CreateOption Attach -Linux -Caching $azsdisk.Caching 
    }
    # Delete the OS disk VHD file
    #TODO: If disk exists put into an array to delete later
     if($OsDisk){$DisksCreated += $azsdisk}
}
Else {
    # Create Data managed disks.
    Write-Host -BackgroundColor Gray -ForegroundColor Green "Create the Data managed disk: $($azsdisk.Name)"
    #Clean up last variable
    $DataDisk = $null 
    #Create new Disk
    $DataDisk = New-AzDisk -DiskName $azsdisk.Name -Disk $DiskConfig -ResourceGroupName $azsVM.ResourceGroupName
    if(!$DataDisk){Write-Error $("DATA DISK NAMED " + $azdisk.Name +" CREATION FAILED,")
                    $DisksMissed += $azsdisk }
    # Create the Data managed disk configuration.
    $VirtualMachine = Add-AzVMDataDisk -VM $VirtualMachine -ManagedDiskId $DataDisk.Id -CreateOption Attach -Lun $azsdisk.Lun `
    -Caching $azsdisk.Caching
    
    # Delete the Data disk VHD file
     if($DataDisk){$DisksCreated += $azsdisk} 
    }
}

#Check if we had failed disks and ask if we want to continue
if($DisksMissed.count -notlike 0 -and $DisksMissed.count -notlike $null){
$DisksMissed | select -Property @{Name="Lun";Expression={if($_.Lun -notlike $null){$_.Lun} else{"OS Disk for "+$_.OSType}}},`
                                Name,`
                                DiskSizeGB,`
                                Caching,`
                                @{Name="Disk Location";Expression={$_.vhd.uri}}
Write-Warning "THE FOLLOWING DISKS ABOVE COULD NOT BE CREATED"
do{
$ContinueDiskDeletion = Read-Host -Prompt "Continue Migration (Y/N)"
switch -wildcard ($Continue){
N*{write "Stopping"
Revert-VM
 return}
Y*{write "Continuing"
   continue}
default {"Invalid Response"}

}
}until($ContinueDiskDeletion -like "Y*" -or $ContinueDiskDeletion -like "N*")

}

#Add NICs to config
$NICs | %{
if($_.Primary){$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $_.Id -Primary}
else{$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $_.Id} 
            }

#Add Boot Diagnostics if needed
if ($azsVMstoragediag) {
$VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Enable -StorageAccountName $azsVMstoragediag -ResourceGroupName $azsVM.ResourceGroupName
}


#Convert Availability set (IF needed)
if($avSet -ne $null){
Write-Host -BackgroundColor Gray -ForegroundColor Green "Convert the availability set ($avSetName) to a managed availability set..."
Update-AzAvailabilitySet -AvailabilitySet $avSet -Sku Aligned | Out-Null
                    }


# Create the new virtual machine with managed disks and boot
##TODO Output VM with get-vm to show to the user it's complete
Write-Host -BackgroundColor Gray -ForegroundColor Green "Create the new virtual machine ($($azsVM.Name)) with managed disks..."
try{New-AzVM -VM $VirtualMachine -ResourceGroupName $azsVM.ResourceGroupName -Location $azsVM.Location
}catch{Write-Warning "Unable to create vm for reason" $Error[0] 
        return}


##TODO wrap this so it adds a warn prompt before starting this process
Write-Warning "Cleaning up old disks"

foreach ($azsdisk in $DisksCreated) { 
#Get VM Storage account location for Unmanaged Disk
$storageacc = ([System.Uri]$azsdisk.Vhd.Uri).Host.Split('.')[0]
$azsStorage = Get-AzStorageAccount -ResourceGroupName $azsVM.ResourceGroupName -Name $storageacc
Set-AzCurrentStorageAccount -Name $storageacc -ResourceGroupName $azsVM.ResourceGroupName | Out-Null
$storageContainerName = (Get-AzStorageContainer).Name
Write-Warning "Do you want to delete the following"
$azdisk| select -Property @{Name="Lun";Expression={if($_.Lun -notlike $null){$_.Lun} else{"OS Disk for "+$_.OSType}}},`
                                Name,`
                                DiskSizeGB,`
                                Caching,`
                                @{Name="Disk Location";Expression={$_.vhd.uri}}
Remove-AzStorageBlob -Container $storageContainerName -Blob "$($azsdisk.Vhd.Uri.Split('/')[-1])" -Force -Confirm:$True
}

$Endtime = Get-Date

$Allotted = $Endtime - $Starttime
#Add Extensions and verify as added
#New-AzConnectedMachineExtension

