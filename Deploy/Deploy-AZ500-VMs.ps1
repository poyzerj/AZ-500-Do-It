<#
.SYNOPSIS
    Deploy hub-vm, spoke1-vm, spoke2-vm directly via PowerShell using Standard_B2s_v2.
    Bypasses the portal's VM size picker entirely — the API confirmed this SKU has
    NO restrictions on your subscription, even though it's not showing in the portal list.

.NOTES
    Assumes network already exists in Central US:
      rg-az500-doit / JPVNetHub / JPVNetSpoke1 / JPVNetSpoke2 / NSGs (with RDP rule already added)
    No public IPs — access only via P2S/S2S once the gateway is up.
#>

$Location  = "centralus"
$Rg        = "rg-az500-doit-cus"
$VmSize    = "Standard_F1amds_v7"

$AdminUser = "adminjpoyzer"
$AdminPasswordSecure = (ConvertTo-SecureString "K1pe3kjt!0729" -AsPlainText -Force)  # <-- FILL IN

function New-LabVm {
    param($VmName, $VnetName, $SubnetName, $NsgName)

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $VnetName
    $subnet = $vnet.Subnets | Where-Object Name -eq $SubnetName
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $Rg -Name $NsgName

    $nic = New-AzNetworkInterface -ResourceGroupName $Rg -Location $Location `
            -Name "$VmName-nic" -SubnetId $subnet.Id -NetworkSecurityGroupId $nsg.Id
            # No -PublicIpAddressId — private IP only

    $cred = New-Object System.Management.Automation.PSCredential ($AdminUser, $AdminPasswordSecure)

    $vmConfig = New-AzVMConfig -VMName $VmName -VMSize $VmSize |
        Set-AzVMBootDiagnostic -Disable |
        Set-AzVMOperatingSystem -Windows -ComputerName $VmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate |
        Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2025-datacenter-g2" -Version "latest" |
        Add-AzVMNetworkInterface -Id $nic.Id

    Write-Host "Deploying $VmName ($VmSize)..."
    New-AzVM -ResourceGroupName $Rg -Location $Location -VM $vmConfig
    Write-Host "$VmName deployed." -ForegroundColor Green
}

New-LabVm -VmName "JPAZVM11"    -VnetName "JPVNetHub"    -SubnetName "HubSubnet"    -NsgName "JPNSGHub"
New-LabVm -VmName "JPAZVM12" -VnetName "JPVNetSpoke1" -SubnetName "Spoke1Subnet" -NsgName "JPNSGSpoke1"
New-LabVm -VmName "JPAZVM13" -VnetName "JPVNetSpoke2" -SubnetName "Spoke2Subnet" -NsgName "JPNSGSpoke2"

Write-Host "`nAll three VMs submitted. Check boot diagnostics once provisioning completes." -ForegroundColor Cyan