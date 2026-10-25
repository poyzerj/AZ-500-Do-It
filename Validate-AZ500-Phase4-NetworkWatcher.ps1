<#
.SYNOPSIS
    AZ-500 Do-It — Phase 4 (Visibility & Validation): run the full Network
    Watcher diagnostic pass against Phases 1-2 and report pass/fail.

.DESCRIPTION
    Phase 4 deploys nothing. VNet Flow Logs (and NSG Flow Logs before that)
    were evaluated and dropped from the build: raw flow log JSON is painful
    to review by hand, and it doesn't even capture the tests below, since
    IP Flow Verify never sends a real packet. The five Network Watcher
    diagnostics here validate the same enforcement more directly, with
    output that's actually readable - this script replaces what used to be
    Deploy-AZ500-Phase4-NetworkWatcher.ps1 and
    Remove-AZ500-Phase4-NetworkWatcher.ps1, both retired since there's
    nothing left to deploy or tear down.

    Runs, against JPAZVM12 (Spoke1) by default:
      1. Effective Security Rules  - combined subnet+NIC rule set on the NIC
      2. Next Hop                  - JPAZVM12 -> JPAZVM13 (expect Virtual
                                      Appliance via the firewall's private IP)
      3. IP Flow Verify x3         - outbound internet, inbound RDP from a
                                      non-on-prem IP (deny), inbound RDP from
                                      on-prem (allow)
      4. NSG Diagnostics           - same three flows as IP Flow Verify, via
                                      the newer configuration-diagnostic API,
                                      which also names the matched rule
      5. Connection Troubleshoot   - a real, non-simulated reachability and
                                      latency check, JPAZVM12 -> JPAZVM13 over
                                      RDP (3389). Expected result: Unreachable
                                      - JPNSGSpoke2 only allows RDP from the
                                      hub subnet and on-prem, not from Spoke1,
                                      so Deny-VirtualNetwork-Inbound should
                                      catch this. Unlike every other test
                                      here, this one sends real packets
                                      rather than simulating a rule
                                      evaluation.

    Requires Phases 1 and 2 already deployed - this only validates what
    should already exist there, it doesn't build anything.

.NOTES
    Run from a session already authenticated via Connect-AzAccount.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",
    [string]$Location          = "centralus",

    [string]$Spoke1VmName = "JPAZVM12",
    [string]$Spoke2VmName = "JPAZVM13",
    [string]$Spoke1VmIp   = "10.1.0.4",
    [string]$Spoke2VmIp   = "10.2.0.4",
    [string]$NonOnPremTestIp = "203.0.113.10",   # TEST-NET-3, safe placeholder - any non-home-VLAN IP works
    [string]$OnPremTestIp    = "192.168.20.50"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-TestResult($name, $expected, $actual, $pass) {
    $color = if ($pass) { "Green" } else { "Red" }
    $status = if ($pass) { "PASS" } else { "FAIL" }
    Write-Host "[$status] $name — expected: $expected, actual: $actual" -ForegroundColor $color
}

try {
    Write-Step "Verifying resource group exists"
    Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null

    Write-Step "Locating Network Watcher for $Location"
    $nw = Get-AzNetworkWatcher -Location $Location -ErrorAction Stop
    Write-Host "Using Network Watcher: $($nw.Name)" -ForegroundColor Green

    $spoke1Vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $Spoke1VmName -ErrorAction Stop
    $spoke2Vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $Spoke2VmName -ErrorAction Stop
    $spoke1NicName = ($spoke1Vm.NetworkProfile.NetworkInterfaces[0].Id -split '/')[-1]

    # ==== 1. Effective Security Rules ====
    Write-Step "1. Effective Security Rules — $spoke1NicName"
    $effectiveRules = Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName $spoke1NicName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    foreach ($nsgResult in $effectiveRules) {
        $nsgName = ($nsgResult.NetworkSecurityGroup.Id -split '/')[-1]
        Write-Host "NSG: $nsgName" -ForegroundColor Yellow
        $nsgResult.EffectiveSecurityRules |
            Sort-Object Priority |
            Select-Object Name, Priority, Direction, Access, Protocol |
            Format-Table -AutoSize
    }
    Write-Host "  Confirm Deny-VirtualNetwork-Inbound (4000) and Deny-Internet-Inbound (4010) both rank above the platform AllowVnetInBound default (65000)." -ForegroundColor Yellow

    # ==== 2. Next Hop ====
    Write-Step "2. Next Hop — $Spoke1VmName -> $Spoke2VmIp"
    $nextHop = Get-AzNetworkWatcherNextHop -NetworkWatcher $nw -TargetVirtualMachineId $spoke1Vm.Id `
        -SourceIPAddress $Spoke1VmIp -DestinationIPAddress $Spoke2VmIp -ErrorAction Stop
    $test1Pass = ($nextHop.NextHopType -eq "VirtualAppliance")
    Write-TestResult "Next Hop: $Spoke1VmName -> $Spoke2VmIp" "VirtualAppliance" $nextHop.NextHopType $test1Pass
    if ($test1Pass) {
        Write-Host "  Next hop IP: $($nextHop.NextHopIpAddress) — confirm this matches your firewall's private IP." -ForegroundColor Green
    }

    # ==== 3. IP Flow Verify (x3) ====
    Write-Step "3. IP Flow Verify"
    $test2 = Test-AzNetworkWatcherIPFlow -NetworkWatcher $nw -TargetVirtualMachineId $spoke1Vm.Id `
        -Direction Outbound -Protocol TCP -LocalIPAddress $Spoke1VmIp -LocalPort "*" `
        -RemoteIPAddress "8.8.8.8" -RemotePort "443" -ErrorAction Stop
    Write-TestResult "Outbound $Spoke1VmName -> 8.8.8.8:443" "Allow" $test2.Access ($test2.Access -eq "Allow")

    $test3 = Test-AzNetworkWatcherIPFlow -NetworkWatcher $nw -TargetVirtualMachineId $spoke1Vm.Id `
        -Direction Inbound -Protocol TCP -LocalIPAddress $Spoke1VmIp -LocalPort "3389" `
        -RemoteIPAddress $NonOnPremTestIp -RemotePort "*" -ErrorAction Stop
    Write-TestResult "Inbound RDP from $NonOnPremTestIp (non-on-prem)" "Deny" $test3.Access ($test3.Access -eq "Deny")

    $test4 = Test-AzNetworkWatcherIPFlow -NetworkWatcher $nw -TargetVirtualMachineId $spoke1Vm.Id `
        -Direction Inbound -Protocol TCP -LocalIPAddress $Spoke1VmIp -LocalPort "3389" `
        -RemoteIPAddress $OnPremTestIp -RemotePort "*" -ErrorAction Stop
    Write-TestResult "Inbound RDP from $OnPremTestIp (on-prem)" "Allow" $test4.Access ($test4.Access -eq "Allow")

    # ==== 4. NSG Diagnostics (configuration diagnostic) ====
    Write-Step "4. NSG Diagnostics — same three flows, via the configuration-diagnostic API"
    $diagProfiles = @(
        (New-AzNetworkWatcherNetworkConfigurationDiagnosticProfile -Direction Outbound -Protocol TCP -Source $Spoke1VmIp -Destination "8.8.8.8" -DestinationPort 443),
        (New-AzNetworkWatcherNetworkConfigurationDiagnosticProfile -Direction Inbound -Protocol TCP -Source $NonOnPremTestIp -Destination $Spoke1VmIp -DestinationPort 3389),
        (New-AzNetworkWatcherNetworkConfigurationDiagnosticProfile -Direction Inbound -Protocol TCP -Source $OnPremTestIp -Destination $Spoke1VmIp -DestinationPort 3389)
    )
    $diag = Invoke-AzNetworkWatcherNetworkConfigurationDiagnostic -NetworkWatcher $nw -TargetResourceId $spoke1Vm.Id -Profile $diagProfiles -ErrorAction Stop
    foreach ($result in $diag.Results) {
        $matchedRule = $result.NetworkSecurityGroupResult.MatchedRule.RuleName
        Write-Host ("  {0,-8} {1}:* -> {2}:{3}  =>  {4}  (rule: {5})" -f `
            $result.Profile.Direction, $result.Profile.Source, $result.Profile.Destination, `
            $result.Profile.DestinationPort, $result.NetworkSecurityGroupResult.SecurityRuleAccessResult, $matchedRule)
    }

    # ==== 5. Connection Troubleshoot — the one real-traffic test ====
    Write-Step "5. Connection Troubleshoot — real reachability check, $Spoke1VmName -> $Spoke2VmName over RDP"
    $connectivity = Test-AzNetworkWatcherConnectivity -NetworkWatcher $nw -SourceId $spoke1Vm.Id `
        -DestinationId $spoke2Vm.Id -DestinationPort 3389 -ErrorAction Stop
    Write-Host ("  Status: {0}   Avg latency: {1} ms   Probes sent/failed: {2}/{3}" -f `
        $connectivity.ConnectionStatus, $connectivity.AvgLatencyInMs, $connectivity.ProbesSent, $connectivity.ProbesFailed) -ForegroundColor Yellow
    Write-Host "  Expected: Unreachable. $Spoke2VmName's NSG only allows RDP from the hub subnet and on-prem, not from $Spoke1VmName directly - 'Unreachable' here is the correct result and is itself confirmation Deny-VirtualNetwork-Inbound is enforcing on real traffic, not just evaluated hypothetically." -ForegroundColor Yellow

    # ==== Summary ====
    Write-Step "DONE"
    $allPass = $test1Pass -and ($test2.Access -eq "Allow") -and ($test3.Access -eq "Deny") -and ($test4.Access -eq "Allow")
    if ($allPass) {
        Write-Host "All Next Hop / IP Flow Verify checks passed — Phases 1 and 2 are enforcing as designed." -ForegroundColor Green
    } else {
        Write-Host "One or more checks did not match expected results — review output above before considering Phase 4 complete." -ForegroundColor Red
    }
    Write-Host "Review the Effective Security Rules, NSG Diagnostics, and Connection Troubleshoot output above as well - all five checks together are Phase 4's evidence, not just the three pass/fail tests." -ForegroundColor Yellow
}
catch {
    Write-Host "`n*** VALIDATION FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
