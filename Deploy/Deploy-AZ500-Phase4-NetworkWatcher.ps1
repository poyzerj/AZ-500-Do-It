<#
.SYNOPSIS
    AZ-500 Do-It — Phase 4 (Visibility & Validation): enable NSG Flow Logs
    on all three NSGs, then run the design doc's validation test plan
    (Next Hop + IP Flow Verify) and report pass/fail against expected
    results.

.DESCRIPTION
    Part 1 — Enable Flow Logs:
      Creates a storage account for raw flow log storage (cheap — a few
      cents/month at lab scale) and enables NSG Flow Logs v2 on JPNSGHub,
      JPNSGSpoke1, and JPNSGSpoke2, pointed at it. Traffic Analytics
      (richer Log Analytics-based views) is optional via -EnableTrafficAnalytics,
      off by default to keep this phase's cost minimal.

    Part 2 — Run validation tests:
      Executes the test plan from the design document programmatically:
        1. Next Hop: JPAZVM12 -> JPAZVM13's IP (expect Virtual Appliance,
           firewall's private IP) — confirms the Phase 2 UDR is winning
           over the automatic peering route.
        2. IP Flow Verify: JPAZVM12 outbound to 8.8.8.8:443 (expect Allow)
        3. IP Flow Verify: inbound RDP to JPAZVM12 from a non-on-prem IP
           (expect Deny)
        4. IP Flow Verify: inbound RDP to JPAZVM12 from 192.168.20.50
           (expect Allow)
      Requires Phases 1 and 2 to already be deployed — this only validates
      what should already exist, it doesn't build anything from those
      phases.

