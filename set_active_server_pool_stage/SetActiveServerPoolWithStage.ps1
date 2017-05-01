##
# Print the settings for debugging purposes
##
function Print-DebugVariables($LtmIp, $UserName, $VirtualServer, $ServerPool, $StageServerPool) {
    Write-Host "Using LTM IP: $LtmIP"
    Write-Host "Using Username: $UserName"
    Write-Host "Using Virtual Server: $VirtualServer"
    Write-Host "Using New Server Pool: $ServerPool"
    Write-Host "Using New Stage Server Pool: $StageServerPool"
}

##
# Get the current virtual server pool name
##
function Get-CurrentPool($LtmIp, $VirtualServer, $Credential) {
    $uri = "https://$LtmIp/mgmt/tm/ltm/virtual/$VirtualServer"
    Write-Host "Requesting current server pool from $uri"
    $response = Invoke-RestMethod -Uri $uri -Credential $Credential -Method Get 

    return $response.pool
}

##
# Some LTM devices can be paired for failover.  Query a known device to
# select the active device in the group.
##
function Get-ActiveLtmDevice($LtmIp, $Credential) {
    $uri = "https://$LtmIp/mgmt/tm/cm/device"

    Write-Host "Requesting device config from $uri"
    $response = Invoke-RestMethod -Uri $uri -Credential $Credential -Method Get 

    $active = $null
    foreach ($item in $response.Items) {
        if ($item.failoverState -eq "active") {
            $active = $item.name
            Write-Host "$active is an active node"
        }
        else {
            Write-Host $item.fullPath " is not active" 
        }
    }
    if ($active -eq $null) {
        Write-Error "No active device found."
    }

    return $active
}

##
# Set a virtual server's pool name
##
function Set-ServerPool($LtmIp, $VirtualServer, $Pool, $Credential) {
    $uri = "https://$LtmIp/mgmt/tm/ltm/virtual/$VirtualServer"
    Write-Host "Setting server pool $Pool at $uri"

    $request = @{
        pool="$Pool"
    }

    $body = $request | ConvertTo-Json
    Invoke-RestMethod -Uri $uri -Credential $Credential -Method Patch -Body $body -ContentType 'application/json'
}

##
# Generate the name of a data group on the f5 based on the virtual server name.
# The name of datagroups created by this script is in the form 'dg_<virtual server name'.
##
function Format-DataGroupName($VirtualServer) {
    $dataGroupName = $VirtualServer -replace '/Common/',''
    return "dg_$dataGroupName"
}

##
# Retrieve a datagroup from the f5 device.
##
function Get-DataGroup($LtmIp, $DataGroupName, $Credential) {    
    $uri = "https://$LtmIp/mgmt/tm/ltm/data-group/internal/$DataGroupName"
    Write-Host "Getting data group $dataGroupName at $uri"
  
    try {
        $response = Invoke-RestMethod -Uri $uri -Credential $Credential -Method Get
    }
    catch {
        if ($_.Exception.Response.StatusCode.Value__ -eq 404) {
            $response = $null
        }
        else {
            throw $_.Exception
        }
    }
    
    return $response
}

##
# Create a new data group on the f5 with the blue_green_pool information setup.
##
function Create-DataGroupPool($LtmIp, $DataGroupName, $ServerPool, $StageServerPool, $Credential) {
     $uri = "https://$LtmIp/mgmt/tm/ltm/data-group/internal/"
     Write-Host "Creating data group $dataGroupName at $uri"

     $request = @{
       name = $DataGroupName
       type = "string"
       records = Generate-DataGroupPoolRecord -ServerPool $ServerPool -StageServerPool $StageServerPool
    }

    $body = $request | ConvertTo-Json
    Invoke-RestMethod -Uri $uri -Credential $Credential -Method Post -Body $body -ContentType 'application/json'
}

