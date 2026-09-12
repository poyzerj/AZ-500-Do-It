<#
.SYNOPSIS
    Deploys Storage Account + Private Endpoint (blob) + Private DNS Zone,
    linked to Hub-VNet, Spoke1-VNet, Spoke2-VNet.

.NOTES
    Assumes the network (VNets/subnets) already exists in rg-az500-doit-cus.
#>

$Location           = "centralus"
$Rg                  = "rg-az500-doit-cus"

$HubVnetName         = "JPVNetHub"
$PeSubnetName        = "PrivateEndpointSubnet"
$Spoke1VnetName      = "JPVNetSpoke1"
$Spoke2VnetName      = "JPVNetSpoke2"

$StorageAccountName  = "jpaz500storage0729"
$DnsZoneName         = "privatelink.blob.core.windows.net"

# ---- Storage Account ----
Write-Host "Creating storage account: $StorageAccountName" -ForegroundColor Cyan
$sa = New-AzStorageAccount -ResourceGroupName $Rg -Name $StorageAccountName `
        -Location $Location -SkuName "Standard_LRS" -Kind StorageV2 `
        -AllowBlobPublicAccess $false

# ---- Private Endpoint ----
$hubVnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $HubVnetName
$peSubnet = Get-AzVirtualNetworkSubnetConfig -Name $PeSubnetName -VirtualNetwork $hubVnet

$plsConnection = New-AzPrivateLinkServiceConnection -Name "az500storage-pe-connection" `
    -PrivateLinkServiceId $sa.Id -GroupId "blob"

Write-Host "Creating Private Endpoint..." -ForegroundColor Cyan
$pe = New-AzPrivateEndpoint -ResourceGroupName $Rg -Location $Location `
        -Name "jpaz500storage-pe" -Subnet $peSubnet `
        -PrivateLinkServiceConnection $plsConnection

# ---- Disable public access ----
Set-AzStorageAccount -ResourceGroupName $Rg -Name $StorageAccountName -PublicNetworkAccess Disabled

# ---- Private DNS Zone + links ----
Write-Host "Creating Private DNS Zone: $DnsZoneName" -ForegroundColor Cyan
New-AzPrivateDnsZone -ResourceGroupName $Rg -Name $DnsZoneName

$spoke1Vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $Spoke1VnetName
$spoke2Vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $Spoke2VnetName

New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $Rg -ZoneName $DnsZoneName `
    -Name "link-hub" -VirtualNetworkId $hubVnet.Id

New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $Rg -ZoneName $DnsZoneName `
    -Name "link-spoke1" -VirtualNetworkId $spoke1Vnet.Id`

New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $Rg -ZoneName $DnsZoneName `
    -Name "link-spoke2" -VirtualNetworkId $spoke2Vnet.Id

# ---- A record pointing at the PE's NIC private IP ----
$peNic = Get-AzNetworkInterface -ResourceId $pe.NetworkInterfaces[0].Id
$peIp = $peNic.IpConfigurations[0].PrivateIpAddress

New-AzPrivateDnsRecordSet -ResourceGroupName $Rg -ZoneName $DnsZoneName `
    -Name $StorageAccountName -RecordType A -Ttl 3600 `
    -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -IPv4Address $peIp)

<# ---- Test blob ----
$ctx = $sa.Context
New-AzStorageContainer -Name "testcontainer" -Context $ctx -Permission Off
"Hello from AZ-500 Do-It" | Out-File -FilePath ".\test.txt"
Set-AzStorageBlobContent -File ".\test.txt" -Container "testcontainer" -Blob "test.txt" -Context $ctx

Write-Host "`n===== DEPLOY COMPLETE =====" -ForegroundColor Green
Write-Host "Storage Account:     $StorageAccountName"
Write-Host "Private Endpoint IP: $peIp"
Write-Host "DNS Zone:            $DnsZoneName (linked to Hub, Spoke1, Spoke2)"
Write-Host "`nSave the storage account name above — you'll need it for nslookup/curl validation later."
#>