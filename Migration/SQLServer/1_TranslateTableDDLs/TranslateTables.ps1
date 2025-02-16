﻿#======================================================================================================================#
#                                                                                                                      #
#  AzureSynapseScriptsAndAccelerators - PowerShell and T-SQL Utilities                                                 #
#                                                                                                                      #
#  This utility was developed to aid SMP/MPP migrations to Azure Synapse Migration Practitioners.                      #
#  It is not an officially supported Microsoft application or tool.                                                    #
#                                                                                                                      #
#  The utility and any script outputs are provided on "AS IS" basis and                                                #
#  there are no warranties, express or implied, including, but not limited to implied warranties of merchantability    #
#  or fitness for a particular purpose.                                                                                #
#                                                                                                                      #                    
#  The utility is therefore not guaranteed to generate perfect code or output. The output needs carefully reviewed.    #
#                                                                                                                      #
#                                       USE AT YOUR OWN RISK.                                                          #
#                                                                                                                      #
#======================================================================================================================#
#
# =================================================================================================================================================
# Description:
#       USE this to generate table schema out of SQL Server and prepare it for Azure Synapse Dedicated SQL Pool. 
#       Parameters driven configuration files are the input of this powershell scripts 
# =================================================================================================================================================
# =================================================================================================================================================
# 
# Authors: Faisal Malik and Gaiye "Gail" Zhou
# Tested with Azure Synaspe Analytics and SQL Server 2017 
# 
# Use this to set Powershell permissions (examples)
# Set-ExecutionPolicy Unrestricted -Scope CurrentUser 
# Unblock-File -Path C:\migratemaster\modules\1_TranslateMetaData\TranslateMetaData.ps1


Function GetDurations() {
    [CmdletBinding()] 
    param( 
        [Parameter(Position = 1, Mandatory = $true)] [datetime]$StartTime, 
        [Parameter(Position = 1, Mandatory = $true)] [datetime]$FinishTime
    ) 

    $ReturnValues = @{ }
    $Timespan = (New-TimeSpan -Start $StartTime -End $FinishTime)

    $Days = [math]::floor($Timespan.Days)
    $Hrs = [math]::floor($Timespan.Hours) 
    $Mins = [math]::floor($Timespan.Minutes)
    $Secs = [math]::floor($Timespan.Seconds)
    $MSecs = [math]::floor($Timespan.Milliseconds)

    if ($Days -ne 0) {

        $Hrs = $Days * 24 + $Hrs 
    }

   
    $durationText = '' # initialize it! 

    if (($Hrs -eq 0) -and ($Mins -eq 0) -and ($Secs -eq 0)) {
        $durationText = "$MSecs milliseconds." 
    }
    elseif (($Hrs -eq 0) -and ($Mins -eq 0)) {
        $durationText = "$Secs seconds $MSecs milliseconds." 
    }
    elseif ( ($Hrs -eq 0) -and ($Mins -ne 0)) {
        $durationText = "$Mins minutes $Secs seconds $MSecs milliseconds." 
    }
    else {
        $durationText = "$Hrs hours $Mins minutes $Secs seconds $MSecs milliseconds."
    }

    $ReturnValues.add("DurationText",  $durationText)

    $ReturnValues.add("Hours", $Hrs)
    $ReturnValues.add("Minutes", $Mins)
    $ReturnValues.add("Seconds", $Secs)
    $ReturnValues.add("Milliseconds", $MSecs)

    return $ReturnValues

}
Function GetPassword([SecureString] $securePassword) {
	$securePassword = Read-Host "Password" -AsSecureString
	$P = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
	return $P
}

function CleanUp {
    param (
        [string]$TempWorkPath = ""
    )
        
        Remove-Item -path $TempWorkPath -Recurse -Force
        Write-Host "  $TempWorkPath was successfully deleted." -ForegroundColor Magenta
}

