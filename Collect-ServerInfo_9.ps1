#loginto multple vcenters
#Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope ([VMware.VimAutomation.ViCore.Types.V1.ConfigurationScope]::User)
#Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope ([VMware.VimAutomation.ViCore.Types.V1.ConfigurationScope]::Session)
try {$check = Get-PSSnapin VMware.VimAutomation.Core -ErrorAction stop}
Catch {Add-PSSnapin VMware.VimAutomation.Core}


function Get-ActivationStatus {
[CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$HostName = $Env:COMPUTERNAME
    )
    process {
        try {
            $wpa = Get-WmiObject SoftwareLicensingProduct -ComputerName $HostName `
            -Filter "ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f'" `
            -Property LicenseStatus -ErrorAction Stop
        } catch {
            $status = New-Object ComponentModel.Win32Exception ($_.Exception.ErrorCode)
            $wpa = $null    
        }
        $out = New-Object psobject -Property @{
            ComputerName = $HostName;
            Status = [string]::Empty;
        }
        if ($wpa) {
            :outer foreach($item in $wpa) {
                switch ($item.LicenseStatus) {
                    0 {$out.Status = "Unlicensed"}
                    1 {$out.Status = "Licensed"; break outer}
                    2 {$out.Status = "Out-Of-Box Grace Period"; break outer}
                    3 {$out.Status = "Out-Of-Tolerance Grace Period"; break outer}
                    4 {$out.Status = "Non-Genuine Grace Period"; break outer}
                    5 {$out.Status = "Notification"; break outer}
                    6 {$out.Status = "Extended Grace"; break outer}
                    default {$out.Status = "Unknown value"}
                }
            }
        } else {$out.Status = $status.Message}
        $out.status
        
    }
}


