function Start-Wait($seconds,$msg) { 
     $doneDT = (Get-Date).AddSeconds($seconds) 
     while($doneDT -gt (Get-Date)) { 
         $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds 
         $percent = ($seconds - $secondsLeft) / $seconds * 100 
         Write-Progress -Activity "Working..." -Status "$msg..." -SecondsRemaining $secondsLeft -PercentComplete $percent 
         [System.Threading.Thread]::Sleep(500) 
     } 
     Write-Progress -Activity "Working" -Status "$msg..." -SecondsRemaining 0 -Completed 
 }

$showProgress = $true
$results = @()
$SVCresults = @()
Connect-VIServer server


#stop all services
Write-host "Stopping SolarWinds Services on server" -ForegroundColor Yellow
get-service -ComputerName server -DisplayName solar* | Stop-Service
Start-Wait -seconds 10 -msg "Waiting 10 seconds..."
get-service -ComputerName server -DisplayName solar* | ft -AutoSize
#restart db server
write-host "Working on server..." -ForegroundColor Yellow
$DBserverinfo = Get-vm server
if($showProgress) { Write-Progress -Activity "Restarting DB Server..." -Status "Waiting for VM server to REBOOT" -PercentComplete 25 }

        $results += Stop-VMGuest server -Server server -Confirm:$false
        $DBserverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
        while ($DBserverinfo.ExtensionData.Runtime.PowerState -eq "poweredOn")
        {
            Start-Sleep -Seconds 2
            $DBserverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
        }
if($showProgress) { Write-Progress -Activity "Restarting DB Server..." -Status "Waiting for VM server to power back on" -PercentComplete 50 }
        $results += Start-VM -VM server -Server server -Confirm:$false | Wait-Tools -TimeoutSeconds 180
        Start-Wait -seconds 30 -msg "Waiting 30 seconds..."
#wait to db server comes back online

write-host "Checking SQL Services on server" -ForegroundColor Yellow

$SVCresults = get-service -ComputerName server -name mssqlserver -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
write-host "Checking services on server" -ForegroundColor Yellow

 while ($SVCresults.Status -ne "running")
    {
       Start-Sleep -Seconds 10
       $SVCresults = get-service -ComputerName server -name mssqlserver -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    }
write-host "server is ONLINE" -ForegroundColor Green
get-service -ComputerName server -DisplayName SQL* | ft -AutoSize
write-host "Working on server..." -ForegroundColor Yellow
$ORIONserverinfo = Get-VM server
#restart server
if($showProgress) { Write-Progress -Activity "Restarting Orion Server..." -Status "Waiting for VM server to REBOOT" -PercentComplete 75 }
        $results += Stop-VMGuest server -Server server -Confirm:$false
        $ORIONserverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
        while ($ORIONserverinfo.ExtensionData.Runtime.PowerState -eq "poweredOn")
        {
            Start-Sleep -Seconds 2
            $ORIONserverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
        }

if($showProgress) { Write-Progress -Activity "Restarting Orion Server..." -Status "Waiting for VM server to power back on" -PercentComplete 85 }
        $results += Start-VM -VM server -Server server -Confirm:$false | Wait-Tools -TimeoutSeconds 180
        Start-Wait -seconds 30 -msg "Waiting 30 seconds..."
#verify
write-host "Checking Services on server" -ForegroundColor Yellow
$SVCresults = get-service -ComputerName server -name OrionModuleEngine -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

while ($SVCresults.Status -ne "running")
{
       Start-Sleep -Seconds 10
       $SVCresults = get-service -ComputerName server -name OrionModuleEngine -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}

write-host "server is back online" -ForegroundColor Yellow
get-service -ComputerName server -DisplayName solar* | ft -AutoSize
Disconnect-VIServer server -Confirm:$false