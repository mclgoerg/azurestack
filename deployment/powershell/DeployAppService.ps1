﻿[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String] $azsPath,

    [parameter(Mandatory = $true)]
    [String]$downloadPath,

    [Parameter(Mandatory = $true)]
    [String] $customDomainSuffix,

    [Parameter(Mandatory = $true)]
    [String] $deploymentMode,

    [Parameter(Mandatory = $true)]
    [ValidateSet("AzureAd", "ADFS")]
    [String] $authenticationType,

    [Parameter(Mandatory = $false)]
    [String] $azureDirectoryTenantName,

    [parameter(Mandatory = $true)]
    [String] $tenantID,

    [parameter(Mandatory = $true)]
    [pscredential] $azsCreds,

    [parameter(Mandatory = $true)]
    [String] $VMpwd,
    
    [parameter(Mandatory = $true)]
    [String] $ScriptLocation,

    [parameter(Mandatory = $false)]
    [String] $skipAppService,

    [Parameter(Mandatory = $true)]
    [String] $branch,

    [Parameter(Mandatory = $true)]
    [String] $sqlServerInstance,

    [Parameter(Mandatory = $true)]
    [String] $databaseName,

    [Parameter(Mandatory = $true)]
    [String] $tableName,

    [Parameter(Mandatory = $true)]
    [String] $multiNode,

    [Parameter(Mandatory = $true)]
    [String] $certPath,

    [Parameter(Mandatory = $true)]
    [String] $certPwd
)

#Global:VerbosePreference = "Continue"
$Global:ErrorActionPreference = 'Stop'
$Global:ProgressPreference = 'SilentlyContinue'

$logFolder = "DeployAppService"
$logName = $logFolder
$progressName = $logFolder

### SET LOG LOCATION ###
$logDate = Get-Date -Format FileDate
New-Item -ItemType Directory -Path "$ScriptLocation\Logs\$logDate\$logFolder" -Force | Out-Null
$logPath = "$ScriptLocation\Logs\$logDate\$logFolder"

### START LOGGING ###
Write-Host "Starting logging"
$runTime = $(Get-Date).ToString("MMdd-HHmmss")
$fullLogPath = "$logPath\$($logName)$runTime.txt"
Start-Transcript -Path "$fullLogPath" -Append
Write-Host "Creating log folder"
Write-Host "Log folder has been created at $logPath"
Write-Host "Log file stored at $fullLogPath"
Write-Host "Starting logging"
Write-Host "Log started at $runTime"


$progressStage = $progressName
$progressCheck = CheckProgress -progressStage $progressStage

