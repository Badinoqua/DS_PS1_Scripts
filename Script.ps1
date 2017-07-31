#
# Script.ps1
#
Clear
Get-Host 

$DSM_URI = "https://ds10:4119/webservice/Manager?WSDL"

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} #Used to bypass the DSM SSL certificate errors
$objManager = New-WebServiceProxy -uri $DSM_URI -namespace WebServiceProxy -class DSMClass
