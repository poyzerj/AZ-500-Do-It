<#
.SYNOPSIS
    AZ-500 Do-It — Remove the gateway layer only: S2S connection,
    VPN Gateway (VpnGw1, which carries the P2S/Entra config), Local
    Network Gateway, and the gateway's Public IP.

.DESCRIPTION
    Order matters — connection must go before the gateway, gateway
    before the LNG/PIP (Azure won't let you delete a PIP still attached
    to a gateway).

    P2S has no separate object to delete — it's a config block on the
    VPN Gateway itself, so removing the gateway removes P2S/Entra auth
    with it.

    Leaves untouched: VNets, subnets, peerings, NSGs, VMs, storage,
    Private Endpoint, Private DNS Zone.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",

    [string]$GatewayName       = "JPVPNGW",
    [string]$GatewayPipName    = "JPVPNGW-PIP",
    [string]$LngName           = "JPLNGW",
    [string]$ConnectionName    = "JPAZ-to-JPHome"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Skip($msg)       { Write-Host $msg -ForegroundColor Yellow }
function Ok($msg)         { Write-Host $msg -ForegroundColor Green }

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    # ---- 1. S2S Connection ----
    Write-Step "Removing S2S connection: $ConnectionName"
    $conn = Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $ResourceGroupName -Name $ConnectionName -ErrorAction SilentlyContinue
    if ($conn) {
        Remove-AzVirtualNetworkGatewayConnection -ResourceGroupName $ResourceGroupName -Name $ConnectionName -Force -ErrorAction Stop
        Ok "Removed connection: $ConnectionName"
    } else { Skip "Connection '$ConnectionName' not found — skipping." }

    # ---- 2. VPN Gateway (also removes P2S/AAD config) ----
    Write-Step "Removing VPN Gateway: $GatewayName (this can take 15-30 minutes)"
    $gw = Get-AzVirtualNetworkGateway -ResourceGroupName $ResourceGroupName -Name $GatewayName -ErrorAction SilentlyContinue
    if ($gw) {
        Remove-AzVirtualNetworkGateway -ResourceGroupName $ResourceGroupName -Name $GatewayName -Force -ErrorAction Stop
        Ok "Removed VPN Gateway: $GatewayName (P2S/Entra config removed with it)"
    } else { Skip "VPN Gateway '$GatewayName' not found — skipping." }

    # ---- 3. Local Network Gateway ----
    Write-Step "Removing Local Network Gateway: $LngName"
    $lng = Get-AzLocalNetworkGateway -ResourceGroupName $ResourceGroupName -Name $LngName -ErrorAction SilentlyContinue
    if ($lng) {
        Remove-AzLocalNetworkGateway -ResourceGroupName $ResourceGroupName -Name $LngName -Force -ErrorAction Stop
        Ok "Removed LNG: $LngName"
    } else { Skip "LNG '$LngName' not found — skipping." }

    # ---- 4. Gateway Public IP ----
    Write-Step "Removing Gateway Public IP: $GatewayPipName"
    $pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $GatewayPipName -ErrorAction SilentlyContinue
    if ($pip) {
        Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $GatewayPipName -Force -ErrorAction Stop
        Ok "Removed Public IP: $GatewayPipName"
    } else { Skip "Public IP '$GatewayPipName' not found — skipping." }

    Write-Step "DONE — gateway layer removed"
    Write-Host "Untouched: VNets, subnets, peerings, NSGs, VMs, storage, Private Endpoint, Private DNS Zone." -ForegroundColor Green
}
catch {
    Write-Host "`n*** REMOVAL FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}