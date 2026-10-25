# Phase 4 (Visibility & Validation) — Azure Portal Walkthrough

Portal-only equivalent of `Validate-AZ500-Phase4-NetworkWatcher.ps1`. Resource group throughout: `rg-az500-doit-cus`. Requires Phases 1 and 2 already deployed — this phase validates them, it doesn't build anything from them.

**Note:** this phase was originally built around flow logs (first NSG Flow Logs, then VNet Flow Logs after Microsoft retired new NSG Flow Log creation ahead of the Sept 30, 2027 retirement). Flow logs were dropped from the build entirely: the raw JSON is hard to review by hand, and it doesn't even capture the specific tests below, since IP Flow Verify never sends real traffic. Network Watcher's other diagnostic tools validate the same enforcement more directly, with output that's actually readable live.

---

## Step 1: Effective Security Rules

1. Portal search bar → **Virtual machines** → `JPAZVM12` → **Networking** → select the NIC → **Effective security rules** (under Help)
2. Review the combined list — confirm `Deny-VirtualNetwork-Inbound` (priority 4000) and `Deny-Internet-Inbound` (priority 4010) both appear ranked above the platform default `AllowVnetInBound` (priority 65000)

This is the combined result of the NSG's own rule list plus Azure's defaults — it's the actual enforced state on this NIC, not just what the NSG's rule blade shows you.

## Step 2: Next Hop test (validates Phase 2's UDRs)

1. Portal search bar → **Network Watcher** → left menu **Next hop** (under "Network diagnostic tools")
2. Fill in:

   | Field | Value |
   |---|---|
   | Virtual machine | JPAZVM12 |
   | Network interface | JPAZVM12-nic |
   | Source IP address | 10.1.0.4 |
   | Destination IP address | 10.2.0.4 |

3. **Next hop** → expect **Next hop type: Virtual Appliance**, with the IP matching your Azure Firewall's private IP. If it instead shows peering/VNet as the next hop, the `/16` UDR from Phase 2 isn't taking effect — go back and check the route table association.

## Step 3: IP Flow Verify tests (validates Phases 1 and 2)

Portal search bar → **Network Watcher** → left menu **IP flow verify**. Run three checks:

**Test A — outbound internet access should work**

| Field | Value |
|---|---|
| Virtual machine | JPAZVM12 |
| Protocol | TCP |
| Direction | Outbound |
| Local IP address | 10.1.0.4 |
| Local port | any |
| Remote IP address | 8.8.8.8 |
| Remote port | 443 |

Expect: **Access: Allow**

**Test B — RDP from a non-on-prem source should be blocked**

| Field | Value |
|---|---|
| Virtual machine | JPAZVM12 |
| Protocol | TCP |
| Direction | Inbound |
| Local IP address | 10.1.0.4 |
| Local port | 3389 |
| Remote IP address | 203.0.113.10 *(any IP outside your home VLANs works)* |
| Remote port | any |

Expect: **Access: Deny**

**Test C — RDP from on-prem should work**

| Field | Value |
|---|---|
| Virtual machine | JPAZVM12 |
| Protocol | TCP |
| Direction | Inbound |
| Local IP address | 10.1.0.4 |
| Local port | 3389 |
| Remote IP address | 192.168.20.50 |
| Remote port | any |

Expect: **Access: Allow**

## Step 4: NSG Diagnostics (re-validates the same flows, names the matching rule)

1. Portal search bar → **Network Watcher** → left menu **NSG diagnostics**
2. Target `JPAZVM12`, and run the same three flows as Step 3 (same direction, protocol, local/remote IP and port fields)
3. Expect the same Allow/Deny results as IP Flow Verify — the difference is NSG Diagnostics also shows the exact rule name that matched and, if the result is unexpected, suggests a fix

This is the newer of the two rule-evaluation tools and is worth knowing by name for the exam specifically — it overlaps with IP Flow Verify but adds the "what would fix this" suggestion.

## Step 5: Connection Troubleshoot — the one real-traffic test

1. Portal search bar → **Network Watcher** → left menu **Connection troubleshoot**
2. Source: `JPAZVM12`. Destination: `JPAZVM13`. Destination port: `3389`
3. **Check** → expect **Unreachable**

This result is correct, not a failure: `JPNSGSpoke2`'s rules only allow RDP from the hub subnet and from on-prem, not from Spoke1 directly, so `Deny-VirtualNetwork-Inbound` should be catching this. The portal output will name that rule as the reason. This is the only test in the whole Phase 4 pass that sends actual packets across the network rather than simulating a rule evaluation — worth a screenshot for the portfolio specifically because it proves the deny is firing on real traffic, not just evaluated hypothetically.

---

If all five checks above match their expected results, Phase 4 is done — you have live diagnostic evidence, not just configuration, that Phases 1 and 2 work.

**Nothing to clean up afterward** — this phase never deployed anything.
