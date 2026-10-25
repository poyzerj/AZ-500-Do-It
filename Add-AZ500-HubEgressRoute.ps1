<#
.SYNOPSIS
    AZ-500 Do-It — Give JPAZVM11's subnet an explicit internet egress path
    through JPAZFW01, matching what the spokes already have.

.DESCRIPTION
    Effective Routes on JPAZVM11-nic showed "Associated route table: -" and
    0.0.0.0/0 -> Internet (not Virtual Appliance) -- Hub traffic was never
    routed through the firewall at all, so every firewall rule change made
    tonight (adding the Hub /22 as a source, opening it to any/any) never had
    a chance to matter. Most likely cause: implicit default outbound access
    isn't actually provisioning a working egress path for a subnet this
    recently created, even though the system route still shows in the table.

    Fix: a dedicated route table (RT-Hub) with a 0.0.0.0/0 -> Virtual
    Appliance -> <firewall private IP> route, associated ONLY to the Hub's
    VM subnet -- deliberately NOT to GatewaySubnet (Microsoft explicitly
    advises against custom UDRs there, can break the VPN gateway),
    AzureFirewallSubnet (can't route through itself), or AzureBastionSubnet
    (Bastion needs its own direct path, forcing it through the firewall can
    break Bastion itself). The script auto-detects the Hub's VM subnet by
    excluding those three reserved subnet names.

    Hub-to-spoke traffic is left alone -- it already works via direct VNet
    peering (the double-hop RDP already validated this), so this only adds
    the internet-bound route, nothing spoke-specific.

.NOTES
    Run from a session already authenticated via Connect-AzAccount.
    Idempotent-ish: reuses RT-Hub and skips association if already present.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",
    [string]$HubVNetName       = "JPVNetHub",
    [string]$FirewallName      = "JPAZFW01",
    [string]$RouteTableName    = "RT-Hub",
    [string]$HubVmSubnetName   = ""   # leave blank to auto-detect
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

try {
    Write-Step "Looking up firewall private IP"
    $fw = Get-AzFirewall -ResourceGroupName $ResourceGroupName -Name $FirewallName -ErrorAction Stop
    $fwPrivateIp = $fw.IpConfigurations[0].PrivateIPAddress
    Write-Host "  $FirewallName private IP: $fwPrivateIp" -ForegroundColor Green

    Write-Step "Identifying Hub's VM subnet"
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HubVNetName -ErrorAction Stop
    $reserved = @("GatewaySubnet", "AzureFirewallSubnet", "AzureBastionSubnet")

    if ($HubVmSubnetName) {
        $vmSubnet = $vnet.Subnets | Where-Object { $_.Name -eq $HubVmSubnetName }
        if (-not $vmSubnet) { throw "Subnet '$HubVmSubnetName' not found in $HubVNetName." }
    } else {
        $candidates = $vnet.Subnets | Where-Object { $reserved -notcontains $_.Name }
        if ($candidates.Count -eq 0) {
            throw "No non-reserved subnet found in $HubVNetName -- pass -HubVmSubnetName explicitly."
        } elseif ($candidates.Count -gt 1) {
            Write-Host "  Multiple candidate subnets found, re-run with -HubVmSubnetName to pick one:" -ForegroundColor Yellow
            $candidates | ForEach-Object { Write-Host "    $($_.Name)  $($_.AddressPrefix)" }
            throw "Ambiguous -- specify -HubVmSubnetName."
        }
        $vmSubnet = $candidates[0]
    }
    Write-Host "  Using subnet: $($vmSubnet.Name)  ($($vmSubnet.AddressPrefix))" -ForegroundColor Green

    Write-Step "Route table ($RouteTableName)"
    $rt = Get-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $RouteTableName -ErrorAction SilentlyContinue
    if (-not $rt) {
        $rt = New-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $RouteTableName -Location $vnet.Location -ErrorAction Stop
        Write-Host "  Created $RouteTableName." -ForegroundColor Green
    } else {
        Write-Host "  $RouteTableName already exists -- reusing it." -ForegroundColor Yellow
    }

    $existingRoute = $rt.Routes | Where-Object { $_.Name -eq "to-Internet" }
    if ($existingRoute) {
        Write-Host "  'to-Internet' route already exists (next hop $($existingRoute.NextHopIpAddress)) -- leaving as-is." -ForegroundColor Yellow
    } else {
        Add-AzRouteConfig -RouteTable $rt -Name "to-Internet" -AddressPrefix "0.0.0.0/0" `
            -NextHopType VirtualAppliance -NextHopIpAddress $fwPrivateIp | Out-Null
        $rt = Set-AzRouteTable -RouteTable $rt -ErrorAction Stop
        Write-Host "  Added 0.0.0.0/0 -> Virtual Appliance -> $fwPrivateIp." -ForegroundColor Green
    }

    Write-Step "Associating $RouteTableName to $($vmSubnet.Name)"
    Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $vmSubnet.Name `
        -AddressPrefix $vmSubnet.AddressPrefix -RouteTable $rt | Out-Null
    Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop | Out-Null
    Write-Host "  Associated." -ForegroundColor Green

    Write-Step "DONE"
    Write-Host "Re-check Effective Routes on JPAZVM11-nic -- 0.0.0.0/0 should now show Virtual Appliance -> $fwPrivateIp." -ForegroundColor Green
    Write-Host "Then retest from inside the VM: Test-NetConnection 8.8.8.8 -Port 443" -ForegroundColor Green
}
catch {
    Write-Host "`n*** FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
