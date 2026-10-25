<#
.SYNOPSIS
    AZ-500 Do-It — Diagnose why JPAZVM12 / JPAZVM13 can't reach the on-prem
    DC (192.168.40.15) for domain join, when JPAZVM11 (hub) can.

.DESCRIPTION
    Checks, in order, the three layers most likely to block spoke-to-on-prem
    traffic while leaving hub-to-on-prem traffic untouched:

    1. Gateway transit peering — do the Hub<->Spoke1 and Hub<->Spoke2
       peerings have AllowGatewayTransit (hub side) / UseRemoteGateways
       (spoke side) turned on? Without this, spokes have NO path to
       on-prem at all, regardless of firewall/NSG/UDR state. VM11 doesn't
       need this because it already sits in the hub next to the gateway.

    2. Route tables — are RT-Spoke1 / RT-Spoke2 deployed and associated to
       the spoke subnets yet? If so, is "Propagate gateway routes" on, so
       the gateway-learned 192.168.40.0/24 route stays more specific than
       the 0.0.0.0/0 -> Firewall default route (longest-prefix match)? If
       propagation is off, or an explicit UDR exists for 192.168.40.0/24,
       on-prem traffic gets force-routed through the firewall, which
       (per the Phase 2 design) only has rules for HTTPS egress and
       Windows Update - nothing for DNS/Kerberos/LDAP/SMB.

    3. Effective routes — the actual resolved next hop for 192.168.40.15
       from JPAZVM12-nic and JPAZVM13-nic, which settles #1/#2 definitively
       instead of inferring it from config.

    4. NSG outbound — confirms nothing non-default is blocking outbound
       DNS (53) from the spoke NSGs toward 192.168.40.0/24.

.NOTES
    Run from a session already authenticated via Connect-AzAccount.
    Read-only — makes no changes.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",

    [string]$HubVNetName     = "JPVNetHub",
    [string]$Spoke1VNetName  = "JPVNetSpoke1",
    [string]$Spoke2VNetName  = "JPVNetSpoke2",

    [string]$Spoke1NicName   = "JPAZVM12-nic",
    [string]$Spoke2NicName   = "JPAZVM13-nic",

    [string]$OnPremPrefix    = "192.168.40.0/24",

    [string]$RouteTable1Name = "RT-Spoke1",
    [string]$RouteTable2Name = "RT-Spoke2",

    [string]$FirewallPolicyName = "JPAZFW01-Policy"
)

$ErrorActionPreference = "Stop"
function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

