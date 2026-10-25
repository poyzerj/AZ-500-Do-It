<#
.SYNOPSIS
    AZ-500 Do-It — Deploy Azure Bastion into JPVNetHub for browser-based RDP,
    bypassing P2S/GSA/MTU entirely.

.DESCRIPTION
    Deployed as a same-night workaround after P2S OpenVPN RDP kept failing
    with a Path MTU black hole (confirmed via `ping -f -l 1400`), and Global
    Secure Access on the work laptop turned out to be blocking other
    workarounds too (FortiClient SSL-VPN double-hop, direct Proxmox access).
    Bastion only needs plain HTTPS to portal.azure.com, so it sidesteps all
    of that.

    Uses Basic SKU (~$0.19/hr) rather than the free Developer SKU — Developer
    SKU's automation story is thin/inconsistently documented right now, and
    with a deadline tonight, a few dollars for a cmdlet that's known to work
    beats troubleshooting an unfamiliar deployment path. Convert to Developer
    SKU later via the portal if you want this to be a $0 standing resource.

    Only reaches JPAZVM11 (hub) directly, since Bastion doesn't need peering
    to do that. To reach JPAZVM12/JPAZVM13 (spokes), RDP into JPAZVM11 via
    Bastion first, then mstsc from inside that session to 10.1.0.4 / 10.2.0.4
    — same double-hop trick already validated earlier tonight, same
    Allow-RDP-From-Hub NSG rule making it work.

    Idempotent-ish: skips subnet/PIP/Bastion creation if they already exist.

.NOTES
    Run from a session already authenticated via Connect-AzAccount.
    Takes ~10-15 minutes — New-AzBastion blocks until provisioning finishes.

    Default Bastion subnet prefix (10.0.3.0/26) assumes Hub is 10.0.0.0/22
    with AzureFirewallSubnet at 10.0.2.0/26 and nothing else using the
    10.0.3.0/24 block. The script prints existing subnets before touching
    anything so you can sanity-check that assumption; if it's wrong, rerun
    with -BastionSubnetPrefix pointed at a free /26.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName   = "rg-az500-doit-cus",
    [string]$HubVNetName         = "JPVNetHub",
    [string]$BastionSubnetPrefix = "10.0.3.0/26",
    [string]$BastionPipName      = "JPBastion-PIP",
    [string]$BastionName         = "JPBastion",
    [string]$Sku                 = "Basic"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

try {
    Write-Step "Verifying resource group and hub VNet"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HubVNetName -ErrorAction Stop

    Write-Step "Existing subnets in $HubVNetName (sanity-check before adding Bastion's)"
    $vnet.Subnets | ForEach-Object {
        Write-Host ("  {0,-24} {1}" -f $_.Name, $_.AddressPrefix)
    }

    $existingBastionSubnet = $vnet.Subnets | Where-Object { $_.Name -eq "AzureBastionSubnet" }
    if ($existingBastionSubnet) {
        Write-Host "`nAzureBastionSubnet already exists ($($existingBastionSubnet.AddressPrefix)) — skipping subnet creation." -ForegroundColor Yellow
    } else {
        Write-Step "Adding AzureBastionSubnet ($BastionSubnetPrefix)"
        Add-AzVirtualNetworkSubnetConfig -Name "AzureBastionSubnet" -VirtualNetwork $vnet -AddressPrefix $BastionSubnetPrefix | Out-Null
        $vnet = Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop
        Write-Host "  Subnet added." -ForegroundColor Green
    }

    Write-Step "Public IP ($BastionPipName)"
    $pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $BastionPipName -ErrorAction SilentlyContinue
    if ($pip) {
        Write-Host "  $BastionPipName already exists — reusing it." -ForegroundColor Yellow
    } else {
        $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $BastionPipName `
            -Location $vnet.Location -AllocationMethod Static -Sku Standard -ErrorAction Stop
        Write-Host "  Created $BastionPipName." -ForegroundColor Green
    }

    $existingBastion = Get-AzBastion -ResourceGroupName $ResourceGroupName -Name $BastionName -ErrorAction SilentlyContinue
    if ($existingBastion) {
        Write-Host "`nBastion '$BastionName' already exists — nothing to deploy." -ForegroundColor Yellow
    } else {
        Write-Step "Deploying Bastion ($Sku SKU) — this takes ~10-15 minutes, script will block until done"
        New-AzBastion -ResourceGroupName $ResourceGroupName -Name $BastionName `
            -PublicIpAddressRgName $ResourceGroupName -PublicIpAddressName $BastionPipName `
            -VirtualNetworkRgName $ResourceGroupName -VirtualNetworkName $HubVNetName `
            -Sku $Sku -ErrorAction Stop | Out-Null
        Write-Host "  Bastion deployed." -ForegroundColor Green
    }

    Write-Step "DONE"
    Write-Host "In the Azure Portal: JPAZVM11 -> Connect -> Bastion -> enter the VM's local admin credentials -> Connect." -ForegroundColor Green
    Write-Host "That gets you into the hub VM through a browser tab, no VPN client involved." -ForegroundColor Green
    Write-Host "For JPAZVM12/JPAZVM13 (spokes): once inside JPAZVM11, mstsc to 10.1.0.4 / 10.2.0.4 from there." -ForegroundColor Green
    Write-Host "`nCost note: Basic SKU Bastion + its Standard public IP accrue hourly while they exist." -ForegroundColor Yellow
    Write-Host "Delete both (Remove-AzBastion, Remove-AzPublicIpAddress) once you're past tomorrow's deadline if you don't want them as standing resources." -ForegroundColor Yellow
}
catch {
    Write-Host "`n*** DEPLOYMENT FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
