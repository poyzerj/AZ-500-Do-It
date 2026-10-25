<#
.SYNOPSIS
    AZ-500 Do-It — enable ICMPv4 Echo Request (ping) on each lab VM via Run Command.

.DESCRIPTION
    The lab VMs (JPAZVM11/12/13) come up with ICMP blocked at the guest OS level by default -
    same story as RDP: the Windows Firewall's "File and Printer Sharing (Echo Request -
    ICMPv4-In)" rule exists but is disabled out of the box, even once NSG/Firewall layers
    above it allow the traffic through.

    Runs via Invoke-AzVMRunCommand (the VM agent's Run Command feature), so it doesn't depend
    on any particular network path already being open - it goes in over the control plane.

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
# so it works even while ICMP is still fully blocked at the Windows Firewall.
$pingScript = @'
# Enable the built-in Windows Firewall rule group for ICMPv4 Echo Request, on every profile
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Name "*ICMP4-ERQ-In*" -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -ErrorAction SilentlyContinue

# Some images don't ship that exact built-in rule - create one explicitly so this is
# idempotent and works regardless of which predefined rule names exist on the image
if (-not (Get-NetFirewallRule -DisplayName "Allow ICMPv4-In (Ping)" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Allow ICMPv4-In (Ping)" -Direction Inbound -Protocol ICMPv4 `
        -IcmpType 8 -Action Allow -Profile Domain,Private,Public | Out-Null
}

# Report back what actually got applied, so the Run Command output confirms it rather than
# just assuming the change took
$rules = Get-NetFirewallRule | Where-Object {
    $_.DisplayName -match "ICMP" -or $_.DisplayName -eq "Allow ICMPv4-In (Ping)"
} | Select-Object DisplayName, Enabled, Direction, Profile

Write-Output ($rules | Format-Table -AutoSize | Out-String)
'@

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    foreach ($vmName in $VmNames) {
        Write-Step "Enabling ping (ICMPv4 Echo Request) on $vmName"
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName `
            -CommandId "RunPowerShellScript" -ScriptString $pingScript -ErrorAction Stop

        $output = $result.Value | Select-Object -ExpandProperty Message
        Write-Host $output -ForegroundColor Green
    }

    Write-Step "DONE"
    Write-Host "ICMPv4 Echo Request enabled on: $($VmNames -join ', ')" -ForegroundColor Green
    Write-Host "Test with: Test-Connection <vm-ip> -Count 2  (remember NSG/Firewall rules still need to allow ICMP for the path you're testing)" -ForegroundColor Yellow
}
catch {
    Write-Host "`n*** FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