try {
    Write-Step "1. Gateway transit peering (Hub <-> Spoke1 / Spoke2)"
    $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HubVNetName -ErrorAction Stop

    foreach ($spokeName in @($Spoke1VNetName, $Spoke2VNetName)) {
        $hubPeering = $hubVnet.VirtualNetworkPeerings | Where-Object { $_.RemoteVirtualNetwork.Id -like "*/$spokeName" }
        if ($hubPeering) {
            Write-Host "$HubVNetName -> $spokeName : AllowGatewayTransit = $($hubPeering.AllowGatewayTransit)" -ForegroundColor $(if ($hubPeering.AllowGatewayTransit) { "Green" } else { "Red" })
        } else {
            Write-Host "No peering found from $HubVNetName to $spokeName !" -ForegroundColor Red
        }

        $spokeVnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $spokeName -ErrorAction Stop
        $spokePeering = $spokeVnet.VirtualNetworkPeerings | Where-Object { $_.RemoteVirtualNetwork.Id -like "*/$HubVNetName" }
        if ($spokePeering) {
            Write-Host "$spokeName -> $HubVNetName : UseRemoteGateways  = $($spokePeering.UseRemoteGateways)" -ForegroundColor $(if ($spokePeering.UseRemoteGateways) { "Green" } else { "Red" })
        } else {
            Write-Host "No peering found from $spokeName back to $HubVNetName !" -ForegroundColor Red
        }
    }

    Write-Step "2. Route tables (RT-Spoke1 / RT-Spoke2) — existence, routes, gateway propagation, subnet association"
    foreach ($rtName in @($RouteTable1Name, $RouteTable2Name)) {
        $rt = Get-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $rtName -ErrorAction SilentlyContinue
        if (-not $rt) {
            Write-Host "$rtName does not exist yet — Phase 2 UDRs not deployed. Firewall routing is NOT the cause." -ForegroundColor Yellow
            continue
        }
        Write-Host "$rtName found. DisableBgpRoutePropagation = $($rt.DisableBgpRoutePropagation) (should be False so on-prem routes stay direct)" -ForegroundColor $(if ($rt.DisableBgpRoutePropagation) { "Red" } else { "Green" })
        $rt.Routes | Format-Table Name, AddressPrefix, NextHopType, NextHopIpAddress -AutoSize
        $onPremRoute = $rt.Routes | Where-Object { $_.AddressPrefix -eq $OnPremPrefix }
        if ($onPremRoute) {
            Write-Host "EXPLICIT UDR for $OnPremPrefix exists on $rtName -> NextHopType $($onPremRoute.NextHopType) — this would force on-prem traffic through that hop." -ForegroundColor Red
        }
        $assocSubnets = ($rt.Subnets | ForEach-Object { $_.Id -split '/' | Select-Object -Last 1 }) -join ", "
        Write-Host "Associated subnets: $assocSubnets"
    }

    Write-Step "3. Effective routes for JPAZVM12-nic and JPAZVM13-nic (ground truth for the actual next hop to on-prem)"
    foreach ($nicName in @($Spoke1NicName, $Spoke2NicName)) {
        Write-Host "--- $nicName effective routes ---" -ForegroundColor Cyan
        try {
            Get-AzEffectiveRouteTable -ResourceGroupName $ResourceGroupName -NetworkInterfaceName $nicName |
                Where-Object { $_.State -eq "Active" } |
                Format-Table @{N='AddressPrefix';E={$_.AddressPrefix -join ","}}, NextHopType, @{N='NextHopIp';E={$_.NextHopIpAddress -join ","}}, Source -AutoSize
        } catch {
            Write-Host "Could not retrieve effective routes for $nicName (VM may need to be running): $_" -ForegroundColor Yellow
        }
    }

    Write-Step "4. NSG outbound rules for each spoke NIC (confirming nothing blocks outbound DNS/53 toward on-prem)"
    foreach ($nicName in @($Spoke1NicName, $Spoke2NicName)) {
        $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $nicName -ErrorAction SilentlyContinue
        if (-not $nic -or -not $nic.NetworkSecurityGroup) {
            Write-Host "$nicName has no directly-attached NSG (may inherit from subnet only)." -ForegroundColor Yellow
            continue
        }
        $nsgName = $nic.NetworkSecurityGroup.Id -split '/' | Select-Object -Last 1
        $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $nsgName
        Write-Host "--- $nsgName outbound rules ---" -ForegroundColor Cyan
        $nsg.SecurityRules + $nsg.DefaultSecurityRules |
            Where-Object { $_.Direction -eq "Outbound" } |
            Sort-Object Priority |
            Format-Table Name, Priority, Access, Protocol, DestinationAddressPrefix, DestinationPortRange -AutoSize
    }

    Write-Step "5. Is the Azure Firewall policy even deployed yet?"
    $fwPolicy = Get-AzFirewallPolicy -ResourceGroupName $ResourceGroupName -Name $FirewallPolicyName -ErrorAction SilentlyContinue
    if ($fwPolicy) {
        Write-Host "$FirewallPolicyName exists — Phase 2 is deployed. If on-prem traffic is routing through it (see steps 2/3 above), it has no rule for DNS/Kerberos/LDAP/SMB to on-prem, which would explain the domain-join failure exactly like the earlier RDP issue." -ForegroundColor Yellow
    } else {
        Write-Host "$FirewallPolicyName does not exist — Phase 2 not deployed. The firewall cannot be the cause; focus on step 1 (gateway transit peering) and step 3 (effective routes)." -ForegroundColor Yellow
    }

    Write-Step "DONE"
    Write-Host "Paste this entire output back to Claude for diagnosis."
}
catch {
    Write-Host "Diagnostic script hit an error: $_" -ForegroundColor Red
}