function Get-ConfigData{
    Param(
        [Parameter()]
        [string]$FolderPath = "",
        [Parameter()]
        [string]$XlsxFile = "",
        [Parameter()]
        [string]$SqlServerName = "",
        [Parameter()]
        [string]$OutputFilesFullPath = ""
    )

    # Create an Excel workbook...
    $Excel = New-Object -ComObject Excel.Application;
    $Workbook = $Excel.WorkBooks.Open((Join-Path -Path (Convert-Path -Path $FolderPath) -ChildPath $XlsxFile));
    $WorkSheet = $Workbook.WorkSheets.Item(1); # Only 1 sheet so this doesn't need to change...
    $StartRow = 2; # ...ignore headers...

    # Insert into a System.Data.DataTable...
    $DataTable = New-Object -TypeName System.Data.DataTable;
    $null = $DataTable.Columns.Add('recId', 'System.Int32');

    $DataTable.Columns['recId'].AutoIncrement = $true;
    $null = $DataTable.Columns.Add('Active', 'System.Int32');
    $null = $DataTable.Columns.Add('ServerName', 'System.String');
    $null = $DataTable.Columns.Add('DatabaseName', 'System.String');
    $null = $DataTable.Columns.Add('SchemaName', 'System.String');
    $null = $DataTable.Columns.Add('AsaDatabaseName', 'System.String');
    $null = $DataTable.Columns.Add('AsaSchemaName', 'System.String');
    $null = $DataTable.Columns.Add('ObjectName', 'System.String');
    $null = $DataTable.Columns.Add('DropFlag', 'System.String');
    $null = $DataTable.Columns.Add('ObjectType', 'System.String');
    $null = $DataTable.Columns.Add('AsaTableType', 'System.String');
    $null = $DataTable.Columns.Add('TableDistrubution', 'System.String');
    $null = $DataTable.Columns.Add('HashKeys', 'System.String');
    $null = $DataTable.Columns.Add('OutputFolder', 'System.String');
    $null = $DataTable.Columns.Add('OutputFileName', 'System.String');

    # Load the DataTable...
    do {
        $Active = $WorkSheet.Cells.Item($StartRow, 1).Value();
        $DatabaseName = $WorkSheet.Cells.Item($StartRow, 2).Value();
        $SchemaName = $WorkSheet.Cells.Item($StartRow, 3).Value();      
        $AsaDatabaseName = $WorkSheet.Cells.Item($StartRow, 4).Value();
        $AsaSchemaName = $WorkSheet.Cells.Item($StartRow, 5).Value();
        $ObjectName = $WorkSheet.Cells.Item($StartRow, 6).Value();
        $ObjectType = $WorkSheet.Cells.Item($StartRow, 7).Value();
        $DropFlag = $WorkSheet.Cells.Item($StartRow, 8).Value();
        $AsaTableType = $WorkSheet.Cells.Item($StartRow, 9).Value();
        $TableDistrubution = $WorkSheet.Cells.Item($StartRow, 10).Value();
        $HashKeys = $WorkSheet.Cells.Item($StartRow, 11).Value();

        #$OutputFileName = $AsaDatabaseName + "_" + $AsaSchemaName + "_" + $ObjectName + ".sql"

        $Row = $DataTable.NewRow();
        $Row.Active = $Active;
        #$Row.ServerName = $SqlServerName
        $Row.DatabaseName = $DatabaseName;
        $Row.SchemaName = $SchemaName;
        $Row.AsaDatabaseName = $AsaDatabaseName;
        $Row.AsaSchemaName = $AsaSchemaName;
        $Row.ObjectName = $ObjectName;
        $Row.AsaTableType = $AsaTableType;
        $Row.ObjectType = $ObjectType;
        $Row.TableDistrubution = $TableDistrubution;
        $Row.HashKeys = $HashKeys;
        $Row.DropFlag = $DropFlag;
        #$Row.OutputFolder = $OutputFilesFullPath
        #$Row.OutputFileName = $OutputFileName;

        $DataTable.Rows.Add($Row);
        $StartRow++;    

    } while ($null -ne $WorkSheet.Cells.Item($StartRow, 1).Value());
    $Excel.Quit();

    #return ,$DataTable   # Ask Faisal why there is a comma in front of $DataTable 
    return $DataTable 
    
}

