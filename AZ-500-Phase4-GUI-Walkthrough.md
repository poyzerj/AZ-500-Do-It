# Phase 4 (Visibility & Validation) — Azure Portal Walkthrough

Portal-only equivalent of `Deploy-AZ500-Phase4-NetworkWatcher.ps1`. Resource group throughout: `rg-az500-doit-cus`. Requires Phases 1 and 2 already deployed — this phase validates them, it doesn't build anything from them.

---

## Step 1: Enable NSG Flow Logs

1. Portal search bar → **Network Watcher** → left menu **Logs** → **NSG flow logs** → **+ Create**
2. Fill in:

   | Field | Value |
   |---|---|
   | Subscription / Resource group | rg-az500-doit-cus |
   | NSG | `JPNSGHub` |
   | Flow log storage account | Create new → `jpaz500flowlogs`, Standard LRS |
   | Flow log version | Version 2 |
   | Retention | 7 days |
   | Traffic analytics | Off *(optional — turn on only if you want richer Log Analytics-based views; adds cost)* |

3. **Create**
4. Repeat for `JPNSGSpoke1` and `JPNSGSpoke2`, reusing the same `jpaz500flowlogs` storage account for all three.

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

## Step 4: Review the flow logs

1. Once traffic has generated for a few minutes, go to the `jpaz500flowlogs` storage account → **Containers** → `insights-logs-networksecuritygroupflowevent`
2. Browse into the JSON blobs for one of the NSGs — confirm you can see actual flow records with `A`/`D` (allow/deny) markers matching the tests above. This is the difference between "the rule exists" and "the rule is actually firing" — worth a screenshot for the portfolio write-up.

If all four checks (Next Hop + the three IP Flow Verify tests) match expectations and the flow logs show real entries, Phase 4 is done — you have evidence, not just configuration, that Phases 1 and 2 work.

---

**Cleanup:** run `Remove-AZ500-Phase4-NetworkWatcher.ps1`, or manually delete the three flow log configurations (Network Watcher → NSG flow logs → select each → Disable/Delete) and the `jpaz500flowlogs` storage account. Cost here is minor either way — a few days of small JSON logs in a Standard LRS account is fractions of a cent — but no reason to leave it running indefinitely.
