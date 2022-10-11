# Convert-VMtoManagedDisk
This Powershell Script is used to migrate Azure Stack Hub (AzSH) VMs with Unmanaged Disks to Managed Disks.
Note that this process DOES delete the VM config as part of freeing up the disks for conversion then rebuild the VM

This script at this time properly converts and carries over the following:
VM Envelope (CPU/RAM/Disk count, see Get-AzVMSize for what is pulled here)
VM config Tags
VM NICs (Via Reattachment of NICs)
VM OS Unmanaged Disks (Standard and Premium)
VM Data Unmanaged Disks (Standard and Premium)
VM Storage Diagnostic accounts
VM Availability Sets (NOTE The Availability set will be converted from a Classic to an Aligned SKU in doing this)

Note currently VM Extensions are NOT carried over by this script and will need to be reapplied manually (Work is being done to accommodate this though)

If VM fails during creation this script WILL offer to attempt to recreate the VM using the config stored by the script using the Unmanaged Disks BEFORE attempting to clean up the Unmanaged Disks. If processing is stopped at this point note that the Unmanaged Disks WILL be left behind and even if recovered that any disks that WERE converted will remain so