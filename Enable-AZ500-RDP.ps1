<#
.SYNOPSIS
    AZ-500 Do-It — enable Remote Desktop (service + Windows Firewall) on each lab VM via Run Command.

.DESCRIPTION
    The lab VMs (JPAZVM11/12/13) come up with RDP blocked at the guest OS level by default -
    confirmed via Network Watcher's port scanner ("Destination port accessible: Timeout") during
    Phase 4 validation, even once the NSG and Azure Firewall layers both allow the traffic. This
    script fixes that at the one layer Network Watcher can't reach from outside: the VM's own
    Windows Firewall and Terminal Services registry setting.

    Runs via Invoke-AzVMRunCommand (the VM agent's Run Command feature), so it doesn't depend on
    RDP already working - it goes in over the control plane rather than the data plane, which is
    exactly what you need before RDP itself is usable.

    Meant to run right after Deploy-Domain-Join.ps1, as the last prep step before RDP'ing in or
    demoing live for the first time.

.NOTES
    Run from a session already authenticated via Connect-AzAccount.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",
    [string[]]$VmNames = @("JPAZVM11", "JPAZVM12", "JPAZVM13")
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# This block runs INSIDE the guest OS via Run Command - it never touches the network path,
# so it works even while RDP is still fully blocked at the Windows Firewall.
$rdpScript = @'
# Enable Remote Desktop connections
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0

# Enable the built-in Windows Firewall rule group for Remote Desktop, on every profile
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Report back what actually got applied, so the Run Command output confirms it rather than
# just assuming the change took
$deny = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections"
$rules = Get-NetFirewallRule -DisplayGroup "Remote Desktop" | Select-Object DisplayName, Enabled, Direction, Profile

Write-Output "fDenyTSConnections: $($deny.fDenyTSConnections)  (0 = RDP allowed)"
Write-Output ($rules | Format-Table -AutoSize | Out-String)
'@

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    foreach ($vmName in $VmNames) {
        Write-Step "Enabling RDP on $vmName"
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName `
            -CommandId "RunPowerShellScript" -ScriptString $rdpScript -ErrorAction Stop

        $output = $result.Value | Select-Object -ExpandProperty Message
        Write-Host $output -ForegroundColor Green
    }

    Write-Step "DONE"
    Write-Host "RDP enabled (service + firewall) on: $($VmNames -join ', ')" -ForegroundColor Green
    Write-Host "Re-run Network Watcher's port scanner / Connection Troubleshoot to confirm 'Destination port accessible' now passes." -ForegroundColor Yellow
}
catch {
    Write-Host "`n*** FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
