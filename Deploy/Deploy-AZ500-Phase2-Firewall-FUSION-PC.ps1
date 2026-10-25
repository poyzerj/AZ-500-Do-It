<#
.SYNOPSIS
    AZ-500 Do-It — Phase 2 (Centralized Firewall & Egress Control): deploy
    Azure Firewall in the hub, configure a firewall policy, and update the
    spoke route tables so spoke-to-internet and spoke-to-spoke traffic
    routes through it.

.DESCRIPTION
    1. Adds the AzureFirewallSubnet to JPVNetHub (10.0.2.0/26).
    2. Creates a Standard SKU public IP for the firewall.
    3. Creates a Firewall Policy (Threat Intelligence: Alert mode) with one
       rule collection group containing a network rule collection (baseline
       HTTPS egress) and an application rule collection (Windows Update FQDN
       tag).
    4. Deploys Azure Firewall (Standard) into the hub, attached to the
       policy and public IP.
    5. Creates rt-spoke1 / rt-spoke2 route tables with routes for 0.0.0.0/0
       AND the other spoke's exact /23 prefix, both pointing at the firewall's
       private IP — the /23 routes are what actually override the system
       peering routes; without them, spoke-to-spoke traffic would keep
       using direct peering and bypass the firewall entirely despite the
       default route being in place.
    6. Associates each route table to its spoke subnet.

    On-premises-bound traffic is deliberately left on the existing Gateway
    Transit path — this script does not touch that routing, per the design
    document's scope.

