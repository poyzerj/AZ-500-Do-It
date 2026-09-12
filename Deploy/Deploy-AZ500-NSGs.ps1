<#
.SYNOPSIS
    AZ-500 Do-It — Deploy JPNSGHub, JPNSGSpoke1, JPNSGSpoke2 with RDP-from-Hub,
    RDP-from-Home, Ping-from-Home, and DNS-from-Home rules, and associate each
    to its matching subnet.

.DESCRIPTION
    Creates 3 NSGs, each with 4 rules:
      - Allow-RDP-From-Hub   (priority 100, TCP/3389, source = hub VNet/subnet)
      - Allow-RDP-From-Home  (priority 110, TCP/3389, source = both home VLANs)
      - Allow-Ping-From-Home (priority 120, ICMP,      source = both home VLANs)
      - Allow-DNS-From-Home  (priority 130, TCP+UDP/53, source = both home VLANs)

    Then associates each NSG to its matching subnet on Hub-VNet / Spoke1-VNet / Spoke2-VNet.

.NOTES
    Subnet names default to HubSubnet / Spoke1Subnet / Spoke2Subnet — adjust
    via params if your actual subnet names differ.

    DNS rule is needed on JPNSGHub specifically if hub-vm is acting as a DNS
    relay for on-prem conditional forwarders — included on all three NSGs
    here for consistency, since it's harmless on the spokes even if unused.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",
    [string]$Location          = "centralus",

    [string]$HubVNetName       = "JPVNetHub",
    [string]$Spoke1VNetName    = "JPVNetSpoke1",
    [string]$Spoke2VNetName    = "JPVNetSpoke2",

    [string]$HubSubnetName     = "HubSubnet",
    [string]$Spoke1SubnetName  = "Spoke1Subnet",
    [string]$Spoke2SubnetName  = "Spoke2Subnet",

    [string]$HubNsgSource      = "10.0.0.0/16",   # whole Hub-VNet, for Hub-NSG's own rule
    [string]$SpokeNsgSource    = "10.0.1.0/24",   # Hub subnet CIDR, used on both spoke NSGs

    [string]$HomeLanNsgSource    = "192.168.20.0/24",  # home LAN VLAN
    [string]$HomeServerNsgSource = "192.168.40.0/24"   # home server VLAN
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

function New-RdpNsg {
    param(
        [string]$NsgName,
        [string]$SourceCidr,
        [string[]]$HomeSourceCidrs,
        [string]$ResourceGroupName,
        [string]$Location
    )

    Write-Step "Creating $NsgName (RDP from hub: $SourceCidr | RDP+Ping+DNS from home: $($HomeSourceCidrs -join ', '))"

    $rule1 = New-AzNetworkSecurityRuleConfig `
        -Name "Allow-RDP-From-Hub" `
        -Description "Allow RDP inbound from hub" `
        -Access Allow `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority 100 `
        -SourceAddressPrefix $SourceCidr `
        -SourcePortRange "*" `
        -DestinationAddressPrefix "*" `
        -DestinationPortRange 3389

    $rule2 = New-AzNetworkSecurityRuleConfig `
        -Name "Allow-RDP-From-Home" `
        -Description "Allow RDP inbound from home" `
        -Access Allow `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority 110 `
        -SourceAddressPrefix $HomeSourceCidrs `
        -SourcePortRange "*" `
        -DestinationAddressPrefix "*" `
        -DestinationPortRange 3389

    $rule3 = New-AzNetworkSecurityRuleConfig `
        -Name "Allow-Ping-From-Home" `
        -Description "Allow Ping inbound from home" `
        -Access Allow `
        -Protocol Icmp `
        -Direction Inbound `
        -Priority 120 `
        -SourceAddressPrefix $HomeSourceCidrs `
        -SourcePortRange "*" `
        -DestinationAddressPrefix "*" `
        -DestinationPortRange "*"

    $rule4 = New-AzNetworkSecurityRuleConfig `
        -Name "Allow-DNS-From-Home" `
        -Description "Allow DNS inbound from home (TCP+UDP 53) for forwarder/relay" `
        -Access Allow `
        -Protocol "*" `
        -Direction Inbound `
        -Priority 130 `
        -SourceAddressPrefix $HomeSourceCidrs `
        -SourcePortRange "*" `
        -DestinationAddressPrefix "*" `
        -DestinationPortRange 53

    $nsg = New-AzNetworkSecurityGroup `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location `
        -Name $NsgName `
        -SecurityRules $rule1, $rule2, $rule3, $rule4 `
        -ErrorAction Stop

    Write-Host "$NsgName created: RDP from hub ($SourceCidr), RDP+Ping+DNS from home ($($HomeSourceCidrs -join ', '))" -ForegroundColor Green
    return $nsg
}

function Set-SubnetNsg {
    param(
        [string]$VNetName,
        [string]$SubnetName,
        [object]$Nsg,
        [string]$ResourceGroupName
    )

    Write-Step "Associating $($Nsg.Name) to $VNetName/$SubnetName"

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction Stop
    $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }

    if (-not $subnet) {
        throw "Subnet '$SubnetName' not found on VNet '$VNetName'. Check -HubSubnetName/-Spoke1SubnetName/-Spoke2SubnetName params."
    }

    Set-AzVirtualNetworkSubnetConfig `
        -VirtualNetwork $vnet `
        -Name $SubnetName `
        -AddressPrefix $subnet.AddressPrefix `
        -NetworkSecurityGroup $Nsg `
        -ErrorAction Stop | Out-Null

    Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop | Out-Null

    Write-Host "Associated $($Nsg.Name) -> $VNetName/$SubnetName" -ForegroundColor Green
}

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    $homeSources = @($HomeLanNsgSource, $HomeServerNsgSource)

    # ---- Create NSGs ----
    $hubNsg    = New-RdpNsg -NsgName "JPNSGHub"    -SourceCidr $HubNsgSource   -HomeSourceCidrs $homeSources -ResourceGroupName $ResourceGroupName -Location $Location
    $spoke1Nsg = New-RdpNsg -NsgName "JPNSGSpoke1" -SourceCidr $SpokeNsgSource -HomeSourceCidrs $homeSources -ResourceGroupName $ResourceGroupName -Location $Location
    $spoke2Nsg = New-RdpNsg -NsgName "JPNSGSpoke2" -SourceCidr $SpokeNsgSource -HomeSourceCidrs $homeSources -ResourceGroupName $ResourceGroupName -Location $Location

    # ---- Associate to subnets ----
    Set-SubnetNsg -VNetName $HubVNetName    -SubnetName $HubSubnetName    -Nsg $hubNsg    -ResourceGroupName $ResourceGroupName
    Set-SubnetNsg -VNetName $Spoke1VNetName -SubnetName $Spoke1SubnetName -Nsg $spoke1Nsg -ResourceGroupName $ResourceGroupName
    Set-SubnetNsg -VNetName $Spoke2VNetName -SubnetName $Spoke2SubnetName -Nsg $spoke2Nsg -ResourceGroupName $ResourceGroupName

    Write-Step "DONE — all 3 NSGs created and associated"
}
catch {
    Write-Host "`n*** DEPLOYMENT FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}