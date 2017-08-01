#---------------------------------------------------------------------------------------------------------------------
# AUTHOR		: Yanni Kashoqa
# TITLE			: OfficeScan to Deep Security Scan Configuration Migration Tool
#
# VERSION		: 1.0
#
# DESCRIPTION	: This PowerShell script will migrate OfficeScan scan settings and exclusions to Deep Security
#
# DISCLAIMER	: Please feel free to make any changes or modifications as seen fit.
#
# FEATURES
# - Extract Exclusions and Scan Settings From OfficeScan Clients Registries
# - Create Exclusions containers in Deep Security
# - Create Scan Configurations in Deep Security
# - Create Policies in Deep Security.  The policy names will match the OfficeScan domain of the migrated system.
#
# REQUIRMENTS
# - PowerShell 3.0
# - SOAP Web Service API must be enabled in Deep Security console (Administration > System Settings > Advanced)
# - Remote systems are online and pingable
# - Remote Registry Service is running on remote systems
# - Account used to execute the script need to be a local admin on remote systems
#
# USAGE
# - Populate the source list file Migrate-OSCE_Settings_SourceList.txt with the system names leaving the header intact
# - Modify the script Customer Specific Variables to reflect the existing environment
# - Open a Powershell console as an administrator
# - Navigate to the script location and execute the script
#
#---------------------------------------------------------------------------------------------------------------------