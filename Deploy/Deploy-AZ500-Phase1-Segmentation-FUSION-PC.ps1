<#
.SYNOPSIS
    AZ-500 Do-It — Phase 1 (Segmentation): create ASGs, retarget existing NSG
    rules to them, remove the unused spoke-side DNS rule, and add explicit
    deny-by-default rules to JPNSGHub / JPNSGSpoke1 / JPNSGSpoke2.

.DESCRIPTION
    This does NOT recreate the NSGs — Deploy-AZ500-NSGs.ps1 already did that.
    It hardens what's already deployed:

      1. Creates JPASGHub / JPASGSpoke1 / JPASGSpoke2
         and associates each to its VM's NIC.
      2. Retargets the existing Allow-RDP-From-Hub, Allow-RDP-From-Home, and
         Allow-Ping-From-Home rules on all three NSGs from destination "*"
         to the matching ASG. Allow-DNS-From-Home is retargeted on
         JPNSGHub only.
      3. Removes Allow-DNS-From-Home from JPNSGSpoke1 / JPNSGSpoke2 — it's
         unused there (on-prem DNS forwarding only ever targets the hub;
         see Deploy-DNS-Forwarder-VM11.ps1).
      4. Adds Deny-VirtualNetwork-Inbound (priority 4000) and
         Deny-Internet-Inbound (priority 4010) to all three NSGs. This is
         what actually removes the implicit trust the platform default
         AllowVnetInBound rule (65000) grants across the peered spokes —
         the existing allow rules only ever covered specific sources/ports,
         they never closed off everything else.

    Idempotent — safe to re-run. Existing rules are removed and recreated
    rather than skipped, so re-running after a manual portal change will
    reset it back to this design.

.NOTES
    Run from a session already authenticated via Connect-AzAccount.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",
    [string]$Location          = "centralus",

    [string]$HubNsgName    = "JPNSGHub",
    [string]$Spoke1NsgName = "JPNSGSpoke1",
    [string]$Spoke2NsgName = "JPNSGSpoke2",

    [string]$HubVmName    = "JPAZVM11",
    [string]$Spoke1VmName = "JPAZVM12",
    [string]$Spoke2VmName = "JPAZVM13",

    [string]$HubAsgName    = "JPASGHub",
    [string]$Spoke1AsgName = "JPASGSpoke1",
    [string]$Spoke2AsgName = "JPASGSpoke2"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

function New-OrGetAsg {
    param([string]$Name, [string]$ResourceGroupName, [string]$Location)

    $asg = Get-AzApplicationSecurityGroup -ResourceGroupName $ResourceGroupName -Name $Name -ErrorAction SilentlyContinue
    if ($asg) {
        Write-Host "$Name already exists — reusing." -ForegroundColor Yellow
        return $asg
    }

    $asg = New-AzApplicationSecurityGroup -ResourceGroupName $ResourceGroupName -Name $Name -Location $Location -ErrorAction Stop
    Write-Host "$Name created." -ForegroundColor Green
    return $asg
}

function Set-NicAsg {
    param([string]$VmName, [object]$Asg, [string]$ResourceGroupName)

    $nicName = "$VmName-nic"
    $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $nicName -ErrorAction Stop
    $ipConfig = $nic.IpConfigurations[0]
    $ipConfig.ApplicationSecurityGroups = @($Asg)

    Set-AzNetworkInterface -NetworkInterface $nic -ErrorAction Stop | Out-Null
    Write-Host "$nicName -> associated with $($Asg.Name)" -ForegroundColor Green
}