.NOTES
    Azure Firewall bills hourly (~$1.25/hr Standard SKU) plus data
    processing — this is not a free resource like Phase 1's ASGs/NSGs.
    Use Remove-AZ500-Phase2-Firewall.ps1 to tear it down when you're done.

    Run from a session already authenticated via Connect-AzAccount.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",
    [string]$Location          = "centralus",

    [string]$HubVNetName        = "JPVNetHub",
    [string]$FirewallSubnetCidr = "10.0.2.0/26",

    [string]$Spoke1VNetName    = "JPVNetSpoke1",
    [string]$Spoke2VNetName    = "JPVNetSpoke2",
    [string]$Spoke1SubnetName  = "Spoke1Subnet",
    [string]$Spoke2SubnetName  = "Spoke2Subnet",
    [string]$Spoke1Prefix      = "10.1.0.0/23",
    [string]$Spoke2Prefix      = "10.2.0.0/23",

    [string]$FirewallName       = "JPAZFW01",
    [string]$FirewallPolicyName = "JPAZFW01-Policy",
    [string]$FirewallPipName    = "JPAZFW01-PIP",

    [string]$RouteTable1Name = "RT-Spoke1",
    [string]$RouteTable2Name = "RT-Spoke2"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    # ---- Step 1: AzureFirewallSubnet ----
    Write-Step "Adding AzureFirewallSubnet ($FirewallSubnetCidr) to $HubVNetName"
    $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HubVNetName -ErrorAction Stop

    $existingFwSubnet = $hubVnet.Subnets | Where-Object { $_.Name -eq "AzureFirewallSubnet" }
    if ($existingFwSubnet) {
        Write-Host "AzureFirewallSubnet already exists — reusing." -ForegroundColor Yellow
    } else {
        Add-AzVirtualNetworkSubnetConfig -Name "AzureFirewallSubnet" -VirtualNetwork $hubVnet -AddressPrefix $FirewallSubnetCidr | Out-Null
        $hubVnet = Set-AzVirtualNetwork -VirtualNetwork $hubVnet -ErrorAction Stop
        Write-Host "AzureFirewallSubnet created." -ForegroundColor Green
    }

    # ---- Step 2: Public IP ----
    Write-Step "Creating firewall public IP ($FirewallPipName)"
    $pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $FirewallPipName -ErrorAction SilentlyContinue
    if (-not $pip) {
        $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $FirewallPipName `
            -Location $Location -AllocationMethod Static -Sku Standard -ErrorAction Stop
        Write-Host "$FirewallPipName created." -ForegroundColor Green
    } else {
        Write-Host "$FirewallPipName already exists — reusing." -ForegroundColor Yellow
    }

    # ---- Step 3: Firewall Policy + rules ----
    Write-Step "Creating firewall policy ($FirewallPolicyName)"
    $policy = Get-AzFirewallPolicy -ResourceGroupName $ResourceGroupName -Name $FirewallPolicyName -ErrorAction SilentlyContinue
    if (-not $policy) {
        $policy = New-AzFirewallPolicy -ResourceGroupName $ResourceGroupName -Name $FirewallPolicyName `
            -Location $Location -ThreatIntelMode "Alert" -ErrorAction Stop
        Write-Host "$FirewallPolicyName created (Threat Intelligence: Alert)." -ForegroundColor Green
    } else {
        Write-Host "$FirewallPolicyName already exists — reusing." -ForegroundColor Yellow
    }

    Write-Step "Configuring rule collection group (rcg-spoke-egress)"
    $spokePrefixes = @($Spoke1Prefix, $Spoke2Prefix)

    $networkRule = New-AzFirewallPolicyNetworkRule -Name "allow-https-egress" `
        -Protocol TCP -SourceAddress $spokePrefixes -DestinationAddress "*" -DestinationPort 443

    $networkRuleCollection = New-AzFirewallPolicyFilterRuleCollection -Name "net-allow-required" `
        -Priority 100 -ActionType Allow -Rule $networkRule

    $appRule = New-AzFirewallPolicyApplicationRule -Name "allow-windows-update" `
        -SourceAddress $spokePrefixes -FqdnTag "WindowsUpdate"

    $appRuleCollection = New-AzFirewallPolicyFilterRuleCollection -Name "app-allow-updates" `
        -Priority 200 -ActionType Allow -Rule $appRule

    New-AzFirewallPolicyRuleCollectionGroup -Name "rcg-spoke-egress" -Priority 200 `
        -FirewallPolicyObject $policy -RuleCollection $networkRuleCollection, $appRuleCollection `
        -ErrorAction Stop | Out-Null

    Write-Host "rcg-spoke-egress configured: net-allow-required (443 egress), app-allow-updates (WindowsUpdate FQDN tag)." -ForegroundColor Green

    # ---- Step 4: Deploy Azure Firewall ----
    Write-Step "Deploying Azure Firewall ($FirewallName) — this can take 5-10 minutes"
    $existingFw = Get-AzFirewall -ResourceGroupName $ResourceGroupName -Name $FirewallName -ErrorAction SilentlyContinue
    if ($existingFw) {
        Write-Host "$FirewallName already exists — reusing." -ForegroundColor Yellow
        $firewall = $existingFw
    } else {
        $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HubVNetName -ErrorAction Stop
        $pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $FirewallPipName -ErrorAction Stop
        $policy = Get-AzFirewallPolicy -ResourceGroupName $ResourceGroupName -Name $FirewallPolicyName -ErrorAction Stop

        $firewall = New-AzFirewall -Name $FirewallName -ResourceGroupName $ResourceGroupName -Location $Location `
            -VirtualNetwork $hubVnet -PublicIpAddress $pip -FirewallPolicyId $policy.Id -SkuTier "Standard" `
            -ErrorAction Stop
        Write-Host "$FirewallName deployed." -ForegroundColor Green
    }

    $firewallPrivateIp = $firewall.IpConfigurations[0].PrivateIPAddress
    Write-Host "Firewall private IP: $firewallPrivateIp" -ForegroundColor Green

    # ---- Step 5: Route tables ----
    Write-Step "Creating route tables"
    function New-OrGetRouteTable {
        param([string]$Name, [string]$ResourceGroupName, [string]$Location)
        $rt = Get-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $Name -ErrorAction SilentlyContinue
        if ($rt) {
            Write-Host "$Name already exists — reusing." -ForegroundColor Yellow
            return $rt
        }
        $rt = New-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $Name -Location $Location -ErrorAction Stop
        Write-Host "$Name created." -ForegroundColor Green
        return $rt
    }

    $rt1 = New-OrGetRouteTable -Name $RouteTable1Name -ResourceGroupName $ResourceGroupName -Location $Location
    $rt2 = New-OrGetRouteTable -Name $RouteTable2Name -ResourceGroupName $ResourceGroupName -Location $Location

    Write-Step "Adding routes to $RouteTable1Name (0.0.0.0/0 and $Spoke2Prefix -> firewall)"
    Add-AzRouteConfig -Name "to-Internet" -RouteTable $rt1 -AddressPrefix "0.0.0.0/0" `
        -NextHopType "VirtualAppliance" -NextHopIpAddress $firewallPrivateIp | Out-Null
    Add-AzRouteConfig -Name "to-Spoke2" -RouteTable $rt1 -AddressPrefix $Spoke2Prefix `
        -NextHopType "VirtualAppliance" -NextHopIpAddress $firewallPrivateIp | Out-Null
    Set-AzRouteTable -RouteTable $rt1 -ErrorAction Stop | Out-Null

    Write-Step "Adding routes to $RouteTable2Name (0.0.0.0/0 and $Spoke1Prefix -> firewall)"
    Add-AzRouteConfig -Name "to-Internet" -RouteTable $rt2 -AddressPrefix "0.0.0.0/0" `
        -NextHopType "VirtualAppliance" -NextHopIpAddress $firewallPrivateIp | Out-Null
    Add-AzRouteConfig -Name "to-Spoke1" -RouteTable $rt2 -AddressPrefix $Spoke1Prefix `
        -NextHopType "VirtualAppliance" -NextHopIpAddress $firewallPrivateIp | Out-Null
    Set-AzRouteTable -RouteTable $rt2 -ErrorAction Stop | Out-Null

    # ---- Step 6: Associate route tables to spoke subnets ----
    Write-Step "Associating route tables to spoke subnets"
    $rt1 = Get-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $RouteTable1Name -ErrorAction Stop
    $spoke1Vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $Spoke1VNetName -ErrorAction Stop
    $spoke1Subnet = $spoke1Vnet.Subnets | Where-Object { $_.Name -eq $Spoke1SubnetName }
    Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $spoke1Vnet -Name $Spoke1SubnetName `
        -AddressPrefix $spoke1Subnet.AddressPrefix -NetworkSecurityGroup $spoke1Subnet.NetworkSecurityGroup `
        -RouteTable $rt1 -ErrorAction Stop | Out-Null
    Set-AzVirtualNetwork -VirtualNetwork $spoke1Vnet -ErrorAction Stop | Out-Null
    Write-Host "$RouteTable1Name -> $Spoke1VNetName/$Spoke1SubnetName" -ForegroundColor Green

    $rt2 = Get-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $RouteTable2Name -ErrorAction Stop
    $spoke2Vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $Spoke2VNetName -ErrorAction Stop
    $spoke2Subnet = $spoke2Vnet.Subnets | Where-Object { $_.Name -eq $Spoke2SubnetName }
    Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $spoke2Vnet -Name $Spoke2SubnetName `
        -AddressPrefix $spoke2Subnet.AddressPrefix -NetworkSecurityGroup $spoke2Subnet.NetworkSecurityGroup `
        -RouteTable $rt2 -ErrorAction Stop | Out-Null
    Set-AzVirtualNetwork -VirtualNetwork $spoke2Vnet -ErrorAction Stop | Out-Null
    Write-Host "$RouteTable2Name -> $Spoke2VNetName/$Spoke2SubnetName" -ForegroundColor Green

    Write-Step "DONE"
    Write-Host "Firewall private IP: $firewallPrivateIp — verify this matches what Network Watcher's Next Hop tool reports before moving to Phase 4 validation." -ForegroundColor Green
    Write-Host "On-premises-bound routing is unchanged (still via Gateway Transit), per design scope." -ForegroundColor Green
}
catch {
    Write-Host "`n*** DEPLOYMENT FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
