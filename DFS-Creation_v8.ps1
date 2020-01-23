function log($string, $color, [ValidateSet("True","False")] $Sameline)
{
   if ($Color -eq $null) {$color = "white"}
   if ($sameline -eq "true") {write-host -NoNewline $string -foregroundcolor $color}
   Else {write-host $string -foregroundcolor $color}
   $string | out-file -Filepath $global:logfile -append
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

$logtime = Get-date -Format "MM-dd-yyyy_hh-mm-ss"
$global:logfile = 'C:\temp\'+"DFSCreate_"+$logtime+".txt"
write-output ("Script started at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $global:logfile -Append
#add FileShareUtils Module
if(!(get-module -name FileShareUtils)) {Import-Module FileShareUtils *>> $global:logfile}
if(!(get-module -name activedirectory)) {Import-Module activedirectory *>> $global:logfile}
$folderinfo = Import-Csv C:\temp\dfs\dfs.csv
Log " " 
Log "Beginning DFS Creation..." Yellow

foreach ($folder in $folderinfo)
{
    Log " "
    $foldername = $folder.cm
    $destination = $folder.Destination
    $path = "\\domain.com\" + $destination + "\" + $foldername
    Log "Working on $path..." yellow
    if ($foldername -match '^[ \t]+|[ \t]+$|�' -or $Destination -match '^[ \t]+|[ \t]+$|�')
    {
        log "There is an invalid character for: $foldername..." red  
        log "Please correct the invalid character or trailing spaces." red
    }

    
    Else
    {
        if (test-path $Path) {Log "DFS Location, $path, Exists Already" Red}     
        else
                                                                                                                                                                                                                                                                                                                                                                                                    {   
        #create Global Groups
        If ($destination -match "folderinfo")
        {
            $RW = "AM-" + $foldername + "-globalgroup"    
            $RO = "AM-" + $foldername + "-globalgroup"
            $viewgroup = "domain\globalgroup"
            $nfolder = "\\server\c$\folder\" + $foldername + "-info"
                               
        }
        elseif ($destination -match "folderinfo")
        {
            $RW = "AM-" + $foldername + "-CD"    
            $RO = "AM-" + $foldername + "-CD"
            $viewgroup = "domain\globalgroup"
            $nfolder = "\\server\c$\folder\" + $foldername + "-info"

        }
        elseif ($destination -match "folderinfo")
        {
            $RW = "AM-" + $foldername + "-RW"   
            $RO = "AM-" + $foldername + "-RO"
            $viewgroup = "domain\globalgroup"
            $nfolder = "\\server\c$\folder\" + $foldername
        }

        #Create AD Universal Groups
        try
        {
            New-ADGroup -Name $RW -SamAccountName $RW -GroupCategory Security -GroupScope Universal -Path "OU Location" -Description $path -ErrorAction Stop *>> $global:logfile
            $RWresults = get-adgroup $RW -Properties * -ErrorAction Stop
            Log "Created Group: $RW" green
            $RWresults | select name, description | out-string | Tee-Object $global:logfile -Append
        }
        Catch {Log "Error with Creating Group: $RW" red}

       
        Try
        {
            New-ADGroup -Name $RO -SamAccountName $RO -GroupCategory Security -GroupScope Universal -Path "OU Location" -Description $path -ErrorAction Stop *>> $global:logfile
            $ROresults = get-adgroup $RO -Properties * -ErrorAction Stop
            Log "Created Group: $RO" green
            $ROresults | select name, description | out-string | Tee-Object $global:logfile -Append
        }      
        Catch {Log "Error with Creating Group: $RO" red}

     
        If (test-path $nfolder) {Log "Local Folder Exists Already, $nfolder" red}
        Else
        {
            New-item $nfolder -ItemType Directory *>> $global:logfile
            if (test-path $nfolder) 
            {
                Log "Created Directory: $nfolder" green

                #set NTFS Permissions
                icacls $nfolder /grant ($RW + ':(OI)(CI)M') *>> $global:logfile
                icacls $nfolder /grant ($RO + ':(OI)(CI)RX') *>> $global:logfile
                Log "Added below permissions:" yellow
                icacls $nfolder | Tee-Object $global:logfile -Append

                #create Share
                $sharename = $nfolder -replace(" ","-") | split-path -Leaf
                $localname = $nfolder | split-path -Leaf
                $localpath = "C:\ifs\data\Tier2\Base\NewData2\" + $localname
                New-NetShare -Server server -Name $sharename -Path $localpath -Permissions "Authenticated Users|FullControl" *>> $global:logfile
                $targetpath = "\\server\" + $sharename
                if (test-path $targetpath) 
                {
                    Log "Created Shared: $targetpath" green
                    Get-NetShare -Server server -name $sharename | Tee-Object $global:logfile -Append
                    #Create DFS Share
                    Log "Creating DFS Share..." yellow
                    New-DfsnFolder -Path $path -TargetPath $targetpath *>> $global:logfile
                    $RWGrp = $rw + ":RX"
                    $ROGrp = $ro + ":RX"
                    $ViewRXGrp = $viewgroup + ":RX"
                    dfsutil property sd grant $path $RWGrp protect *>> $global:logfile
                    dfsutil property sd grant $path $ROGrp protect *>> $global:logfile
                    dfsutil property sd grant $path domain\group:RX protect *>> $global:logfile
                    dfsutil property sd grant $path domain\group:RX protect *>> $global:logfile
                    dfsutil property sd grant $path $ViewRXGrp protect *>> $global:logfile
                    Start-Wait -seconds 10 -msg "Creating DFS Share..."
                    if (test-path $path) 
                    {
                        Log "Created DFS Share: $path" green
                        Log "Added below View Permissions on DFS Folder:" yellow
                        dfsutil property SD $path | Tee-Object $global:logfile -Append
                    }
                    else {Log "Error with DFS Share Creation for $path" red}        

                }
                else {Log "Error with Share Creation for $targetpath" red}        




            }
            else {Log "Error with Creating Directory: $nfolder" red}
        }   

    }

    } 
}
Log "DONE" green
#remove FileShareUtils Module
if (get-module -name FileShareUtils) {remove-Module FileShareUtils *>> $global:logfile}
write-output ("Script stopped at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $global:logfile -Append