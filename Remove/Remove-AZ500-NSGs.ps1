<#
.SYNOPSIS
    AZ-500 Do-It — Remove Hub-NSG, Spoke1-NSG, Spoke2-NSG.

.DESCRIPTION
    Disassociates each NSG from its subnet first (Azure won't let you delete
    an NSG that's still attached to a subnet/NIC), then deletes all 3 NSGs.

    Leaves VNets, subnets, peerings, VMs, storage, and gateway untouched.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",

    [string]$HubVNetName       = "JPVNetHub",
    [string]$Spoke1VNetName    = "JPVNetSpoke1",
    [string]$Spoke2VNetName    = "JPVNetSpoke2",

    [string]$HubSubnetName     = "HubSubnet",
    [string]$Spoke1SubnetName  = "Spoke1Subnet",
    [string]$Spoke2SubnetName  = "Spoke2Subnet",

    [string[]]$NsgNames        = @("JPNSGHub", "JPNSGSpoke1", "JPNSGSpoke2")
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

function Remove-SubnetNsgAssociation {
    param(
        [string]$VNetName,
        [string]$SubnetName,
        [string]$ResourceGroupName
    )

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        Write-Host "VNet '$VNetName' not found — skipping NSG disassociation." -ForegroundColor Yellow
        return
    }

    $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
    if (-not $subnet) {
        Write-Host "Subnet '$SubnetName' not found on '$VNetName' — skipping." -ForegroundColor Yellow
        return
    }

    if (-not $subnet.NetworkSecurityGroup) {
        Write-Host "$VNetName/$SubnetName has no NSG attached — skipping disassociation." -ForegroundColor Yellow
        return
    }

    Write-Host "Disassociating NSG from $VNetName/$SubnetName"
    Set-AzVirtualNetworkSubnetConfig `
        -VirtualNetwork $vnet `
        -Name $SubnetName `
        -AddressPrefix $subnet.AddressPrefix `
        -NetworkSecurityGroup $null `
        -ErrorAction Stop | Out-Null

    Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop | Out-Null
    Write-Host "Disassociated NSG from $VNetName/$SubnetName" -ForegroundColor Green
}

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    # ---- Disassociate NSGs from subnets first ----
    Remove-SubnetNsgAssociation -VNetName $HubVNetName    -SubnetName $HubSubnetName    -ResourceGroupName $ResourceGroupName
    Remove-SubnetNsgAssociation -VNetName $Spoke1VNetName -SubnetName $Spoke1SubnetName -ResourceGroupName $ResourceGroupName
    Remove-SubnetNsgAssociation -VNetName $Spoke2VNetName -SubnetName $Spoke2SubnetName -ResourceGroupName $ResourceGroupName

    # ---- Delete the NSGs ----
    foreach ($nsgName in $NsgNames) {
        Write-Step "Removing NSG: $nsgName"
        $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $nsgName -ErrorAction SilentlyContinue
        if ($nsg) {
            Remove-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $nsgName -Force -ErrorAction Stop
            Write-Host "Removed: $nsgName" -ForegroundColor Green
        } else {
            Write-Host "NSG '$nsgName' not found — skipping." -ForegroundColor Yellow
        }
    }

    Write-Step "DONE — all 3 NSGs disassociated and removed"
    Write-Host "Untouched: VNets, Subnets, Peerings, VMs, storage, Private Endpoint, Private DNS Zone, Gateway." -ForegroundColor Green
}
catch {
    Write-Host "`n*** REMOVAL FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}