function Get-MetaData {
    param(
        [string] $outFolderName = "",
        [string] $source_datasource = "",
        [string] $source_database = "",
        [string] $UseIntegratedSecurity = "",
        [string] $UserName = "",
        [string] $Password = $securePassword,
        [string] $ThreePartsName = "NO",
        [string] $AsaDatabaseName = "AsaDbName",
        [string] $AsaSchemaName = "edw",
        [string] $source_table = '',
        [string] $source_schema = '',
        [string] $Active = '',
        [string] $OutputFileName = ''
    )
        
    if ($Active -eq 1){
        $tablename = $source_table
        $sqlVariable = "TABLENAME=$tablename"
        $sqlMetaDataFileName = "GetTableMetaData.sql"
        $sqlMetaDataFilePath = $MetaDataFilePath
        $sqlMetaDataFileFullPath = join-path $sqlMetaDataFilePath $sqlMetaDataFileName
         
        New-Item -ItemType Directory -Force -Path $outFolderName | Out-Null   

        if ($ThreePartsName.ToUpper() -eq "NO")
        {
            $tempSQLFileName = $AsaSchemaName + '.' + $source_table + '_t' + '.sql'
        }
        else {
            $tempSQLFileName = $AsaDatabaseName + "." + $AsaSchemaName + '.' + $source_table + '_t' + '.sql'

        }
       

        $tempSQLFullPath = join-path $TempWorkFullPath $tempSQLFileName

        if ($ThreePartsName.ToUpper() -eq "NO")
        {
            $tempFileName = $AsaSchemaName + '.' + $source_table + '.txt'
        }
        else {

            $tempFileName = $AsaDatabaseName +"." +  $AsaSchemaName + '.' + $source_table + '.txt'
        }


        $tempFileFullPath = join-path $TempWorkFullPath $tempFileName

    if ($UseIntegratedSecurity -eq 1){
        (Invoke-Sqlcmd -InputFile $sqlMetaDataFileFullPath `
                -ServerInstance $source_datasource -database $source_database -Variable $sqlVariable -OutputAs DataTables -ErrorAction Stop) | 
        ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Set-Content $tempFileFullPath
    }
    else 
    {
        (Invoke-Sqlcmd -InputFile $sqlMetaDataFileFullPath `
        -ServerInstance $source_datasource -database $source_database -Username $UserName -Password $Password -Variable $sqlVariable -OutputAs DataTables -ErrorAction Stop) | 
    ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Set-Content $tempFileFullPath
    }       

    $output = Get-Content $tempFileFullPath

    $output | foreach { $_.replace('"|"', '|').TrimStart('"').TrimEnd('"') } | Out-File $tempSQLFullPath 

    Get-ASASchema  -ThreePartsName $ThreePartsName `
                    -AsaDatabaseName $AsaDatabaseName `
                    -TableDistrubution $TableDistrubution `
                    -HashKeys $HashKeys `
                    -AsaTableType $AsaTableType `
                    -AsaSchemaName $AsaSchemaName `
                    -ObjectName $source_table `
                    -DropFlag $DropFlag `
                    -schemaFilePath $tempSQLFullPath `
                    -OutputFileName $OutputFileName

    }

    return $Active
}

function Get-ASASchema {

    param(
        [string] $ThreePartsName = "NO",
        [string] $AsaDatabaseName = "",
        [string] $TableDistrubution = "",
        [string] $HashKeys = "",
        [string] $AsaTableType = "",
        [string] $AsaSchemaName = "",
        [string] $ObjectName = "",
        [string] $DropFlag = "",
        [string] $schemaFilePath = $tempSQLFullPath,
        [string] $OutputFileName = ""
    )

    if ($TableDistrubution.ToUpper() -eq 'HASH') {

        $dist = $TableDistrubution.ToUpper() + '(' + $HashKeys + ')'

    }else {

        $dist = $TableDistrubution.ToUpper()
    }

    if ($AsaTableType.ToUpper() -eq 'CCI') {

        $idx = '               ,CLUSTERED COLUMNSTORE INDEX'

    }elseif ($AsaTableType.ToUpper() -eq 'HEAP') { 

        $idx = '               ,HEAP'
    
    }else {

        $idx = ''
    }

    $sbfr = [System.Text.StringBuilder]::new()

    #Generate File Header timeStamp 
    $myTimeStamp = (Get-Date)
    $myFileHeader = "-- Code generated on $myTimeStamp "
    [void]$sbfr.AppendLine("------------------------------------------------")
    [void]$sbfr.AppendLine($myFileHeader)
    [void]$sbfr.AppendLine("------------------------------------------------")

    if ( ($DropFlag.ToUpper() -eq 'YES') -or ($DropFlag.ToUpper() -eq 'Y') )  {

        if  (($ThreePartsName.ToUpper() -eq "YES") -or ($ThreePartsName.ToUpper() -eq "Y") )
        {

            [void]$sbfr.AppendLine('IF OBJECT_ID(N''[' + $AsaDatabaseName + '].[' +$AsaSchemaName + '].[' + $ObjectName + ']'')' + ' IS NOT NULL')
            [void]$sbfr.AppendLine('DROP TABLE [' + $AsaDatabaseName + '].[' + $AsaSchemaName + '].[' + $ObjectName + ']')
        }
        else {
            [void]$sbfr.AppendLine('IF OBJECT_ID(N''[' + $AsaSchemaName + '].[' + $ObjectName + ']'')' + ' IS NOT NULL')
            [void]$sbfr.AppendLine('DROP TABLE [' + $AsaSchemaName + '].[' + $ObjectName + ']')
        }

        [void]$sbfr.AppendLine('GO')

    }

    if  (($ThreePartsName.ToUpper() -eq "YES") -or ($ThreePartsName.ToUpper() -eq "Y") )
    {
        [void]$sbfr.AppendLine('CREATE TABLE [' + $AsaDatabaseName + '].[' + $AsaSchemaName + '].[' + $ObjectName + ']')
    }
    else {
        [void]$sbfr.AppendLine('CREATE TABLE [' + $AsaSchemaName + '].[' + $ObjectName + ']')
    }

    [void]$sbfr.AppendLine('(')

    
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine( ') ' )
    [void]$sb.AppendLine( 'WITH' )
    [void]$sb.AppendLine( '         (' )
    [void]$sb.AppendLine( '               DISTRIBUTION = ' + $dist )
    [void]$sb.AppendLine(                 $idx )
    [void]$sb.AppendLine( '         ) ' )
    [void]$sb.AppendLine( 'GO ' )


    $sb.ToString() | Add-Content -Path $schemaFilePath 

    if ( [string]::IsNullOrWhiteSpace($OutputFileName) ) {
        $OutputFileName = $AsaSchemaName + '.' + $ObjectName + '.sql' 
        $schemaOutFilePath = join-path $outFolderName $OutputFileName
    }
    else {
        $schemaOutFilePath= join-path $outFolderName $OutputFileName

    }

    Set-Content $schemaOutFilePath $sbfr.ToString()

    Get-Content -Path $tempSQLFullPath | Add-Content -Path $schemaOutFilePath

    (Get-Content $schemaOutFilePath) | ? { $_.trim() -ne "" } | Set-Content $schemaOutFilePath

    
  
    if((Select-String -Path $schemaOutFilePath -Pattern "currently not supported in Azure Synapse" -AllMatches).Matches.Count -gt 0) {
        $newoutputfilename = "chk_" + $OutputFileName
        Rename-Item -Path $schemaOutFilePath -NewName $newoutputfilename
    } 
     
}


########################################################################################
#
# Main Program Starts here
#
########################################################################################

$ProgramStartTime = (Get-Date)

$ScriptPath = Split-Path $MyInvocation.MyCommand.Path -Parent
Set-Location -Path $ScriptPath   
$FolderPath = $ScriptPath 
$XlsxFile = "SourceToTargetTablesConfig.xlsx"
$TempWorkFolder= "_Temp"
$TempWorkFullPath = join-path $FolderPath $TempWorkFolder


$MetaDataFilePath = Read-Host -prompt "Enter the Translate MetaData Config File Path or press 'Enter' to accept the default [$($FolderPath)]"
if ([string]::IsNullOrWhiteSpace($MetaDataFilePath)) {
        $MetaDataFilePath = $FolderPath
    }

    
$MetaDataFile = Read-Host -prompt "Enter the Translate MetaData Config File Name or press 'Enter' to accept the default [$($XlsxFile)]"
if ([string]::IsNullOrWhiteSpace($MetaDataFile)) {
        $MetaDataFile = $XlsxFile
    }

$MetaDataFileFullPath = join-path $MetaDataFilePath $MetaDataFile
    

if (!(test-path $MetaDataFileFullPath )) {
        Write-Host "Could not find MetaData Config File: $MetaDataFileFullPath " -ForegroundColor Red
        break 
    }


# Get Json File Input 
$defaultJsonCfgFile = "translate_config.json"

$jconCfgFile = Read-Host -prompt "Enter the Config File Name or press 'Enter' to accept the default [$($defaultJsonCfgFile)]"
if([string]::IsNullOrWhiteSpace($jconCfgFile)) {
        $jconCfgFile = $defaultJsonCfgFile
    }

$JsonCfgFileFullPath = join-path $ScriptPath  $jconCfgFile
if (!(test-path $JsonCfgFileFullPath )) {
        Write-Host "Could not find Translate Config File: $JsonCfgFileFullPath " -ForegroundColor Red
        break 
    }
    
$JsonConfig = Get-Content -Path $JsonCfgFileFullPath | ConvertFrom-Json 
    
$SqlServerName = $JsonConfig.ServerName
$UseIntegrated =  $JsonConfig.IntegratedSecurity
$ThreePartsName =  $JsonConfig.ThreePartsName
$OutputFilesFolder = $JsonConfig.OutputFolder

if (Test-Path $OutputFilesFolder)
{
    Write-Host "Previous Contents in this folder will be removed: $OutputFilesFolder" -ForegroundColor Red
	Remove-Item -Force -Recurse -Path $OutputFilesFolder 
    #New-Item -Path $OutputFilesFolder -ItemType Directory -Force 
}

if ( ($ThreePartsName.ToUpper() -eq "YES") -or  ($ThreePartsName.ToUpper() -eq "Y") ) {
	$ThreePartsName = "YES" 
}
else {
    $ThreePartsName = "NO" 
}


if ( ($UseIntegrated.ToUpper() -eq "YES") -or ($UseIntegrated.ToUpper() -eq "Y") )  
{

    $UseIntegratedSecurity = "1"
}
else 
{
	Write-Host "Need Login Information..." -ForegroundColor Yellow
	$UseIntegratedSecurity = "0" 
	$UserName = Read-Host -prompt "Enter the User Name to connect to the SQL Server"
  
	if ([string]::IsNullOrWhiteSpace($UserName)) {
		Write-Host "A user name must be entered" -ForegroundColor Red
		break
	}
	$Password = GetPassword
	if ([string]::IsNullOrWhiteSpace($Password)) {
		Write-Host "A password must be entered." -ForegroundColor Red
		break
	}
}


try {
      

    if (!(test-path $TempWorkFullPath)) {
        Write-Host "  $TempWorkFullPath was created to store temporary working files." -ForegroundColor Magenta
        New-Item -ItemType Directory -Force -Path $TempWorkFullPath | Out-Null
    }

    $configTable = Get-ConfigData -FolderPath $FolderPath -XlsxFile $MetaDataFile -SqlServerName $SqlServerName -OutputFilesFullPath $OutputFilesFolder

    #Write-Output -NoEnumerate $ds -- checking the datatable content
    foreach ($row in $configTable) { 
        $isActive = $row.Active
        $source_datasource = $SqlServerName
        $source_database = $row.DatabaseName
        $source_table = $row.ObjectName
        $source_schema = $row.SchemaName
        $AsaDatabaseName = $row.AsaDatabaseName
        $AsaSchemaName = $row.AsaSchemaName
        $AsaTableType = $row.AsaTableType
        $ObjectType = $row.ObjectType
        $TableDistrubution = $row.TableDistrubution
        $HashKeys = $row.HashKeys
        $DropFlag = $row.DropFlag
        $OutputFolder = $OutputFilesFolder

        if ($ThreePartsName.ToUpper() -eq "YES")
        {
            $OutputFileName =  $AsaDatabaseName + "_" + $AsaSchemaName + "_" + $row.ObjectName + ".sql"
        }
        else {
            $OutputFileName = $AsaSchemaName + "_" + $row.ObjectName + ".sql"
        }
       

        $StartTime = (Get-Date)

        $ReturnOutput = Get-MetaData -outFolderName $OutputFolder `
         -source_datasource $source_datasource `
         -source_database $source_database `
         -UseIntegratedSecurity $UseIntegratedSecurity `
         -UserName $UserName `
         -Password $Password `
         -ThreePartsName $ThreePartsName `
         -AsaDatabaseName $AsaDatabaseName `
         -AsaSchemaName  $AsaSchemaName `
         -source_table $source_table `
         -source_schema $source_schema `
         -Active $isActive `
         -OutputFileName $OutputFileName

         
         $FinishTime = (Get-Date)
         $runDuration = GetDurations  -StartTime  $StartTime -FinishTime $FinishTime
         $runDurationText = $runDuration.DurationText

         if ($ReturnOutput -match "error")
         {
             $DisplayMessage = "  Error Generating Azure Synapse Create Table SQL File for -----> " + $source_database + "." + $source_schema + '.' + $source_table + ". Error: " + $ReturnOutput 
             Write-Host $DisplayMessage -ForegroundColor Red -BackgroundColor Black
         } else {
     
             $ReturnOutput | ForEach-Object {
                 if (($_ -NotMatch "INFO") -and ($_ -notin (0,1))){
     
                     Write-Host $_ -ForegroundColor Green -BackgroundColor Black 
     
                 }
             }
             if ($ReturnOutput -eq 1){
                 $DisplayMessage = "  Generated Azure Synapse Create Table SQL File for: -----> " + $source_database + "." + $source_schema + '.' + $source_table + " -------- Duration: $runDurationText "
                 Write-Host $DisplayMessage -ForegroundColor Green -BackgroundColor Black
             }
     
         }
         
    }
    
    CleanUp -TempWorkPath $TempWorkFullPath

}
catch [Exception] {
    Write-Warning $_.Exception.Message
}


$ProgramFinishTime = (Get-Date)


$progDuration = GetDurations  -StartTime  $ProgramStartTime -FinishTime $ProgramFinishTime
$progDurationText = $progDuration.DurationText

Write-Host "  Total time translating these SQL Files: $progDurationText " -ForegroundColor Magenta -BackgroundColor Black

Set-Location -Path $ScriptPath
