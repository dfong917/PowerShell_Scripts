#Automate Builds
#connect to am2svsctr01
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
<#
.SYNOPSIS
	Returns the folderpath for a folder
.DESCRIPTION
	The function will return the complete folderpath for
	a given folder, optionally with the "hidden" folders
	included. The function also indicats if it is a "blue"
	or "yellow" folder.
.NOTES
	Authors: Luc Dekens
.PARAMETER Folder
	On or more folders
.PARAMETER ShowHidden
	Switch to specify if "hidden" folders should be included
	in the returned path. The default is $false.
.EXAMPLE
	PS> Get-FolderPath -Folder (Get-Folder -Name "MyFolder")
.EXAMPLE
	PS> Get-Folder | Get-FolderPath -ShowHidden:$true
#>


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
        $ExcelValue = $BuildValue[$i] #| ft -HideTableHeaders | Out-String
        <#if (!$tableheaders) 
        {
            $ExcelValue = $BuildValue[$i]
            $global:worksheet.cells.item($excelcount, $excelcolumn) = $ExcelValue
        }
        Else 
        {
            $ExcelValue = $BuildValue[$i] | ft -HideTableHeaders -AutoSize | Out-String
            $global:worksheet.cells.item($excelcount, $excelcolumn) = $ExcelValue #| ft -HideTableHeaders -AutoSize | Out-String
        }#>
        $global:worksheet.cells.item($excelcount, $excelcolumn) = $ExcelValue
        $excelcount ++
    }


}

Function Login-vCenter ($Domain_login)
{
    Add-PSSnapin VMware.VimAutomation.Core
    Connect-VIServer $Global:vCenter -Credential $Domain_login | out-file $global:logfile -Append

    #Write-host "Do you want to load PowerCli?" -ForegroundColor Yellow 
    #$Readhost = Read-Host " ( y / n ) "
    #if ($Readhost = "y") {Add-PSSnapin VMware.VimAutomation.Core}
    #write-host `n
    #Write-host "Select which vCenter to build:" -ForegroundColor Yellow
    #Write-host "1 - AM1SVSCTR01"
    #Write-host "2 - AM2SVSCTR01"
    #Write-host "3 - EU1SVSCTR01"
    #Write-host "4 - EU2SVSCTR01"
    #Write-host "5 - AS1SVSCTR01"
    #Write-host "C - Cancel"
    #$result = Read-host "(1, 2, 3, 4, 5, C)"

    #Switch ($result)            
    #    {            
    #       1 { Connect-VIServer AM1SVSCTR01 -WarningAction SilentlyContinue
    #           $Global:BuildFile = "C:\temp\AM1_Test2.xlsm"

    #         }            
    #       2 { 
    #           Connect-VIServer AM2SVSCTR01 -WarningAction SilentlyContinue
    #           $Global:BuildFile = "C:\temp\AM2_Test2.xlsm"
    #
    #         }           
    #       3 { Connect-VIServer EU1SVSCTR01}          
    #       4 { Connect-VIServer EU2SVSCTR01}          
    #       5 { Connect-VIServer AS1SVSCTR01}        
    #       C { return }            
    #    }   

}
cls
$WarningPreference = "SilentlyContinue"
$host.ui.RawUI.WindowTitle = 'BUILDING SPREADSHEET...Please Do Not Close!'
$logtime = Get-date -Format "MM-dd-yyyy_hh-mm-ss"
$global:logfile = 'C:\temp\'+"VMBUILDLog_"+$logtime+".txt"
write-output ("Script started at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $logfile -Append
# OLD CRED
#Log "Enter Domain Credentials:" yellow
#$Domaincred = Get-Credential -Message "CGSH Domain Account" -UserName $domain_id
$key = Get-Content "c:\temp\SharedPath\AES.key"
$Dpassword = get-content c:\temp\SharedPath\DPassword.txt | convertto-securestring -Key $key
$domaincred = new-object -typename System.Management.Automation.PSCredential -argumentlist "cgsh\dfongadmin",$Dpassword
Login-vCenter $Domaincred

Log "Building Spreadsheet...Please Wait" Yellow -Sameline True

#$global:excel = new-object -comobject Excel.Application
# Edit this value to the location of your vmware_expert_system.xlsm
#$global:excelfile = $global:excel.workbooks.open("$global:buildfile")
#$global:worksheet = $global:excelfile.worksheets.item(2) # Select Capacity Worksheet
#$global:workform = $global:excelfile.worksheets.item(1) # Select Capacity Worksheet
#Write-Host "Clearing existing capacity data...2/8"
# Clear existing data
#$global:workform.Range("A2:J11").ClearContents() | out-null
#$global:worksheet.Range("A2:D31").ClearContents() | out-null
#$global:worksheet.Range("G2:H80").ClearContents() | out-null
# fully qualified path to target workbook
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
# etc.

#$worksheet.cells.item(2,2) = "david fong"
$templates=@()
$templates = get-folder templates | get-template -NoRecursion | Sort-Object Name
#$tcount = $templates.count
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

#$worksheet.cells.item(1,1) = "red"
#$worksheet.cells.item(2,1) = "blue"
#$worksheet.cells.item(3,1) = "orange"
#$worksheet.cells.item(4,1) = "green"
#$worksheet.cells.item(5,1) = "brown"
#$worksheet.cells.item(6,1) = "yellow"
#$worksheet.cells.item(7,1) = "violet"

#$global:excelfile.save() 
#$global:excelfile.close()
#[System.Runtime.Interopservices.Marshal]::ReleaseComObject($global:excelfile) | Out-Null
#$global:excel.Quit()
#[System.Runtime.Interopservices.Marshal]::ReleaseComObject($global:excel) | Out-Null
#[System.GC]::Collect()
#[System.GC]::WaitForPendingFinalizers()
#get-process excel | stop-process
# no $ needed on variable name in Remove-Variable call
#Remove-Variable excel
log "...DONE" green -Sameline True
#Invoke-Item $global:buildfile
Disconnect-VIServer * -Confirm:$false
Log " "
log "This Window will be Closed in 20 seconds..." yellow
Start-Sleep -Seconds 20 
write-output ("Script stopped at " + (Get-date -Format "MM-dd-yyyy_hh-mm-ss") + " by " + $env:userdomain + "\" + $env:username) | out-file $global:logfile -Append
