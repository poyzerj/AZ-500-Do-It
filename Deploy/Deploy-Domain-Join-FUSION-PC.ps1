<#
.SYNOPSIS
    AZ-500 Do-It — Set DNS server to 192.168.40.15 and domain-join
    JPAZVM11, JPAZVM12, JPAZVM13 to poyzerj.local.

.DESCRIPTION
    Part 1: Updates each VM's NIC to use 192.168.40.10 (POYZERJDC10) as its
            DNS server, via Azure networking — no RDP needed.
    Part 2: Remotely renews each VM's DHCP lease (so the new DNS setting
            actually takes effect inside the guest OS, since an Azure NIC
            DNS change alone doesn't push into a running VM until it renews
            its lease) and then runs the domain-join command via
            Invoke-AzVMRunCommand. The inline script reports an explicit
            JOIN_RESULT marker so this outer script can tell a real success
            from a masked failure, instead of just trusting the Run Command
            extension's own status code (which reports "succeeded" even
            when Add-Computer inside it fails, since that failure is a
            non-terminating error on the guest side).

.NOTES
    SECURITY: This still passes the domain admin password to
    Invoke-AzVMRunCommand, which logs the run command (including its script
    body) to Azure Activity Log / VM run command history. Treat this as
    sensitive — rotate the password after this lab work is done, same
    caution as flagged earlier when the FortiGate PSK ended up in a script
    file.

    The password is no longer hardcoded here — a previous revision of this
    script had it typed as [SecureString] with a plaintext default, which
    PowerShell silently auto-converts at bind time. That meant the value
    later interpolated into the join payload as the literal text
    "System.Security.SecureString" (SecureString's ToString() doesn't
    return the password) instead of the real password, so the join failed
    with no visible error. You'll be prompted for the password at runtime
    instead.

    Run this from a session already authenticated via Connect-AzAccount,
    targeting your subscription.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",
    [string[]]$VmNames         = @("JPAZVM11", "JPAZVM12", "JPAZVM13"),
    [string]$DnsServerIp       = "192.168.40.15",
    [string]$DomainName        = "poyzerj.local",
    [string]$DomainAdminUser   = "POYZERJ\adminjpoyzer",

    [Parameter()]
    [SecureString]$DomainAdminPassword = (Read-Host -Prompt "Domain admin password" -AsSecureString)
)

$ErrorActionPreference = "Stop"

# Decode the SecureString to plaintext only right here, right before it's
# needed to build the remote script payload.
$plainPassword = [System.Net.NetworkCredential]::new('', $DomainAdminPassword).Password

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

try {
    # ---- Part 1: Set DNS server on each VM's NIC ----
    Write-Step "Setting DNS server ($DnsServerIp) on each VM's NIC"
    foreach ($vmName in $VmNames) {
        $nicName = "$vmName-nic"
        Write-Host "Updating $nicName..."

        $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $nicName -ErrorAction Stop
        $nic.DnsSettings.DnsServers.Clear()
        $nic.DnsSettings.DnsServers.Add($DnsServerIp)
        Set-AzNetworkInterface -NetworkInterface $nic -ErrorAction Stop | Out-Null

        Write-Host "$nicName -> DNS set to $DnsServerIp" -ForegroundColor Green
    }

    # ---- Part 2: Renew DHCP lease + domain-join each VM remotely ----
    Write-Step "Renewing DHCP lease and domain-joining each VM to $DomainName"

    $joinScript = @"
Write-Output "Renewing DHCP lease so the new DNS server actually takes effect..."
ipconfig /release | Out-Null
ipconfig /renew | Out-Null
Start-Sleep -Seconds 5
Write-Output "Current DNS servers:"
Get-DnsClientServerAddress -AddressFamily IPv4 | Format-Table -AutoSize | Out-String | Write-Output

`$securePass = ConvertTo-SecureString '$plainPassword' -AsPlainText -Force
`$cred = New-Object System.Management.Automation.PSCredential('$DomainAdminUser', `$securePass)

try {
    Add-Computer -DomainName '$DomainName' -Credential `$cred -Force -Restart -ErrorAction Stop
    Write-Output "JOIN_RESULT: SUCCESS"
} catch {
    Write-Output "JOIN_RESULT: FAILURE - `$(`$_.Exception.Message)"
}
"@

    foreach ($vmName in $VmNames) {
        Write-Host "Joining $vmName to $DomainName..."

        $result = Invoke-AzVMRunCommand `
            -ResourceGroupName $ResourceGroupName `
            -VMName $vmName `
            -CommandId "RunPowerShellScript" `
            -ScriptString $joinScript `
            -ErrorAction Stop

        $stdout = ($result.Value | Where-Object { $_.Code -like "*StdOut*" }).Message

        if ($stdout -match "JOIN_RESULT: SUCCESS") {
            Write-Host "$vmName joined successfully — VM is restarting." -ForegroundColor Green
        } elseif ($stdout -match "JOIN_RESULT: FAILURE") {
            Write-Host "$vmName domain-join FAILED:" -ForegroundColor Red
            ($stdout -split "`n" | Where-Object { $_ -match "JOIN_RESULT" }) | ForEach-Object {
                Write-Host "  $_" -ForegroundColor Red
            }
            Write-Host "Full output:" -ForegroundColor Yellow
            Write-Host $stdout
        } else {
            Write-Host "$vmName - couldn't find a JOIN_RESULT marker, check full output below:" -ForegroundColor Yellow
            $result.Value | Format-List
        }
    }

    Write-Step "DONE"
    Write-Host "Give successfully-joined VMs 2-3 minutes to finish restarting, then verify with:" -ForegroundColor Green
    Write-Host '  (Get-ADComputer -Filter * -Server "192.168.40.10").Name' -ForegroundColor Green
    Write-Host "(run that last line from POYZERJDC10 or any machine with the AD PowerShell module and connectivity to it)"
}
catch {
    Write-Host "`n*** FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