Function Get-ServerInfo {

[CmdletBinding()]

Param (

    [parameter(ValueFromPipeline=$True)]
    [string[]]$ComputerName

)

Begin
{
    #Initialize
    Write-Verbose "Initializing"

}

Process
{

    #---------------------------------------------------------------------
    # Process each ComputerName
    #---------------------------------------------------------------------

    if (!($PSCmdlet.MyInvocation.BoundParameters[“Verbose”].IsPresent))
    {
        Write-Host "Processing $ComputerName"
    }

    Write-Verbose "=====> Processing $ComputerName <====="

    #$htmlreport = @()
    $htmlbody = @()
    $logtime = Get-date -Format "MM-dd-yyyy_hh-mm-ss"
    $global:htmlfile = "C:\temp\BuildInfo_" + $logtime + ".html"
    #$global:htmlfile = "c:\temp\Info.html"
    $spacer = "<br />"

    #---------------------------------------------------------------------
    # Do 10 pings and calculate the fastest response time
    # Not using the response time in the report yet so it might be
    # removed later.
    #---------------------------------------------------------------------
    
    try
    {
        #$bestping = (Test-Connection -ComputerName $ComputerName -Count 10 -ErrorAction STOP | Sort ResponseTime)[0].ResponseTime
        $bestping = (Test-Connection -ComputerName $ComputerName)
    }
    catch
    {
        Write-Warning $_.Exception.Message
        $bestping = "Unable to connect"
    }

    if ($bestping -eq "Unable to connect")
    {
        if (!($PSCmdlet.MyInvocation.BoundParameters[“Verbose”].IsPresent))
        {
            Write-Host "Unable to connect to $ComputerName"
        }

        "Unable to connect to $ComputerName"
    }
    else
    {

        #---------------------------------------------------------------------
        # Collect computer system information and convert to HTML fragment
        #---------------------------------------------------------------------
    
        Write-Verbose "Collecting computer system information"

        $subhead = "<h3>Computer System Information</h3>"
        $htmlbody += $subhead
    
        try
        {
            #$ou = get-adou -ComputerName $ComputerName
            #Get-ADComputer -Server $computername | select DistinguishedName | ft -HideTableHeaders | Out-String
            #$OU_info = $ou
            $VMinfo = get-vm $ComputerName | Where-Object {$_.PowerState -ne "PoweredOff"}
            $serverinfo = $vminfo | % {[PSCustomObject] @{Name = $_.Name
            vCenter = $_.Uid.Substring($_.Uid.IndexOf('@')+1).Split(":")[0]
            }
            }
            $servervcenter = $serverinfo.vCenter
            $timeZone=Get-WmiObject -Class win32_timezone -ComputerName $computername 
            $localTime = Get-WmiObject -Class win32_localtime -ComputerName $computername 
            $csinfo = Get-WmiObject Win32_ComputerSystem -ComputerName $ComputerName -ErrorAction STOP |
                Select-Object Name <#,Manufacturer,Model#>,
                            @{Name='Physical Processors';Expression={$_.NumberOfProcessors}},
                            @{Name='Logical Processors';Expression={$_.NumberOfLogicalProcessors}},
                            @{Name='Total Physical Memory (Gb)';Expression={
                                $tpm = $_.TotalPhysicalMemory/1GB;
                                "{0:F0}" -f $tpm
                            }},
                            DnsHostName,
                            Domain,
                            @{Name='OU Location';Expression={$global:adou}},
                            @{Name='Time Zone';Expression={$timeZone.Caption}},
                            @{Name='Current Time';Expression={(Get-Date -Day $localTime.Day -Month $localTime.Month)}},
                            @{Name='vmTools';Expression={$Vminfo.Guest.ToolsVersion}},
                            @{Name='vmHardware';Expression={$Vminfo.version}}


       
            $htmlbody += $csinfo | ConvertTo-Html -Fragment
            $htmlbody += $spacer
       
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }



        #---------------------------------------------------------------------
        # Collect operating system information and convert to HTML fragment
        #---------------------------------------------------------------------
    
        Write-Verbose "Collecting operating system information"

        $subhead = "<h3>Operating System Information</h3>"
        $htmlbody += $subhead
    
        try
        {
           
            
            $osinfo = Get-WmiObject Win32_OperatingSystem -ComputerName $ComputerName -ErrorAction STOP | 
                Select-Object @{Name='Operating System';Expression={$_.Caption}},
                            @{Name='Architecture';Expression={$_.OSArchitecture}},
                            Version,Organization,
                            @{Name='Install Date';Expression={
                                $installdate = [datetime]::ParseExact($_.InstallDate.SubString(0,8),"yyyyMMdd",$null);
                                $installdate.ToShortDateString()
                            }},
                            WindowsDirectory,
                            @{Name='License Status';Expression={$global:licinfo}}



            $htmlbody += $osinfo | ConvertTo-Html -Fragment
            $htmlbody += $spacer
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        #---------------------------------------------------------------------
        # Collect local admin information and convert to HTML fragment
        #---------------------------------------------------------------------

        Write-Verbose "Collecting local admin information"

        $subhead = "<h3>Local Account Information</h3>"
        $htmlbody += $subhead
        Try
        {
            $lcl = @()
            $lcl_results = @()
            $Computer = [ADSI]("WinNT://$Computername,computer")
            $Group_adm = $Computer.PSBase.Children.Find("Administrators")
            $Group_rdp = $Computer.PSBase.Children.Find("Remote Desktop Users")
            $lcl_adm = $group_adm.psbase.invoke("members")  | ForEach{$_.GetType().InvokeMember("Name",  'GetProperty',  $null, $_, $null)} | Select-Object @{Name='Administrator';Expression={$_}}, @{Name='Remote Desktop Users';Expression={$_}}       
            $lcl_rdp = $group_rdp.psbase.invoke("members")  | ForEach{$_.GetType().InvokeMember("Name",  'GetProperty',  $null, $_, $null)} | Select-Object @{Name='Remote Desktop Users';Expression={$_}}
            $lcl_results = $lcl_adm + $lcl_rdp
            
            $htmlbody += $lcl_results | ConvertTo-Html -Fragment

            $htmlbody += $spacer
            

        }
         catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        #---------------------------------------------------------------------
        # Collect physical memory information and convert to HTML fragment
        #---------------------------------------------------------------------

       <# Write-Verbose "Collecting physical memory information"

        $subhead = "<h3>Physical Memory Information</h3>"
        $htmlbody += $subhead

        try
        {
            $memorybanks = @()
            $physicalmemoryinfo = @(Get-WmiObject Win32_PhysicalMemory -ComputerName $ComputerName -ErrorAction STOP |
                Select-Object DeviceLocator,Manufacturer,Speed,Capacity)

            foreach ($bank in $physicalmemoryinfo)
            {
                $memObject = New-Object PSObject
                $memObject | Add-Member NoteProperty -Name "Device Locator" -Value $bank.DeviceLocator
                $memObject | Add-Member NoteProperty -Name "Manufacturer" -Value $bank.Manufacturer
                $memObject | Add-Member NoteProperty -Name "Speed" -Value $bank.Speed
                $memObject | Add-Member NoteProperty -Name "Capacity (GB)" -Value ("{0:F0}" -f $bank.Capacity/1GB)

                $memorybanks += $memObject
            }

            $htmlbody += $memorybanks | ConvertTo-Html -Fragment
            $htmlbody += $spacer
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        } #>


       <# #---------------------------------------------------------------------
        # Collect pagefile information and convert to HTML fragment
        #---------------------------------------------------------------------

        $subhead = "<h3>PageFile Information</h3>"
        $htmlbody += $subhead

        Write-Verbose "Collecting pagefile information"

        try
        {
            $pagefileinfo = Get-WmiObject Win32_PageFileUsage -ComputerName $ComputerName -ErrorAction STOP |
                Select-Object @{Name='Pagefile Name';Expression={$_.Name}},
                            @{Name='Allocated Size (Mb)';Expression={$_.AllocatedBaseSize}}

            $htmlbody += $pagefileinfo | ConvertTo-Html -Fragment
            $htmlbody += $spacer
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        } #>

        <#
        #---------------------------------------------------------------------
        # Collect BIOS information and convert to HTML fragment
        #---------------------------------------------------------------------

        $subhead = "<h3>BIOS Information</h3>"
        $htmlbody += $subhead

        Write-Verbose "Collecting BIOS information"

        try
        {
            $biosinfo = Get-WmiObject Win32_Bios -ComputerName $ComputerName -ErrorAction STOP |
                Select-Object Status,Version,Manufacturer,
                            @{Name='Release Date';Expression={
                                $releasedate = [datetime]::ParseExact($_.ReleaseDate.SubString(0,8),"yyyyMMdd",$null);
                                $releasedate.ToShortDateString()
                            }},
                            @{Name='Serial Number';Expression={$_.SerialNumber}}

            $htmlbody += $biosinfo | ConvertTo-Html -Fragment
            $htmlbody += $spacer
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }
        #>

        #---------------------------------------------------------------------
        # Collect logical disk information and convert to HTML fragment
        #---------------------------------------------------------------------

        $subhead = "<h3>Logical Disk Information</h3>"
        $htmlbody += $subhead

        Write-Verbose "Collecting logical disk information"

        try
        {
            $diskinfo = Get-WmiObject Win32_LogicalDisk -ComputerName $ComputerName -ErrorAction STOP | 
                Select-Object DeviceID,FileSystem,VolumeName,
                @{Expression={$_.Size /1Gb -as [int]};Label="Total Size (GB)"},
                @{Expression={$_.Freespace / 1Gb -as [int]};Label="Free Space (GB)"}

            $htmlbody += $diskinfo | ConvertTo-Html -Fragment
            $htmlbody += $spacer
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }


        #---------------------------------------------------------------------
        # Collect volume information and convert to HTML fragment
        #---------------------------------------------------------------------

        $subhead = "<h3>Volume Information</h3>"
        $htmlbody += $subhead

        Write-Verbose "Collecting volume information"

        try
        {
            $volinfo = Get-WmiObject Win32_Volume -ComputerName $ComputerName -ErrorAction STOP | 
                Select-Object Label,Name,DeviceID,SystemVolume,BlockSize,
                @{Expression={$_.Capacity /1Gb -as [int]};Label="Total Size (GB)"},
                @{Expression={$_.Freespace / 1Gb -as [int]};Label="Free Space (GB)"}

            $htmlbody += $volinfo | ConvertTo-Html -Fragment
            $htmlbody += $spacer
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }


        #---------------------------------------------------------------------
        # Collect VM Disk info information and convert to HTML fragment
        #---------------------------------------------------------------------

        
        $subhead = "<h3>VM Disk Information</h3>"
        $htmlbody += $subhead

        Write-Verbose "Collecting VM Disk information"

        try
        {
            $vmdiskinfo = get-vm $ComputerName | Get-HardDisk | select name,filename,capacitygb, @{N='SCSIid';E={
            $hd = $_
            $ctrl = $hd.Parent.Extensiondata.Config.Hardware.Device | where{$_.Key -eq $hd.ExtensionData.ControllerKey}
            "$($ctrl.BusNumber):$($_.ExtensionData.UnitNumber)"}}

            $htmlbody += $vmdiskinfo | ConvertTo-Html -Fragment
            $htmlbody += $spacer
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        #---------------------------------------------------------------------
        # Collect network interface information and convert to HTML fragment
        #---------------------------------------------------------------------    

        $subhead = "<h3>Network Interface Information</h3>"
        $htmlbody += $subhead

        Write-Verbose "Collecting network interface information"

        try
        {
            $nics = @()
            $nicinfo = @(Get-WmiObject Win32_NetworkAdapter -ComputerName $ComputerName -ErrorAction STOP | Where {$_.PhysicalAdapter} |
                Select-Object Name,AdapterType,MACAddress,
                @{Name='ConnectionName';Expression={$_.NetConnectionID}},
                @{Name='Enabled';Expression={$_.NetEnabled}},
                @{Name='Speed';Expression={$_.Speed/1000000}})

            $nwinfo = Get-WmiObject Win32_NetworkAdapterConfiguration -ComputerName $ComputerName -ErrorAction STOP |
                Select-Object Description, DHCPServer,  
                @{Name='IpAddress';Expression={$_.IpAddress -join '; '}},  
                @{Name='IpSubnet';Expression={$_.IpSubnet -join '; '}},  
                @{Name='DefaultIPgateway';Expression={$_.DefaultIPgateway -join '; '}},  
                @{Name='DNSServerSearchOrder';Expression={$_.DNSServerSearchOrder -join '; '}},
                @{Name='DNSDomainSuffixSearchOrder';Expression={$_.DNSDomainSuffixSearchOrder -join '; '}},
                @{Name='DNSDomain';Expression={$_.DNSDomain -join '; '}},
                @{Name='RegisterDNSCheckbox';Expression={$_.fulldnsregistrationenabled -join '; '}}

            foreach ($nic in $nicinfo)
            {
                $nicObject = New-Object PSObject
                $nicObject | Add-Member NoteProperty -Name "Connection Name" -Value $nic.connectionname
                $nicObject | Add-Member NoteProperty -Name "Adapter Name" -Value $nic.Name
                $nicObject | Add-Member NoteProperty -Name "Type" -Value $nic.AdapterType
                $nicObject | Add-Member NoteProperty -Name "MAC" -Value $nic.MACAddress
                $nicObject | Add-Member NoteProperty -Name "Enabled" -Value $nic.Enabled
                $nicObject | Add-Member NoteProperty -Name "Speed (Mbps)" -Value $nic.Speed
        
                $ipaddress = ($nwinfo | Where {$_.Description -eq $nic.Name}).IpAddress
                $nicObject | Add-Member NoteProperty -Name "IPAddress" -Value $ipaddress
                $dnscfg = ($nwinfo | Where {$_.Description -eq $nic.Name}).DNSServerSearchOrder
                $nicObject | Add-Member NoteProperty -Name "DNS" -Value $dnscfg
                $dnssearch = ($nwinfo | Where {$_.Description -eq $nic.Name}).DNSDomainSuffixSearchOrder
                $nicObject | Add-Member NoteProperty -Name "DNS Search Suffix" -Value $dnssearch
                $dnsdomain = ($nwinfo | Where {$_.Description -eq $nic.Name}).DNSDomain
                $nicObject | Add-Member NoteProperty -Name "DNSDomain" -Value $dnsdomain
                $regdns = ($nwinfo | Where {$_.Description -eq $nic.Name}).RegisterDNSCheckbox
                $nicObject | Add-Member NoteProperty -Name "Register DNS Checkbox" -Value $regdns

                $nics += $nicObject
            }

            $htmlbody += $nics | ConvertTo-Html -Fragment
            $htmlbody += $spacer
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        #---------------------------------------------------------------------
        # Collect Firewall Information
        #---------------------------------------------------------------------    

        $subhead = "<h3>Firewall Information</h3>"
        $htmlbody += $subhead
        try
        {
            $firewall = netsh -r $ComputerName advfirewall show allprofiles 
            $fw_public = $firewall| Select-String public -Context 0,2 | % {$_.Context.PostContext}
            $fw_private = $firewall| Select-String private -Context 0,2 | % {$_.Context.PostContext}
            $fw_domain = $firewall| Select-String domain -Context 0,2 | % {$_.Context.PostContext}
            $fw_results = New-Object PSObject
            $fw_results | Add-Member NoteProperty -Name "Public Profile" -Value $fw_public[1]
            $fw_results | Add-Member NoteProperty -Name "Private Profile" -Value $fw_private[1]
            $fw_results | Add-Member NoteProperty -Name "Domain Profile" -Value $fw_domain[1]
        
            $htmlbody += $fw_results | ConvertTo-Html -Fragment
            $htmlbody += $spacer 
        
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        
        #---------------------------------------------------------------------
        # Collect Cylance Information
        #---------------------------------------------------------------------    

        $subhead = "<h3>Cylance Information</h3>"
        $htmlbody += $subhead
        try
        {
           
            $cylance_results = Get-Service -ComputerName $ComputerName cylancesvc -ErrorAction Stop | select status,name,displayname
            $htmlbody += $cylance_results | ConvertTo-Html -Fragment
            $htmlbody += $spacer 
        
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        #---------------------------------------------------------------------
        # Collect Registry Key Information
        #---------------------------------------------------------------------    

        $subhead = "<h3>Registry Key</h3>"
        $htmlbody += $subhead
        $ValueName = "cadca5fe-87d3-4b96-b7fb-a231484277cc"
        $ValueData = 0
        $reg_results = @()
        try
        {
            $Hive = [Microsoft.Win32.RegistryHive]“LocalMachine”;
            $regKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($Hive,$computername);
            $ref = $regKey.OpenSubKey(“SOFTWARE\Microsoft\Windows\CurrentVersion\QualityCompat”,$true);
            $regkey = $ref.GetValueNames() | Out-String
            $reg_info = New-Object PSObject
            $reg_info | Add-Member NoteProperty -Name "Registry Path" -Value "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\QualityCompat"
            $reg_info | Add-Member NoteProperty -Name "Registry Key" -Value $regKey
            $reg_info | Add-Member NoteProperty -Name "Value" -Value $ref.getValue($ValueName, $ValueData)
            $reg_results += $reg_info
            $htmlbody += $reg_results | ConvertTo-Html -Fragment
            $htmlbody += $spacer 
        
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        #---------------------------------------------------------------------
        # Collect Certificate Information
        #---------------------------------------------------------------------    

        $subhead = "<h3>Certificate Information</h3>"
        $htmlbody += $subhead
        $ValueName = "cadca5fe-87d3-4b96-b7fb-a231484277cc"
        $ValueData = 0
        $Cert_results = @()
        try
        {
            
            $cert_results = $computername | ForEach-Object {Invoke-Command -ScriptBlock { Get-ChildItem Cert:\LocalMachine\My} -ComputerName $_} | select PsComputerName, Issuer, NotAfter, DnsNameList, subject
            $htmlbody += $cert_results | ConvertTo-Html -Fragment
            $htmlbody += $spacer 
        
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        #---------------------------------------------------------------------
        # CPU Sched Sensitivity
        #---------------------------------------------------------------------    

        $subhead = "<h3>CPU Sched Sensitivity</h3>"
        $htmlbody += $subhead
        #$Cert_results = @()
        $sched_results = @()
        try
        {
            
            #$cert_results = $computername | ForEach-Object {Invoke-Command -ScriptBlock { Get-ChildItem Cert:\LocalMachine\My} -ComputerName $_} | select PsComputerName, Issuer, NotAfter, DnsNameList, subject
            $sched_results = Get-View -ViewType VirtualMachine -Filter @{"Name" = $server} -Server $servervcenter -Property Name,Config.LatencySensitivity | Select Name,@{N='Sensitivity Level';E={$_.Config.LatencySensitivity.Level}}
            $htmlbody += $sched_results | ConvertTo-Html -Fragment
            $htmlbody += $spacer 
        
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        #---------------------------------------------------------------------
        # SMB1 Status
        #---------------------------------------------------------------------    

        $subhead = "<h3>SMB1 Status</h3>"
        $htmlbody += $subhead
        #$Cert_results = @()
        $smb1_install = @()
        $smb1_results = @()
        try
        {
            
            #$cert_results = $computername | ForEach-Object {Invoke-Command -ScriptBlock { Get-ChildItem Cert:\LocalMachine\My} -ComputerName $_} | select PsComputerName, Issuer, NotAfter, DnsNameList, subject
            #$sched_results = Get-View -ViewType VirtualMachine -Filter @{"Name" = $server} -Server $servervcenter -Property Name,Config.LatencySensitivity | Select Name,@{N='Sensitivity Level';E={$_.Config.LatencySensitivity.Level}}
            
            $smb1_install = Invoke-Command -ComputerName $ComputerName -scriptblock {Get-WindowsFeature FS-SMB1}
            $smb1_results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {Get-SmbServerConfiguration | Select EnableSMB1Protocol} | select pscomputername, enablesmb1protocol, @{N='Installed';E={$smb1_install.installed}}


            $htmlbody += $smb1_results | ConvertTo-Html -Fragment
            $htmlbody += $spacer 
        
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }

        #---------------------------------------------------------------------
        # Collect patch information and convert to HTML fragment
        #---------------------------------------------------------------------


        $subhead = "<h3>OS Patch Information</h3>"
        $htmlbody += $subhead
 
        Write-Verbose "Collecting Patch information"
        try
        {
            
            $objSession = [activator]::CreateInstance([type]::GetTypeFromProgID("Microsoft.Update.Session","$computername"))
            $Searcher = $objSession.CreateUpdateSearcher()
            $historyCount = $Searcher.GetTotalHistoryCount()

            $Patchresults += $Searcher.QueryHistory(0, $historyCount) | Select-Object Title,@{name="Operation"; expression={switch($_.operation){1 {"Installation"}; 2 {"Uninstallation"}; 3 {"Other"}}}},
            @{name="Status"; expression={switch($_.resultcode){1 {"In Progress"}; 2 {"Succeeded"}; 3 {"Succeeded With Errors"};4 {"Failed"}; 5 {"Aborted"}}}},Date | Sort-Object Date -Descending #| select -Last 10

            $htmlbody += $Patchresults | ConvertTo-Html -Fragment
            $htmlbody += $spacer 
        
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }


<#
        #---------------------------------------------------------------------
        # Collect software information and convert to HTML fragment
        #---------------------------------------------------------------------

        $subhead = "<h3>Software Information</h3>"
        $htmlbody += $subhead
 
        Write-Verbose "Collecting software information"
        
        try
        {
            $software = Get-WmiObject Win32_Product -ComputerName $ComputerName -ErrorAction STOP | Select-Object Vendor,Name,Version | Sort-Object Vendor,Name
        
            $htmlbody += $software | ConvertTo-Html -Fragment
            $htmlbody += $spacer 
        
        }
        catch
        {
            Write-Warning $_.Exception.Message
            $htmlbody += "<p>An error was encountered. $($_.Exception.Message)</p>"
            $htmlbody += $spacer
        }
 #>

        #---------------------------------------------------------------------
        # Generate the HTML report and output to file
        #---------------------------------------------------------------------
	
        Write-Verbose "Producing HTML report"
    
        $reportime = Get-Date

        #Common HTML head and styles
	    $htmlhead="<html>
				    <style>
				    BODY{font-family: Arial; font-size: 8pt;}
				    H1{font-size: 20px;}
				    H2{font-size: 18px;}
				    H3{font-size: 16px;}
				    TABLE{border: 1px solid black; border-collapse: collapse; font-size: 8pt;}
				    TH{border: 1px solid black; background: #dddddd; padding: 5px; color: #000000;}
				    TD{border: 1px solid black; padding: 5px; }
				    td.pass{background: #7FFF00;}
				    td.warn{background: #FFE600;}
				    td.fail{background: #FF0000; color: #ffffff;}
				    td.info{background: #85D4FF;}
				    </style>
				    <body>
				    <h1 align=""center"">Server Info: $ComputerName</h1>
				    <h3 align=""center"">Generated: $reportime</h3>"

        $htmltail = "</body>
			    </html>"

        $Global:htmlreport += $htmlhead + $htmlbody + $htmltail

        #$Global:htmlreport | Out-File $htmlfile -Encoding Utf8
    }

}

End
{
    #Wrap it up
    Write-Verbose "=====> Finished <====="
}

}


$Global:htmlreport = @()
#$Global:htmlbody = @()
$patchresults = @()
$servers = gc C:\temp\Check\verifycheck.txt
$vcenters = gc c:\temp\vcenters.txt | Where-Object {$_ -notmatch "#"}
Connect-VIServer $vcenters
foreach ($server in $servers)
{
    $global:adou = Get-ADComputer $server | select DistinguishedName | ft -HideTableHeaders | Out-String
    $global:licinfo = Get-ActivationStatus -HostName $server
    Get-ServerInfo -ComputerName $server

}
$post = "<BR><i>Report generated on $((Get-Date).ToString()) from script: $($PSCommandPath)</i>"
$Global:htmlreport += $post
$Global:htmlreport | Out-File $global:htmlfile -Encoding Utf8
Disconnect-VIServer * -Confirm:$false
#Invoke-Item $global:htmlfile

& 'C:\Program Files\Internet Explorer\iexplore.exe' $global:htmlfile



