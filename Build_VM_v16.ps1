 #Adding EU1
 #Changing disk size for PV drives
 #added AS1
 
 param(
  [CmdletBinding()]
  [parameter(Mandatory = $true)]
  [String[]]$Global:Filename
  )

function log($string, $color, [ValidateSet("True","False")] $Sameline)
{
   if ($Color -eq $null) {$color = "white"}
   if ($sameline -eq "true") {write-host -NoNewline $string -foregroundcolor $color}
   Else {write-host $string -foregroundcolor $color}
   $string | out-file -Filepath $global:logfile -append
}

Function Login-vCenter ($Domain_login)
{
    
    Add-PSSnapin VMware.VimAutomation.Core
    Switch ($Global:Filename)
    {
      {$_ -match "AM2"} {Connect-VIServer AM2SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append; break}
      {$_ -match "AM1"} {Connect-VIServer AM1SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append; break}
      {$_ -match "EU1"} {Connect-VIServer EU1SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append; break}
      {$_ -match "EU2"} {Connect-VIServer EU21SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append; break}
      {$_ -match "AS1"} {Connect-VIServer AS1SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append; break}
    
    } 
    #if ($Global:Filename -match "AM2") {Connect-VIServer AM2SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append}
    #if ($Global:Filename -match "AM1") {Connect-VIServer AM1SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append}
    #if ($Global:Filename -match "EU1") {Connect-VIServer EU1SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append}
    #if ($Global:Filename -match "EU2") {Connect-VIServer EU2SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append}
    #if ($Global:Filename -match "AS1") {Connect-VIServer AS1SVSCTR01 -Credential $Domain_login | Out-File $global:logfile -Append}

}

function Get-FolderByPath{
  <# .SYNOPSIS Retrieve folders by giving a path .DESCRIPTION The function will retrieve a folder by it's path. The path can contain any type of leave (folder or datacenter). .NOTES Author: Luc Dekens .PARAMETER Path The path to the folder. This is a required parameter. .PARAMETER Path The path to the folder. This is a required parameter. .PARAMETER Separator The character that is used to separate the leaves in the path. The default is '/' .EXAMPLE PS> Get-FolderByPath -Path "Folder1/Datacenter/Folder2"
.EXAMPLE
  PS> Get-FolderByPath -Path "Folder1>Folder2" -Separator '>'
#>
 
  param(
  [CmdletBinding()]
  [parameter(Mandatory = $true)]
  [System.String[]]${Path},
  [char]${Separator} = '/'
  )
 
  process{
    if((Get-PowerCLIConfiguration).DefaultVIServerMode -eq "Multiple"){
      $vcs = $defaultVIServers
    }
    else{
      $vcs = $defaultVIServers[0]
    }
 
    foreach($vc in $vcs){
      foreach($strPath in $Path){
        $root = Get-Folder -Name Datacenters -Server $vc
        $strPath.Split($Separator) | %{
          $root = Get-Inventory -Name $_ -Location $root -Server $vc -NoRecursion
          if((Get-Inventory -Location $root -NoRecursion | Select -ExpandProperty Name) -contains "vm"){
            $root = Get-Inventory -Name "vm" -Location $root -Server $vc -NoRecursion
          }
        }
        $root | where {$_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl]}|%{
          Get-Folder -Name $_.Name -Location $root.Parent -NoRecursion -Server $vc
        }
      }
    }
  }
}

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

