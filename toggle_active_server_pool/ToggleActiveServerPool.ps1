##
# Print the settings for debugging purposes
##
function Print-DebugVariables($LtmIp, $UserName, $VirtualServer, $BlueServerPool, $GreenServerPool) {
    Write-Host "Using LTM IP: $LtmIP"
    Write-Host "Using Username: $UserName"
    Write-Host "Using Virtual Server: $VirtualServer"
    Write-Host "Using Blue Server Pool: $BlueServerPool"
    Write-Host "Using Green Server Pool: $GreenServerPool"
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
# Get the current virtual server pool name
##
function Get-CurrentPool($LtmIp, $VirtualServer, $Credential) {
    $uri = "https://$LtmIp/mgmt/tm/ltm/virtual/$VirtualServer"
    Write-Host "Requesting current server pool from $uri"
    $response = Invoke-RestMethod -Uri $uri -Credential $Credential -Method Get 

    return $response.pool
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

Print-DebugVariables $F5BigIP $F5LtmUserName $F5LtmVirtualServer $F5LtmBlueServerPool $F5LtmGreenServerPool

#create F5 Credentials
$secpasswd = ConvertTo-SecureString $F5LtmUserPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($F5LtmUserName, $secpasswd)

#select the active device
$activeLtmBigIp = Get-ActiveLtmDevice -LtmIp $F5LtmBigIP -Credential $cred

# Check the current server pool
$currentPool = Get-CurrentPool -LtmIp $activeLtmBigIp -VirtualServer $F5LtmVirtualServer -Credential $cred
Write-Host "The current pool is $currentPool"

If($currentPool -Match $F5LtmBlueServerPool) {
    Write-Host "Blue server pool is active.  Switching to Green"
    Set-ServerPool -LtmIp $activeLtmBigIp -VirtualServer $F5LtmVirtualServer -Pool $F5LtmGreenServerPool -Credential $cred
}
ElseIf($currentPool -Match $F5LtmGreenServerPool) {
    Write-Host "Green server pool is active.  Switching to Blue"
    Set-ServerPool -LtmIp $activeLtmBigIp -VirtualServer $F5LtmVirtualServer -Pool $F5LtmBlueServerPool -Credential $cred
}
Else {
    Write-Error "Current pool does not match the configured blue or green pool name.  No changes will be made"
}

