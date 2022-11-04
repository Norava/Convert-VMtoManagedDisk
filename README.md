# Convert-VMtoManagedDisk
**Description**
This Powershell Script is used to migrate Azure Stack Hub (AzSH) VMs with Unmanaged Disks to Managed Disks.
Note that this process DOES delete the VM config as part of freeing up the disks for conversion then rebuild the VM

**Scope**
This script at this time properly converts and carries over the following:
VM Envelope (CPU/RAM/Disk count, see Get-AzVMSize for what is pulled here)
VM config Tags
VM NICs (Via Reattachment of NICs)
VM OS Unmanaged Disks (Standard and Premium)
VM Data Unmanaged Disks (Standard and Premium)
VM Storage Diagnostic accounts
VM Availability Sets (NOTE The Availability set will be converted from a Classic to an Aligned SKU in doing this)

**Known Limits**
-VM Extensions are NOT carried over by this script and will need to be reapplied manually (Work is being done to accommodate this)
-If VM fails during creation this script WILL offer to attempt to recreate the VM using the config stored by the script using the Unmanaged Disks BEFORE attempting to clean up the Unmanaged Disks. If processing is stopped at this point note that the Unmanaged Disks WILL be left behind and even if recovered that any disks that WERE converted will remain so
-This script is currently for AAD enabled stamps only (Currently in progress to add ADFS stamp functionality)

**Requirements**
- Powershell 5.1 or higher
- Azure Az Module
- Network connection to the stamp in question
- A user account that can access the VM to be migrated

**Parameters**:
AADTenantName 
The name of the AAD Tenant used to sign into the stamp
Example: contoso.onmicrosoft.com

FQDN
The Fully Qualified Domain Name for the stamp
Example: stamp1.contoso.net

OutReport
Where to save a report containing the selected VM's configuration to (Default to %USERPROFILE%\Documents)
Example: C:\Temp\MigrationReports

VMName
The name in AzSH of the VM to be migrated
Example: SVR-VM1

**Example of use**:
.\Convert-VMtoManagedDisks.ps1 -AADTenantName "contoso.onmicrosoft.com"   -FQDN "ProdStamp1.contosolabs.net" -VMName "SVR-App1"  -OutReport C:\Reports\

**Steps to use**:
**1:** Run script giving the appropriate data to flags as needed

**2:**Script will prompt user to log in with an account that has User access (Not Admin access) to the VM to be migrated

**3:** The VM will be searched for across all VMs with unmanaged disks across all subscriptions the User has access to. If multiple VMs with the same display name come up, the user will be prompted to select the correct one

**4:** A report will be generated with information on the VM. It is highly recommended to review this report to verify the correct VM is marked to migrate. It is further recommended to keep hold of this report in case errors occur during migration

**5:** Provided the VM is correctly marked, provide a Y to the script to continue with deletion of the VM object (Note disks and attached resources aren't deleted here but the VM object itself IS and will remain down until migration completes)

**6:** Script will run through ALL disks for the VM and attempt to convert them to Managed Disks.
**6-1:** If ANY disks fail User will be prompted to cancel migration
**6-2:** Upon cancel script will prompt User to attempt automatic VM Rebuild

**7:** Provided script succeeds User is advised to check VM and readd any VM Extensions that were configured on the old VM as needed and test all disks as present in VM
