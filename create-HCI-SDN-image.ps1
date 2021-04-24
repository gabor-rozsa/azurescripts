#PURPOSE: Create Azure Stack HCI OS based SDN VM image file
#WRITTEN BY: Gabor ROZSA
#DATE: 2021-04-24
#NOTES:
#   check the official documentation on creating the SDN VM image file: https://docs.microsoft.com/en-us/azure-stack/hci/manage/sdn-express
#   the Convert-WindowsImage.ps1 is faulty, remove the -PassThru parameter at every occurence of the Dismount-Diskimage command

$installkitpath = "c:\temp\AzureStackHCI_17784.1408_EN-US.iso" #specify the Azure Stack HCI OS install media location
$vhdxpath = "c:\temp\SDN-VM.vhdx"  #specify name and the path for the SDN VM image
$Edition = 1   # 1 = Azure Stack HCI

import-module convert-windowsimage

Convert-WindowsImage -SourcePath $installkitpath -Edition $Edition -VHDPath $vhdxpath -SizeBytes 100GB -DiskLayout UEFI