<#
.SYNOPSIS
    AZ-500 Do-It — Fix RDP failures over Point-to-Site VPN caused by an MTU/PMTU black hole.

.DESCRIPTION
    P2S connects, ping works, but RDP times out to every VM. Confirmed via
    `ping -f -l 1400 <VM private IP>` returning "Packet needs to be fragmented
    but DF set" — a classic Path MTU black hole. OpenVPN (what Azure P2S uses)
    adds its own encapsulation overhead, so the effective MTU across the P2S
    tunnel is lower than the client's normal 1500. Small ICMP echo packets fit
    fine either way, so ping succeeds. RDP's initial TLS/NLA negotiation sends
    much larger packets, which get fragmented — and something in the path is
    dropping those fragments/oversized packets silently instead of returning a
    proper "fragmentation needed" ICMP message back to the client, so the
    client never learns to shrink its packets on its own. Lowering the P2S
    adapter's own MTU forces Windows to never send a packet that large over
    that interface in the first place, side-stepping the black hole entirely.

    This only affects the P2S tunnel. S2S uses a different protocol (IPsec)
    with different encapsulation characteristics and isn't affected — which is
    why RDP already works fine over S2S to the same VMs.

    This script must be run AFTER connecting the P2S VPN (the adapter has to
    exist), from an elevated PowerShell/cmd prompt. It auto-detects the P2S
    adapter by name match (default: "VPN"); override with -InterfaceNameMatch
    if auto-detect picks the wrong row or finds nothing.

.NOTES
    Run elevated ("Run as Administrator"), while connected to the P2S VPN.

    `store=persistent` ties the setting to the adapter's current interface
    index. Azure's P2S client adapter can sometimes get recreated with a new
    index on a fresh connect — if MTU reverts to 1500 after reconnecting,
    just re-run this script; it's idempotent and takes a few seconds.

    Retest afterward:
      ping -f -l 1400 <VM private IP>   -> should now succeed
      mstsc /v:<VM private IP>          -> should now connect
#>

[CmdletBinding()]
param(
    [int]$Mtu = 1400,
    [string]$InterfaceNameMatch = "VPN"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

Write-Step "Current IPv4 interfaces"
$ifaceOutput = netsh interface ipv4 show interfaces
$ifaceOutput | ForEach-Object { Write-Host $_ }

$lines = $ifaceOutput | Select-String -Pattern '^\s*\d+\s'
$candidates = @()
foreach ($line in $lines) {
    $parts = $line.ToString().Trim() -split '\s+', 5
    if ($parts.Count -ge 5) {
        $candidates += [PSCustomObject]@{
            Idx   = $parts[0]
            MTU   = $parts[2]
            State = $parts[3]
            Name  = $parts[4]
        }
    }
}

$target = $candidates | Where-Object { $_.Name -match $InterfaceNameMatch -or $_.Name -match "Azure" -or $_.Name -match "TAP" } | Select-Object -First 1

if (-not $target) {
    Write-Host "`nCould not auto-detect the P2S VPN interface (looked for a name matching '$InterfaceNameMatch', 'Azure', or 'TAP')." -ForegroundColor Yellow
    Write-Host "Check the table above for your VPN connection's row, then re-run:" -ForegroundColor Yellow
    Write-Host "  .\Set-AZ500-P2S-MTU.ps1 -InterfaceNameMatch '<exact or partial name from the Name column>'" -ForegroundColor Yellow
    return
}

Write-Step "Setting MTU=$Mtu on interface idx $($target.Idx) ('$($target.Name)', current MTU=$($target.MTU))"
netsh interface ipv4 set subinterface "$($target.Idx)" mtu=$Mtu store=persistent | Out-Null

Write-Step "Verifying"
netsh interface ipv4 show interfaces | Where-Object { $_ -match "^\s*$($target.Idx)\s" -or $_ -match "Idx" }

Write-Host "`nDone. Retest while still connected to the P2S VPN:" -ForegroundColor Green
Write-Host "  ping -f -l 1400 <VM private IP>   -> should now succeed" -ForegroundColor Green
Write-Host "  mstsc to the VM                   -> should now connect" -ForegroundColor Green
Write-Host "`nIf you disconnect/reconnect the P2S VPN and RDP breaks again, just re-run this script." -ForegroundColor Yellow
