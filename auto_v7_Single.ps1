#Gather Vcenter data and insert into Excel Tables
#
 param(
  [CmdletBinding()]
  [parameter(Mandatory = $true)]
  [String[]]$Global:vCenter
  )

function log($string, $color, [ValidateSet("True","False")] $Sameline)
{
   if ($Color -eq $null) {$color = "white"}
   if ($sameline -eq "true") {write-host -NoNewline $string -foregroundcolor $color}
   Else {write-host $string -foregroundcolor $color}
   $string | out-file -Filepath $global:logfile -append
}

function Get-FolderPath{

param(
[parameter(valuefrompipeline = $true,
position = 0,
HelpMessage = "Enter a folder")]
[VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl[]]$Folder,
[switch]$ShowHidden = $false
)

 

begin
{
    $excludedNames = "Datacenters","vm","host"
}


process{
$Folder | 
%{
    $fld = $_.Extensiondata
    $fldType = "yellow"
    if($fld.ChildType -contains "VirtualMachine")
    {
        $fldType = "blue"
    }
    $path = $fld.Name
    while($fld.Parent)
    {
        $fld = Get-View $fld.Parent
        if((!$ShowHidden -and $excludedNames -notcontains $fld.Name) -or $ShowHidden)
        {
            $path = $fld.Name + "\" + $path
        }
    }
    $row = "" | Select Name,Path,Type
    $row.Name = $_.Name
    $row.Path = $path
    $row.Type = $fldType
    $row
}
}
}

Function Get-Excel
{
    Param(
    $BuildValue,
    $StrCount,
    $excelcolumn,
    $tableheaders
    )
    $excelcount = 2
    for ($i=0; $i -lt $StrCount; $i++)
    {
        $ExcelValue = $BuildValue[$i]
        $global:worksheet.cells.item($excelcount, $excelcolumn) = $ExcelValue
        $excelcount ++
    }


}

Function Login-vCenter ($Domain_login)
{
    Add-PSSnapin VMware.VimAutomation.Core
    Connect-VIServer $Global:vCenter -Credential $Domain_login | out-file $global:logfile -Append

}
cls
$WarningPreference = "SilentlyContinue"
$host.ui.RawUI.WindowTitle = 'BUILDING SPREADSHEET...Please Do Not Close!'
$logtime = Get-date -Format "MM-dd-yyyy_hh-mm-ss"
$global:logfile = 'C:\temp\'+"VMBUILDLog_"+$logtime+".txt"
write-output ("Script started at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $logfile -Append

$key = Get-Content "c:\temp\SharedPath\AES.key"
$Dpassword = get-content c:\temp\SharedPath\DPassword.txt | convertto-securestring -Key $key
$domaincred = new-object -typename System.Management.Automation.PSCredential -argumentlist "domain\ID",$Dpassword
Login-vCenter $Domaincred

Log "Building Spreadsheet...Please Wait" Yellow -Sameline True


$targetWbFullPath = 'C:\Temp\am_vmbuild.xlsm'
# target workbook name
$targetWbName = Split-Path $targetWbFullPath -Leaf
$xl = [Runtime.Interopservices.Marshal]::GetActiveObject('Excel.Application')
# get the list of names of open workbooks
$wbList = $xl.Workbooks | ForEach-Object {$_.Name}
# if your target workbook is in the list…
$targetWb = if ($wbList -contains $targetWbName) {
 # …get it
 $xl.Workbooks.Item($targetWbName)
} else {
 # if your target workbook is not in the list…
 # exit the script, or…
 return
 # open it
 # $xl.Workbooks.Open($targetWbFullPath)
}
# get the sheet to modify
$global:worksheet = $targetWb.Sheets.Item('Workspace')


$templates=@()
$templates = get-folder templates | get-template -NoRecursion | Sort-Object Name
Get-Excel -BuildValue $templates.name -StrCount $templates.Count -excelcolumn 1

$cluster = get-cluster | Sort-Object name
Get-Excel -BuildValue $cluster.name -StrCount $cluster.Count -excelcolumn 2
log "...Please Wait" yellow -Sameline True
$datastores_info=@()
$datastores_info = Get-Datastore | sort -Descending freespacemb | select -First 50 | ft -HideTableHeaders -AutoSize| Out-String
$datastores = $datastores_info -split '["\n\r"|"\r\n"|\n|\r]'
$datastores = $datastores | where{$_ -ne ""}
Get-Excel -BuildValue $datastores -StrCount $datastores.Count -excelcolumn 3

$customization =@()
$customization = Get-OSCustomizationSpec | select name
Get-Excel -BuildValue $customization.name -StrCount $customization.count -excelcolumn 4

$vlan=@()
$vlan = Get-VirtualPortGroup -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | where {$_.portbinding -eq "static"} | Sort-Object
Get-Excel -BuildValue $vlan.name -StrCount $vlan.Count -excelcolumn 7
log "...Please Wait" yellow -Sameline True
$folders=@()
$folders= get-folder | get-folderpath | select path | Sort-Object path
Get-Excel -BuildValue $folders.path -StrCount $folders.Count -excelcolumn 8

log "...DONE" green -Sameline True

Disconnect-VIServer * -Confirm:$false
Log " "
log "This Window will be Closed in 20 seconds..." yellow
Start-Sleep -Seconds 20 
write-output ("Script stopped at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $global:logfile -Append
