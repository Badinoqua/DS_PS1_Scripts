
#--------------------------------------------------------------------------------------------------------------------------------------------------
# Script Specific Variables
#--------------------------------------------------------------------------------------------------------------------------------------------------
$startupVariables=""
new-variable -force -name startupVariables -value ( Get-Variable | % { $_.Name }) 
$ErrorActionPreference = 'SilentlyContinue'
$FileDate = get-date -format MMddyyyy-HHmm
$PSVersionRequired = "3"
$LogFile    = "$PSScriptRoot\Migrate-OSCE_Settings_Log-$FileDate.log"
$ReportFile = "$PSScriptRoot\Migrate-OSCE_Settings_Report-$FileDate.csv"
$SourceFile = "$PSScriptRoot\Migrate-OSCE_Settings_SourceList.txt"
$Seperator = @"
`n
$("*" * 50)
`n
"@

#--------------------------------------------------------------------------------------------------------------------------------------------------
# Customer Specific Variables
#--------------------------------------------------------------------------------------------------------------------------------------------------
# Modify the following variables to match your environment
$DSM_URI = "https://DSM_ServerName:4119/webservice/Manager?WSDL"	# Enter your DSM SOAP Web Service API link or simply modify the server name in the link.
$Enable_Alerts = $true					# Enable Alerts for the Scan Configurations
$Using_Same_Exclusions = $true			# Does the different scan types in OfficeScan use the same Exclusion List?
$CookiesAction = "DELETE"				# Options are: DELETE, PASS
$BasePolicyName = "Lab Base Policy"		# This is the name of your Base Policy.  All subpolicies will be created under this policy.

#**************************************************************************************************************************************************
#Region Standard Functions
#**************************************************************************************************************************************************

#--------------------------------------------------------------------------------------------------------------------------------------------------
# CheckPSVersion
#--------------------------------------------------------------------------------------------------------------------------------------------------
Function CheckPSVersion { 
	$PS_Version =	$PSVersionTable.PSVersion.Major
	If ($PS_Version -lt $PSVersionRequired){
		MyLog -OutputFile $LogFile -msg "[ERROR]	Pwershell version is $PS_Version. Powershell version $PSVersionRequired is required."
		Write-Host "[ERROR]	Pwershell version is $PS_Version. Powershell version $PSVersionRequired is required."
		Exit
	}
}

#--------------------------------------------------------------------------------------------------------------------------------------------------
# MyLog
#--------------------------------------------------------------------------------------------------------------------------------------------------
Function MyLog { 
    param (	[parameter(Mandatory=$true)] $OutputFile,
			[parameter(Mandatory=$true)] $msg) 
			
    $f_LogDate = get-date -format "MM-dd-yyyy HH:mm:ss"
	If ($msg -eq $Seperator) {
		Write-Output "$Seperator" | Out-File $OutputFile -append
	}ElseIf($OutputFile -eq $LogFile){
		Write-Output "$f_LogDate	$msg" | Out-File $OutputFile -append
	}ElseIf ($OutputFile -eq $ReportFile) {
		Write-Output "$msg" | Out-File $OutputFile -append
	}
} 

#--------------------------------------------------------------------------------------------------------------------------------------------------
# Connect-DSM
#--------------------------------------------------------------------------------------------------------------------------------------------------
Function Connect-DSM {
	$f_DSM_Cred = Get-Credential -Message "Enter DSM Credentials"
	$f_DSM_ID = $f_DSM_Cred.GetNetworkCredential().UserName
	$f_DSM_PASS = $f_DSM_Cred.GetNetworkCredential().Password
	
	MyLog -OutputFile $LogFile -msg "[INFO]		Connecting to DSM server $DSM_URI"
	try{
		$f_sID = $objManager.authenticate($f_DSM_ID,$f_DSM_PASS)
		Remove-Variable f_DSM_ID
		Remove-Variable	f_DSM_PASS
		MyLog -OutputFile $LogFile -msg "[INFO]		Connection to DSM server $DSM_URI was SUCCESSFUL"
	}
	catch{
		MyLog -OutputFile $LogFile -msg "[ERROR]	Failed to logon to DSM.	$_"
		Remove-Variable f_DSM_ID
		Remove-Variable	f_DSM_PASS
		#Cleanup
		Exit 
	}
	return $f_sID
}

