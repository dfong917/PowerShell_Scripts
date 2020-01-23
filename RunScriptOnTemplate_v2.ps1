                  


Function Start-Wait($seconds,$msg) { 
     $doneDT = (Get-Date).AddSeconds($seconds) 
     while($doneDT -gt (Get-Date)) { 
         $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds 
         $percent = ($seconds - $secondsLeft) / $seconds * 100 
         Write-Progress -Activity "Working..." -Status "$msg..." -SecondsRemaining $secondsLeft -PercentComplete $percent 
         [System.Threading.Thread]::Sleep(500) 
     } 
     Write-Progress -Activity "Working" -Status "$msg..." -SecondsRemaining 0 -Completed 
 }

add-pssnapin VMware.VimAutomation.Core
$vcenters = "servers"
Connect-VIServer $vcenters
$results =@()
$key = Get-Content "c:\temp\SharedPath\AES.key"
$Lpassword = get-content c:\temp\SharedPath\LPassword.txt | convertto-securestring -Key $key
$batchfile = 'PowerShell.exe -ExecutionPolicy Bypass -File c:\temp\CryptoSettings.ps1' 
$pcommand = "Get-WindowsFeature FS-SMB1 | ft -autosize"
$smbremove = "Disable-WindowsOptionalFeature -Online -FeatureName smb1protocol -norestart"
$smbprotocol = "Get-SmbServerConfiguration | Select EnableSMB1Protocol"
$enableprotocol = 'Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -confirm:$false'


$updatetempnames = Get-Content c:\temp\updatetemplates.txt

foreach ($updateTempName in $updateTempNames) 
{   
	    #Get Template
        #clone new template
        switch (($updateTempName -split '_')[0])
        {

            AM1
            {
                $vcenter = "server"
                $Luserid = "acct"
            }
            AM2
            {
                $vcenter = "server"
                if ($updateTempName -match "2016") {$Luserid = "acct"}
                else {$Luserid = "acct"}

            }
            EU1
            {
                $vcenter = "server"
                if ($updateTempName -match "2016") {$Luserid = "server"}
                else {$Luserid = "acct"}

            }
            EU2
            {
                $vcenter = "server"
                if ($updateTempName -match "2016") {$Luserid = "acct"}
                else {$Luserid = "acct"}

            }
            AAA
            {
                $vcenter = "server"
                if ($updateTempName -match "2016") {$Luserid = "acct"}
                else {$Luserid = "acct"}
            }


        }
        $localcred = new-object -typename System.Management.Automation.PSCredential -argumentlist $Luserid,$Lpassword
        write-host "Converting Template $updateTempName to VM.." -ForegroundColor Yellow
        Set-Template -Template $updateTempName -ToVM -Server $vcenter -Confirm:$false
        write-host "Starting VM $updateTempName..." -ForegroundColor Yellow
        Start-VM -VM $updateTempName -Server $vcenter -Confirm:$false | Wait-Tools
        Start-Wait -seconds 60 -msg "Waiting for $updateTempName to Start..."
        Copy-VMGuestFile -Source "c:\temp\CryptoSettings.ps1" -Destination "c:\temp\" -VM $updateTempName -LocalToGuest -GuestCredential $localcred -Server $vcenter -Force
        Invoke-VMScript -VM $updatetempname -GuestCredential $localcred -Server $vcenter -ScriptType bat -ScriptText $batchfile -Verbose
        Start-Wait -seconds 60 -msg "Running Crypto Script..."
        write-host "Crypto Script is done..." -ForegroundColor Yellow
        write-host "Checking SMB status on $updatetempname..." -ForegroundColor Yellow
        $smbresult = Invoke-VMScript -VM $updatetempname -GuestCredential $localcred -Server $vcenter -ScriptType Powershell -ScriptText $pcommand -Verbose
        $smbresult
        if ($smbresult -match "Installed")
        { 
          write-host "Removing SMB1 from features on $updatetempname" -ForegroundColor Yellow
          Invoke-VMScript -VM $updatetempname -GuestCredential $localcred -Server $vcenter -ScriptType Powershell -ScriptText $smbremove -Verbose    
        }

        write-host "Checking SMB Protocol status on $updatetempname..." -ForegroundColor Yellow
        $smbprotocolresult = Invoke-VMScript -VM $updatetempname -GuestCredential $localcred -Server $vcenter -ScriptType Powershell -ScriptText $smbprotocol -Verbose
        $smbprotocolresult
        if ($smbprotocolresult -match "false") 
        {  
           write-host "Enabling SMBV1 on $updatetempname..." -foregroundcolor yellow
           Invoke-VMScript -VM $updatetempname -GuestCredential $localcred -Server $vcenter -ScriptType Powershell -ScriptText $enableprotocol -Verbose   
           write-host "Double Checking SMB Protocol status on $updatetempname..." -ForegroundColor Yellow
           $smbprotocolresult = Invoke-VMScript -VM $updatetempname -GuestCredential $localcred -Server $vcenter -ScriptType Powershell -ScriptText $smbprotocol -Verbose
           $smbprotocolresult
        }


        write-host "Restarting Template $updateTempName..." -ForegroundColor Yellow
        $serverinfo = Get-VM $updatetempname -Server $vcenter
        $results += restart-VMGuest -vm $updateTempName -Server $vcenter -Confirm:$false | wait-tools
        Start-Wait -seconds 90 -msg "Waiting for $updateTempName to Restart..."
        write-host "$updatetempname is powered back on..." -ForegroundColor Yellow
        Invoke-VMScript -VM $updateTempName -GuestCredential $localcred -Server $vcenter -ScriptType bat -ScriptText "del c:\temp\cryptosettings.ps1" -Verbose
        write-host "Shutting down template $updateTempName..." -ForegroundColor Yellow
        $results += Stop-VMGuest -vm $updateTempName -Server $vcenter -Confirm:$false
        $serverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
        while ($serverinfo.ExtensionData.Runtime.PowerState -eq "poweredOn")
        {
           Start-Sleep -Seconds 2
           $serverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
        }
        $vminfo = get-vm $updateTempName -Server $vcenter
        set-vm $vminfo -Notes "$($vminfo.Notes) `nAdded CryptoSettings.ps1" -Confirm:$false
        
        write-host "Converting $updatetempname back to template..." -ForegroundColor Yellow
        Set-VM -VM $updateTempName -ToTemplate -Server $vcenter -Confirm:$false
        write-host "Done for $updatetempname" -ForegroundColor Green


}


Disconnect-VIServer * -Confirm:$false







