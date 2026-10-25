<#
.SYNOPSIS
    AZ-500 Do-It — Allow RDP and Ping from the Point-to-Site VPN client pool.

.DESCRIPTION
    P2S connects fine (Entra ID auth, tunnel establishes), but RDP and ping to
    every VM fail once connected. Root cause: Phase 1's explicit
    Deny-VirtualNetwork-Inbound rule (priority 4000, source = VirtualNetwork)
    also denies the P2S client address pool. Azure's "VirtualNetwork" service
    tag includes the point-to-site client address pool whenever a VPN gateway
    is present — it isn't just the VNet's own address space. The existing
    Allow-RDP-From-Home and Allow-Ping-From-Home rules only ever listed
    on-premises source CIDRs (192.168.20.0/24, 192.168.40.0/24), so a P2S
    client's traffic never matches an allow rule above the deny — it falls
    straight through to Deny-VirtualNetwork-Inbound and gets dropped. This
    explains why all three VMs fail identically: the same deny rule exists on
    all three NSGs.

    This script adds the P2S client address pool (172.16.20.0/24) as an
    additional source on Allow-RDP-From-Home and Allow-Ping-From-Home on
    JPNSGHub, JPNSGSpoke1, and JPNSGSpoke2 — preserving each rule's existing
    ASG destination, priority, and port range. It does not touch anything
    else (Allow-RDP-From-Hub, the deny rules, DNS, UDRs, or the firewall).

    Idempotent — safe to re-run; skips a rule/source pair that's already
    present.

.NOTES
    Run from a session already authenticated via Connect-AzAccount.

    Verify afterward with Network Watcher -> IP Flow Verify: source IP your
    P2S client's assigned address (something in 172.16.20.0/24), inbound TCP
    3389 (or ICMP) against any VM -> expect Allow. Or just reconnect the P2S
    client and retry RDP/ping directly.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",

    [string]$HubNsgName    = "JPNSGHub",
    [string]$Spoke1NsgName = "JPNSGSpoke1",
    [string]$Spoke2NsgName = "JPNSGSpoke2",

    [string]$P2SClientPool = "172.16.20.0/24"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

function Add-SourceToRule {
    param([object]$Nsg, [string]$RuleName, [string]$NewSourcePrefix)

    $existing = $Nsg.SecurityRules | Where-Object { $_.Name -eq $RuleName }
    if (-not $existing) {
        Write-Host "  $RuleName not found on $($Nsg.Name) — skipping." -ForegroundColor Yellow
        return
    }

    $currentSources = @($existing.SourceAddressPrefix)
    if ($currentSources -contains $NewSourcePrefix) {
        Write-Host "  $RuleName on $($Nsg.Name) already includes $NewSourcePrefix — skipping." -ForegroundColor Yellow
        return
    }

    $newSources = $currentSources + $NewSourcePrefix

    $Nsg | Remove-AzNetworkSecurityRuleConfig -Name $RuleName | Out-Null

    $ruleParams = @{
        Name                 = $RuleName
        Description          = $existing.Description
        Access               = $existing.Access
        Protocol             = $existing.Protocol
        Direction            = $existing.Direction
        Priority             = $existing.Priority
        SourceAddressPrefix  = $newSources
        SourcePortRange      = $existing.SourcePortRange
        DestinationPortRange = $existing.DestinationPortRange
    }

    if ($existing.DestinationApplicationSecurityGroups -and $existing.DestinationApplicationSecurityGroups.Count -gt 0) {
        $ruleParams["DestinationApplicationSecurityGroupId"] = $existing.DestinationApplicationSecurityGroups.Id
    } else {
        $ruleParams["DestinationAddressPrefix"] = $existing.DestinationAddressPrefix
    }

    $Nsg | Add-AzNetworkSecurityRuleConfig @ruleParams | Out-Null

    Write-Host "  $RuleName on $($Nsg.Name) -> added source $NewSourcePrefix" -ForegroundColor Green
}

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    foreach ($nsgName in @($HubNsgName, $Spoke1NsgName, $Spoke2NsgName)) {
        Write-Step "Updating $nsgName"
        $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $nsgName -ErrorAction Stop
        Add-SourceToRule -Nsg $nsg -RuleName "Allow-RDP-From-Home"  -NewSourcePrefix $P2SClientPool
        Add-SourceToRule -Nsg $nsg -RuleName "Allow-Ping-From-Home" -NewSourcePrefix $P2SClientPool
        Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg -ErrorAction Stop | Out-Null
    }

    Write-Step "DONE"
    Write-Host "Reconnect the P2S client and retry RDP/ping against any VM." -ForegroundColor Green
    Write-Host "Verify with Network Watcher -> IP Flow Verify: source = your P2S client IP (172.16.20.x), inbound TCP 3389 or ICMP -> expect Allow." -ForegroundColor Green
}
catch {
    Write-Host "`n*** UPDATE FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
