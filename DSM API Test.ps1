#
# DSM_API_Test.ps1
#

Clear

$DSM_URI = "https://tmlab-ds10.cloudapp.net:4119/webservice/Manager?WSDL"

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} #Used to bypass the DSM SSL certificate errors
$objManager = New-WebServiceProxy -uri $DSM_URI -namespace WebServiceProxy -class DSMClass


$DSM_Cred = Get-Credential -Message "Enter DSM Credentials"
$DSM_ID = $DSM_Cred.GetNetworkCredential().UserName
$DSM_PASS = $DSM_Cred.GetNetworkCredential().Password
Write-Host $DSM_ID

try{
	$sID = $objManager.authenticate($DSM_ID,$DSM_PASS)
	Remove-Variable DSM_ID
	Remove-Variable	DSM_PASS
	Write-Output "[INFO]	Connection to DSM server $DSM_URI was SUCCESSFUL"
}
catch{
	Write-Output "[ERROR]	Failed to logon to DSM.	$_"
	Remove-Variable DSM_ID
	Remove-Variable	DSM_PASS
}



<#

	$ObjDomain = "Cloud Windows"
	$Policy = $objManager.securityProfileRetrieveByName($ObjDomain,$sID)
	$PolicyName = $Policy.Name
	If ($PolicyName -ne $null){
		Write-Host "$PolicyName Already exist"
	}
	
	$Policy.name
#>	

	$Computer = "tmlab-ds10.cloudapp.net"
	$hostDetailRetrieveByNameStartsWith = $objManager.hostDetailRetrieveByNameStartsWith($Computer,'Low',$sID) #Not Case Sensitive
	$HostID = $hostDetailRetrieveByNameStartsWith.ID
	$OverallStatus = $hostDetailRetrieveByNameStartsWith.overallStatus
	$Version = $hostDetailRetrieveByNameStartsWith.OverallVersion
	
	$hostDetailRetrieveByNameStartsWith
	
	#$objManager | get-member -type method
	
	
	