if ($progressCheck -eq "Complete") {
    Write-Host "Azure Stack POC Configurator Stage: $progressStage previously completed successfully"
}
elseif (($skipAppService -eq $false) -and ($progressCheck -ne "Complete")) {
    # We first need to check if in a previous run, this section was skipped, but now, the user wants to add this, so we need to reset the progress.
    if ($progressCheck -eq "Skipped") {
        Write-Host "Operator previously skipped this step, but now wants to perform this step. Updating AzSPoC database to Incomplete."
        # Update the AzSPoC database back to incomplete
        StageReset -progressStage $progressStage
        $progressCheck = CheckProgress -progressStage $progressStage
    }
    $rpAttempt = 0
    $rpSuccess = $false
    while ((($progressCheck -eq "Incomplete") -or ($progressCheck -eq "Failed")) -and ($rpAttempt -lt 3)) {
        $rpAttempt++ # Increment the attempt
        Write-Host "This is deployment attempt $rpAttempt for the deployment of the App Service Resource Provider."
        try {
            if ($progressCheck -eq "Failed") {
                # Clean up previous attempt - RG
                $ArmEndpoint = "https://adminmanagement.$customDomainSuffix"
                Add-AzureRMEnvironment -Name "AzureStackAdmin" -ArmEndpoint "$ArmEndpoint" -ErrorAction Stop
                Add-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $tenantID -Credential $azsCreds -ErrorAction Stop | Out-Null
                $sub = Get-AzureRmSubscription | Where-Object { $_.Name -eq "Default Provider Subscription" }
                $azureContext = Get-AzureRmSubscription -SubscriptionID $sub.SubscriptionId | Select-AzureRmSubscription
                $azsLocation = (Get-AzureRmLocation).DisplayName
                $appServiceRGCheck = (Get-AzureRmResourceGroupDeployment -ResourceGroupName "appservice-infra" -Name "AppService.DeployCloud" -ErrorAction SilentlyContinue)
                if ($appServiceRGCheck) {
                    Write-Output "There is evidence of a previous attempted App Service deployment in the App Service Resource Group. Starting cleanup..."
                    Get-AzureRmResourceGroup -Name "appservice-infra" -Location $azsLocation -ErrorAction SilentlyContinue | Remove-AzureRmResourceGroup -Force -ErrorAction SilentlyContinue -Verbose
                }
                # Update the AzSPoC database back to incomplete status if previously failed
                StageReset -progressStage $progressStage
                $progressCheck = CheckProgress -progressStage $progressStage
            }
            Write-Host "Clearing previous Azure/Azure Stack logins"
            Get-AzureRmContext -ListAvailable | Where-Object { $_.Environment -like "Azure*" } | Remove-AzureRmAccount | Out-Null
            Clear-AzureRmContext -Scope CurrentUser -Force
            Disable-AzureRMContextAutosave -Scope CurrentUser

            # Need to ensure this stage doesn't start before the App Service components have been downloaded
            $appServicePreReqJobCheck = CheckProgress -progressStage "AddAppServicePreReqs"
            while ($appServicePreReqJobCheck -ne "Complete") {
                Write-Host "The AddAppServicePreReqs stage of the process has not yet completed. Checking again in 20 seconds"
                Start-Sleep -Seconds 20
                $appServicePreReqJobCheck = CheckProgress -progressStage "AddAppServicePreReqs"
                if ($appServicePreReqJobCheck -eq "Failed") {
                    throw "The AddAppServicePreReqs stage of the process has failed. This should fully complete before the App Service deployment can be started. Check the AddAppServicePreReqs log, ensure that step is completed first, and rerun."
                }
            }
            # Need to ensure this stage doesn't start before the App Service File Server has been deployed
            $appServiceFSJobCheck = CheckProgress -progressStage "AppServiceFileServer"
            while ($appServiceFSJobCheck -ne "Complete") {
                Write-Host "The AppServiceFileServer stage of the process has not yet completed. Checking again in 20 seconds"
                Start-Sleep -Seconds 20
                $appServiceFSJobCheck = CheckProgress -progressStage "AppServiceFileServer"
                if ($appServiceFSJobCheck -eq "Failed") {
                    throw "The AppServiceFileServer stage of the process has failed. This should fully complete before the App Service deployment can be started. Check the AppServiceFileServer log, ensure that step is completed first, and rerun."
                }
            }
            # Need to ensure this stage doesn't start before the App Service SQL Server has been deployed
            $appServiceSQLJobCheck = CheckProgress -progressStage "AppServiceSQLServer"
            while ($appServiceSQLJobCheck -ne "Complete") {
                Write-Host "The AppServiceSQLServer stage of the process has not yet completed. Checking again in 20 seconds"
                Start-Sleep -Seconds 20
                $appServiceSQLJobCheck = CheckProgress -progressStage "AppServiceSQLServer"
                if ($appServiceSQLJobCheck -eq "Failed") {
                    throw "The AppServiceSQLServer stage of the process has failed. This should fully complete before the App Service deployment can be started. Check the AppServiceSQLServer log, ensure that step is completed first, and rerun."
                }
            }

            $serverFull2016JobCheck = CheckProgress -progressStage "ServerFull2016Image"
            while ($serverFull2016JobCheck -ne "Complete") {
                Write-Host "The ServerFull2016Image stage of the process has not yet completed. Checking again in 20 seconds"
                Start-Sleep -Seconds 20
                $serverFull2016JobCheck = CheckProgress -progressStage "ServerFull2016Image"
                if ($serverFull2016JobCheck -eq "Failed") {
                    throw "The ServerFull2016Image stage of the process has failed. This should fully complete before the App Service deployment can be started. Check the AppServiceSQLServer log, ensure that step is completed first, and rerun."
                }
            }

            Write-Host "Logging into Azure Stack into the admin space to retrieve relevant info"
            # Login to Azure Stack to grab FQDNs and also Identity App ID locally
            <#
            $ArmEndpoint = "https://management.$customDomainSuffix"
            Add-AzureRMEnvironment -Name "AzureStackUser" -ArmEndpoint "$ArmEndpoint" -ErrorAction Stop
            Add-AzureRmAccount -EnvironmentName "AzureStackUser" -TenantId $tenantID -Credential $azsCreds -ErrorAction Stop | Out-Null
            Write-Host "Selecting the *ADMIN APPSVC BACKEND subscription"
            $sub = Get-AzureRmSubscription | Where-Object { $_.Name -eq '*ADMIN APPSVC BACKEND' }
            $azureContext = Get-AzureRmSubscription -SubscriptionID $sub.SubscriptionId | Select-AzureRmSubscription
            $subID = $azureContext.Subscription.Id
            Write-Host "Current subscription ID is: $subID"
            #>
            $ArmEndpoint = "https://adminmanagement.$customDomainSuffix"
            Add-AzureRMEnvironment -Name "AzureStackAdmin" -ArmEndpoint "$ArmEndpoint" -ErrorAction Stop
            Add-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $tenantID -Credential $azsCreds -ErrorAction Stop | Out-Null
            $sub = Get-AzureRmSubscription | Where-Object { $_.Name -eq "Default Provider Subscription" }
            $azureContext = Get-AzureRmSubscription -SubscriptionID $sub.SubscriptionId | Select-AzureRmSubscription
            Write-Host "Getting File Server and SQL App Server FQDN"
            $fileServerFqdn = (Get-AzureRmPublicIpAddress -Name "fileserver_ip" -ResourceGroupName "appservice-fileshare").DnsSettings.Fqdn
            $sqlAppServerFqdn = (Get-AzureRmPublicIpAddress -Name "sqlapp_ip" -ResourceGroupName "appservice-sql").DnsSettings.Fqdn
            Write-Host "Getting Application ID"
            $identityApplicationID = Get-Content -Path "$downloadPath\ApplicationIDBackup.txt" -ErrorAction SilentlyContinue
            Write-Host "File Server is at: $fileServerFqdn"
            Write-Host "SQL for App Service is at: $sqlAppServerFqdn"
            Write-Host "Identity Application ID is: $identityApplicationID"

            if ($multiNode -eq $false) {
                $certPwd = $VMpwd
            }

            if ($multiNode -eq $true) {
                # Need to clean up old Cert folders to avoid conflicts with deployments
                if ($([System.IO.Directory]::Exists("${Env:ProgramFiles(x86)}\ARM\AppService"))) {
                    Remove-Item -Path "${Env:ProgramFiles(x86)}\ARM\AppService" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
                }
                if ($([System.IO.Directory]::Exists("${Env:ProgramFiles(x86)}\ARM\AppServiceCerts"))) {
                    Remove-Item -Path "${Env:ProgramFiles(x86)}\ARM\AppServiceCerts" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
                }
            }

            Write-Host "Checking variables are present before creating JSON"
            # Check Variables #
            if (($authenticationType.ToString() -like "AzureAd") -and ($azureDirectoryTenantName)) {
                Write-Host "Azure Directory Tenant Name is present: $azureDirectoryTenantName"
            }
            elseif ($authenticationType.ToString() -like "ADFS") {
                Write-Host "ADFS deployment, no need for Azure Directory Tenant Name"
            }
            elseif (($authenticationType.ToString() -like "AzureAd") -and ($azureDirectoryTenantName)) {
                throw "Missing Azure Directory Tenant Name - Exiting process"
            }
            if ($fileServerFqdn) { 
                Write-Host "File Server FQDN is present: $fileServerFqdn"
            }
            else {
                throw "Missing File Server FQDN - Exiting process"
            }
            if ($VMpwd) {
                Write-Host "Virtual Machine password is present."
            }
            else {
                throw "Missing Virtual Machine password - Exiting process"
            }
            if ($certPwd) {
                Write-Host "Certificate password is present."
            }
            else {
                throw "Missing certificate password - Exiting process"
            }
            if ($sqlAppServerFqdn) {
                Write-Host "SQL Server FQDN is present: $sqlAppServerFqdn"
            }
            else {
                throw "Missing SQL Server FQDN - Exiting process"
            }
            if ($identityApplicationID) {
                Write-Host "Identity Application ID present: $identityApplicationID"
            }
            else {
                throw "Missing Identity Application ID - Exiting process"
            }

            $AppServicePath = "$azsPath\appservice"
            Set-Location "$AppServicePath"

            # Pull the pre-deployment JSON file from online, or the local zip file.
            if ($deploymentMode -eq "Online") {
                Write-Host "Downloading the AppServiceDeploymentSettings.json file from GitHub"
                $appServiceJsonURI = "https://raw.githubusercontent.com/mattmcspirit/azurestack/$branch/deployment/appservice/AppServiceDeploymentSettings.json"
                $appServiceJsonDownloadLocation = "$AppServicePath\AppSvcPre.json"
                DownloadWithRetry -downloadURI "$appServiceJsonURI" -downloadLocation "$appServiceJsonDownloadLocation" -retries 10
            }
            elseif (($deploymentMode -eq "PartialOnline") -or ($deploymentMode -eq "Offline")) {
                if ([System.IO.File]::Exists("$azsPath\appservice\AppSvcPre.json")) {
                    Write-Host "Located AppSvcPre.json file"
                }
                if (-not [System.IO.File]::Exists("$azsPath\appservice\AppSvcPre.json")) {
                    throw "Missing AppSvcPre.json file in extracted app service dependencies folder. Please ensure this exists at $azsPath\appservice\ - Exiting process"
                }
            }
            $JsonConfig = Get-Content -Path "$AppServicePath\AppSvcPre.json"
            # Edit the JSON from deployment

            Write-Host "Starting editing the JSON file"
            $JsonConfig = $JsonConfig.Replace("<<customDomainSuffix>>", $customDomainSuffix)

            if ($authenticationType.ToString() -like "AzureAd") {
                $JsonConfig = $JsonConfig.Replace("<<AzureDirectoryTenantName>>", $azureDirectoryTenantName)
            }
            elseif ($authenticationType.ToString() -like "ADFS") {
                $JsonConfig = $JsonConfig.Replace("<<AzureDirectoryTenantName>>", "adfs")
            }
            if ($multinode -eq $true) {
                $JsonConfig = $JsonConfig.Replace("<<controllerSkuSize>>", "Standard_F4s")
                $JsonConfig = $JsonConfig.Replace("<<managementSkuSize>>", "Standard_F4s")
                $JsonConfig = $JsonConfig.Replace("<<publisherSkuSize>>", "Standard_F2s")
                $JsonConfig = $JsonConfig.Replace("<<frontendSkuSize>>", "Standard_F2s")
                $JsonConfig = $JsonConfig.Replace("<<workerSkuSize>>", "Standard_F2s")
                $JsonConfig = $JsonConfig.Replace('"<<instances>>"', 2)
            }
            else {
                $JsonConfig = $JsonConfig.Replace("<<controllerSkuSize>>", "Standard_A2")
                $JsonConfig = $JsonConfig.Replace("<<managementSkuSize>>", "Standard_A2")
                $JsonConfig = $JsonConfig.Replace("<<publisherSkuSize>>", "Standard_A2")
                $JsonConfig = $JsonConfig.Replace("<<frontendSkuSize>>", "Standard_A2")
                $JsonConfig = $JsonConfig.Replace("<<workerSkuSize>>", "Standard_A2")
                $JsonConfig = $JsonConfig.Replace('"<<instances>>"', 1)
            }
            $JsonConfig = $JsonConfig.Replace("<<FileServerDNSLabel>>", $fileServerFqdn)
            $JsonConfig = $JsonConfig.Replace("<<Password>>", $VMpwd)
            $JsonConfig = $JsonConfig.Replace("<<certPassword>>", $certPwd)
            if ($multinode -eq $true) {
                $CertPathDoubleSlash = $certPath.Replace("\", "\\")
            }
            else {
                $CertPathDoubleSlash = $AppServicePath.Replace("\", "\\")
            }
            $JsonConfig = $JsonConfig.Replace("<<CertPathDoubleSlash>>", $CertPathDoubleSlash)
            $JsonConfig = $JsonConfig.Replace("<<SQLServerName>>", $sqlAppServerFqdn)
            $SQLServerUser = "sa"
            $JsonConfig = $JsonConfig.Replace("<<SQLServerUser>>", $SQLServerUser)
            $JsonConfig = $JsonConfig.Replace("<<IdentityApplicationId>>", $identityApplicationID)
            Out-File -FilePath "$AppServicePath\AppSvcPost.json" -InputObject $JsonConfig

            # Check App Service Database is clean - could exist from a previously failed run
            Write-Host "Checking for existing App Service database and logins.  Will clean up if this is a rerun."
            $secureVMpwd = ConvertTo-SecureString -AsPlainText $VMpwd -Force
            $dbCreds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $SQLServerUser, $secureVMpwd -ErrorAction Stop
            $appServiceDBCheck = Get-SqlInstance -ServerInstance $sqlAppServerFqdn -Credential $dbCreds | Get-SqlDatabase | Where-Object { $_.Name -like "*appservice*" }
            foreach ($appServiceDB in $appServiceDBCheck) {
                Write-Host "$($appServiceDB.Name) database found. Cleaning up to ensure a successful rerun of the AppService deployment"
                $cleanupQuery = "ALTER DATABASE $($appServiceDB.Name) SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $($appServiceDB.Name)"
                Invoke-Sqlcmd -Server $sqlAppServerFqdn -Credential $dbCreds -Query "$cleanupQuery" -Verbose 
            }

            $appServiceLoginCheck = Get-SqlLogin -ServerInstance $sqlAppServerFqdn -Credential $dbCreds -Verbose: $false | Where-Object { $_.Name -like "*appservice*" }
            foreach ($appServiceLogin in $appServiceLoginCheck) {
                Write-Host "$($appServiceLogin.Name) login found. Cleaning up"
                Remove-SqlLogin -ServerInstance $sqlAppServerFqdn -Credential $dbCreds -LoginName $appServiceLogin.Name -Force -Verbose
            }

            # Check if there is a previous failure for the App Service deployment - easier to completely clean the RG and start fresh
            Write-Host "Logging back into Azure Stack"
            $ArmEndpoint = "https://adminmanagement.$customDomainSuffix"
            Add-AzureRMEnvironment -Name "AzureStackAdmin" -ArmEndpoint "$ArmEndpoint" -ErrorAction Stop
            Add-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $tenantID -Credential $azsCreds -ErrorAction Stop | Out-Null
            $sub = Get-AzureRmSubscription | Where-Object { $_.Name -eq "Default Provider Subscription" }
            $azureContext = Get-AzureRmSubscription -SubscriptionID $sub.SubscriptionId | Select-AzureRmSubscription
            $azsLocation = (Get-AzureRmLocation).DisplayName
            $appServiceFailCheck = (Get-AzureRmResourceGroupDeployment -ResourceGroupName "appservice-infra" -Name "AppService.DeployCloud" -ErrorAction SilentlyContinue)
            if ($appServiceFailCheck.ProvisioningState -eq 'Failed') {
                Write-Output "There is evidence of a previously failed App Service deployment in the App Service Resource Group. Starting cleanup..."
                Get-AzureRmResourceGroup -Name "appservice-infra" -Location $azsLocation -ErrorAction SilentlyContinue | Remove-AzureRmResourceGroup -Force -ErrorAction SilentlyContinue -Verbose
            }

            # Deploy App Service EXE
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($azsCreds.Password)
            $appServiceInstallPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $appServiceLogTime = $(Get-Date).ToString("MMdd-HHmmss")
            $appServiceLogPath = "$AppServicePath\AppSvcLog$appServiceLogTime.txt"
            Set-Location "$AppServicePath"
            Write-Host "Starting deployment of the App Service"

            if ($deploymentMode -eq "Online") {
                Start-Process -FilePath .\AppService.exe -ArgumentList "/quiet /log `"$appServiceLogPath`" Deploy UserName=$($azsCreds.UserName) Password=$appServiceInstallPwd ParamFile=`"$AppServicePath\AppSvcPost.json`"" -PassThru
            }
            elseif (($deploymentMode -eq "PartialOnline") -or ($deploymentMode -eq "Offline")) {
                Start-Process -FilePath .\AppService.exe -ArgumentList "/quiet /log `"$appServiceLogPath`" Deploy OfflineInstallationPackageFile=`"$AppServicePath\appserviceoffline.zip`" UserName=$($azsCreds.UserName) Password=$appServiceInstallPwd ParamFile=`"$AppServicePath\AppSvcPost.json`"" -PassThru
            }

            while ((Get-Process AppService -ErrorAction SilentlyContinue).Responding) {
                Write-Host "App Service is deploying. Checking in 20 seconds"
                Start-Sleep -Seconds 20
            }
            if (!(Get-Process AppService -ErrorAction SilentlyContinue).Responding) {
                Write-Host "App Service deployment has finished executing."
            }

            $appServiceErrorCode = "Exit code: 0xffffffff"
            Write-Host "Checking App Service log file for issues"
            if ($(Select-String -Path $appServiceLogPath -Pattern "$appServiceErrorCode" -SimpleMatch -Quiet) -eq "True") {
                Write-Host "App Service install failed with $appServiceErrorCode"
                Write-Host "An error has occurred during deployment. Please check the App Service logs at $appServiceLogPath"
                # Need to check if the process failed, but the Resource Group shows success
                Write-Host "Logging back into Azure Stack to confirm the Resource Group shows as Succeeded or Failed"
                $ArmEndpoint = "https://adminmanagement.$customDomainSuffix"
                Add-AzureRMEnvironment -Name "AzureStackAdmin" -ArmEndpoint "$ArmEndpoint" -ErrorAction Stop
                Add-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $tenantID -Credential $azsCreds -ErrorAction Stop | Out-Null
                $sub = Get-AzureRmSubscription | Where-Object { $_.Name -eq "Default Provider Subscription" }
                $azureContext = Get-AzureRmSubscription -SubscriptionID $sub.SubscriptionId | Select-AzureRmSubscription
                $appServiceFailCheck = (Get-AzureRmResourceGroupDeployment -ResourceGroupName "appservice-infra" -Name "AppService.DeployCloud" -ErrorAction SilentlyContinue)
                if ($appServiceFailCheck.ProvisioningState -eq 'Succeeded') {
                    Write-Output "There is evidence of a failed App Service deployment in the log file, but the App Service Resource Group shows success. Starting cleanup..."
                    Get-AzureRmResourceGroup -Name "appservice-infra" -Location $azsLocation -ErrorAction SilentlyContinue | Remove-AzureRmResourceGroup -Force -ErrorAction SilentlyContinue -Verbose
                    throw "$($appServiceFailCheck.DeploymentName) has $($appServiceFailCheck.ProvisioningState), however the logs show a failure. Please check the App Service logs at $appServiceLogPath for full details. You should be able to rerun the script and it complete successfully."
                }
                elseif ($null -eq $appServiceFailCheck) {
                    Write-Output "There is evidence of a failed App Service deployment in the log file, and the App Service Resource Group looks incomplete. Starting cleanup..."
                    Get-AzureRmResourceGroup -Name "appservice-infra" -Location $azsLocation -ErrorAction SilentlyContinue | Remove-AzureRmResourceGroup -Force -ErrorAction SilentlyContinue -Verbose
                    throw "There is evidence of a failed App Service deployment in the log file, and the App Service Resource Group looks incomplete. This will be cleaned up ahead of a rerun. Please check the App Service logs at $appServiceLogPath for full details. You should be able to rerun the script and it complete successfully."
                }
                throw "App Service install failed with $appServiceErrorCode. Please check the App Service logs at $appServiceLogPath"
            }
            else {
                Write-Host "App Service log file indicates successful deployment"
            }
            Write-Host "Checking App Service resource group for successful deployment"
            # Ensure logged into Azure Stack
            $ArmEndpoint = "https://adminmanagement.$customDomainSuffix"
            Add-AzureRMEnvironment -Name "AzureStackAdmin" -ArmEndpoint "$ArmEndpoint" -ErrorAction Stop
            Add-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $tenantID -Credential $azsCreds -ErrorAction Stop | Out-Null
            $sub = Get-AzureRmSubscription | Where-Object { $_.Name -eq "Default Provider Subscription" }
            $azureContext = Get-AzureRmSubscription -SubscriptionID $sub.SubscriptionId | Select-AzureRmSubscription
            $appServiceRgCheck = (Get-AzureRmResourceGroupDeployment -ResourceGroupName "appservice-infra" -Name "AppService.DeployCloud" -ErrorAction SilentlyContinue)
            if ($appServiceRgCheck.ProvisioningState -ne 'Succeeded') {
                Write-Host "An error has occurred during deployment. Please check the App Service logs at $appServiceLogPath"
                throw "$($appServiceRgCheck.DeploymentName) has $($appServiceRgCheck.ProvisioningState). Please check the App Service logs at $appServiceLogPath"
            }
            else {
                Write-Host "App Service deployment with name: $($appServiceRgCheck.DeploymentName) has $($appServiceRgCheck.ProvisioningState)"
            }
            # Update the AzSPoC database with successful completion
            $progressStage = $progressName
            # Update the AzSPoC database with successful completion
            $progressCheck = CheckProgress -progressStage $progressStage
            StageComplete -progressStage $progressStage
            $progressCheck = CheckProgress -progressStage $progressStage
            $rpSuccess = $true
        }
        catch {
            Write-Host "Attempt #$rpAttempt failed with $_.Exception.Message."
            Write-Host "This will be retried a maximum of 3 times"
            Set-Location $ScriptLocation
        }
    }
    if (($rpSuccess -eq $false) -and ($rpAttempt -ge 3)) {
        Write-Host "Deploying the App Service Resource Provider failed after 3 attempts. Check the logs and rerun the script"
        $progressStage = $progressName
        StageFailed -progressStage $progressStage
        $progressCheck = CheckProgress -progressStage $progressStage
        Set-Location $ScriptLocation
        throw "Deploying the App Service Resource Provider failed after 3 attempts. Check the logs and rerun the script"
    }
}
elseif ($skipAppService -and ($progressCheck -ne "Complete")) {
    Write-Host "Operator chose to skip App Service Deployment`r`n"
    # Update the AzSPoC database with skip status
    $progressStage = $progressName
    StageSkipped -progressStage $progressStage
}
Set-Location $ScriptLocation
$endTime = $(Get-Date).ToString("MMdd-HHmmss")
Write-Host "Logging stopped at $endTime"
Stop-Transcript -ErrorAction SilentlyContinue