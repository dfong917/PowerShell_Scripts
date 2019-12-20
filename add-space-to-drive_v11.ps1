function log($string, $color)
{
   if ($Color -eq $null) {$color = "white"}
   write-host $string -foregroundcolor $color
   $string | out-file -Filepath $global:logfile -append
}


#This is latest working version
#11/14/2019 Added support for Servers with drives in multiple datastores
#11/22/2019 Added prompt to confirm Disk Space Add
#Variables
Connect-VIServer am1svsctr01, am2svsctr01, eu1svsctr01, eu2svsctr01, as1svsctr01
#$servername = "am2netser2012"
$scriptresults = @()
$driveexist = @()
$servers = import-csv c:\temp\adddrivespace.csv
$logtime = Get-date -Format "MM-dd-yyyy_hh-mm-ss"
$global:logfile = 'C:\temp\'+"AdddriveSpace_"+$logtime+".txt"
$count = @($servers).count
$displayloop = 1
write-output ("Script started at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) + "on Script: {$MyInvocation.ScriptName}"| out-file $global:logfile -Append



foreach ($server in $servers)
{
    log " " 
    log "($displayloop of $global:count Disk Space Adds)" Yellow
    $drive = $server.drive
    $driveexist = "No"
    $diskfile = "C:\temp\DiskInfo_" + $server.name + "_" + $logtime + ".csv"


    $ComputerName = $server.name
    $Vm = Get-VM -Name $server.name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Where-Object {$_.PowerState -ne "PoweredOff"}

    if ($vm)

    {
        
        $serverinfo = $vm | % {[PSCustomObject] @{Name = $_.Name
                    vCenter = $_.Uid.Substring($_.Uid.IndexOf('@')+1).Split(":")[0]
                    }
                    }
        $servervcenter = $serverinfo.vCenter

        if ($drive -match "c:")
        {
            if ($vm.guest -notmatch "2003")
            {
                Log "Server and OS:" yellow
                $vm | select name, guest | ft -AutoSize | tee-object $global:logfile -Append
                #$info | Get-HardDisk | select name, filename, capacitygb
                $results = Get-HardDisk -VM $vm -Server $servervcenter | select name, filename, capacitygb #| Out-String
                Log "Hard Disk Info:" yellow
                $results | out-string | tee-object $global:logfile -Append
                #$DSspace = $vm | Get-HardDisk -Server $servervcenter | Get-Datastore #| Out-String
                $DSspace = $vm | Get-HardDisk -Server $servervcenter | where {$_.Name -eq "hard disk 1"} | get-datastore
                #$DSspace = $vm | Get-HardDisk -Server $servervcenter| where {$_.Name -eq $obj_tempDiskInfos.vmWareDiskName} | Get-Datastore
                Log "DataStore Info:" yellow
                $DSspace | Out-String | tee-object $global:logfile -Append
                if ( ($dsspace.FreeSpaceGB / $dsspace.CapacityGB) -gt .09) 
                {
                    $Cdrive = $results | Where-Object {$_.name -EQ "Hard disk 1"}
                    $NewDiskSpace = $Cdrive.CapacityGB + $server.addspaceGB
                    $Addspace = $server.addspaceGB
                    #Log "Adding $addspace GB Disk Space on $vm for Drive $drive" yellow
                    Log "Add $addspace GB Disk Space on $vm for Drive $drive ?" yellow
                    do { $PromptInput = (Read-Host 'Do you want to Continue? (Y/N)').ToLower() } while ($PromptInput -notin @('y','n'))
                    if ($PromptInput -eq 'y')
                    {
                        Log "Adding $addspace GB Disk Space on $vm for Drive $drive" yellow
                        Get-HardDisk -vm $VM -Server $servervcenter | where {$_.Name -eq "hard disk 1"} | Set-HardDisk -CapacityGB $NewDiskSpace -Confirm:$false | out-string
                        $C_DiskPart = "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume C >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q"
                        #$scriptresults += 
                        Invoke-VMScript -VM $VM -Server $servervcenter -ScriptType bat -ScriptText $C_DiskPart *>> $global:logfile 
                        $value = Get-WMIObject Win32_Logicaldisk -filter "deviceid='C:'" -ComputerName $vm |
                        Select PSComputername,DeviceID,
                        @{Name="SizeGB";Expression={$_.Size/1GB -as [int]}},
                        @{Name="FreeGB";Expression={[math]::Round($_.Freespace/1GB,2)}}
                        log "$Addspace GB added to $vm on $drive" yellow
                        Log "New Disk Space Config:" yellow
                        $value | ft -AutoSize | tee-object $global:logfile -Append
                    }
                    Else {Log "$addspace GB Disk Space NOT ADDED to $vm for Drive $drive" red}
                }
                Else {log "Free Space below 9% for datastore: $dsspace.name" red}
            }
        
            Else {Write-host "$computername is a 2003 server" red}
        }


        Else #other than c: drive

        {

            $obj_DiskDrive = @()
            $obj_LogicalDisk = @()
            $obj_LogicalDiskToPartition = @()
            $obj_DiskDriveToDiskPartition = @()
            $obj_VMView = @()
            $obj_DiskInfos = @()


            #Get wmi objects
            $obj_DiskDrive = Get-WmiObject -Class win32_DiskDrive -ComputerName $ComputerName
            $obj_LogicalDisk = Get-WmiObject -Class Win32_LogicalDisk -ComputerName $ComputerName
            $obj_LogicalDiskToPartition = Get-WmiObject -Class Win32_LogicalDiskToPartition -ComputerName $ComputerName
            $obj_DiskDriveToDiskPartition = Get-WmiObject -Class Win32_DiskDriveToDiskPartition -ComputerName $ComputerName

            #Get vm               
            $obj_VMView = Get-View -ViewType VirtualMachine -Filter @{"Name" = "$($Vm.Name)"}

            #Get vm disk
            $obj_VMDisk = Get-HardDisk -VM $Vm

            #Match the informations      
            foreach ($obj_vmWareSCSIController in ($obj_VMView.Config.Hardware.Device | Where-Object -FilterScript {$_.DeviceInfo.Label -match "SCSI"})) 
            {
                foreach ($obj_vmWareDiskDevice in ($obj_VMView.Config.Hardware.Device | Where-Object -FilterScript {$_.ControllerKey -eq $obj_vmWareSCSIController.Key})) 
                {                                    
                    $obj_tempDiskInfos = "" | Select-Object -Property Date, vCenterName, vmName, vmWareSCSIController, wmWareSCSIID, vmWareDiskName, vmWareDiskFile,
                        vmWareSizeGB, WindowsSerialNumber, WindowsSCSIBus, WindowsSCSILogicalUnit, WindowsSCSIPort, WindowsSCSITargetId, WindowsDisk, WindowsDriveLetter,
                        WindowsLocicalDiskSizeGB, WindowsLocicalDiskFreeSpaceGB, WindowsLocicalDiskUsedSpaceGB

                    #Select WMI object
                    $obj_currentDiskDrive = @()
                    $obj_currentDiskDrive = $obj_DiskDrive | Where-Object -FilterScript {$_.SerialNumber -eq $obj_vmWareDiskDevice.Backing.Uuid.Replace("-","")}

                    $obj_currentDiskDriveToDiskPartition = @()
                    $obj_currentDiskDriveToDiskPartition = $obj_DiskDriveToDiskPartition | Where-Object -FilterScript {$_.Antecedent -eq $obj_currentDiskDrive.Path}

                    $obj_currentLogicalDiskToPartition = @()
                    $obj_currentLogicalDiskToPartition = $obj_LogicalDiskToPartition | Where-Object -FilterScript {$_.Antecedent -eq $obj_currentDiskDriveToDiskPartition.Dependent}

                    $obj_currentLogicalDisk = @()
                    $obj_currentLogicalDisk = $obj_LogicalDisk | Where-Object -FilterScript {$_.Path.Path -eq $obj_currentLogicalDiskToPartition.Dependent}

                    #Select vmWare object
                    $obj_CurrentvmWareHarddisk = @()
                    $obj_CurrentvmWareHarddisk = $obj_VMDisk | Where-Object -FilterScript {$_.Name -eq $obj_vmWareDiskDevice.DeviceInfo.Label}

                    #Generate output
                    $obj_tempDiskInfos.Date = Get-Date -Format "yyyy.MM.dd HH:mm:ss"
                    $obj_tempDiskInfos.vCenterName = $defaultVIServer.Name
                    $obj_tempDiskInfos.vmName = $Vm.Name
                    $obj_tempDiskInfos.vmWareSCSIController = $obj_vmWareSCSIController.DeviceInfo.Label
                    $obj_tempDiskInfos.wmWareSCSIID = "$($obj_vmWareSCSIController.BusNumber) : $($obj_vmWareDiskDevice.UnitNumber)"
                    $obj_tempDiskInfos.vmWareDiskName = $obj_vmWareDiskDevice.DeviceInfo.Label
                    $obj_tempDiskInfos.vmWareDiskFile = $obj_vmWareDiskDevice.Backing.FileName
                    $obj_tempDiskInfos.vmWareSizeGB = $obj_CurrentvmWareHarddisk.CapacityGB              
                    $obj_tempDiskInfos.WindowsSerialNumber = $obj_currentDiskDrive.SerialNumber
                    $obj_tempDiskInfos.WindowsSCSIBus = $obj_currentDiskDrive.SCSIBus
                    $obj_tempDiskInfos.WindowsSCSILogicalUnit = $obj_currentDiskDrive.SCSILogicalUnit
                    $obj_tempDiskInfos.WindowsSCSIPort = $obj_currentDiskDrive.SCSIPort
                    $obj_tempDiskInfos.WindowsSCSITargetId = $obj_currentDiskDrive.SCSITargetId
                    $obj_tempDiskInfos.WindowsDisk = $obj_currentDiskDrive.Path.Path
                    $obj_tempDiskInfos.WindowsDriveLetter = ($obj_currentLogicalDisk).Caption
                    $obj_tempDiskInfos.WindowsLocicalDiskSizeGB = $obj_currentLogicalDisk.Size / 1GB
                    $obj_tempDiskInfos.WindowsLocicalDiskFreeSpaceGB = $obj_currentLogicalDisk.FreeSpace / 1GB
                    $obj_tempDiskInfos.WindowsLocicalDiskUsedSpaceGB = ($obj_currentLogicalDisk.Size / 1GB) - ($obj_currentLogicalDisk.FreeSpace / 1GB)
                    if ($obj_tempDiskInfos.WindowsDriveLetter -match $server.drive)
                    {
                        #add drive
                        $driveexist = "Yes"
                        #$results = Get-HardDisk -VM $vm -Server $servervcenter | select name, filename, capacitygb #| Out-String
                        $results = Get-HardDisk -VM $vm -Server $servervcenter | where {$_.Name -eq $obj_tempDiskInfos.vmWareDiskName} | Select @{Name="DriveLetter";Expression={$obj_tempDiskInfos.WindowsDriveLetter}}, CapacityGB, Name, Filename
                        Log "Hard Disk Info for $VM :" yellow
                        $results | out-string | tee-object $global:logfile -Append
                       
                        $DSspace = $vm | Get-HardDisk -Server $servervcenter| where {$_.Name -eq $obj_tempDiskInfos.vmWareDiskName} | Get-Datastore #| Out-String
                        
                        Log "DataStore Info:" yellow
                        $DSspace | Out-String | tee-object $global:logfile -Append
                        if ( ($dsspace.FreeSpaceGB / $dsspace.CapacityGB) -gt .09) 
                        {
                            $adddrive = $results | Where-Object {$_.name -EQ $obj_tempDiskInfos.vmWareDiskName}
                            $NewDiskSpace = $adddrive.CapacityGB + $server.addspaceGB
                    
                            $Addspace = $server.addspaceGB
                            Log "Add $addspace GB Disk Space on $vm for Drive $drive ?" yellow
                            do { $PromptInput = (Read-Host 'Do you want to Continue? (Y/N)').ToLower() } while ($PromptInput -notin @('y','n'))
                            if ($PromptInput -eq 'y')
                            {
                                Get-HardDisk -vm $VM -Server $servervcenter | where {$_.Name -eq $obj_tempDiskInfos.vmWareDiskName} | Set-HardDisk -CapacityGB $NewDiskSpace -Confirm:$false | out-string
                                $driveletter = $obj_tempDiskInfos.WindowsDriveLetter.Trim(":"," ")
                                $ADD_DiskPart = "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume $driveletter >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q"
                                #$scriptresults += 
                                Invoke-VMScript -VM $VM -Server $servervcenter -ScriptType bat -ScriptText $ADD_DiskPart *>> $global:logfile 
                                $value = Get-WMIObject Win32_Logicaldisk -filter "deviceid='$drive'" -ComputerName $vm |
                                Select PSComputername,DeviceID,
                                @{Name="SizeGB";Expression={$_.Size/1GB -as [int]}},
                                @{Name="FreeGB";Expression={[math]::Round($_.Freespace/1GB,2)}},
                                @{Name="VM DISK";Expression={$obj_tempDiskInfos.vmWareDiskName}},
                                @{Name="Datastore";Expression={$DSspace.name}}
                                log "$Addspace GB added to $vm on $drive" yellow
                                Log "New Disk Space Config:" yellow
                                $value | ft -AutoSize | tee-object $global:logfile -Append
                            }
                            Else {Log "$addspace GB Disk Space NOT ADDED to $vm for Drive $drive" red}
                    
                        }
                        Else {log "Free Space below 9% for datastore: $dsspace.name for $computername" red}
                    }
                    #$obj_DiskInfos += $obj_tempDiskInfos
                }
            }

            If ($driveexist -eq "No") {log "Drive Letter $drive not found on $ComputerName" red}
        }
    }
    else {Log "$computername server not found" red}
    $displayloop ++
}


log "DONE" green
Disconnect-VIServer * -Confirm:$false
write-output ("Script stopped at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $global:logfile -Append
