##
# Print the settings for debugging purposes
##
function Print-DebugVariables($LtmIp, $UserName, $LtmDeviceGroup) {
    Write-Host "Using LTM Big IP address: $LtmIP"
    Write-Host "Using Username: $UserName"  
    Write-Host "Using LTM Device Group: $LtmDeviceGroup"       
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
# Sync config changes from a device to the device group
##
function Sync-LtmGroup($LtmIp, $LtmDeviceGroup, $Credential) {
    $uri = "https://$LtmIp/mgmt/tm/cm"

    Write-Host "syncing device config at $uri"

    $request = @{
        command="run"
        utilCmdArgs="config-sync to-group $LtmDeviceGroup"
    }

    $body = $request | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $uri -Credential $Credential -Method Post -Body $body -ContentType 'application/json'

    write-host $response
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

Print-DebugVariables $F5LtmBigIP $F5LtmUserName $F5LtmDeviceGroup

#create F5 Credentials
$secpasswd = ConvertTo-SecureString $F5LtmUserPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($F5LtmUserName, $secpasswd)

#select the active device
$activeLtmBigIp = Get-ActiveLtmDevice -LtmIp $F5LtmBigIP -Credential $cred

#sync the active device to the device group
Sync-LtmGroup $activeLtmBigIp $F5LtmDeviceGroup $cred