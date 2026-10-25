<#
.SYNOPSIS
    AZ-500 Do-It — Undo Phase 2: disassociate and delete the route tables,
    delete Azure Firewall, its policy, its public IP, and the
    AzureFirewallSubnet.

.DESCRIPTION
    Deletion order matters — the firewall must go before the policy and
    public IP it depends on, and route tables must be disassociated from
    the spoke subnets before they can be deleted.

    Leaves JPNSGHub/Spoke1/Spoke2, ASGs, VNets, VMs, and the gateway
    untouched.

.NOTES
    Run this when you're done with Phase 2 to stop the hourly Azure
    Firewall charge (~$1.25/hr Standard SKU) plus data processing — unlike
    Phase 1's ASGs/NSGs, this phase actually costs money while it's
    running.

    Run from a session already authenticated via Connect-AzAccount.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",

    [string]$Spoke1VNetName   = "JPVNetSpoke1",
    [string]$Spoke2VNetName   = "JPVNetSpoke2",
    [string]$Spoke1SubnetName = "Spoke1Subnet",
    [string]$Spoke2SubnetName = "Spoke2Subnet",

    [string]$RouteTable1Name = "RT-Spoke1",
    [string]$RouteTable2Name = "RT-Spoke2",

    [string]$HubVNetName        = "JPVNetHub",
    [string]$FirewallName       = "JPAZFW01",
    [string]$FirewallPolicyName = "JPAZFW01-Policy",
    [string]$FirewallPipName    = "JPAZFW01-PIP"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

function Remove-SubnetRouteTableAssociation {
    param([string]$VNetName, [string]$SubnetName, [string]$ResourceGroupName)

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        Write-Host "VNet '$VNetName' not found — skipping." -ForegroundColor Yellow
        return
    }
    $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
    if (-not $subnet -or -not $subnet.RouteTable) {
        Write-Host "$VNetName/$SubnetName has no route table associated — skipping." -ForegroundColor Yellow
        return
    }

    Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName `
        -AddressPrefix $subnet.AddressPrefix -NetworkSecurityGroup $subnet.NetworkSecurityGroup `
        -RouteTable $null -ErrorAction Stop | Out-Null
    Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop | Out-Null
    Write-Host "Route table disassociated from $VNetName/$SubnetName" -ForegroundColor Green
}

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    # ---- Step 1: disassociate + delete route tables ----
    Write-Step "Disassociating route tables from spoke subnets"
    Remove-SubnetRouteTableAssociation -VNetName $Spoke1VNetName -SubnetName $Spoke1SubnetName -ResourceGroupName $ResourceGroupName
    Remove-SubnetRouteTableAssociation -VNetName $Spoke2VNetName -SubnetName $Spoke2SubnetName -ResourceGroupName $ResourceGroupName

    Write-Step "Deleting route tables"
    foreach ($rtName in @($RouteTable1Name, $RouteTable2Name)) {
        $rt = Get-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $rtName -ErrorAction SilentlyContinue
        if ($rt) {
            Remove-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $rtName -Force -ErrorAction Stop
            Write-Host "$rtName removed" -ForegroundColor Green
        } else {
            Write-Host "$rtName not found — skipping" -ForegroundColor Yellow
        }
    }

    # ---- Step 2: delete firewall ----
    Write-Step "Deleting Azure Firewall ($FirewallName) — this can take several minutes"
    $firewall = Get-AzFirewall -ResourceGroupName $ResourceGroupName -Name $FirewallName -ErrorAction SilentlyContinue
    if ($firewall) {
        Remove-AzFirewall -ResourceGroupName $ResourceGroupName -Name $FirewallName -Force -ErrorAction Stop
        Write-Host "$FirewallName removed" -ForegroundColor Green
    } else {
        Write-Host "$FirewallName not found — skipping" -ForegroundColor Yellow
    }

    # ---- Step 3: delete policy ----
    Write-Step "Deleting firewall policy ($FirewallPolicyName)"
    $policy = Get-AzFirewallPolicy -ResourceGroupName $ResourceGroupName -Name $FirewallPolicyName -ErrorAction SilentlyContinue
    if ($policy) {
        Remove-AzFirewallPolicy -ResourceGroupName $ResourceGroupName -Name $FirewallPolicyName -Force -ErrorAction Stop
        Write-Host "$FirewallPolicyName removed" -ForegroundColor Green
    } else {
        Write-Host "$FirewallPolicyName not found — skipping" -ForegroundColor Yellow
    }

    # ---- Step 4: delete public IP ----
    Write-Step "Deleting firewall public IP ($FirewallPipName)"
    $pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $FirewallPipName -ErrorAction SilentlyContinue
    if ($pip) {
        Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $FirewallPipName -Force -ErrorAction Stop
        Write-Host "$FirewallPipName removed" -ForegroundColor Green
    } else {
        Write-Host "$FirewallPipName not found — skipping" -ForegroundColor Yellow
    }

    # ---- Step 5: remove AzureFirewallSubnet ----
    Write-Step "Removing AzureFirewallSubnet from $HubVNetName"
    $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HubVNetName -ErrorAction SilentlyContinue
    if ($hubVnet -and ($hubVnet.Subnets | Where-Object { $_.Name -eq "AzureFirewallSubnet" })) {
        Remove-AzVirtualNetworkSubnetConfig -Name "AzureFirewallSubnet" -VirtualNetwork $hubVnet | Out-Null
        Set-AzVirtualNetwork -VirtualNetwork $hubVnet -ErrorAction Stop | Out-Null
        Write-Host "AzureFirewallSubnet removed" -ForegroundColor Green
    } else {
        Write-Host "AzureFirewallSubnet not found — skipping" -ForegroundColor Yellow
    }

    Write-Step "DONE — Phase 2 fully torn down"
    Write-Host "Untouched: NSGs, ASGs, VNets, VMs, gateway. Verify in the portal that no firewall-related hourly charges remain." -ForegroundColor Green
}
catch {
    Write-Host "`n*** REMOVAL FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
