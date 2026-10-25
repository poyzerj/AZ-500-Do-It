<#
.SYNOPSIS
    AZ-500 Do-It — Undo Phase 1 (Segmentation): removes the deny-by-default
    rules, restores Allow-DNS-From-Home on the spokes, retargets rule
    destinations back to "*", disassociates ASGs from VM NICs, and deletes
    the 3 ASGs.

.DESCRIPTION
    Restores JPNSGHub / JPNSGSpoke1 / JPNSGSpoke2 to exactly the state
    Deploy-AZ500-NSGs.ps1 originally created — this only undoes what
    Deploy-AZ500-Phase1-Segmentation.ps1 changed. It does NOT delete the
    NSGs themselves, VNets, subnets, VMs, or anything else — use the other
    Remove-AZ500-*.ps1 scripts for that.

    Note: NSGs and ASGs are free Azure resources with no ongoing charge on
    their own — this script exists for a clean rollback/re-run story, not
    because leaving Phase 1 in place costs you anything. Azure Firewall
    (Phase 2) and DDoS Protection Standard (Phase 5) are the pieces in this
    project that actually bill by the hour/month — tear those down via
    their own Remove scripts when you're done with them.

.NOTES
    Run from a session already authenticated via Connect-AzAccount.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",

    [string]$HubNsgName    = "JPNSGHub",
    [string]$Spoke1NsgName = "JPNSGSpoke1",
    [string]$Spoke2NsgName = "JPNSGSpoke2",

    [string]$HubVmName    = "JPAZVM11",
    [string]$Spoke1VmName = "JPAZVM12",
    [string]$Spoke2VmName = "JPAZVM13",

    [string]$HubAsgName    = "JPASGHub",
    [string]$Spoke1AsgName = "JPASGSpoke1",
    [string]$Spoke2AsgName = "JPASGSpoke2",

    [string]$HomeLanNsgSource    = "192.168.20.0/24",
    [string]$HomeServerNsgSource = "192.168.40.0/24"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

function Remove-RuleIfExists {
    param([object]$Nsg, [string]$RuleName)

    $existing = $Nsg.SecurityRules | Where-Object { $_.Name -eq $RuleName }
    if ($existing) {
        $Nsg | Remove-AzNetworkSecurityRuleConfig -Name $RuleName | Out-Null
        Write-Host "  $RuleName removed from $($Nsg.Name)" -ForegroundColor Green
    } else {
        Write-Host "  $RuleName already absent from $($Nsg.Name) — nothing to remove." -ForegroundColor Yellow
    }
}