.NOTES
    Run from a session already authenticated via Connect-AzAccount.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-az500-doit-cus",
    [string]$Location          = "centralus",

    [string]$FlowLogStorageAccountName = "jpaz500flowlogs",

    [string[]]$NsgNames = @("JPNSGHub", "JPNSGSpoke1", "JPNSGSpoke2"),
    [int]$RetentionDays = 7,

    [switch]$EnableTrafficAnalytics,
    [string]$LogAnalyticsWorkspaceId,   # required only if -EnableTrafficAnalytics is set

    # ---- validation test parameters ----
    [string]$Spoke1VmName = "JPAZVM12",
    [string]$Spoke2VmName = "JPAZVM13",
    [string]$Spoke1VmIp   = "10.1.0.4",
    [string]$Spoke2VmIp   = "10.2.0.4",
    [string]$NonOnPremTestIp = "203.0.113.10",   # TEST-NET-3, safe placeholder — any non-home-VLAN IP works
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

    # ==== PART 1: Enable Flow Logs ====

    Write-Step "Locating Network Watcher for $Location"
    $nw = Get-AzNetworkWatcher -Location $Location -ErrorAction SilentlyContinue
    if (-not $nw) {
        Write-Host "No Network Watcher found for $Location — creating one." -ForegroundColor Yellow
        $nwRg = "NetworkWatcherRG"
        if (-not (Get-AzResourceGroup -Name $nwRg -ErrorAction SilentlyContinue)) {
            New-AzResourceGroup -Name $nwRg -Location $Location | Out-Null
        }
        $nw = New-AzNetworkWatcher -ResourceGroupName $nwRg -Name "NetworkWatcher_$Location" -Location $Location -ErrorAction Stop
    }
    Write-Host "Using Network Watcher: $($nw.Name)" -ForegroundColor Green

    Write-Step "Creating/reusing flow log storage account ($FlowLogStorageAccountName)"
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $FlowLogStorageAccountName -ErrorAction SilentlyContinue
    if (-not $storageAccount) {
        $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $FlowLogStorageAccountName `
            -Location $Location -SkuName "Standard_LRS" -Kind "StorageV2" -MinimumTlsVersion "TLS1_2" -ErrorAction Stop
        Write-Host "$FlowLogStorageAccountName created." -ForegroundColor Green
    } else {
        Write-Host "$FlowLogStorageAccountName already exists — reusing." -ForegroundColor Yellow
    }

    foreach ($nsgName in $NsgNames) {
        Write-Step "Enabling Flow Logs v2 on $nsgName"
        $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $nsgName -ErrorAction Stop

        $flowLogParams = @{
            Name                = "$nsgName-flowlog"
            NetworkWatcher      = $nw
            TargetResourceId    = $nsg.Id
            StorageAccountId    = $storageAccount.Id
            Enabled             = $true
            Format              = "Json"
            EnabledFormatVersion = 2
            RetentionInDays     = $RetentionDays
        }
        if ($EnableTrafficAnalytics) {
            if (-not $LogAnalyticsWorkspaceId) {
                throw "-EnableTrafficAnalytics requires -LogAnalyticsWorkspaceId."
            }
            $flowLogParams["EnableTrafficAnalytics"] = $true
            $flowLogParams["TrafficAnalyticsWorkspaceId"] = $LogAnalyticsWorkspaceId
        }

        New-AzNetworkWatcherFlowLog @flowLogParams -ErrorAction Stop | Out-Null
        Write-Host "$nsgName -> Flow Logs v2 enabled, $RetentionDays-day retention." -ForegroundColor Green
    }

    # ==== PART 2: Validation tests ====

    Write-Step "Running validation test plan"

    # Test 1: Next Hop, Spoke1 VM -> Spoke2 VM IP
    $spoke1Vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $Spoke1VmName -ErrorAction Stop
    $nextHop = Get-AzNetworkWatcherNextHop -NetworkWatcher $nw -TargetVirtualMachineId $spoke1Vm.Id `
        -SourceIPAddress $Spoke1VmIp -DestinationIPAddress $Spoke2VmIp -ErrorAction Stop

    $test1Pass = ($nextHop.NextHopType -eq "VirtualAppliance")
    Write-TestResult "Next Hop: $Spoke1VmName -> $Spoke2VmIp" "VirtualAppliance" $nextHop.NextHopType $test1Pass
    if ($test1Pass) {
        Write-Host "  Next hop IP: $($nextHop.NextHopIpAddress) — confirm this matches your firewall's private IP." -ForegroundColor Green
    }

    # Test 2: IP Flow Verify, outbound HTTPS to internet
    $test2 = Test-AzNetworkWatcherIPFlow -NetworkWatcher $nw -TargetVirtualMachineId $spoke1Vm.Id `
        -Direction Outbound -Protocol TCP -LocalIPAddress $Spoke1VmIp -LocalPort "*" `
        -RemoteIPAddress "8.8.8.8" -RemotePort "443" -ErrorAction Stop
    Write-TestResult "IP Flow Verify: $Spoke1VmName -> 8.8.8.8:443 outbound" "Allow" $test2.Access ($test2.Access -eq "Allow")

    # Test 3: IP Flow Verify, inbound RDP from non-on-prem source (expect Deny)
    $test3 = Test-AzNetworkWatcherIPFlow -NetworkWatcher $nw -TargetVirtualMachineId $spoke1Vm.Id `
        -Direction Inbound -Protocol TCP -LocalIPAddress $Spoke1VmIp -LocalPort "3389" `
        -RemoteIPAddress $NonOnPremTestIp -RemotePort "*" -ErrorAction Stop
    Write-TestResult "IP Flow Verify: RDP from $NonOnPremTestIp (non-on-prem)" "Deny" $test3.Access ($test3.Access -eq "Deny")

    # Test 4: IP Flow Verify, inbound RDP from on-prem source (expect Allow)
    $test4 = Test-AzNetworkWatcherIPFlow -NetworkWatcher $nw -TargetVirtualMachineId $spoke1Vm.Id `
        -Direction Inbound -Protocol TCP -LocalIPAddress $Spoke1VmIp -LocalPort "3389" `
        -RemoteIPAddress $OnPremTestIp -RemotePort "*" -ErrorAction Stop
    Write-TestResult "IP Flow Verify: RDP from $OnPremTestIp (on-prem)" "Allow" $test4.Access ($test4.Access -eq "Allow")

    Write-Step "DONE"
    $allPass = $test1Pass -and ($test2.Access -eq "Allow") -and ($test3.Access -eq "Deny") -and ($test4.Access -eq "Allow")
    if ($allPass) {
        Write-Host "All 4 tests passed — Phases 1 and 2 are enforcing as designed." -ForegroundColor Green
    } else {
        Write-Host "One or more tests did not match expected results — review output above before considering Phase 4 complete." -ForegroundColor Red
    }
    Write-Host "Flow logs will take a few minutes to start populating the storage account — review them in the portal (test #5 in the design doc's plan, not automated here)." -ForegroundColor Yellow
}
catch {
    Write-Host "`n*** DEPLOYMENT/VALIDATION FAILED ***" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
