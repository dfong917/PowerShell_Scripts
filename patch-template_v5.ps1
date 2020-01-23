add-pssnapin VMware.VimAutomation.Core
$vcenters = "server"
Connect-VIServer $vcenters

#Show Progress
$WarningPreference = "SilentlyContinue"
$results =@()
$showProgress = $true
$key = Get-Content "c:\temp\SharedPath\AES.key"
$Lpassword = get-content c:\temp\SharedPath\LPassword.txt | convertto-securestring -Key $key

$updateTempNames = gc C:\temp\Newfolder1\template.txt


$logRoot = "C:\temp\Newfolder1\logs"
$log = New-Object -TypeName "System.Text.StringBuilder" "";

function writeLog {
    $logtime = Get-date -Format "MM-dd-yyyy_hh-mm-ss"
    write-host "This is logtime $logtime"
    $filename = "Template-Update-" + $logtime + ".log"
    write-host "This is filename $filename"
	$exist = Test-Path $logRoot\$filename
    write-host "This is exist $exist"
	$logFile = New-Object System.IO.StreamWriter("$logroot\$filename", $exist)
	$logFile.write($log)
	$logFile.close()
    write-host "This is logfile $logfile"
}

[void]$log.appendline((("[Start Batch - ")+(get-date)+("]")))


