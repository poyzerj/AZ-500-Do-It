<#
.SYNOPSIS
    Removes Hub-VNet, Spoke1-VNet, Spoke2-VNet (and their subnets).
    Will FAIL if peerings still exist on them — remove peerings first,
    or this script attempts that automatically below.
#>

$Rg = "rg-az500-doit-cus"
$VnetNames = @("JPVNetHub", "JPVNetSpoke1", "JPVNetSpoke2")

foreach ($VnetName in $VnetNames) {

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $VnetName -ErrorAction SilentlyContinue

    if (-not $vnet) {
        Write-Host "$VnetName not found — skipping" -ForegroundColor Yellow
        continue
    }

    # Remove any peerings on this VNet first (VNet removal fails if peerings exist)
    $peerings = Get-AzVirtualNetworkPeering -ResourceGroupName $Rg -VirtualNetworkName $VnetName -ErrorAction SilentlyContinue
    foreach ($peering in $peerings) {
        Write-Host "Removing peering: $($peering.Name) on $VnetName"
        Remove-AzVirtualNetworkPeering -ResourceGroupName $Rg -VirtualNetworkName $VnetName -Name $peering.Name -Force
    }

    Write-Host "Removing VNet: $VnetName" -ForegroundColor Cyan
    Remove-AzVirtualNetwork -ResourceGroupName $Rg -Name $VnetName -Force
}

Write-Host "`n===== NETWORK TEARDOWN COMPLETE =====" -ForegroundColor Green
Write-Host "Removed: Hub-VNet, Spoke1-VNet, Spoke2-VNet (+ subnets + any peerings)."
Write-Host "Note: NSGs are NOT removed by this script — they're independent resources."