<#
 Function Connect-Mstsc {

    [cmdletbinding(SupportsShouldProcess,DefaultParametersetName='UserPassword')]
    param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=0)]
        [Alias('CN')]
            [string[]]     $ComputerName,
        [Parameter(ParameterSetName='UserPassword',Mandatory=$true,Position=1)]
        [Alias('U')] 
            [string]       $User,
        [Parameter(ParameterSetName='UserPassword',Mandatory=$true,Position=2)]
        [Alias('P')] 
            [string]       $Password,
        [Parameter(ParameterSetName='Credential',Mandatory=$true,Position=1)]
        [Alias('C')]
            [PSCredential] $Credential,
        [Alias('A')]
            [switch]       $Admin,
        [Alias('MM')]
            [switch]       $MultiMon,
        [Alias('F')]
            [switch]       $FullScreen,
        [Alias('Pu')]
            [switch]       $Public,
        [Alias('W')]
            [int]          $Width,
        [Alias('H')]
            [int]          $Height,
        [Alias('WT')]
            [switch]       $Wait
    )

    begin {
        [string]$MstscArguments = ''
        $MstscArguments += "C:\Scripts\Default.rdp"
        switch ($true) {
            {$Admin}      {$MstscArguments += '/admin '}
            {$MultiMon}   {$MstscArguments += '/multimon '}
            {$FullScreen} {$MstscArguments += '/f '}
            {$Public}     {$MstscArguments += '/public '}
            {$Width}      {$MstscArguments += "/w:$Width "}
            {$Height}     {$MstscArguments += "/h:$Height "}
        }

        if ($Credential) {
            $User     = $Credential.UserName
            $Password = $Credential.GetNetworkCredential().Password
        }
    }
    process {
        foreach ($Computer in $ComputerName) {
            $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
            $Process = New-Object System.Diagnostics.Process
            
            # Remove the port number for CmdKey otherwise credentials are not entered correctly
            if ($Computer.Contains(':')) {
                $ComputerCmdkey = ($Computer -split ':')[0]
            } else {
                $ComputerCmdkey = $Computer
            }

            $ProcessInfo.FileName    = "$($env:SystemRoot)\system32\cmdkey.exe"
            $ProcessInfo.Arguments   = "/generic:TERMSRV/$ComputerCmdkey /user:$User /pass:$($Password)"
            $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $Process.StartInfo = $ProcessInfo
            if ($PSCmdlet.ShouldProcess($ComputerCmdkey,'Adding credentials to store')) {
                [void]$Process.Start()
            }

            $ProcessInfo.FileName    = "$($env:SystemRoot)\system32\mstsc.exe"
            $ProcessInfo.Arguments   = "$MstscArguments /v $Computer"
            $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
            $Process.StartInfo       = $ProcessInfo
            if ($PSCmdlet.ShouldProcess($Computer,'Connecting mstsc')) {
                [void]$Process.Start()
                if ($Wait) {
                    $null = $Process.WaitForExit()
                }       
            }
        }
    }
}

#>

cls
$WarningPreference = "SilentlyContinue"

