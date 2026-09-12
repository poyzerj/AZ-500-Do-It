<#
.SYNOPSIS
    AZ-500 Do-It — Install DNS Server role on hub-vm and configure it as the
    relay for hybrid DNS resolution (on-prem -> Azure Private DNS Zones).

.DESCRIPTION
    Run this ON hub-vm itself (RDP in first, then run locally).

    This is the consolidated version including fixes found during the
    original build's troubleshooting:
      - Correct forwarder order (168.63.129.16 first)
      - EnableReordering disabled, so Windows doesn't silently re-prioritize
        forwarders by measured RTT (which put public resolvers ahead of
        168.63.129.16 every time, defeating the whole point of this setup)

    After this, hub-vm becomes the relay: on-prem DC forwards to hub-vm,
    hub-vm forwards to 168.63.129.16, which resolves Azure private DNS zones
    (including privatelink.blob.core.windows.net for the storage private
    endpoint).
#>

[CmdletBinding()]
param(
    [string]$AzureInternalDns = "168.63.129.16",
    [string[]]$PublicFallbackDns = @("8.8.8.8", "9.9.9.9")
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

try {
    Write-Step "Installing DNS Server role"
    $feature = Get-WindowsFeature -Name DNS
    if ($feature.Installed) {
        Write-Host "DNS role already installed — skipping install." -ForegroundColor Yellow
    } else {
        Install-WindowsFeature -Name DNS -IncludeManagementTools -ErrorAction Stop
        Write-Host "DNS role installed." -ForegroundColor Green
    }

    Write-Step "Configuring forwarders (168.63.129.16 first, then public fallback)"
    $forwarderList = @($AzureInternalDns) + $PublicFallbackDns
    Set-DnsServerForwarder -IPAddress $forwarderList -ErrorAction Stop
    Write-Host "Forwarders set: $($forwarderList -join ', ')" -ForegroundColor Green

    Write-Step "Disabling forwarder reordering (critical fix)"
    # Without this, Windows measures RTT to each forwarder and silently
    # re-prioritizes by speed — a fast public resolver will consistently
    # beat 168.63.129.16's RTT (reached over a VPN tunnel from on-prem
    # callers), causing queries to bypass Azure's internal DNS entirely
    # regardless of configured order.
    Set-DnsServerForwarder -EnableReordering $false -ErrorAction Stop
    Write-Host "EnableReordering set to False." -ForegroundColor Green

    Write-Step "Verifying configuration"
    $result = Get-DnsServerForwarder
    Write-Host "Configured order:  $($result.IPAddress -join ', ')"
    Write-Host "Reordered order:   $($result.ReorderedIPAddress -join ', ')  (should match configured order above)"
    Write-Host "EnableReordering:  $($result.EnableReordering)  (should be False)"

    Write-Step "DONE"
    Write-Host "hub-vm's private IP is what on-prem DNS servers should point their forwarder/conditional forwarder at." -ForegroundColor Green
    Write-Host "Run 'Get-NetIPAddress -AddressFamily IPv4' on this VM to confirm its IP if you don't already have it noted." -ForegroundColor Green
}
catch {
    Write-Host "`n*** SETUP FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}