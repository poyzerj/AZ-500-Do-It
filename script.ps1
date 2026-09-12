$Rg = "rg-az500-doit-cus"
$Spoke1Name = "JPVNetSpoke1"
$Spoke2Name = "JPVNetSpoke2"


$spoke1Vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $Spoke1Name
$spoke2Vnet = Get-AzVirtualNetwork -ResourceGroupName $Rg -Name $Spoke2Name

Add-AzVirtualNetworkPeering `
    -Name "JPVNetSpoke1-to-JPVNetSpoke2" `
    -VirtualNetwork $spoke1Vnet `
    -RemoteVirtualNetworkId $spoke2Vnet.Id `
    -AllowForwardedTraffic


Add-AzVirtualNetworkPeering 
    -Name "JPVNetSpoke2-to-JPVNetSpoke1" `
    -VirtualNetwork $spoke2Vnet `
    -RemoteVirtualNetworkId $spoke1Vnet.Id `
    -AllowForwardedTraffic

