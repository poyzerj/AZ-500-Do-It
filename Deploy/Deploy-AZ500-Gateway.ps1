<#
.SYNOPSIS
    AZ-500 Do-It — Deploy the VPN Gateway layer (VpnGw1 + S2S to home FortiGate).

.DESCRIPTION
    Assumes the network layer already exists (rg-az500-doit-cus):
      - Hub-VNet with GatewaySubnet already carved out
      - Spoke1-VNet, Spoke2-VNet, peerings, NSGs

    This script ONLY touches: Gateway Public IP, VPN Gateway (VpnGw1),
    Local Network Gateway, and the S2S IPsec connection.

    P2S (AAD auth) is NOT included here — that depends on tomorrow's
    M365 dev tenant + enterprise app work. There's a commented stub
    at the bottom showing where it slots in once the tenant exists.

.NOTES
    Fill in the FortiGatePublicIP, FortiGateLanCidr, and SharedKey
    parameters below BEFORE running. Everything else assumes your
    existing naming convention.

    Gateway provisioning takes 30-45 minutes. This script will block
    until it's done (or fails) — that's intentional so you get a clean
    pass/fail instead of a silent false-success.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName   = "rg-az500-doit-cus",
    [string]$Location            = "centralus",

    [string]$HubVNetName         = "JPVNetHub",
    [string]$GatewaySubnetName   = "GatewaySubnet",

    [string]$GatewayPipName      = "JPVPNGW-PIP",
    [string]$GatewayName         = "JPVPNGW",

    [string]$LngName             = "JPLNGW",

    # ---- FILL THESE IN AFTER YOU LOOK THEM UP ----

    [string]$FortiGatePublicIP = "75.72.109.239",      # e.g. "203.0.113.45"

    [string[]]$FortiGateLanCidr = @("192.168.20.0/24", "192.168.40.0/24"),     # home LAN behind the FortiGate, e.g. "192.168.20.0/24"

    [string]$SharedKey = "K1pe3kjt!0729"          # IPsec PSK — match this EXACTLY on the FortiGate side
    # ------------------------------------------------
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

try {
    Write-Step "Verifying resource group and Hub-VNet exist"
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
    $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HubVNetName -ErrorAction Stop
    $gwSubnet = $hubVnet.Subnets | Where-Object { $_.Name -eq $GatewaySubnetName }
    if (-not $gwSubnet) {
        throw "GatewaySubnet not found on $HubVNetName. Create it before running this script."
    }
    Write-Host "Found RG: $($rg.ResourceGroupName), Hub-VNet: $($hubVnet.Name), GatewaySubnet: $($gwSubnet.AddressPrefix)"

    # ---- Public IP for the gateway ----
    Write-Step "Creating Public IP for VPN Gateway ($GatewayPipName)"
    $gwPip = New-AzPublicIpAddress `
        -ResourceGroupName $ResourceGroupName `
        -Name $GatewayPipName `
        -Location $Location `
        -AllocationMethod Static `
        -Sku Standard `
        -Zone 1,2,3 `
        -ErrorAction Stop
    Write-Host "Public IP created: $($gwPip.IpAddress)"

    # ---- Gateway IP config ----
    $gwIpConfig = New-AzVirtualNetworkGatewayIpConfig `
        -Name "gwipconfig1" `
        -SubnetId $gwSubnet.Id `
        -PublicIpAddressId $gwPip.Id

    # ---- VPN Gateway (VpnGw1, route-based) ----
    Write-Step "Deploying VpnGw1 Virtual Network Gateway ($GatewayName) — this will take 30-45 minutes"
    $vpnGateway = New-AzVirtualNetworkGateway `
        -ResourceGroupName $ResourceGroupName `
        -Name $GatewayName `
        -Location $Location `
        -IpConfigurations $gwIpConfig `
        -GatewayType Vpn `
        -VpnType RouteBased `
        -GatewaySku VpnGw1AZ `
        -VpnGatewayGeneration Generation1 `
        -ErrorAction Stop
    Write-Host "VPN Gateway deployed: $($vpnGateway.Name) — provisioning state: $($vpnGateway.ProvisioningState)"

    if ($vpnGateway.ProvisioningState -ne "Succeeded") {
        throw "Gateway provisioning did not report 'Succeeded' — check the portal before continuing."
    }

    # ---- Local Network Gateway (represents the home FortiGate) ----
    Write-Step "Creating Local Network Gateway ($LngName) for home FortiGate"
    $lng = New-AzLocalNetworkGateway `
        -ResourceGroupName $ResourceGroupName `
        -Name $LngName `
        -Location $Location `
        -GatewayIpAddress $FortiGatePublicIP `
        -AddressPrefix $FortiGateLanCidr `
        -ErrorAction Stop
    Write-Host "Local Network Gateway created: $($lng.Name) -> $($lng.GatewayIpAddress) covering $($lng.LocalNetworkAddressSpace.AddressPrefixes)"

    # ---- IPsec policy: AES256 / SHA256 / DHGroup14 / PFS2048 ----
    Write-Step "Building custom IPsec policy (AES256/SHA256/DHGroup14/PFS2048)"
    $ipsecPolicy = New-AzIpsecPolicy `
        -SALifeTimeSeconds 27000 `
        -SADataSizeKilobytes 102400000 `
        -IpsecEncryption AES256 `
        -IpsecIntegrity SHA256 `
        -IkeEncryption AES256 `
        -IkeIntegrity SHA256 `
        -DhGroup DHGroup14 `
        -PfsGroup PFS2048

    # ---- S2S Connection ----
    Write-Step "Creating S2S VPN connection (vpngw-hub -> lng-home-fortigate)"
    $connection = New-AzVirtualNetworkGatewayConnection `
        -ResourceGroupName $ResourceGroupName `
        -Name "JPAZ-to-JPHome" `
        -Location $Location `
        -VirtualNetworkGateway1 $vpnGateway `
        -LocalNetworkGateway2 $lng `
        -ConnectionType IPsec `
        -IpsecPolicies $ipsecPolicy `
        -SharedKey $SharedKey `
        -ErrorAction Stop

    Write-Host "`nS2S connection created: $($connection.Name) — provisioning state: $($connection.ProvisioningState)"
    Write-Host "Connection status will show 'Unknown' or 'Connecting' until the FortiGate side is configured to match." -ForegroundColor Yellow

    Write-Step "DONE — Gateway + LNG + S2S connection deployed successfully"
    Write-Host "Next: configure the matching IPsec tunnel on the FortiGate (peer IP = $($gwPip.IpAddress), PSK = the one you just used, same IKE/IPsec params)." -ForegroundColor Green
}
catch {
    Write-Host "`n*** DEPLOYMENT FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}

<#
========================================================================
P2S (AAD AUTH) STUB — uncomment and fill in once the M365 dev tenant
and enterprise app are set up (tomorrow's project).
========================================================================
#>

$tenantId   = "2f523dde-a56d-49cf-a37c-15b2e19accab"
$audience   = "41b23e61-6c1e-4545-b367-cd054e0ed4b4"   # Azure VPN enterprise app
$issuer     = "https://sts.windows.net/$tenantId/"
$aadTenant  = "https://login.microsoftonline.com/$tenantId"

Set-AzVirtualNetworkGateway `
    -VirtualNetworkGateway $vpnGateway `
    -VpnClientAddressPool "172.16.20.0/24" `
    -VpnClientProtocol "OpenVPN" `
    -VpnAuthenticationType "AAD" `
    -AadTenant $aadTenant `
    -AadAudience $audience `
    -AadIssuer $issuer