##
# Update the blue_green_pool record of the specified datagroup
##
function Update-DataGroupPool($LtmIp, $DataGroupName, $ServerPool, $StageServerPool, $DataGroup, $Credential) {
     $uri = "https://$LtmIp/mgmt/tm/ltm/data-group/internal/$DataGroupName"
     Write-Host "Updating data group $dataGroupName at $uri"

     # Generate new record data
     $newRecords = Generate-DataGroupPoolRecord -ServerPool $ServerPool -StageServerPool $StageServerPool

     $records = $DataGroup.records
     if ($records -eq $null) {
         $records = $newRecords
     }
     else {
        $keys = @("blue_green_pool", "blue_green_pool_stage")

        foreach ($key in $keys) {
            # Try updating 'blue_green_pool' 
            $poolRecord = $records | Where-Object -Property name -eq $key
            $newRecord = $newRecords | Where-Object -Property name -eq $key
            if ($poolRecord -eq $null) {
                $records = $records += $newRecord
            }
            else {
                $poolRecord.data = $newRecord.data
            }
        }
     }

    $request = @{
       records = $records
    }

    $body = $request | ConvertTo-Json
    Invoke-RestMethod -Uri $uri -Credential $Credential -Method Patch -Body $body -ContentType 'application/json'
}

##
# Create the structure for a data group's blue_green_pool and stage records
##
function Generate-DataGroupPoolRecord($ServerPool, $StageServerPool) {
    return @(@{
                name = "blue_green_pool"
                data = $ServerPool
            }, 
            @{
                name = "blue_green_pool_stage"
                data = $StageServerPool
            }
        )
}

##
# Configure a data group with the blue_green_pool setting that is specified
##
function Config-DataGroupPool($LtmIp, $VirtualServer, $ServerPool, $StageServerPool, $Credential)
{
    $dataGroupName = $dataGroupName = Format-DataGroupName -VirtualServer $VirtualServer
    $dg = Get-DataGroup -LtmIp $LtmIp -DataGroupName $dataGroupName -Credential $Credential

    if ($dg -eq $null) {
        Write-Host "$dataGroupName was not found.  Creating..."
        Create-DataGroupPool -LtmIp $LtmIp -DataGroupName $dataGroupName -ServerPool $ServerPool -StageServerPool $StageServerPool -Credential $Credential
    }
    else {
        write-host "$dataGroupName found.  Updating..."
        Update-DataGroupPool -LtmIp $LtmIp -DataGroupName $dataGroupName -ServerPool $ServerPool -StageServerPool $StageServerPool -DataGroup $dg -Credential $Credential
    }
}

# Handle untrusted certs since we use self-signed certificates.
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

Print-DebugVariables $stepF5LtmBigIP $stepF5LtmUserName $stepF5LtmVirtualServer $stepF5LtmNewServerPool $stepF5LtmNewStageServerPool

#create F5 Credentials
$secpasswd = ConvertTo-SecureString $stepF5LtmUserPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($stepF5LtmUserName, $secpasswd)

#select the active device
$activeLtmBigIp = Get-ActiveLtmDevice -LtmIp $stepF5LtmBigIP -Credential $cred

# Check the current server pool
$currentPool = Get-CurrentPool -LtmIp $activeLtmBigIp -VirtualServer $stepF5LtmVirtualServer -Credential $cred
Write-Host "The current pool is $currentPool"

If($currentPool -Match $stepF5LtmNewServerPool) {
    Write-Host "Specified server pool is already active.  Skipping..."
}
Else {
    Set-ServerPool -LtmIp $activeLtmBigIp -VirtualServer $stepF5LtmVirtualServer -Pool $stepF5LtmNewServerPool -Credential $cred
    Config-DataGroupPool -LtmIp $activeLtmBigIp -VirtualServer $stepF5LtmVirtualServer -ServerPool $stepF5LtmNewServerPool -StageServerPool $stepF5LtmNewStageServerPool -Credential $cred
}