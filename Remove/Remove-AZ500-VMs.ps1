<#
.SYNOPSIS
    Removes hub-vm, spoke1-vm, spoke2-vm and their dependent resources
    (OS disks, NICs, auto-created boot diagnostics storage accounts).

    Leaves untouched:
      - VNets, Subnets, Peerings, NSGs
      - staz500doit* storage account, Private Endpoint, Private DNS Zone

.NOTES
    No public IPs to clean up — these VMs were deployed without PIPs.
#>

$Rg = "rg-az500-doit-cus"
$VmNames = @("JPAZVM11", "JPAZVM12", "JPAZVM13")

foreach ($VmName in $VmNames) {

    Write-Host "`n===== Removing $VmName =====" -ForegroundColor Cyan

    $vm = Get-AzVM -ResourceGroupName $Rg -Name $VmName -ErrorAction SilentlyContinue

    if ($vm) {
        $osDiskName = $vm.StorageProfile.OsDisk.Name

        Write-Host "Removing VM: $VmName"
        Remove-AzVM -ResourceGroupName $Rg -Name $VmName -Force

        Write-Host "Removing OS disk: $osDiskName"
        Remove-AzDisk -ResourceGroupName $Rg -DiskName $osDiskName -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "$VmName not found — skipping VM/disk removal" -ForegroundColor Yellow
    }

    $nic = Get-AzNetworkInterface -ResourceGroupName $Rg -Name "$VmName-nic" -ErrorAction SilentlyContinue
    if ($nic) {
        Write-Host "Removing NIC: $VmName-nic"
        Remove-AzNetworkInterface -ResourceGroupName $Rg -Name "$VmName-nic" -Force
    } else {
        Write-Host "$VmName-nic not found — skipping NIC removal" -ForegroundColor Yellow
    }
}

# ---- Clean up auto-created boot diagnostics storage accounts ----


Write-Host "`n===== TEARDOWN COMPLETE =====" -ForegroundColor Green
Write-Host "Removed: VMs, OS disks, NICs."
Write-Host "Untouched: VNets, Subnets, Peerings, NSGs, staz500doit* storage, Private Endpoint, Private DNS Zone."