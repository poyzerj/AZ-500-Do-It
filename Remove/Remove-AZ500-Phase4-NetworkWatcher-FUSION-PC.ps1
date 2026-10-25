<#
.SYNOPSIS
    AZ-500 Do-It — Undo Phase 4: disable VNet Flow Logs on all three VNets
    and delete the flow log storage account.

.DESCRIPTION
    Does not touch Network Watcher itself (it's a free, subscription-level
    service enabled by default — disabling it can affect other tooling, so
    this script leaves it alone) or anything from other phases.

    NOTE: originally written against NSG Flow Logs; switched to Virtual
    Network Flow Logs when Microsoft retired new NSG Flow Logs creation
    ahead of the Sept 30, 2027 retirement. If you still have an old
    NSG-targeted flow log around from before the switch, remove it
    manually via Network Watcher → NSG flow logs in the portal (or
    Remove-AzNetworkWatcherFlowLog with the NSG's resource ID) — this
    script only looks for the VNet-named ones.

.NOTES
    Cost here is low (a storage account with a few days of small JSON logs
    is fractions of a cent), but there's no reason to leave it running once
    you're done validating — run this to clean up.

    If you ran Deploy-AZ500-Phase4-NetworkWatcher.ps1 with
    -EnableTrafficAnalytics, also manually remove the Log Analytics
    workspace you pointed it at if you created one specifically for this
    (this script doesn't delete a workspace, since you may be reusing one
    shared with other purposes).

    Run from a session already authenticated via Connect-AzAccount.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",

    [string[]]$VNetNames = @("JPVNetHub", "JPVNetSpoke1", "JPVNetSpoke2"),
    [string]$FlowLogStorageAccountName = "jpaz500flowlogs",
    [string]$Location = "centralus"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    Write-Step "Locating Network Watcher for $Location"
    $nw = Get-AzNetworkWatcher -Location $Location -ErrorAction SilentlyContinue
    if (-not $nw) {
        Write-Host "No Network Watcher found for $Location — nothing to disable, skipping to storage account cleanup." -ForegroundColor Yellow
    } else {
        foreach ($vnetName in $VNetNames) {
            Write-Step "Disabling Flow Logs on $vnetName"
            $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName -ErrorAction SilentlyContinue
            if (-not $vnet) {
                Write-Host "$vnetName not found — skipping." -ForegroundColor Yellow
                continue
            }

            $flowLog = Get-AzNetworkWatcherFlowLog -NetworkWatcher $nw -Name "$vnetName-flowlog" -ErrorAction SilentlyContinue
            if ($flowLog) {
                Remove-AzNetworkWatcherFlowLog -NetworkWatcher $nw -Name "$vnetName-flowlog" -ErrorAction Stop
                Write-Host "$vnetName-flowlog removed" -ForegroundColor Green
            } else {
                Write-Host "$vnetName-flowlog not found — skipping." -ForegroundColor Yellow
            }
        }
    }

    Write-Step "Deleting flow log storage account ($FlowLogStorageAccountName)"
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $FlowLogStorageAccountName -ErrorAction SilentlyContinue
    if ($storageAccount) {
        Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $FlowLogStorageAccountName -Force -ErrorAction Stop
        Write-Host "$FlowLogStorageAccountName removed" -ForegroundColor Green
    } else {
        Write-Host "$FlowLogStorageAccountName not found — skipping." -ForegroundColor Yellow
    }

    Write-Step "DONE — Phase 4 flow logging torn down"
    Write-Host "Network Watcher itself was left enabled (free, subscription-level, shared with other tooling)." -ForegroundColor Green
}
catch {
    Write-Host "`n*** REMOVAL FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
