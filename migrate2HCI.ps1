<#

.SYNOPSIS
Migrate VM to HCI cluster
.DESCRIPTION
Provides selection menu to ease VM migration to HCI cluster from legacy Hyper-V clusters. Fixes network and disk configuration.
.NOTES
Requires administrative access on SOURCE and DESTINATION cluster(s).

  Version:        1.5
  Author:         Rózsa Gábor
  Creation Date:  2021-06-30
  Purpose/Change: Added checkpoint handling
#>

#Requires -Version 7.1
#Requires -RunAsAdministrator

#basic variables
$yesResponse = "[Y] Yes "
$noResponse = "[N] No"

#cluster selector
$ClusterInfra = "Source cluster #1"
$ClusterDev = "Source cluster #2"
$ClusterHCI = "Target HCI cluster"
$questionStringCluster = "`r`nSelect a cluster"
$exitString = "[q] quit"
$infraResponse = "[1] Source cluster #1"
$devResponse = "[2] Source cluster #2"
$Repeat = $true
while ($Repeat) {
  Clear-Host
  Write-Host "Migrate VM to HCI cluster" -ForegroundColor White -BackgroundColor Green  

  Write-Host $questionStringCluster -ForegroundColor Yellow
  Write-Host $infraResponse -ForegroundColor Yellow
  Write-Host "$devResponse" -ForegroundColor White
  Write-Host "$exitString"  -ForegroundColor Red
  Write-Host "`r`nResponse: " -NoNewline
  $userResponse = (Read-Host).ToUpper()
  switch ($userResponse) {
    "1" { $Cluster = $ClusterInfra; break }
    "2" { $Cluster = $ClusterDev; break }
    "q" { exit }
    Default { Write-Host "Invalide Response, Infra cluster selected"; $Cluster = $ClusterInfra; break }
  }

  #VM selector
  Write-Host "Selected cluster: $Cluster" -ForegroundColor Green
  Write-Host "Getting all VM from cluster $Cluster"
  $AllVM = Get-VM –ComputerName (Get-ClusterNode -cluster $Cluster)
  foreach ($VM in $AllVM) { Write-Host $AllVM.IndexOf($VM) "-" $VM.Name }
  Write-Host "Press 'q' to quit" -ForegroundColor Red
  DO {
    $VMnum = Read-Host "Please enter the VM number"
    if ($VMnum -eq "q" ) {
      exit  
    }
    elseif ($VMnum -gt $AllVM.length - 1) {
      Write-Host "Enter a valid number or press 'q' to quit!" -ForegroundColor Red
    }
  } UNTIL ($VMnum -le $AllVM.length - 1)
  $SelectedVM = $AllVM[$VMnum]

  #Getting VM pre-details
  $SelectedVMName = $SelectedVM.Name
  $SelectedVMNotes = $SelectedVM.Notes
  Write-Host "Selected VM:" $SelectedVMName -ForegroundColor Green
  try {
    $VMIPaddress = (Resolve-DnsName $SelectedVMName -ErrorAction Stop).IPAddress
  }
  catch {
    $VMIPaddress = "none"
  }
  $VMFootprint = 0
  $VMDisks = $SelectedVM | Get-VMHardDiskDrive | Select-object -expandproperty path
  $total_size = Invoke-Command -ComputerName $SelectedVM.ComputerName -ScriptBlock {   
    param($VMDisks) 
    $total = 0 
            
    foreach ($disk in $VMDisks) {
      $size = [math]::round((get-item -Path $disk | select-object -ExpandProperty length) / 1GB, 2)
      $total += $size
    } 
    return $total
  } -ArgumentList (, $VMDisks)
  $VMFootprint += $total_size
  Write-Host "VMs footprint: $VMFootprint GB"
  
  #Checking for checkpoint(s)
  $SelectedVMCheckpoint = Get-VMSnapshot -ComputerName $SelectedVM.ComputerName -VMName $SelectedVMName
  if ($SelectedVMCheckpoint -ne "") {
    Write-Host "Checkpoint(s) found! Migration is only possible if the checkpoint(s) is removed!" -ForegroundColor Red 
    Write-Host "Do you want to remove the checkpoint(s)?" -ForegroundColor Red 
    Write-Host $yesResponse -ForegroundColor Yellow -NoNewline
    Write-Host "$noResponse : " -ForegroundColor White -NoNewline
    $userResponse = (Read-Host).ToUpper()
    switch ($userResponse) {
      "Y" { $SelectedVMCheckpoint | Remove-VMSnapshot -IncludeAllChildSnapshots ; Write-Host "Checkpoint(s) removed" -ForegroundColor Green; break }
      "N" { Write-Host "Script cannot continue. Exiting..."; exit }
      Default { Write-Host "Invalide Response"; Write-Host "Script cannot continue. Exiting..."; exit }
    }
  }
  

  #checking online HCI node
  $HCInode1 = "hci node #1"
  $HCInode2 = "hci node #2"
  $HCInode3 = "hci node #3"
  IF (Test-Connection -BufferSize 32 -Count 1 -ComputerName $HCInode1 -Quiet) {
    #Write-Host "$HCInode1 is Online"
    $HCIname = $HCInode1
  }
  elseif (Test-Connection -BufferSize 32 -Count 1 -ComputerName $HCInode2 -Quiet) {
    #Write-Host "$HCInode2 is Online"
    $HCIname = $HCInode2
  }
  elseif (Test-Connection -BufferSize 32 -Count 1 -ComputerName $HCInode3 -Quiet) {
    #Write-Host "$HCInode3 is Online"
    $HCIname = $HCInode3
  }
  else {
    Write-Host "All HCI nodes are down" -ForegroundColor Black -BackgroundColor Red
  }

  #Checking for existing VM on HCI
  Write-Host "Checking for existing VM on the HCI cluster"
  $AllHCIVM = Get-VM –ComputerName (Get-ClusterNode -cluster $ClusterHCI)
  if ($AllHCIVM.name -contains $SelectedVMName) {
    Write-Host "Existing VM with the same name found! Terminating" -ForegroundColor Red 
    break
  }
  else {
    Write-Host "Selected VM does not existing on node $ClusterHCI"
  }
 
  #Getting VM details
  $VMConfig = $SelectedVM.ConfigurationLocation
  $VMUNC = "\\" + $SelectedVM.ComputerName + "\c$" + $VMConfig.Substring(2)
  Write-Host "The Source VM UNC is: $VMUNC"
  $VMHardDrives = $SelectedVM.HardDrives.Path
  Write-Host "Selected VMs IP address: $VMIPaddress"
  Write-Host "Selected VMs configuration location: $VMConfig"
  Write-Host "Selected VMs hard drive(s): $VMHardDrives"

  #Listing CSVs
  Write-Host "Getting all CSV"
  $AllCSV = Get-ChildItem -Path \\$HCIname\C$\ClusterStorage -Recurse -Depth 0 -Directory -Force -ErrorAction SilentlyContinue | Select-Object FullName
  foreach ($CSV in $AllCSV) { Write-Host $AllCSV.IndexOf($CSV) "-" $CSV.FullName }
  Write-Host "Press 'q' to quit" -ForegroundColor Red
  DO {
    $CSVnum = Read-Host "Enter the CSV number"
    if ($CSVnum -eq "q" ) {
      exit  
    }
    elseif ($CSVnum -gt $AllCSV.length - 1) {
      Write-Host "Enter a valid number or press 'q' to quit!" -ForegroundColor Red
    }
  }
  UNTIL ($CSVnum -le $AllCSV.length - 1)
  $SelectedCSV = $AllCSV[$CSVnum]
  Write-Host "Selected CSV:" $SelectedCSV.FullName -ForegroundColor Green

  #Collecting path information
  $NEWVMUNC = $SelectedCSV.FullName + "\" + $SelectedVMName
  Write-Host "The target UNC path is: $NEWVMUNC"
  $NEWVMPath = "C:\" + $SelectedCSV.FullName.Substring(30) + "\" + $SelectedVMName
  Write-Host "The target VM path is: $NEWVMPath"

  #Removing attached ISO
  Write-Host "Removing attached DVD image (if any)"
  Invoke-Command -ComputerName $SelectedVM.ComputerName -ArgumentList $SelectedVMName -ScriptBlock {
    param($SelectedVMName)  
    Get-VMDvdDrive -VMName $SelectedVMName | Remove-VMDvdDrive
  }
  Write-Host "Removed attached DVD image" -ForegroundColor Green

  #Stopping VM if running
  Write-Host "Status of" $SelectedVMname "is:" $SelectedVM.state -ForegroundColor Yellow
  if ($SelectedVM.state -ne "Off") {
    Invoke-Command -ComputerName $SelectedVM.ComputerName -ArgumentList $SelectedVMName -ScriptBlock {
      param($SelectedVMName)
      Write-Host "Shutting down $SelectedVMName"
      Stop-VM -name $SelectedVMName
    }
    DO {
      Write-Host "Waiting..." -ForegroundColor Red
      Start-Sleep -Seconds 3
      $SelectedVMOff = (Get-VM -ComputerName $SelectedVM.ComputerName -Name $SelectedVMName)
    } Until ($SelectedVMOff.state -eq "Off")
    Write-Host "VM is now turned off" -ForegroundColor Green
  }
  else {
    Write-Host "VM is already turned off, copy process can be started" -ForegroundColor Green
  }

  #Copying the VM to HCI
  Write-Host "Starting robocopy"
  Robocopy $VMUNC $NEWVMUNC /E /MT:32 /R:5 /w:1 /copyall
  Write-Host "Robocopy finished" -ForegroundColor Green

  #Doing the magic remotely
  Invoke-Command -ComputerName $HCIname -ArgumentList $SelectedVMName, $NEWVMPath, $VMHardDrives, $SelectedVMNotes -ScriptBlock {
    param($SelectedVMName, $NEWVMPath, $VMHardDrives, $SelectedVMNotes)
    Write-Host "Active Server: $env:COMPUTERNAME" -ForegroundColor Yellow
    $VMCX = Get-ChildItem -Path $NEWVMPath\*.vmcx -Recurse
    Write-Host "Found $VMCX"
    $VHD = Get-ChildItem -Path $NEWVMPath\*.vhdx -Recurse
    Write-Host "Found $VHD"

    #VM compatibility magic
    $VMfixed = Compare-VM -Path $VMCX
    Write-Host "Checking for incompatibilities" -ForegroundColor Yellow
    #$VMfixed.Incompatibilities[0].MessageId 
    if ($VMfixed.Incompatibilities[0].MessageId -eq "33012") {
      Write-Host "Different network switch and adapter found" -ForegroundColor Yellow
      $VMfixed.Incompatibilities[0].Source | Connect-VMNetworkAdapter -SwitchName ConvergedSwitch
      Write-Host "Network configuration fixed" -ForegroundColor Green
    }
    elseif ($VMfixed.Incompatibilities[1].MessageId -eq "33012") {
      Write-Host "Different network switch and adapter found" -ForegroundColor Yellow
      $VMfixed.Incompatibilities[1].Source | Connect-VMNetworkAdapter -SwitchName ConvergedSwitch
      Write-Host "Network configuration fixed" -ForegroundColor Green
    }
    else {
      Write-Host "No network compatibility issue found"
    }
    if ($VMfixed.Incompatibilities[0].MessageId -eq "40010") {
      Write-Host "VHD not found" -ForegroundColor Yellow
      Set-VMHardDiskDrive $VMfixed.Incompatibilities[0].Source -Path $VHD
      Write-Host "VHD configuration fixed" -ForegroundColor Green
    }
    elseif ($VMfixed.Incompatibilities[1].MessageId -eq "40010") {
      Write-Host "VHD not found" -ForegroundColor Yellow
      Set-VMHardDiskDrive $VMfixed.Incompatibilities[1].Source -Path $VHD
      Write-Host "VHD configuration fixed" -ForegroundColor Green
    }
    else {
      Write-Host "No VHD compatibility issue found"
    }
    Write-Host "Finished checking for incompatibilities" -ForegroundColor Green

    #Importing the VM magic
        Write-Host "Started importing the VM" -ForegroundColor Yellow
    $dummy = Import-VM -CompatibilityReport $VMfixed
    Write-Host "Finished importing the VM" -ForegroundColor Green
    Start-Sleep -s 5
    Write-Host "Clusterizing the VM" -ForegroundColor Yellow
    $NewVM = Get-VM -Name $SelectedVMName
    $NewVM | Add-ClusterVirtualMachineRole
    Write-Host "VM is now clusterized" -ForegroundColor Green
    Write-Host "Updating the vm version" -ForegroundColor Yellow
    $NewVM | Update-VMVersion -Force
    Write-Host "VM version updated" -ForegroundColor Green

    #Questionnaire variables
    $questionStringCPU = "Do you want to set CPU SMT?"
    #$questionStringStartVM = "Do you want to start the VM?"
    $questionStringDescription = "Do you want to set description for the VM?"
    $questionStringGuestService = "Do you want to enable the Guest Service for the VM?"
    $questionStringTPM = "Do you want to enable TPM?"
    $yesResponse = "[Y] Yes "
    $noResponse = "[N] No "
    $keepResponse = "[K] Keep existing "
   
    #Set description
    Write-Host $questionStringDescription -ForegroundColor Yellow
    if ($SelectedVMNotes -ne "") {
      Write-Host "Existing description: $SelectedVMNotes" -ForegroundColor Blue
    }
    Write-Host $yesResponse -ForegroundColor Yellow -NoNewline
    Write-Host $noResponse -ForegroundColor White -NoNewline
    Write-Host "$keepResponse : "-ForegroundColor Green -NoNewline
    $userResponse = (Read-Host).ToUpper()
    switch ($userResponse) {
      "Y" { Set-VM -Name $SelectedVMName -Notes (Read-Host -Prompt "Enter description:"); Write-Host "Description set" -ForegroundColor Green; break }
      "K" { Set-VM -Name $SelectedVMName -Notes $SelectedVMNotes; Write-Host "Description set"; break }
      "N" { break }
      Default { Write-Host "Invalide Response"; Write-Host "Keeping existing description"; Set-VM -Name $SelectedVMName -Notes $SelectedVMNotes; Write-Host "Description set" -ForegroundColor Green; break }
    }

    #Set SMT
    Write-Host $questionStringCPU -ForegroundColor Yellow
    Write-Host "$yesResponse "-ForegroundColor Yellow -NoNewline
    Write-Host "$noResponse : " -ForegroundColor White -NoNewline
    $userResponse = (Read-Host).ToUpper()
    switch ($userResponse) {
      "Y" { Set-VMProcessor -VMName $SelectedVMName -HwThreadCountPerCore 0 ; Write-Host "CPU SMT set" -ForegroundColor Green; break }
      "N" { break }
      Default { Write-Host "Invalide Response"; Write-Host "Setting CPU SMT"; Set-VMProcessor -VMName $SelectedVMName -HwThreadCountPerCore 0 ; Write-Host "CPU SMT set" -ForegroundColor Green; break }
    }

    #Set TPM
    $UntrustedGuardian = Get-HgsGuardian -Name UntrustedGuardian
    if (!$UntrustedGuardian) {
      $UntrustedGuardian = New-HgsGuardian -Name UntrustedGuardian -GenerateCertificates
    }
    Write-Host $questionStringTPM -ForegroundColor Yellow
    Write-Host "$yesResponse "-ForegroundColor Yellow -NoNewline
    Write-Host "$noResponse : " -ForegroundColor White -NoNewline
    $userResponse = (Read-Host).ToUpper()
    switch ($userResponse) {
      "Y" {
        $kp = New-HgsKeyProtector -Owner $UntrustedGuardian -AllowUntrustedRoot;
        $NewVM | Set-VMKeyProtector -KeyProtector $kp.RawData;
        $NewVM | Enable-VMTPM;
        Write-Host "TPM enabled" -ForegroundColor Green;
        break
      }
      "N" { break }
      Default { 
        Write-Host "Invalide Response";
        Write-Host "Enabling TPM";
        $kp = New-HgsKeyProtector -Owner $UntrustedGuardian -AllowUntrustedRoot;
        $NewVM | Set-VMKeyProtector -KeyProtector $kp.RawData;
        $NewVM | Enable-VMTPM;
        Write-Host "TPM enabled" -ForegroundColor Green;
        break 
      }
    }
     
    #Set GuestService
    Write-Host $questionStringGuestService -ForegroundColor Yellow
    Write-Host $yesResponse -ForegroundColor Yellow -NoNewline
    Write-Host "$noResponse : " -ForegroundColor White -NoNewline
    $userResponse = (Read-Host).ToUpper()
    switch ($userResponse) {
      "Y" { Enable-VMIntegrationService -VMName $SelectedVMName -Name *; Write-Host "Guest Service enabled" -ForegroundColor Green; break }
      "N" { break }
      Default { Write-Host "Invalide Response"; Write-Host "Enabling Guest Service"; Enable-VMIntegrationService -VMName $SelectedVMName -Name *; Write-Host "Guest Service enabled" -ForegroundColor Green; break }
    }              
  
    <#
  #Start the migrated VM
  Write-Host $questionStringStartVM -ForegroundColor Yellow
  Write-Host $yesResponse -ForegroundColor Yellow -NoNewline
  Write-Host "$noResponse : " -ForegroundColor White -NoNewline
  $userResponse = (Read-Host).ToUpper()
  switch ($userResponse) {
    "Y" { Start-VM -Name $SelectedVMName ; Write-Host "VM started"; break }
    "N" { break }
    Default { Write-Host "Invalide Response"; break }
  }
  #>
  } 

  #Finished
  Write-Host "Migration of $SelectedVMName is finished." -ForegroundColor Green
  Write-Host "Do not forget to change/set the network configuration!" -ForegroundColor Red

  #Re-run?
  Write-Host "Re-run script?" -ForegroundColor Yellow
  Write-Host $yesResponse -ForegroundColor Yellow -NoNewline
  Write-Host "$noResponse : " -ForegroundColor White -NoNewline
  $userResponse = (Read-Host).ToUpper()
  switch ($userResponse) {
    "Y" { $Repeat = $true; break }
    "N" { Write-Host "Finished running the script" -ForegroundColor Green; $Repeat = $false; exit }
    Default { Write-Host "Invalide Response"; Write-Host "Exiting" -ForegroundColor Green; $Repeat = $false; exit }
  }              
}
