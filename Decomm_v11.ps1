
function add-module
{
    Add-PSSnapin SwisSnapin
    Import-Module ActiveDirectory
    $vcenters = "server", "server","server", "server", "server"
    $display = Connect-VIServer -Server $vcenters
    log " "
    log "Connected to below vCenters:" yellow
    $display
    $key = Get-Content "c:\temp\SharedPath\AES.key"
    $Dpassword = get-content c:\temp\SharedPath\DPassword.txt | convertto-securestring -Key $key
    $domaincred = new-object -typename System.Management.Automation.PSCredential -argumentlist "domain\account",$Dpassword
    New-PSDrive -Name Y -PSProvider FileSystem -Root \\server\c$ -Credential $domaincred -Scope global

}

function log($string, $color)
{
   if ($Color -eq $null) {$color = "white"}
   write-host $string -foregroundcolor $color
   $string | out-file -Filepath $global:logfile -append
}

Function Decomm-Server 
{
    [CmdletBinding()]
    Param(
    [Parameter(ValueFromPipeline=$true)]
    $Server,
    $displayloop=1
    )
    process
    {
        $server_getvm = get-vm $server -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | where {$_.ExtensionData.Config.ManagedBy.extensionKey -NotLike "com.vmware.vcDr-*"}

        If ($server_getvm)
        { 
            $serverinfo = $server_getvm | % {[PSCustomObject] @{Name = $_.Name
            vCenter = $_.Uid.Substring($_.Uid.IndexOf('@')+1).Split(":")[0]
            }
            }
            $servervcenter = $serverinfo.vCenter
            log " "
            log "($displayloop of $global:count Servers)" Yellow
            log "Decomming $server..." yellow
            if ($servervcenter -eq "as1svsctr01") {$VMFolder = get-folder -name $global:folder -location "To Be Deleted" -Server $servervcenter -ErrorAction SilentlyContinue -NoRecursion}
            $VMFolder = get-folder -name $global:folder -location "To Be Deleted" -Server $servervcenter -ErrorAction SilentlyContinue -NoRecursion
            if (!$VMFolder) 
            {
                get-folder -name "To Be Deleted" -Server $servervcenter | select -first 1 | new-folder -name $global:folder| out-file $global:logfile -Append
            }
            if ($server_getvm.powerstate -ne "PoweredOff") 
            {
                if ($server_getvm.ExtensionData.Guest.ToolsStatus -eq "toolsOk") {Stop-VMguest -VM $server -Server $servervcenter -confirm:$false | out-file $global:logfile -Append}
                else {Stop-VM -VM $server -Server $servervcenter -confirm:$false | out-file $global:logfile -Append}
                log "Shutting down $server..." yellow
            }
            while ($server_getvm.ExtensionData.Runtime.PowerState -eq "poweredOn")
            {
                Start-Sleep -Seconds 2
                $server_getvm.ExtensionData.UpdateViewData("Runtime.PowerState")
            }
            log "$Server is shutdown" yellow
            log "Please Wait..." yellow
            move-vm $Server -Server $servervcenter -Destination $global:folder | out-file $global:logfile -Append
            log "$server moved to \To Be Deleted\$global:folder on $servervcenter" yellow
            try
            {

                if ($server.StartsWith("cd","CurrentCultureIgnoreCase"))
                {
                    $serverAD = get-adcomputer $Server -Server server -ErrorAction Stop
                    log "Disabling $server and moving to Computers to Delete OU in Dev..." Yellow
                    $serverAD | Disable-ADAccount | out-file $global:logfile -Append
                    $serverAD | Move-ADObject -TargetPath "OU=Computers to Delete,DC=info,DC=com" | out-file $global:logfile -Append
                    log "...Done" Yellow
                    Get-ADComputer $Server -Server server | select name, enabled, DistinguishedName | ft -AutoSize | tee-object $global:logfile -Append
                
                }
                else
                {
                    $serverAD = get-adcomputer $Server -ErrorAction Stop
                    log "Disabling $server and moving to Computers to Delete OU..." Yellow
                    $serverAD | Disable-ADAccount | out-file $global:logfile -Append
                    $serverAD | Move-ADObject -TargetPath "OU=Computers to Delete,DC=location,DC=com" | out-file $global:logfile -Append
                    log "...Done" Yellow
                    Get-ADComputer $Server | select name, enabled, DistinguishedName | ft -AutoSize | tee-object $global:logfile -Append
                }
            }

            Catch
            {
                log "Could not reach $server in AD" yellow

            }

            try
            {     
                if ([System.Net.DNS]::GetHostEntry($Server))
                {
                    $ipaddress = [system.net.dns]::GetHostAddresses($Server).IPAddressToString
                    dnscmd 2.2.2.2 /RecordDelete domain.com $server A $ipaddress /f
                    log "$server $ipaddress removed from domain.COM DNS" yellow
                }
            
            
            }
            catch {log "$server is not in domain.COM DNS" red}

            Try
            {
                if ($server.StartsWith("cd","CurrentCultureIgnoreCase"))
                {
                    dnscmd server /RecordDelete dev.com $server A /f
                    log "$server $ipaddress removed from dev.com DNS" yellow
                }
            }

            Catch {log "$server is not in domain.com DNS" red}

            $SCCMcomp = gwmi -cn $Global:SCCMServer -namespace root\sms\site_$($Global:sitename) -class sms_r_system -filter "Name='$($server)'"
            if ($SCCMcomp)
            {
                $SCCMcomp.delete() | Tee-Object $global:logfile -Append
                log "$server removed from SCCM" yellow
            }
            Else {log "$server was not in SCCM" red}
            $uri = Get-SwisData $global:swis "SELECT TOP 1 URI FROM Orion.Nodes WHERE NodeName = '$server'"
            if ($uri)
            {
                Remove-SwisObject $global:swis $uri
                Log "$server removed from SolarWinds" yellow
            }
            else {Log "$server was not in SolarWinds" red}
            $displayloop ++
        }

        Else {Log "Cannot find $server in vCenters" red}

    }

} 
cls

$servers = gc C:\temp\verify9\dcom.txt
$logtime = Get-date -Format "MM-dd-yyyy_hh-mm-ss"
$global:logfile = 'C:\temp\'+"ServerDecomm_"+$logtime+".txt"
$date = (get-date).addmonths(1)
$global:folder = $date.ToString('MM-dd-yyyy').replace("/", "-")
$global:SCCMServer = "server" 
$global:sitename = "info" 
write-output ("Script started at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $global:logfile -Append
$global:count = $servers.Count
log "Connecting to vCenters, Please Wait..." Yellow
add-module
$global:swis = Connect-Swis -trusted -Hostname status
$servers | Decomm-Server
log "DONE" green
write-output ("Script stopped at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $global:logfile -Append
Remove-PSDrive y
Disconnect-VIServer * -Confirm:$false