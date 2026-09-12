<#
.SYNOPSIS
    Creates VNet peerings: Hub-to-Spoke1/Spoke1-to-Hub and Hub-to-Spoke2/Spoke2-to-Hub.

.NOTES
    "Use remote gateways" is NOT enabled here since the VPN Gateway doesn't exist yet.
    "Allow gateway transit" is enabled on the hub side now (harmless before the gateway
    exists), but "Use remote gateways" on the spoke side will fail/be ignored until
    the gateway is deployed — come back and re-run the "finish transit" block at the
    bottom of this script once vpn-hub shows Succeeded.
#>

$Rg          = "rg-az500-doit-cus"
$HubVnetName = "JPVNetHub"
$Spoke1Name  = "JPVNetSpoke1"
$Spoke2Name  = "JPVNetSpoke2"

$hubVnet    = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $HubVnetName
$spoke1Vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $Spoke1Name
$spoke2Vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $Spoke2Name

function New-HubSpokePeering {
    param($HubVnet, $SpokeVnet, $HubToSpokeName, $SpokeToHubName)

    Write-Host "Creating $HubToSpokeName ..." -ForegroundColor Cyan
    Add-AzVirtualNetworkPeering -Name $HubToSpokeName -VirtualNetwork $HubVnet `
        -RemoteVirtualNetworkId $SpokeVnet.Id `
        -AllowGatewayTransit `
        -AllowForwardedTraffic

    Write-Host "Creating $SpokeToHubName ..." -ForegroundColor Cyan
    Add-AzVirtualNetworkPeering -Name $SpokeToHubName -VirtualNetwork $SpokeVnet `
        -RemoteVirtualNetworkId $HubVnet.Id `
        -AllowForwardedTraffic
        # -UseRemoteGateways intentionally omitted — gateway doesn't exist yet
}

New-HubSpokePeering -HubVnet $hubVnet -SpokeVnet $spoke1Vnet `
    -HubToSpokeName "Hub-to-Spoke1" -SpokeToHubName "Spoke1-to-Hub"

New-HubSpokePeering -HubVnet $hubVnet -SpokeVnet $spoke2Vnet `
    -HubToSpokeName "Hub-to-Spoke2" -SpokeToHubName "Spoke2-to-Hub"

Write-Host "`n===== PEERING COMPLETE =====" -ForegroundColor Green
Write-Host "Hub-to-Spoke1 / Spoke1-to-Hub: created (Allow gateway transit ON, Use remote gateways OFF for now)"
Write-Host "Hub-to-Spoke2 / Spoke2-to-Hub: created (Allow gateway transit ON, Use remote gateways OFF for now)"
Write-Host "`nOnce vpn-hub gateway shows 'Succeeded', run the block below to finish transit:`n"

# =========================================================================
# RUN THIS SEPARATELY once the VPN Gateway exists and shows "Succeeded"
# =========================================================================
<#
$Rg = "rg-az500-doit-cus"

$spoke1Vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name "JPVNetSpoke1"
$spoke2Vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name "JPVNetSpoke2"

Set-AzVirtualNetworkPeering -VirtualNetwork $spoke1Vnet -Name "JPVNetSpoke1-to-JPVNetHub" -UseRemoteGateways $true
Set-AzVirtualNetworkPeering -VirtualNetwork $spoke2Vnet -Name "JPVNetSpoke2-to-JPVNetHub" -UseRemoteGateways $true

Write-Host "Use remote gateways enabled on JPVNetSpoke1-to-JPVNetHub and JPVNetSpoke2-to-JPVNetHub" -ForegroundColor Green
#>