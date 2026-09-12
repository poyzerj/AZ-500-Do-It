<#
.SYNOPSIS
    AZ-500 Do-It — Teardown the storage/private-endpoint layer only.

.DESCRIPTION
    Removes, in dependency-safe order:
      1. Private Endpoint connection(s) on the storage account (if any pending)
      2. Private Endpoint (pe-staccount-blob)
      3. Private DNS Zone VNet links (Hub, Spoke1, Spoke2)
      4. Private DNS Zone records
      5. Private DNS Zone (privatelink.blob.core.windows.net)
      6. Storage Account

    Leaves VNets, subnets, peerings, NSGs, gateway, and VMs untouched.

.NOTES
    Fill in / confirm StorageAccountName below before running — it's not
    cached from prior sessions, so it's a mandatory param.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName     = "rg-az500-doit-cus",

    [string]$StorageAccountName = "jpaz500storage0729",           # the actual storage account name you deployed

    [string]$PrivateEndpointName   = "jpaz500storage-pe",
    [string]$PrivateDnsZoneName    = "privatelink.blob.core.windows.net",

    [string]$HubVNetName           = "Hub-VNet",
    [string]$Spoke1VNetName        = "Spoke1-VNet",
    [string]$Spoke2VNetName        = "Spoke2-VNet"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    # ---- 1. Private Endpoint ----
    Write-Step "Removing Private Endpoint: $PrivateEndpointName"
    $pe = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -Name $PrivateEndpointName -ErrorAction SilentlyContinue
    if ($pe) {
        Remove-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -Name $PrivateEndpointName -Force -ErrorAction Stop
        Write-Host "Removed Private Endpoint: $PrivateEndpointName"
    } else {
        Write-Host "Private Endpoint '$PrivateEndpointName' not found — skipping."
    }

    # ---- 2. Private DNS Zone VNet links ----
    Write-Step "Removing Private DNS Zone VNet links"
    $links = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $ResourceGroupName -ZoneName $PrivateDnsZoneName -ErrorAction SilentlyContinue
    if ($links) {
        foreach ($link in $links) {
            Remove-AzPrivateDnsVirtualNetworkLink `
                -ResourceGroupName $ResourceGroupName `
                -ZoneName $PrivateDnsZoneName `
                -Name $link.Name `
                -ErrorAction Stop
            Write-Host "Removed VNet link: $($link.Name)"
        }
    } else {
        Write-Host "No VNet links found on zone '$PrivateDnsZoneName' — skipping."
    }

    # ---- 3. Private DNS Zone records (Remove-AzPrivateDnsZone handles records implicitly, ----
    # ---- but explicitly clearing A records first avoids orphaned-record edge cases) ----
    Write-Step "Removing A records from Private DNS Zone"
    $records = Get-AzPrivateDnsRecordSet -ResourceGroupName $ResourceGroupName -ZoneName $PrivateDnsZoneName -RecordType A -ErrorAction SilentlyContinue
    if ($records) {
        foreach ($record in $records) {
            Remove-AzPrivateDnsRecordSet -ResourceGroupName $ResourceGroupName -ZoneName $PrivateDnsZoneName -Name $record.Name -RecordType A -ErrorAction Stop
            Write-Host "Removed A record: $($record.Name)"
        }
    } else {
        Write-Host "No A records found — skipping."
    }

    # ---- 4. Private DNS Zone ----
    Write-Step "Removing Private DNS Zone: $PrivateDnsZoneName"
    $zone = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $PrivateDnsZoneName -ErrorAction SilentlyContinue
    if ($zone) {
        Remove-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $PrivateDnsZoneName -ErrorAction Stop
        Write-Host "Removed Private DNS Zone: $PrivateDnsZoneName"
    } else {
        Write-Host "Private DNS Zone '$PrivateDnsZoneName' not found — skipping."
    }

    # ---- 5. Storage Account ----
    Write-Step "Removing Storage Account: $StorageAccountName"
    $sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
    if ($sa) {
        Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
        Write-Host "Removed Storage Account: $StorageAccountName"
    } else {
        Write-Host "Storage Account '$StorageAccountName' not found — skipping."
    }

    Write-Step "DONE — storage layer removed"
    Write-Host "VNets, peerings, NSGs, VMs, and the VPN Gateway (if deployed) were NOT touched." -ForegroundColor Green
}
catch {
    Write-Host "`n*** TEARDOWN FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}