function Set-RuleDestinationAny {
    <#
    Removes a rule by name (if present) and recreates it with the same
    source/protocol/port/priority, but DestinationAddressPrefix "*" instead
    of an ASG — reverses Set-RuleDestinationAsg from the Deploy script.
    #>
    param([object]$Nsg, [string]$RuleName)

    $existing = $Nsg.SecurityRules | Where-Object { $_.Name -eq $RuleName }
    if (-not $existing) {
        Write-Host "  $RuleName not found on $($Nsg.Name) — skipping." -ForegroundColor Yellow
        return
    }

    $Nsg | Remove-AzNetworkSecurityRuleConfig -Name $RuleName | Out-Null

    $Nsg | Add-AzNetworkSecurityRuleConfig `
        -Name $RuleName `
        -Description $existing.Description `
        -Access $existing.Access `
        -Protocol $existing.Protocol `
        -Direction $existing.Direction `
        -Priority $existing.Priority `
        -SourceAddressPrefix $existing.SourceAddressPrefix `
        -SourcePortRange $existing.SourcePortRange `
        -DestinationAddressPrefix "*" `
        -DestinationPortRange $existing.DestinationPortRange `
        | Out-Null

    Write-Host "  $RuleName -> destination reverted to *" -ForegroundColor Green
}

function Add-DnsFromHomeRule {
    param([object]$Nsg, [string[]]$HomeSourceCidrs)

    $existing = $Nsg.SecurityRules | Where-Object { $_.Name -eq "Allow-DNS-From-Home" }
    if ($existing) {
        Write-Host "  Allow-DNS-From-Home already present on $($Nsg.Name) — skipping." -ForegroundColor Yellow
        return
    }

    $Nsg | Add-AzNetworkSecurityRuleConfig `
        -Name "Allow-DNS-From-Home" `
        -Description "Allow DNS inbound from home (TCP+UDP 53) for forwarder/relay" `
        -Access Allow -Protocol "*" -Direction Inbound -Priority 130 `
        -SourceAddressPrefix $HomeSourceCidrs -SourcePortRange "*" `
        -DestinationAddressPrefix "*" -DestinationPortRange 53 `
        | Out-Null

    Write-Host "  Allow-DNS-From-Home restored on $($Nsg.Name)" -ForegroundColor Green
}

function Remove-NicAsgAssociation {
    param([string]$VmName, [string]$ResourceGroupName)

    $nicName = "$VmName-nic"
    $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $nicName -ErrorAction SilentlyContinue
    if (-not $nic) {
        Write-Host "$nicName not found — skipping." -ForegroundColor Yellow
        return
    }

    $nic.IpConfigurations[0].ApplicationSecurityGroups = $null
    Set-AzNetworkInterface -NetworkInterface $nic -ErrorAction Stop | Out-Null
    Write-Host "$nicName -> ASG association removed" -ForegroundColor Green
}

function Remove-AsgIfExists {
    param([string]$Name, [string]$ResourceGroupName)

    $asg = Get-AzApplicationSecurityGroup -ResourceGroupName $ResourceGroupName -Name $Name -ErrorAction SilentlyContinue
    if ($asg) {
        Remove-AzApplicationSecurityGroup -ResourceGroupName $ResourceGroupName -Name $Name -Force -ErrorAction Stop
        Write-Host "$Name removed" -ForegroundColor Green
    } else {
        Write-Host "$Name not found — skipping." -ForegroundColor Yellow
    }
}

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    $homeSources = @($HomeLanNsgSource, $HomeServerNsgSource)

    # ---- Step 1: revert NSG rules ----
    Write-Step "Reverting $HubNsgName"
    $hubNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $HubNsgName -ErrorAction Stop
    Remove-RuleIfExists -Nsg $hubNsg -RuleName "Deny-VirtualNetwork-Inbound"
    Remove-RuleIfExists -Nsg $hubNsg -RuleName "Deny-Internet-Inbound"
    Set-RuleDestinationAny -Nsg $hubNsg -RuleName "Allow-RDP-From-Hub"
    Set-RuleDestinationAny -Nsg $hubNsg -RuleName "Allow-RDP-From-Home"
    Set-RuleDestinationAny -Nsg $hubNsg -RuleName "Allow-Ping-From-Home"
    Set-RuleDestinationAny -Nsg $hubNsg -RuleName "Allow-DNS-From-Home"
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $hubNsg -ErrorAction Stop | Out-Null

    Write-Step "Reverting $Spoke1NsgName"
    $spoke1Nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $Spoke1NsgName -ErrorAction Stop
    Remove-RuleIfExists -Nsg $spoke1Nsg -RuleName "Deny-VirtualNetwork-Inbound"
    Remove-RuleIfExists -Nsg $spoke1Nsg -RuleName "Deny-Internet-Inbound"
    Set-RuleDestinationAny -Nsg $spoke1Nsg -RuleName "Allow-RDP-From-Hub"
    Set-RuleDestinationAny -Nsg $spoke1Nsg -RuleName "Allow-RDP-From-Home"
    Set-RuleDestinationAny -Nsg $spoke1Nsg -RuleName "Allow-Ping-From-Home"
    Add-DnsFromHomeRule -Nsg $spoke1Nsg -HomeSourceCidrs $homeSources
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $spoke1Nsg -ErrorAction Stop | Out-Null

    Write-Step "Reverting $Spoke2NsgName"
    $spoke2Nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $Spoke2NsgName -ErrorAction Stop
    Remove-RuleIfExists -Nsg $spoke2Nsg -RuleName "Deny-VirtualNetwork-Inbound"
    Remove-RuleIfExists -Nsg $spoke2Nsg -RuleName "Deny-Internet-Inbound"
    Set-RuleDestinationAny -Nsg $spoke2Nsg -RuleName "Allow-RDP-From-Hub"
    Set-RuleDestinationAny -Nsg $spoke2Nsg -RuleName "Allow-RDP-From-Home"
    Set-RuleDestinationAny -Nsg $spoke2Nsg -RuleName "Allow-Ping-From-Home"
    Add-DnsFromHomeRule -Nsg $spoke2Nsg -HomeSourceCidrs $homeSources
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $spoke2Nsg -ErrorAction Stop | Out-Null

    # ---- Step 2: disassociate + delete ASGs ----
    Write-Step "Disassociating ASGs from VM NICs"
    Remove-NicAsgAssociation -VmName $HubVmName    -ResourceGroupName $ResourceGroupName
    Remove-NicAsgAssociation -VmName $Spoke1VmName -ResourceGroupName $ResourceGroupName
    Remove-NicAsgAssociation -VmName $Spoke2VmName -ResourceGroupName $ResourceGroupName

    Write-Step "Deleting ASGs"
    Remove-AsgIfExists -Name $HubAsgName    -ResourceGroupName $ResourceGroupName
    Remove-AsgIfExists -Name $Spoke1AsgName -ResourceGroupName $ResourceGroupName
    Remove-AsgIfExists -Name $Spoke2AsgName -ResourceGroupName $ResourceGroupName

    Write-Step "DONE — Phase 1 changes reverted"
    Write-Host "NSGs are back to the state Deploy-AZ500-NSGs.ps1 originally created. NSGs themselves, VNets, VMs, and gateway are untouched." -ForegroundColor Green
}
catch {
    Write-Host "`n*** REMOVAL FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