$logtime = Get-date -Format "MM-dd-yyyy_hh-mm-ss"
$global:logfile = 'C:\temp\'+"VMBUILDLog_"+$logtime+".txt"
write-output ("Script started at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $global:logfile -Append
$vms = import-csv $Global:Filename | Where-Object {$_.name -and $_.template -and $_.clusters} | foreach-object { $_ }



Log "Beginning VM Build Script..." yellow
#Credentials
$key = Get-Content "c:\temp\SharedPath\AES.key"
$Lpassword = get-content c:\temp\SharedPath\LPassword.txt | convertto-securestring -Key $key
$Dpassword = get-content c:\temp\SharedPath\DPassword.txt | convertto-securestring -Key $key
$localcred = new-object -typename System.Management.Automation.PSCredential -argumentlist "administrator",$Lpassword
$domaincred = new-object -typename System.Management.Automation.PSCredential -argumentlist "cgsh\dfongadmin",$Dpassword

Login-vCenter $Domaincred
$displayloop = 1
$servercount = @($vms).Count
foreach ($vm in $vms)
{
    
    $Template = Get-Template -Name $vm.Template
    $Cluster = $vm.Clusters
    $Datastore = Get-Datastore -Name $vm.'Datastore                         FreeSpace                          Capacity'.split('   ')[0]
    $Custom = Get-OSCustomizationSpec -Name $vm.Customization
    $vCPU = $vm.vCPU
    $Memory = $vm.Memory
    #$VMNetwork = $vm.Network
    $vlan = Get-VirtualPortGroup -name $vm.Network -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | where {$_.portbinding -eq "static"}
    $Location = $vm.Location
    $VMName = $vm.Name
    $host.ui.RawUI.WindowTitle = 'VM BUILD WINDOW for ' + $VMName + '...Please Do Not Close!'
 
    #Where the VM gets built
    $folder_location = ($Location -replace("\\", "/"))
    Log "($displayloop out of $servercount Servers)" yellow
    Log "Building $VMName..." yellow
    New-VM -Name $VMName -Template $Template -ResourcePool (Get-Cluster $Cluster | Get-ResourcePool | Where-Object name -eq resources) -Location (Get-FolderByPath -path $folder_location) -Datastore $Datastore -OSCustomizationSpec $Custom *>> $global:logfile 
    
    #Where the vCPU, memory, and network gets set
    $NewVM = Get-VM -Name $VMName
    log "Changing CPU/Memory Configuration..." yellow
    #$NewVM | Set-VM -MemoryGB $Memory -NumCpu $vCPU -Confirm:$false | Out-File $global:logfile -Append
    Set-VM -VM $NewVM -MemoryGB $Memory -NumCpu $vCPU -Confirm:$false | Out-File $global:logfile -Append
    Log "Powering on $VMName..." yellow
    Start-VM -VM $VMName -Confirm:$false *>> $global:logfile 
    DO 
    {
        Start-Wait -seconds 180 -msg "Checking OS Customization"
        $results += (Get-VMGuest $VMName).HostName
        Write-host -NoNewline "Please Wait..." -ForegroundColor Yellow
        
    
    }
    While (((Get-VMGuest $VMName).HostName) -Ne "$VMName")
    Log "OS Customization done" green
    $Network = Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType Powershell -ScriptText "(gwmi Win32_NetworkAdapter -filter 'netconnectionid is not null').netconnectionid"
    $NetworkName = $Network.ScriptOutput
    $NetworkName = $NetworkName.Trim()
    Log " " 
    Log "Setting IP address for $VMname..." Yellow
    $ip = $vm.'IP Address'
    $gw = (([ipaddress] $ip).GetAddressBytes()[0..2] -join ".") + ".1"
    if (([ipaddress] "$IP").GetAddressBytes()[1] -eq "201")
    {
        $DNS1 = "10.201.30.25"
        $DNS2 = "10.202.30.25"
        $DC = "AM2"
    }
    if (([ipaddress] "$IP").GetAddressBytes()[1] -eq "200")
    {
        $DNS1 = "10.200.30.25"
        $DNS2 = "10.201.30.25"
        $DC = "AM1"
    }
    #EU1 IP Settings
    if (([ipaddress] "$IP").GetAddressBytes()[1] -eq "202")
    {
        $DNS1 = "10.202.30.25"
        $DNS2 = "10.203.30.25"
        $DC = "EU1"
    }
    #EU2 IP Settings
    if (([ipaddress] "$IP").GetAddressBytes()[1] -eq "203")
    {
        $DNS1 = "10.203.30.25"
        $DNS2 = "10.202.30.25"
        $DC = "EU2"
    }
    #AS1 IP Settings
    if (([ipaddress] "$IP").GetAddressBytes()[1] -eq "204")
    {
        $DNS1 = "10.204.30.25"
        $DNS2 = "10.203.30.25"
        $DC = "AS1"
    }
    $netsh = "c:\windows\system32\netsh.exe interface ip set address ""$NetworkName"" static $IP 255.255.255.0 $GW"
    $netsh2 = "c:\windows\system32\netsh.exe interface ip set dnsservers ""$NetworkName"" static $DNS1 validate=no"
    $netsh3 = "c:\windows\system32\netsh.exe interface ip add dnsservers ""$NetworkName"" $DNS2 validate=no"
    $DNS_Search = "reg add HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters /v ""SearchList"" /d ""cgsh.com"" /f"
    $DNSSuffix = "c:\windows\system32\windowspowershell\v1.0\powershell.exe set-dnsclient -InterfaceAlias ""'$NetworkName'"" -ConnectionSpecificSuffix cgsh.com"
    $fwnetsh = "c:\windows\system32\netsh.exe Advfirewall set allprofiles state off"
    Invoke-VMScript -VM $VMname -GuestCredential $localcred -ScriptType bat -ScriptText $netsh *>> $global:logfile
    Invoke-VMScript -VM $VMname -GuestCredential $localcred -ScriptType bat -ScriptText $netsh2 *>> $global:logfile 
    Invoke-VMScript -VM $VMname -GuestCredential $localcred -ScriptType bat -ScriptText $netsh3 *>> $global:logfile 
    Invoke-VMScript -VM $VMname -GuestCredential $localcred -ScriptType bat -ScriptText $DNS_Search *>> $global:logfile 
    Invoke-VMScript -VM $VMname -GuestCredential $localcred -ScriptType bat -ScriptText $DNSSuffix *>> $global:logfile 
    Invoke-VMScript -VM $VMname -GuestCredential $localcred -ScriptType bat -ScriptText $fwnetsh *>> $global:logfile 
    get-vm $VMName | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $vlan -Confirm:$false *>> $global:logfile 
    if (Test-Connection $IP) {Log "...IP Address Completed for $VMName" yellow}
    #if ($vm.c_drive.tostring())
    if ($vm.c_drive)
    {       
        $diskvalue = $vm.c_drive.tostring()
        if ([int]$diskvalue -gt "50")
        {
            log "Increasing C: Drive to $diskvalue GB..." Yellow -Sameline True
            Get-HardDisk -vm $VMName | where {$_.Name -eq "hard disk 1"} | Set-HardDisk -CapacityGB $diskvalue -Confirm:$false *>> $global:logfile 
            $C_DiskPart = "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume C >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q"
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType bat -ScriptText $C_DiskPart *>> $global:logfile 
            log "Done" Green
        }
    }
    if ($vm.e_drive)
    {
        $diskvalue = $vm.e_drive.tostring()
        log "Adding $diskvalue GB to E: Drive..." Yellow -Sameline True
        if ($vm.Template -match "PVSCSI")
        {
            $E_DiskPart = "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume E >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q"
            Get-HardDisk -vm $VMName | where {$_.Name -eq "hard disk 2"} | Set-HardDisk -CapacityGB $diskvalue -Confirm:$false *>> $global:logfile
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType bat -ScriptText $E_DiskPart *>> $global:logfile 
        }
        else
        {
            New-HardDisk -vm $VMName -CapacityGB $diskvalue -StorageFormat Thick *>> $global:logfile 
            $Edisk = @'
            Get-Disk | Where partitionstyle -eq ‘raw’ | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter E -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false -force
'@
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType Powershell -ScriptText $Edisk *>> $global:logfile 
        }
        log "Done" Green
    }
    if ($vm.f_drive)
    {
        $diskvalue = $vm.f_drive.tostring()
        log "Adding $diskvalue GB to F: Drive..." Yellow -Sameline True
        if ($vm.Template -match "PVSCSI")
        {
            $F_DiskPart = "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume F >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q"
            Get-HardDisk -vm $VMName | where {$_.Name -eq "hard disk 3"} | Set-HardDisk -CapacityGB $diskvalue -Confirm:$false *>> $global:logfile 
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType bat -ScriptText $F_DiskPart *>> $global:logfile 
        }
        else
        {
            New-HardDisk -vm $VMName -CapacityGB $diskvalue -StorageFormat Thick *>> $global:logfile 
            $Fdisk = @'
            Get-Disk | Where partitionstyle -eq ‘raw’ | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter F -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false -force
'@
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType Powershell -ScriptText $Fdisk *>> $global:logfile 
        }
        log "Done" Green
    }

    if ($vm.g_drive)
    {
        $diskvalue = $vm.g_drive.tostring()
        log "Adding $diskvalue GB to G: Drive..." Yellow -Sameline True
        if ($vm.Template -match "PVSCSI")
        {
            #$G_DiskPart = "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume G >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q"
            #Get-HardDisk -vm $VMName | where {$_.Name -eq "hard disk 4"} | Set-HardDisk -CapacityGB $diskvalue -Confirm:$false *>> $global:logfile 
            #Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType bat -ScriptText $G_DiskPart *>> $global:logfile 
            New-HardDisk -vm $VMName -CapacityGB $diskvalue -StorageFormat Thick -Controller "SCSI Controller 1" *>> $global:logfile
            $Gdisk = @'
            Get-Disk | Where partitionstyle -eq ‘raw’ | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter G -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false -force
'@
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType Powershell -ScriptText $Gdisk *>> $global:logfile 

        }
        else
        {
            New-HardDisk -vm $VMName -CapacityGB $diskvalue -StorageFormat Thick *>> $global:logfile 
            $Gdisk = @'
            Get-Disk | Where partitionstyle -eq ‘raw’ | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter G -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false -force
'@
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType Powershell -ScriptText $Gdisk *>> $global:logfile 
        }
        log "Done" Green
    }

    if ($vm.h_drive)
    {
        $diskvalue = $vm.h_drive.tostring()
        log "Adding $diskvalue GB to H: Drive..." Yellow -Sameline True
        if ($vm.Template -match "PVSCSI")
        {
            $H_DiskPart = "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume H >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q"
            Get-HardDisk -vm $VMName | where {$_.Name -eq "hard disk 4"} | Set-HardDisk -CapacityGB $diskvalue -Confirm:$false *>> $global:logfile 
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType bat -ScriptText $H_DiskPart *>> $global:logfile 
        }
        else
        {
            New-HardDisk -vm $VMName -CapacityGB $diskvalue -StorageFormat Thick *>> $global:logfile 
            $Hdisk = @'
            Get-Disk | Where partitionstyle -eq ‘raw’ | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter H -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false -force
'@
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType Powershell -ScriptText $Hdisk *>> $global:logfile 
        }
        log "Done" Green
    }
        
    if ($vm.i_drive)
    {
        $diskvalue = $vm.i_drive.tostring()
        log "Adding $diskvalue GB to i: Drive..." Yellow -Sameline True
        if ($vm.Template -match "PVSCSI")
        {
            $I_DiskPart = "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume I >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q"
            Get-HardDisk -vm $VMName | where {$_.Name -eq "hard disk 5"} | Set-HardDisk -CapacityGB $diskvalue -Confirm:$false *>> $global:logfile 
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType bat -ScriptText $H_DiskPart *>> $global:logfile 
        }
        else
        {
            New-HardDisk -vm $VMName -CapacityGB $diskvalue -StorageFormat Thick *>> $global:logfile 
            $Idisk = @'
            Get-Disk | Where partitionstyle -eq ‘raw’ | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter I -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false -force
'@
            Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType Powershell -ScriptText $Idisk *>> $global:logfile 
        }
        log "Done" Green
    }

    #Remove cert
    log "Checking Certs..." Yellow -Sameline True
    $checkcert = @'
            Get-ChildItem Cert:\LocalMachine\MY | Where-Object { ($_.dnsnamelist  -match "2012R2") -AND ($_.Subject -notmatch "CN=$env:COMPUTERNAME") } | Remove-Item -Verbose
            
'@
    Invoke-VMScript -VM $VMName -GuestCredential $localcred -ScriptType Powershell -ScriptText $checkcert *>> $global:logfile 
    log "Done" Green
    
    if (Test-Connection $IP)
    {
        
        Log "Adding $VMName to domain..." yellow
        Add-Computer -ComputerName $IP -DomainName "cgsh.com" -OUPath "OU=Servers,OU=$DC,OU=DataCenters,DC=cgsh,DC=com" -LocalCredential $localcred -Credential $Domaincred -Restart
        Start-Wait -seconds 120 -msg "Adding to Domain"
        DO 
        {
            Start-Wait -seconds 30 -msg "Checking Domain Status"
            $results += (Get-VMGuest $VMName).HostName
            Write-host -NoNewline "Please Wait, Checking..." -ForegroundColor Yellow
        }
        While (((Get-VMGuest $VMName).HostName) -Ne "$VMName.cgsh.com")
        Log "$VMName added to domain" green
        Log " " 
    }

    # Add second script here
    Log "Patching $VMName in a new window..." yellow
    #$lclcred = Get-Credential -Message "Local Admin Account" -UserName superlogin
    #Start-Job -ScriptBlock {C:\Scripts\patch-server.ps1 -servername $args[0] -ip $args[1] -localcred $args[2] -domancred $args[3]} -ArgumentList $VMName, $ip, $lclcred, $Domaincred
    #Connect-Mstsc $ip -Credential $Domaincred

    #remove cert
    #Invoke-Command -ComputerName $IP {Get-ChildItem Cert:\LocalMachine\MY | Where-Object { ($_.dnsnamelist  -match "2012R2") -AND ($_.Subject -notmatch "CN=$env:COMPUTERNAME") } | Remove-Item -Verbose

    start-process powershell.exe "c:\scripts\patch-server_v1.ps1 $vmname $ip $global:DefaultVIServer"
    log " "
    $displayloop ++

}

log "BUILD VM(s) FINISHED" Green
log "This Window will be Closed in 20 seconds..." yellow
Start-Sleep -Seconds 20 
write-output ("Script stopped at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $global:logfile -Append


