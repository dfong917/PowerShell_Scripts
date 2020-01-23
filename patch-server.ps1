 param(
  [CmdletBinding()]
  [parameter(Mandatory = $true)]
  [String[]]$servername,
  [String[]]$ip,
  [String[]]$vcenter
  )
$WarningPreference = "SilentlyContinue"
$key = Get-Content "c:\temp\SharedPath\AES.key"
$Lpassword = get-content c:\temp\SharedPath\LPassword.txt | convertto-securestring -Key $key
$Dpassword = get-content c:\temp\SharedPath\DPassword.txt | convertto-securestring -Key $key
$localcred = new-object -typename System.Management.Automation.PSCredential -argumentlist "account",$Lpassword
$domaincred = new-object -typename System.Management.Automation.PSCredential -argumentlist "domain\account",$Dpassword
$results =@()
$patchresults =@()
add-pssnapin VMware.VimAutomation.Core

$results += Connect-VIServer $vcenter -Credential $domaincred
cls

#Show Progress

$showProgress = $true
$host.ui.RawUI.WindowTitle = 'PATCHING' + ' ' + $Servername + '...Please Do Not Close!'




#Log Parameters and Write Log Function
$logRoot = "C:\temp\Newfolder1\logs"
$log = New-Object -TypeName "System.Text.StringBuilder" "";

function writeLog {
	$exist = Test-Path $logRoot\update-$servername.log
	$logFile = New-Object System.IO.StreamWriter("$logRoot\update-$($servername).log", $exist)
	$logFile.write($log)
	$logFile.close()
}



[void]$log.appendline((("[Start Batch - ")+(get-date)+("]")))
[void]$log.appendline($error)
#Credentials



try 
{

    #Script to run on VM
	$script = "Function WSUSUpdate {
	param ( [switch]`$rebootIfNecessary,
	[switch]`$forceReboot)  
	`$Criteria = ""IsInstalled=0 and Type='Software' and AutoSelectOnWebsites=1""
	`$Searcher = New-Object -ComObject Microsoft.Update.Searcher
	try {
	`$SearchResult = `$Searcher.Search(`$Criteria).Updates
	if (`$SearchResult.Count -eq 0) {
	Write-Output ""There are no applicable updates.""
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
	Write-Output ""There are no applicable updates.""
	}
	If(`$rebootIfNecessary.IsPresent) { If (`$Result.rebootRequired) { stop-Computer -Force} }
	If(`$forceReboot.IsPresent) { stop-Computer -Force }
	}
	WSUSUpdate -rebootIfNecessary
	"
	
	#Running Script on Guest VM
	if($showProgress) { Write-Progress -Activity "Patching Server" -Status "Running Patching Script on Guest VM: $($servername)" -PercentComplete 25 }
	[void]$log.appendline("Running Script on Guest VM: $($servername)")
    $serverinfo = Get-VM $servername

    $patchresults += Invoke-VMScript -VM $servername -ScriptText $script -GuestCredential $localcred   
	if ($patchresults -notmatch "There are no applicable updates") 
    {
        
	    #Wait for Windows Updates to finish after reboot
	    if($showProgress) { Write-Progress -Activity "Patching Server" -Status "Waiting for VM: $($servername) to reboot after Windows Updates" -PercentComplete 50 }
	    [void]$log.appendline("Waiting for VM: $($servername) to reboot after Windows Updates")
        while ($serverinfo.ExtensionData.Runtime.PowerState -eq "poweredOn")
        {
            Start-Sleep -Seconds 2
            $serverinfo.ExtensionData.UpdateViewData("Runtime.PowerState")
        }

	    #Waiting for VM to Power on
        
	    if($showProgress) { Write-Progress -Activity "Patching Server" -Status "Waiting for VM: $($servername) to power back on" -PercentComplete 75 }
	    [void]$log.appendline("Shutting Down VM: $($servername)")
        $results += Start-VM -VM $servername -Confirm:$false | Wait-Tools
	}
    if($showProgress) 
    { 
        Write-Progress -Activity "Patching Server" -Status "Completed.  $servername is Powered Back Online" -PercentComplete 100
        Start-Sleep -Seconds 3
    }    
    if ($showProgress) {Write-Progress -Activity "Patching Server" -Status "Completed.  $servername is Powered Back Online" -Completed} 
	    
}
    
catch 
{ 
	    [void]$log.appendline("Error:")
	    [void]$log.appendline($error)
	    Throw $error
	    #stops post-update copy of template
	    $updateError = $true
}



[void]$log.appendline("Done with Patching VM: $($servername)")
[void]$log.appendline((("[End Batch - ")+(get-date)+("]")))
Write-host "FINISHED" -ForegroundColor Green
write-host "Window will be Closed in 20 seconds..." -ForegroundColor yellow
Start-Sleep -Seconds 20 



writeLog