#---------------------
#Update Template
#---------------------
$date = (get-date)
$templatedate = $date.ToString('MMddyyyy')
foreach ($updateTempName in $updateTempNames) 
{
    try 
    {
	    #Get Template
        #clone new template
        if (($updateTempName -split '_')[0] -eq "AM")
        {
            $vcenter = "server"
            $Luserid = "account"
        }
        if (($updateTempName -split '_')[0] -eq "AM2")
        {
            $vcenter = "server1"
            if ($updateTempName -match "2016") {$Luserid = "account"}
            else {$Luserid = "account"}

        }
        if (($updateTempName -split '_')[0] -eq "EU1")
        {
            $vcenter = "server"
            if ($updateTempName -match "2016") {$Luserid = "account"}
            else {$Luserid = "account"}

        }
        if (($updateTempName -split '_')[0] -eq "EU2")
        {
            $vcenter = "server"
            if ($updateTempName -match "2016") {$Luserid = "account"}
            else {$Luserid = "account"}

        }
        if (($updateTempName -split '_')[0] -eq "AAA")
        {
            $vcenter = "server"
            if ($updateTempName -match "2016") {$Luserid = "acct"}
            else {$Luserid = "acct"}

        }
        
        
        $oldTemplate = Get-Template -Name $updateTempName -Server $vcenter
        $myDs = Get-Datastore -Name $oldtemplate.ExtensionData.Config.DatastoreUrl.name
        if ($oldtemplate -match "PVSCSI") {$newTemplate = ($updateTempName -split '_')[0] + "_" + ($updateTempName -split '_')[1] + "_" + $templatedate + "_PVSCSI"}
        else {$newTemplate = $updatetempname.SubString(0, $updatetempname.LastIndexOf('_')) + "_" + $templatedate}
        


        if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Cloning Template: $($updateTempName) to $newTemplate" -PercentComplete 5 }
	    [void]$log.appendline("Cloning Template: $($updateTempName) to $newTemplate")
        $results += New-Template -Server $vcenter -Template $oldTemplate -Name $newTemplate -Datastore $myDs -Location "Templates"
	    $template = Get-Template $newTemplate -Server $vcenter

	    #Convert Template to VM
	    if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Converting Template: $($newTemplate) to VM" -PercentComplete 10 }
	    [void]$log.appendline("Converting Template: $($newTemplate) to VM")
	    $results += $template | Set-Template -ToVM -Server $vcenter -Confirm:$false

	    #Start VM
	    if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Starting VM: $($newTemplate)" -PercentComplete 20 }
	    [void]$log.appendline("Starting VM: $($newTemplate)")
	    #Get-VM $newTemplate | Start-VM -RunAsync:$RunAsync
        $results += Start-VM -VM $newTemplate -Server $vcenter -Confirm:$false -ErrorAction Stop

	    #Wait for VMware Tools to start
	    if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Waiting for: $($newTemplate) to start VMwareTools" -PercentComplete 30 }
	    [void]$log.appendline("Giving VM: $($newTemplate) to start VMwareTools")
	    #sleep 30
        $results += Wait-Tools -VM $newTemplate -Server $vcenter -ErrorAction Stop


	    #Script to run on VM
	    $script = "Function WSUSUpdate {
		    param ( [switch]`$rebootIfNecessary,
				  [switch]`$forceReboot)  
		    `$Criteria = ""IsInstalled=0 and Type='Software' and AutoSelectOnWebsites=1""
		    `$Searcher = New-Object -ComObject Microsoft.Update.Searcher
		    try {
			    `$SearchResult = `$Searcher.Search(`$Criteria).Updates
			    if (`$SearchResult.Count -eq 0) {
				    Write-Output ""There are no applicable updates first.""
				    exit
			    } 
			    else {
				    `$Session = New-Object -ComObject Microsoft.Update.Session
				    `$Downloader = `$Session.CreateUpdateDownloader()
				    `$Downloader.Updates = `$SearchResult
				    `$Downloader.Download()
				    `$Installer = New-Object -ComObject Microsoft.Update.Installer
				    `$Installer.Updates = `$SearchResult
				    `$Result = `$Installer.Install()
			    }
		    }
		    catch {
			    Write-Output ""There are no applicable updates second.""
                stop-Computer -Force
		    }
		    If(`$rebootIfNecessary.IsPresent) { If (`$Result.rebootRequired) { stop-Computer -Force} }
		    If(`$forceReboot.IsPresent) { stop-Computer -Force }
	    }
	    WSUSUpdate -rebootIfNecessary
	    "
	
	    #Running Script on Guest VM
	    if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Running Patching Script on Guest VM: $($newTemplate)" -PercentComplete 40 }
	    [void]$log.appendline("Running Script on Guest VM: $($newTemplate)")
        $serverinfo = Get-VM $newTemplate -Server $vcenter
        $localcred = new-object -typename System.Management.Automation.PSCredential -argumentlist $Luserid,$Lpassword
        $scriptresults = Invoke-VMScript -VM $newTemplate -ScriptText $script -GuestCredential $localcred -Server $vcenter
	    $nopatches = @()
        $nopatches = $scriptresults | out-string

        if ($nopatches | select-string -Pattern "There are no applicable updates") 
        {
            write-host "There are no patches - $newTemplate will be turned off and converted to Template" -ForegroundColor Red
            #Wait for Windows Updates to finish after reboot
	        if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Waiting for VM: $($newTemplate) to Shutdown after finding No Windows Updates" -PercentComplete 50 }
	        [void]$log.appendline("Waiting for VM: $($newTemplate) to reboot after Windows Updates")
            while ($serverinfo.ExtensionData.Runtime.PowerState -eq "poweredOn")
            {
                Start-Sleep -Seconds 2
                $serverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
            }
             #Convert VM back to Template
	        if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Convert VM: $($newTemplate) to template" -PercentComplete 100 }
	        [void]$log.appendline("Convert VM: $($newTemplate) to template")
            $results += Set-VM -VM $newTemplate -ToTemplate -Server $vcenter -Confirm:$false
        
        
        
        }
        else
        {
	        #Wait for Windows Updates to finish after reboot
	        if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Waiting for VM: $($newTemplate) to reboot after Windows Updates" -PercentComplete 50 }
	        [void]$log.appendline("Waiting for VM: $($newTemplate) to reboot after Windows Updates")
	        #sleep 600
            while ($serverinfo.ExtensionData.Runtime.PowerState -eq "poweredOn")
            {
                Start-Sleep -Seconds 2
                $serverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
            }

	        #Waiting for VM to Power on
        
	        if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Waiting for VM: $($newTemplate) to power back on" -PercentComplete 60 }
	        [void]$log.appendline("Shutting Down VM: $($newTemplate)")
            $results += Start-VM -VM $newTemplate -Server $vcenter -Confirm:$false | Wait-Tools -ErrorAction Stop

            #check second time if any patches needed
            if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Running Patching Script (SECOND TIME) on Guest VM: $($newTemplate)" -PercentComplete 70 }
	        [void]$log.appendline("Running Script on Guest VM: $($newTemplate)")
            $scriptresults = Invoke-VMScript -VM $newTemplate -ScriptText $script -GuestCredential $localcred -Server $vcenter
	        $nopatches = @()
            $nopatches = $scriptresults | out-string
            if ($nopatches | select-string -Pattern "There are no applicable updates") {write-host "There are no additional Patches" -ForegroundColor Red}
            Else
            {
                #Wait for Windows Updates to finish after reboot
	            if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Waiting for VM: $($newTemplate) to reboot after Windows Updates (SECOND TIME)" -PercentComplete 75 }
	            [void]$log.appendline("Waiting for VM: $($newTemplate) to reboot after Windows Updates")
	            #sleep 600
                while ($serverinfo.ExtensionData.Runtime.PowerState -eq "poweredOn")
                {
                    Start-Sleep -Seconds 2
                    $serverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
                }
                if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Waiting for VM: $($newTemplate) to power back on (SECOND TIME)" -PercentComplete 80 }
	            [void]$log.appendline("Shutting Down VM: $($newTemplate)")
                $results += Start-VM -VM $newTemplate -Server $vcenter -Confirm:$false | Wait-Tools -ErrorAction Stop

            }
    
            #remove Cert if exists

            if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Removing Cert for VM: $($newTemplate)" -PercentComplete 85 }
	        [void]$log.appendline("Checking and Removing Cert on VM: $($newTemplate)")
            $script2 = 'Get-ChildItem Cert:\LocalMachine\MY | Where-Object {($_.dnsnamelist  -match "2012R2") -AND ($_.Subject -notmatch "CN=$env:COMPUTERNAME")} | Remove-Item -Verbose'
            $results += Invoke-VMScript -VM $newTemplate -ScriptText $script2 -GuestCredential $localcred -Server $vcenter

	        #Shutdown VM
	        if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Waiting for VM: $($newTemplate) to finish Shutting Down" -PercentComplete 90 }
	        [void]$log.appendline("Waiting for VM: $($newTemplate) to finish Shutting Down")
	        sleep 30
            $results += Stop-VMGuest -vm $newTemplate -Server $vcenter -Confirm:$false
            $serverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
            while ($serverinfo.ExtensionData.Runtime.PowerState -eq "poweredOn")
            {
                Start-Sleep -Seconds 2
                $serverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
            }
	
	        #Convert VM back to Template
	        if($showProgress) { Write-Progress -Activity "Update Template..." -Status "Convert VM: $($newTemplate) to template" -PercentComplete 100 }
	        [void]$log.appendline("Convert VM: $($newTemplate) to template")
	        Get-VM $updateTempName | Set-VM -ToTemplate -Confirm:$false
            $results += Set-VM -VM $newTemplate -ToTemplate -Server $vcenter -Confirm:$false
            }
        }
    catch 
    { 


        write-host "Error"
        write-host "Working on next template..." -ForegroundColor Yellow
        $error[0]
    }

}





write-host "DONE" -ForegroundColor Green
[void]$log.appendline((("[End Batch - ")+(get-date)+("]")))

writeLog
disconnect-viserver * -confirm:$false