#PURPOSE: Inject Windows updates into Azure Stack HCI OS based SDN VM image file
#WRITTEN BY: Gabor ROZSA
#DATE: 2021-04-24
#NOTES:
#   injecting the updates is a lenghty process
#   check the official documentation on creating the SDN VM image file: https://docs.microsoft.com/en-us/azure-stack/hci/manage/sdn-express
#   the Convert-WindowsImage.ps1 is faulty, remove the -PassThru parameter at every occurence of the Dismount-Diskimage command
#   get the latest Azure Stack HCI OS updates from the Microsoft Update Catalog: https://www.catalog.update.microsoft.com/Search.aspx?q=azure%20stack%20hci

$volumes=(get-volume).driveletter #get the current driveletters
mount-diskimage -imagepath C:\Temp\SDN-VM.vhdx #specify the SDN VM image location
$newvolumes=(get-volume).driveletter  #get the driveletters after the VM image is mounted
$mountvolume = $newvolumes | Where-Object {$volumes -notcontains $_} #get the driveletter of the mounted VM image

$updatesfolder = 'C:\Temp\updates' #location of the downloaded Azure HCI OS updates (latest Stack and CU)
Set-Location $updatesfolder

$updates = get-childitem -Recurse | Where-Object { ($_.extension -eq ".msu") -or ($_.extension -eq ".cab") } | Select-Object fullname 
foreach ($update in $updates) {
    write-debug $update.fullname
    $command = "dism /image:" + $mountvolume +":\ /add-package /packagepath:'" + $update.fullname + "'" #comply the command
    write-debug $command
    Invoke-Expression $command #execute the complied command(s)
} 


$command = "dism /image:G:\ /Cleanup-Image /spsuperseded" #comply the cleanup command
Invoke-Expression $command #execute the complied command

dismount-vhd -path C:\Temp\SDN-VM.vhdx -confirm:$false #dismount the VM file