#--------------------------------------------------------------------------------------------------------------------------------------------------
# Cleanup
#--------------------------------------------------------------------------------------------------------------------------------------------------
Function Cleanup { 	
	$objManager.endSession($sID)
	Get-Variable | 
    	Where-Object { $startupVariables -notcontains $_.Name } | 
    	% { Remove-Variable -Name "$($_.Name)" -Force -Scope "Script" } 
}

#**************************************************************************************************************************************************
#Endregion
#**************************************************************************************************************************************************

#**************************************************************************************************************************************************
#Region Process Functions
#**************************************************************************************************************************************************


Function Migrate-Exclusions {
	param (	[parameter(Mandatory=$true)] $objReg,
			[parameter(Mandatory=$true)] $ScanType)
	
	[hashtable]$Exclusions = @{}
	
	switch ($ScanType) 
    { 
        None {
				$DirListName	=	$OSCE_Domain + " - Directory Exclusions"
				$FileListName	=	$OSCE_Domain + " - File Exclusions"
				$ExtListName	=	$OSCE_Domain + " - Extension Exclusions"
			} 
		Real-Time {
				$DirListName	=	$OSCE_Domain + " - RealTime Directory Exclusions"
				$FileListName	=	$OSCE_Domain + " - RealTime File Exclusions"
				$ExtListName	=	$OSCE_Domain + " - RealTime Extension Exclusions"
			} 
        Manual {
				$DirListName	=	$OSCE_Domain + " - Manual Directory Exclusions"
				$FileListName	=	$OSCE_Domain + " - Manual File Exclusions"
				$ExtListName	=	$OSCE_Domain + " - Manual Extension Exclusions"
			} 
        Scheduled {
				$DirListName	=	$OSCE_Domain + " - Scheduled Directory Exclusions"
				$FileListName	=	$OSCE_Domain + " - Scheduled File Exclusions"
				$ExtListName	=	$OSCE_Domain + " - Scheduled Extension Exclusions"
			}
    }
	
	$DirList_Exist	= $objManager.scanDirectoryListRetrieveByName($DirListName,$sID)
	$FileList_Exist	= $objManager.scanFileListRetrieveByName($FileListName,$sID)
	$ExtList_Exist	= $objManager.scanFileExtListRetrieveByName($ExtListName,$sID)
	If ($DirList_Exist.ID -ne $Null -and $FileList_Exist.ID -ne $Null -and $ExtList_Exist.ID -ne $Null){
		$Exclusions.Directory	= $DirList_Exist.ID
		$Exclusions.File		= $FileList_Exist.ID
		$Exclusions.Extension	= $ExtList_Exist.ID
		Return $Exclusions
	}	
	

	$ExcludedExt	= $objReg.GetValue("ExcludedExt")
	$ExcludedExt	= $ExcludedExt.Replace(".","")
	$ExcludedExt	= $ExcludedExt.Replace(",",[Environment]::NewLine)
	
	$ExcludedFile	= $objReg.GetValue("ExcludedFile")
	$ExcludedFile	= $ExcludedFile.Replace("|",[Environment]::NewLine)
	$ExcludedFile	= $ExcludedFile.Replace("%\",'}\')
	$ExcludedFile	= $ExcludedFile.Replace("%",'${')
	
	$ExcludedFolder	= $objReg.GetValue("ExcludedFolder")
	$ExcludedFolder	= $ExcludedFolder.Replace("\*|","\"+[Environment]::NewLine)
	$ExcludedFolder	= $ExcludedFolder.Replace("|","\"+[Environment]::NewLine)
	$ExcludedFolder	= $ExcludedFolder.Replace("%\",'}\')
	$ExcludedFolder	= $ExcludedFolder.Replace("%",'${')
	$ExcludedFolder	= $ExcludedFolder.Replace("\\",'\')
	$ExcludedFolder	= $ExcludedFolder.Replace("*\",'C:\Changeme\')
	
	$DirList		=	
@"
${ExcludedFolder}
"@

	$FileList		=	
@"
${ExcludedFile}
"@

	$ExtList		=	
@"
${ExcludedExt}
"@	

	$newDirList		=	New-Object $objManager.scanDirectoryListRetrieveByName($DirListName,$sID)
	$newDirList.set_Name($DirListName)
	$newDirList.set_Items($DirList)
	
	$newFileList	=	New-Object $objManager.scanFileListRetrieveByName($FileListName,$sID)
	$newFileList.set_Name($FileListName)
	$newFileList.set_Items($FileList)	
	
	$newExtList		=	New-Object $objManager.scanFileExtListRetrieveByName($ExtListName,$sID)
	$newExtList.set_Name($ExtListName)
	$newExtList.set_Items($ExtList)
	
	$SaveDirList	=	$objManager.scanDirectoryListSave($newDirList,$sID)
	$SaveFileList	=	$objManager.scanFileListSave($newFileList,$sID)
	$SaveExtList	=	$objManager.scanFileExtListSave($newExtList,$sID)	
	
	$Exclusions.Directory	= $SaveDirList.ID
	$Exclusions.File		= $SaveFileList.ID
	$Exclusions.Extension	= $SaveExtList.ID
	Return $Exclusions
} 

Function Get-ActionName { 
	param (	[parameter(Mandatory=$true)] $ActionValue)	
	# Deep Security possible actions are: UNSPECIFIED, PASS, DELETE, QUARANTINE, CLEAN, DENY_ACCESS
	# OfficeScan Actions:
	#	0: Deny Access
	#	1: Rename
	#	2: Quarantine
	#	3: Clean
	#	4: Delete
	Switch ($ActionValue)
	{
		0	{ $ActionName = "DENY_ACCESS"}
		1	{ $ActionName = "QUARANTINE"
				MyLog -OutputFile $LogFile -msg "Actual action in OSCE value is RENAME, DS does not have RENAME action.  Using Quarantine."
			}	
		2	{ $ActionName = "QUARANTINE"}
		3	{ $ActionName = "CLEAN"}
		4	{ $ActionName = "DELETE"}
	}
	Return $ActionName
}	

Function Get-Actions { 
	param (	[parameter(Mandatory=$true)] $CustomAction)	
	[hashtable]$Actions = @{}	
	$ActionArray = $CustomAction -split ","

	$UniverseActions	= $ActionArray.get_Item(0).substring(9)
	$JokeActions		= $ActionArray.get_Item(1).substring(5)
	$TrojanActions		= $ActionArray.get_Item(2).substring(7)
	$VirusActions		= $ActionArray.get_Item(3).substring(6)
	$TestVirusActions	= $ActionArray.get_Item(4).substring(11)
	$SpywareActions		= $ActionArray.get_Item(5).substring(8)
	$PackerActions		= $ActionArray.get_Item(6).substring(7)
	$GenericActions		= $ActionArray.get_Item(7).substring(8)
	$OtherActions		= $ActionArray.get_Item(8).substring(6)

	$Universe1stAction	= ($UniverseActions -split "-").get_Item(0)
	$Universe2ndAction	= ($UniverseActions -split "-").get_Item(1)
	$Joke1stAction		= ($JokeActions  -split "-").get_Item(0)
	$Trojan1stAction	= ($TrojanActions  -split "-").get_Item(0)
	$Virus1stAction		= ($VirusActions -split "-").get_Item(0)
	$TestVirus1stAction	= ($TestVirusActions -split "-").get_Item(0)
	$Spyware1stAction	= ($SpywareActions -split "-").get_Item(0)
	$Packer1stAction	= ($PackerActions -split "-").get_Item(0)
	$Generic1stAction	= ($GenericActions -split "-").get_Item(0)
	$Other1stAction		= ($OtherActions -split "-").get_Item(0)
	
	$Actions.Universe1stAction	= Get-ActionName -ActionValue $Universe1stAction
	$Actions.Universe2ndAction	= Get-ActionName -ActionValue $Universe2ndAction
	$Actions.Joke1stAction		= Get-ActionName -ActionValue $Joke1stAction
	$Actions.Trojan1stAction	= Get-ActionName -ActionValue $Trojan1stAction
	$Actions.Virus1stAction		= Get-ActionName -ActionValue $Virus1stAction
	$Actions.TestVirus1stAction	= Get-ActionName -ActionValue $TestVirus1stAction
	$Actions.Spyware1stAction	= Get-ActionName -ActionValue $Spyware1stAction
	$Actions.Packer1stAction	= Get-ActionName -ActionValue $Packer1stAction
	$Actions.Generic1stAction	= Get-ActionName -ActionValue $Generic1stAction
	$Actions.Other1stAction		= Get-ActionName -ActionValue $Other1stAction
	Return $Actions
} 

Function Migrate-ScanSettings { 
    param (	[parameter(Mandatory=$true)] $objReg,
			[parameter(Mandatory=$true)] $objSpywareReg,
			[parameter(Mandatory=$true)] $ScanType)

	switch ($ScanType) 
    { 
 		Real-Time {
				$ScanTypeName = "Real-Time"
				$ConfigurationType = "CONFIGURATIONTYPE_RTS"
				If ($Using_Same_Exclusions){
					$Exclusions = Migrate-Exclusions -objReg $objReg -ScanType "None"
				}Else{
					$Exclusions = Migrate-Exclusions -objReg $objReg -ScanType 	$ScanType		
				}
			}
        Manual {
				$ScanTypeName = "Manual"
				$ConfigurationType = "CONFIGURATIONTYPE_ODS"
				If ($Using_Same_Exclusions){
					$Exclusions = Migrate-Exclusions -objReg $objReg -ScanType "None"
				}Else{
					$Exclusions = Migrate-Exclusions -objReg $objReg -ScanType 	$ScanType		
				}
			}
        Scheduled {
				$ScanTypeName = "Scheduled"
				$ConfigurationType = "CONFIGURATIONTYPE_ODS"
				If ($Using_Same_Exclusions){
					$Exclusions = Migrate-Exclusions -objReg $objReg -ScanType "None"
				}Else{
					$Exclusions = Migrate-Exclusions -objReg $objReg -ScanType 	$ScanType		
				}				
			}
    }

	#General Tab
	#IntelliScan =1, ScanAllFiles = 1 ==> Using IntelliScan
	#IntelliScan =0, ScanAllFiles = 1 ==> Using All Files
	#IntelliScan =0, ScanAllFiles = 0 ==> Using Extensions
	$Enable_IntelliScan = $objReg.GetValue("IntelliScan")
	$Enable_ScanAllFiles = $objReg.GetValue("ScanAllFiles")
	
	If ($Enable_IntelliScan -eq 1 -AND $Enable_ScanAllFiles -eq 1){
		$AntimalwareFilesToScan = "INTELLISCAN"
	}Elseif($Enable_IntelliScan -eq 0 -AND $Enable_ScanAllFiles -eq 1){
		$AntimalwareFilesToScan = "ALLFILES"
	}Elseif($Enable_IntelliScan -eq 0 -AND $Enable_ScanAllFiles -eq 0){
		########################## NOT IMPLEMENTED YET ##############################
		$AntimalwareFilesToScan = "EXTLISTSCAN"
		$ExtList = $objReg.GetValue("ExtList")
		
	}Else{
		MyLog -OutputFile $LogFile -msg "Could not determine Files to Scan value.  Using All Files option."
		$AntimalwareFilesToScan = "ALLFILES"
	}

	#Actions Tab
	#ActiveAction = 1, EnableUniAct = 0 ==> Using Active Action
	#ActiveAction = 0, EnableUniAct = 1 ==> Using Same Action/Universal Actions
	#ActiveAction = 0, EnableUniAct = 0 ==> Using Specific Actions
	$Enable_ActiveAction = $objReg.GetValue("ActiveAction")	#Enables First Action Option
	$Enable_EnableUniAct = $objReg.GetValue("EnableUniAct")	#Enables Second Action Option
	
	If ($Enable_ActiveAction -eq 1 -AND $Enable_EnableUniAct -eq 0){
		#$AntimalwareScanActionType = "ACTIVEACTION" # Generated an error, wrong name in Deep Security
		$AntimalwareScanActionType = "INTELLIACTION"
		$PossibleVirusCustActInActiveAct = $objReg.GetValue("PossibleVirusCustActInActiveAct")
		$scanCustomActionForGeneric =	Get-ActionName -ActionValue $PossibleVirusCustActInActiveAct
		
	}ElseIf ($Enable_ActiveAction -eq 0 -AND $Enable_EnableUniAct -eq 1){
		$AntimalwareScanActionType = "CUSTOMACTION"	#Use universal Actions
		$CustAction = $objReg.GetValue("CustAction")	#Contain all custom actions
		
		$CustomActions	=	Get-Actions -CustomAction $CustAction		
		$scanActionForVirus			=	$CustomActions.Universe1stAction
		$scanActionForTrojans		=	$CustomActions.Universe2ndAction		#Use Second Action since Clean is not possible
		$scanActionForPacker		=	$CustomActions.Universe2ndAction		#Use Second Action since Clean is not possible
		$scanActionForSpyware		=	$CustomActions.Universe2ndAction		#Use Second Action since Clean is not possible
		$scanActionForOtherThreats	=	$CustomActions.Universe1stAction
		$scanCustomActionForGeneric	=	$CustomActions.Universe2ndAction		#Use Second Action since Clean is not possible
		
	}ElseIf ($Enable_ActiveAction -eq 0 -AND $Enable_EnableUniAct -eq 0){
		$AntimalwareScanActionType = "CUSTOMACTION"	#Use Specific Actions
		$CustAction = $objReg.GetValue("CustAction")	#Contain all custom actions
		
		$CustomActions	=	Get-Actions -CustomAction $CustAction		
		$scanActionForVirus			=	$CustomActions.Virus1stAction
		$scanActionForTrojans		=	$CustomActions.Trojan1stAction
		If ($scanActionForTrojans -eq "CLEAN"){
			$scanActionForTrojans	= "QUARANTINE"
		}
		$scanActionForPacker		=	$CustomActions.Packer1stAction
		If ($scanActionForPacker -eq "CLEAN"){
			$scanActionForPacker	= "QUARANTINE"
		}
		$scanActionForSpyware		=	$CustomActions.Spyware1stAction
		If ($scanActionForSpyware -eq "CLEAN"){
			$scanActionForSpyware	= "QUARANTINE"
		}
		$scanActionForOtherThreats	=	$CustomActions.Other1stAction
		$scanCustomActionForGeneric	=	$CustomActions.Generic1stAction
		
	}Else{
		MyLog -OutputFile $LogFile -msg "ERROR:		Could not determine Scan Action type."	
	}
	
	#Options Tab
	$Enable_Spyware 	= $objSpywareReg.GetValue("Enable")
	If ($Enable_Spyware -eq 1){
		$Spyware_Enable = $true
	}Else{
		$Spyware_Enable = $false
	}
	
	$Enable_ScanCompressed = $objReg.GetValue("ScanCompressed")
	If ($Enable_ScanCompressed -eq 1){
		$ScanCompressed_Enable = $true
	}Else{
		$ScanCompressed_Enable = $false
	}
	$MaximumExtractFileSize = $objReg.GetValue("MaximumExtractFileSize")
	$CompressedLayer = $objReg.GetValue("CompressedLayer")
	$CompressedFileCount = $objReg.GetValue("CompressedFileCount")	
	
	$Enable_ScanEmbeddedMSOO = $objReg.GetValue("OleLayer")
	If ($Enable_ScanEmbeddedMSOO -gt 0){
		$ScanOLE_Enable = $true
	}Else{
		$ScanOLE_Enable = $false
	}
	$ScanexploitcodeMSOO = $objReg.GetValue("OleExploitDetection")
	If ($ScanexploitcodeMSOO -eq 1){
		$scanOLEExploit_Enable = $true
	}Else{
		$scanOLEExploit_Enable = $false
	}
	$OLELayers = $objReg.GetValue("OleLayer")
	
	If ($ScanTypeName -eq "Real-Time"){	
		$ScanIncoming = $objReg.GetValue("ScanIncoming")
		$ScanOutgoing = $objReg.GetValue("ScanOutgoing")

		If ($ScanIncoming -eq 1 -AND $ScanOutgoing -eq 1){
			$ScanFilesActivity = "READ_WRITE"
		}Elseif($ScanIncoming -eq 1 -AND $ScanOutgoing -eq 0){
			$ScanFilesActivity = "WRITE_ONLY"
		}Elseif($ScanIncoming -eq 0 -AND $ScanOutgoing -eq 1){
			$ScanFilesActivity = "READ_ONLY"
		}
	
		$Enable_IntelliTrap = $objReg.GetValue("IntelliTrap")
		If ($Enable_IntelliTrap -eq 1){
			$IntelliTrap_Enable = $true
		}Else{
			$IntelliTrap_Enable = $false
		}
			
		$Enable_ScanNetwork = $objReg.GetValue("ScanNetwork")
		If ($Enable_ScanNetwork -eq 1){
			$ScanNetwork_Enable = $true
		}Else{
			$ScanNetwork_Enable = $false
		}
	}
	
	If ($ScanTypeName -eq "Manual" -or $ScanTypeName -eq "Scheduled"){
		$OS_CPUUsage = $objReg.GetValue("ScanSpeed")
		
		switch ($OS_CPUUsage) 
    	{ 
			0 {$DS_CPUUsage = "CPUUSAGE_HIGH"}
			1 {$DS_CPUUsage = "CPUUSAGE_MEDIUM"}
			2 {$DS_CPUUsage = "CPUUSAGE_LOW"}
		}
	}
	
	############################ Save Scan Configuration ################################
	$ScanConfig_Name	=	"$OSCE_Domain - $ScanTypeName Scan configuration"
	$new_ScanConfig		=	$objManager.antiMalwareRetrieveByName($ScanConfig_Name,$sID)	
	
	$new_ScanConfig.set_name($ScanConfig_Name)	
	$new_ScanConfig.set_configurationType($ConfigurationType)	
	$new_ScanConfig.set_fileToScan($AntimalwareFilesToScan)
	$new_ScanConfig.set_excludeScanDirectoryListID($Exclusions.Directory)
	$new_ScanConfig.set_excludeScanFileListID($Exclusions.File)
	$new_ScanConfig.set_excludeScanFileExtListID($Exclusions.Extension)
	$new_ScanConfig.set_scanAction($AntimalwareScanActionType)
	$new_ScanConfig.set_scanActionForVirus($scanActionForVirus)
	$new_ScanConfig.set_scanActionForTrojans($scanActionForTrojans)
	$new_ScanConfig.set_scanActionForPacker($scanActionForPacker)
	$new_ScanConfig.set_scanActionForSpyware($scanActionForSpyware)
	$new_ScanConfig.set_scanActionForOtherThreats($scanActionForOtherThreats)
	$new_ScanConfig.set_scanCustomActionForGeneric($scanCustomActionForGeneric)
	$new_ScanConfig.set_spywareEnabled($Spyware_Enable)
	$new_ScanConfig.set_scanCompressed($ScanCompressed_Enable)
	$new_ScanConfig.set_scanCompressedSmaller($MaximumExtractFileSize)
	$new_ScanConfig.set_scanCompressedLayer($CompressedLayer)
	$new_ScanConfig.set_scanCompressedNumberOfFiles($CompressedFileCount)
	$new_ScanConfig.set_scanOLE($ScanOLE_Enable)
	$new_ScanConfig.set_scanOLEExploit($scanOLEExploit_Enable)
	$new_ScanConfig.set_scanOLELayer($OLELayers)

	If ($ScanTypeName -eq "Real-Time"){
		$new_ScanConfig.set_scanFilesActivity($ScanFilesActivity)
		$new_ScanConfig.set_intelliTrapEnabled($IntelliTrap_Enable)
		$new_ScanConfig.set_scanNetworkFolder($ScanNetwork_Enable)
	}
	
	If ($ScanTypeName -eq "Manual" -or $ScanTypeName -eq "Scheduled"){
		$new_ScanConfig.set_cpuUsage($DS_CPUUsage)
		$new_ScanConfig.set_scanActionForCookie($CookiesAction)
	}
	$new_ScanConfig.set_alert($Enable_Alerts)
	
	$Save_ScanConfig =	$objManager.antiMalwareSave($new_ScanConfig,$sID)
	Return $Save_ScanConfig
} 

Function CheckExistingObjects {
	param (	[parameter(Mandatory=$true)] $Domain	)
	$ObjDomain = $Domain
	$Policy = $objManager.securityProfileRetrieveByName($ObjDomain,$sID)
	$PolicyName = $Policy.Name
	If ($PolicyName -ne $null){
		Return $True
	}

}

#**************************************************************************************************************************************************
#Endregion
#**************************************************************************************************************************************************


#--------------------------------------------------------------------------------------------------------------------------------------------------
# Main
#--------------------------------------------------------------------------------------------------------------------------------------------------
Clear
$StartDateTime    = get-date -format "MMddyyyy HH:mm"
MyLog -OutputFile $LogFile -msg "[INFO]		Script Started on $StartDateTime"
MyLog -OutputFile $LogFile -msg $Seperator

CheckPSVersion

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} #Used to bypass the DSM SSL certificate errors
$objManager = New-WebServiceProxy -uri $DSM_URI -namespace WebServiceProxy -class DSMClass	
$sID = Connect-DSM

$SystemList		= IMPORT-CSV $SourceFile
FOREACH ($Item in $SystemList) {
	$SystemName = $Item.SystemName
	$OSCE_GUID_64	= $null
	$OSCE_GUID_32	= $null
	If(Test-Connection -ComputerName $SystemName -Count 1 ){
		MyLog -OutputFile $LogFile -msg "[INFO]		$SystemName is Online"
		Try {
			$Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $SystemName)
		} Catch {
			MyLog -OutputFile $LogFile -msg "[ERROR]		Could not connect to $SystemName Registry.  Verify that the 'Remote Registry' service is running"
			Continue
		}
		#Identify the location of the Trend Registry:		
		$TMBase_RegKey_Path_32		= "SOFTWARE\\TrendMicro\\PC-cillinNTCorp\\CurrentVersion"
		$TMBase_RegKey_Path_64		= "SOFTWARE\\Wow6432Node\\TrendMicro\\PC-cillinNTCorp\\CurrentVersion"
		$TMBase_RegKey_64			= $Reg.OpenSubKey($TMBase_RegKey_Path_64)
		$TMBase_RegKey_32			= $Reg.OpenSubKey($TMBase_RegKey_Path_32)
		$OSCE_GUID_64				= $TMBase_RegKey_64.GetValue("GUID")
		$OSCE_GUID_32				= $TMBase_RegKey_32.GetValue("GUID")
		
		If ($OSCE_GUID_32 -ne $null){
			$TMBase_RegKey_Path		= "SOFTWARE\\TrendMicro\\PC-cillinNTCorp\\CurrentVersion"
			MyLog -OutputFile $LogFile -msg "[INFO]		$SystemName is 32-bit" 		
		}Elseif ($OSCE_GUID_64 -ne $null){
			$TMBase_RegKey_Path		= "SOFTWARE\\Wow6432Node\\TrendMicro\\PC-cillinNTCorp\\CurrentVersion"
			MyLog -OutputFile $LogFile -msg "[INFO]		$SystemName is 64-bit"
		}Else{
			MyLog -OutputFile $LogFile -msg "WARNING:	OfficeScan is not installed on $SystemName, skipping and going to the next entry"
			Continue	# Skip this system and go to the next.
		}
		
		$RealTime_RegKey_Path			= $TMBase_RegKey_Path + "\\Real Time Scan Configuration"
		$RealTime_Spyware_RegKey_Path	= $TMBase_RegKey_Path + "\\Real Time Scan Configuration\\Spyware Configuration"
		$Manual_RegKey_Path				= $TMBase_RegKey_Path + "\\Manual Scan Configuration"
		$Manual_Spyware_RegKey_Path		= $TMBase_RegKey_Path + "\\Manual Scan Configuration\\Spyware Configuration"
		$Scheduled_RegKey_Path			= $TMBase_RegKey_Path + "\\Prescheduled Scan Configuration"
		$Scheduled_Spyware_RegKey_Path	= $TMBase_RegKey_Path + "\\Prescheduled Scan Configuration\\Spyware Configuration"
		$Misc_RegKey_Path				= $TMBase_RegKey_Path + "\\Misc."
		
		$TMBase_RegKey				= $Reg.OpenSubKey($TMBase_RegKey_Path)
		$Misc_RegKey				= $Reg.OpenSubKey($Misc_RegKey_Path)
		
		$RealTime_RegKey			= $Reg.OpenSubKey($RealTime_RegKey_Path)
		$RealTime_Spyware_RegKey	= $Reg.OpenSubKey($RealTime_Spyware_RegKey_Path)

		$Manual_RegKey				= $Reg.OpenSubKey($Manual_RegKey_Path)
		$Manual_Spyware_RegKey		= $Reg.OpenSubKey($Manual_Spyware_RegKey_Path)
		$Scheduled_RegKey			= $Reg.OpenSubKey($Scheduled_RegKey_Path)
		$Scheduled_Spyware_RegKey	= $Reg.OpenSubKey($Scheduled_Spyware_RegKey_Path)
		
		##############################################################################
		
		$OSCE_Domain				= $TMBase_RegKey.GetValue("Domain")
		
		$CheckExistingObjects = CheckExistingObjects -Domain $OSCE_Domain
		If ($CheckExistingObjects){
			MyLog -OutputFile $LogFile -msg "[WARNING]	The Policy '$OSCE_Domain' Already exist, Skipping to the next system."
		}Else{		
			$OSCE_Version				= $Misc_RegKey.GetValue("ProgramVer")
			
			$RealTime_Config = Migrate-ScanSettings -objReg $RealTime_RegKey -objSpywareReg $RealTime_Spyware_RegKey -ScanType "Real-Time"
			$Manual_Config = Migrate-ScanSettings -objReg $Manual_RegKey -objSpywareReg $Manual_Spyware_RegKey -ScanType "Manual"
			$Scheduled_Config = Migrate-ScanSettings -objReg $Scheduled_RegKey -objSpywareReg $Scheduled_Spyware_RegKey -ScanType "Scheduled"
		
			
			##############################################################################
			#							Create Policy				
			$BasePolicy = $objManager.securityProfileRetrieveByName($BasePolicyName,$sID)
			$RealTime_Schedule = $objManager.scheduleRetrieveByName("Every Day All Day",$sID)
			$PolicyName = $OSCE_Domain		
			$New_Policy = $objManager.securityProfileRetrieveByName($PolicyName,$sID)
			
			# Set Policy Name and Inheritance
			$New_Policy.set_name($PolicyName)
			$New_Policy.set_parentSecurityProfileID($BasePolicy.ID)
			# Enable Features
			$New_Policy.set_antiMalwareState("ON")
			$New_Policy.set_DPIState("INHERITED")
			$New_Policy.set_firewallState("INHERITED")
			$New_Policy.set_logInspectionState("INHERITED")
			$New_Policy.set_integrityState("INHERITED")
			# Set Anti-malware configurations
			$New_Policy.set_antiMalwareRealTimeID($RealTime_Config.ID)
			$New_Policy.set_antiMalwareRealTimeScheduleID($RealTime_Schedule.ID)
			$New_Policy.set_antiMalwareManualID($Manual_Config.ID)		
			$New_Policy.set_antiMalwareScheduledID($Scheduled_Config.ID)

			$SavePolicy = $objManager.securityProfileSave($New_Policy,$sID)
			
			$CheckExistingObjects = CheckExistingObjects -Domain $OSCE_Domain
			If ($CheckExistingObjects){
				MyLog -OutputFile $LogFile -msg "[INFO]		The Policy '$OSCE_Domain' was created successfully."
			}Else{
				MyLog -OutputFile $LogFile -msg "[ERROR]	Failed to create the Policy '$OSCE_Domain'."
			}
		}
	}Else{
		MyLog -OutputFile $LogFile -msg "[WARNING]	$SystemName is Offline, make sure the system is powered on and pingable"
	}
}

#--------------------------------------------------------------------------------------------------------------------------------------------------
# END
#--------------------------------------------------------------------------------------------------------------------------------------------------
$FinishDateTime   = get-date -format "MMddyyyy HH:mm"
MyLog -OutputFile $LogFile -msg "[INFO]		Script Finished on $FinishDateTime"

Cleanup