function Set-RuleDestinationAsg {
    <#
    Removes a rule by name (if present) and recreates it with the same
    source/protocol/port/priority, but DestinationApplicationSecurityGroupId
    instead of DestinationAddressPrefix "*".
    #>
    param(
        [object]$Nsg,
        [string]$RuleName,
        [object]$Asg
    )

    $existing = $Nsg.SecurityRules | Where-Object { $_.Name -eq $RuleName }
    if (-not $existing) {
        Write-Host "  $RuleName not found on $($Nsg.Name) — skipping (nothing to retarget)." -ForegroundColor Yellow
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
        -DestinationApplicationSecurityGroupId $Asg.Id `
        -DestinationPortRange $existing.DestinationPortRange `
        | Out-Null

    Write-Host "  $RuleName -> destination retargeted to $($Asg.Name)" -ForegroundColor Green
}

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

function Add-DenyByDefaultRules {
    param([object]$Nsg)

    Remove-RuleIfExists -Nsg $Nsg -RuleName "Deny-VirtualNetwork-Inbound"
    $Nsg | Add-AzNetworkSecurityRuleConfig `
        -Name "Deny-VirtualNetwork-Inbound" `
        -Description "Explicit deny for intra-VNet traffic not covered by an allow rule above (overrides platform default AllowVnetInBound)" `
        -Access Deny -Protocol "*" -Direction Inbound -Priority 4000 `
        -SourceAddressPrefix "VirtualNetwork" -SourcePortRange "*" `
        -DestinationAddressPrefix "VirtualNetwork" -DestinationPortRange "*" `
        | Out-Null

    Remove-RuleIfExists -Nsg $Nsg -RuleName "Deny-Internet-Inbound"
    $Nsg | Add-AzNetworkSecurityRuleConfig `
        -Name "Deny-Internet-Inbound" `
        -Description "Explicit deny for inbound internet traffic" `
        -Access Deny -Protocol "*" -Direction Inbound -Priority 4010 `
        -SourceAddressPrefix "Internet" -SourcePortRange "*" `
        -DestinationAddressPrefix "*" -DestinationPortRange "*" `
        | Out-Null

    Write-Host "  Deny-by-default rules present on $($Nsg.Name)" -ForegroundColor Green
}

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    # ---- Step 1: ASGs ----
    Write-Step "Creating/reusing Application Security Groups"
    $hubAsg    = New-OrGetAsg -Name $HubAsgName    -ResourceGroupName $ResourceGroupName -Location $Location
    $spoke1Asg = New-OrGetAsg -Name $Spoke1AsgName -ResourceGroupName $ResourceGroupName -Location $Location
    $spoke2Asg = New-OrGetAsg -Name $Spoke2AsgName -ResourceGroupName $ResourceGroupName -Location $Location

    Write-Step "Associating ASGs to VM NICs"
    Set-NicAsg -VmName $HubVmName    -Asg $hubAsg    -ResourceGroupName $ResourceGroupName
    Set-NicAsg -VmName $Spoke1VmName -Asg $spoke1Asg -ResourceGroupName $ResourceGroupName
    Set-NicAsg -VmName $Spoke2VmName -Asg $spoke2Asg -ResourceGroupName $ResourceGroupName

    # ---- Step 2: Retarget existing rules to ASGs ----
    Write-Step "Retargeting $HubNsgName rules to $HubAsgName"
    $hubNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $HubNsgName -ErrorAction Stop
    Set-RuleDestinationAsg -Nsg $hubNsg -RuleName "Allow-RDP-From-Hub"  -Asg $hubAsg
    Set-RuleDestinationAsg -Nsg $hubNsg -RuleName "Allow-RDP-From-Home" -Asg $hubAsg
    Set-RuleDestinationAsg -Nsg $hubNsg -RuleName "Allow-Ping-From-Home" -Asg $hubAsg
    Set-RuleDestinationAsg -Nsg $hubNsg -RuleName "Allow-DNS-From-Home" -Asg $hubAsg
    Add-DenyByDefaultRules -Nsg $hubNsg
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $hubNsg -ErrorAction Stop | Out-Null

    Write-Step "Retargeting $Spoke1NsgName rules to $Spoke1AsgName"
    $spoke1Nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $Spoke1NsgName -ErrorAction Stop
    Set-RuleDestinationAsg -Nsg $spoke1Nsg -RuleName "Allow-RDP-From-Hub"  -Asg $spoke1Asg
    Set-RuleDestinationAsg -Nsg $spoke1Nsg -RuleName "Allow-RDP-From-Home" -Asg $spoke1Asg
    Set-RuleDestinationAsg -Nsg $spoke1Nsg -RuleName "Allow-Ping-From-Home" -Asg $spoke1Asg
    Remove-RuleIfExists -Nsg $spoke1Nsg -RuleName "Allow-DNS-From-Home"
    Add-DenyByDefaultRules -Nsg $spoke1Nsg
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $spoke1Nsg -ErrorAction Stop | Out-Null

    Write-Step "Retargeting $Spoke2NsgName rules to $Spoke2AsgName"
    $spoke2Nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $Spoke2NsgName -ErrorAction Stop
    Set-RuleDestinationAsg -Nsg $spoke2Nsg -RuleName "Allow-RDP-From-Hub"  -Asg $spoke2Asg
    Set-RuleDestinationAsg -Nsg $spoke2Nsg -RuleName "Allow-RDP-From-Home" -Asg $spoke2Asg
    Set-RuleDestinationAsg -Nsg $spoke2Nsg -RuleName "Allow-Ping-From-Home" -Asg $spoke2Asg
    Remove-RuleIfExists -Nsg $spoke2Nsg -RuleName "Allow-DNS-From-Home"
    Add-DenyByDefaultRules -Nsg $spoke2Nsg
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $spoke2Nsg -ErrorAction Stop | Out-Null

    Write-Step "DONE"
    Write-Host "Verify with Network Watcher (IP Flow Verify / Effective Security Rules) before moving to Phase 2." -ForegroundColor Green
}
catch {
    Write-Host "`n*** DEPLOYMENT FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
