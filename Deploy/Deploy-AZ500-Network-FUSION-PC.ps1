<#
.SYNOPSIS
    Deploys Hub-VNet, Spoke1-VNet, Spoke2-VNet and their subnets only.
    No peering, NSGs, VMs, or storage — just the network skeleton.
#>

$Location = "centralus"
$Rg       = "rg-az500-doit-cus"

# Create RG if it doesn't already exist
New-AzResourceGroup -Name $Rg -Location $Location -Force

# ---- Hub-VNet ----
$gatewaySubnetCfg = New-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -AddressPrefix "10.0.0.0/27"
$hubSubnetCfg     = New-AzVirtualNetworkSubnetConfig -Name "HubSubnet" -AddressPrefix "10.0.1.0/24"

New-AzVirtualNetwork -ResourceGroupName $Rg -Location $Location -Name "JPVNetHub" `
    -AddressPrefix "10.0.0.0/22" `
    -Subnet $gatewaySubnetCfg, $hubSubnetCfg

Write-Host "Hub-VNet created (GatewaySubnet, HubSubnet)" -ForegroundColor Green

# ---- Spoke1-VNet ----
$spoke1SubnetCfg = New-AzVirtualNetworkSubnetConfig -Name "Spoke1Subnet" -AddressPrefix "10.1.0.0/24"

New-AzVirtualNetwork -ResourceGroupName $Rg -Location $Location -Name "JPVNetSpoke1" `
    -AddressPrefix "10.1.0.0/23" -Subnet $spoke1SubnetCfg

Write-Host "Spoke1-VNet created (Spoke1Subnet)" -ForegroundColor Green

# ---- Spoke2-VNet ----
$spoke2SubnetCfg = New-AzVirtualNetworkSubnetConfig -Name "Spoke2Subnet" -AddressPrefix "10.2.0.0/24"

New-AzVirtualNetwork -ResourceGroupName $Rg -Location $Location -Name "JPVNetSpoke2" `
    -AddressPrefix "10.2.0.0/23" -Subnet $spoke2SubnetCfg

Write-Host "Spoke2-VNet created (Spoke2Subnet)" -ForegroundColor Green

Write-Host "`n===== NETWORK DEPLOY COMPLETE =====" -ForegroundColor Cyan
Write-Host "JPHub-VNet:    10.0.0.0/22"
Write-Host "Spoke1-VNet: 10.1.0.0/23"
Write-Host "Spoke2-VNet: 10.2.0.0/23"
Write-Host "`nNote: No peerings or NSGs created — this script is VNets/subnets only."
