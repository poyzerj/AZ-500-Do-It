# AZ-500 Lab — Complete Walkthrough (Prerequisite + Phases 1–4)

Resource group throughout: `rg-az500-doit-cus`.

---

## Prerequisite: Redeploy the base environment

Nothing is currently deployed, so start here before Phase 1. Run in order, from a PowerShell 7 session with `Connect-AzAccount` already done:

1. `Deploy-AZ500-Network.ps1` — VNets and subnets
2. `Deploy-AZ500-Peerings.ps1` — hub-spoke peering with gateway transit
3. `Deploy-AZ500-NSGs.ps1` — base NSGs (`JPNSGHub`/`JPNSGSpoke1`/`JPNSGSpoke2`) with the original 4 rules each
4. `Deploy-AZ500-VMs.ps1` — `JPAZVM11`/`JPAZVM12`/`JPAZVM13`
5. `Deploy-AZ500-Gateway.ps1` — VPN Gateway, S2S connection to your FortiGate (takes 30–45 min, fill in `FortiGatePublicIP`/`SharedKey` params first — **use a different value than the domain admin password**, per the Phase 3 write-up)
6. `Deploy-Domain-Join.ps1` — sets DNS to `192.168.40.10`, renews DHCP, joins all three VMs to `poyzerj.local`

Verify: `(Get-ADComputer -Filter * -Server "192.168.40.10").Name` from `POYZERJDC10` should list all three VMs once the joins complete.

---

## Phase 1 — Segmentation (NSGs + ASGs)

**Step 1: Create the three ASGs**
Portal search → **Application security groups** → **+ Create**, resource group `rg-az500-doit-cus`, region Central US:
- `asg-hub-infra`, `asg-spoke1-workload`, `asg-spoke2-workload`

**Step 2: Associate each ASG to its VM's NIC**
**Network interfaces** → `JPAZVM11-nic` → **IP configurations** → click `ipconfig1` → **Application security groups** dropdown → select `asg-hub-infra` → **Save**. Repeat: `JPAZVM12-nic` → `asg-spoke1-workload`, `JPAZVM13-nic` → `asg-spoke2-workload`.

**Step 3: Retarget existing rules on JPNSGHub**
**Network security groups** → `JPNSGHub` → **Inbound security rules**. For `Allow-RDP-From-Hub`, `Allow-RDP-From-Home`, `Allow-Ping-From-Home`, `Allow-DNS-From-Home`: click → **Edit** → Destination: **Application security group** → `asg-hub-infra` → **Save**.

**Step 4: Add deny-by-default rules to JPNSGHub**
**+ Add**, twice:

| Field | Rule A | Rule B |
|---|---|---|
| Name | `Deny-VirtualNetwork-Inbound` | `Deny-Internet-Inbound` |
| Priority | 4000 | 4010 |
| Source | Service Tag: VirtualNetwork | Service Tag: Internet |
| Destination | Service Tag: VirtualNetwork | Any |
| Protocol | Any | Any |
| Action | Deny | Deny |

**Step 5: Repeat for JPNSGSpoke1**
Retarget `Allow-RDP-From-Hub`, `Allow-RDP-From-Home`, `Allow-Ping-From-Home` to `asg-spoke1-workload`. **Delete** `Allow-DNS-From-Home` (unused on spokes). Add the same two deny rules.

**Step 6: Repeat for JPNSGSpoke2**
Same as Step 5, targeting `asg-spoke2-workload`.

**Step 7: Verify**
**Network Watcher** → **IP Flow Verify** → `JPAZVM12`, inbound TCP 3389 from an IP outside `192.168.20.0/24`/`192.168.40.0/24` → expect **Deny**. Same test from an IP inside `192.168.20.0/24` → expect **Allow**.

---

## Phase 2 — Centralized Firewall & Egress Control

**Step 1: Add AzureFirewallSubnet**
`JPVNetHub` → **Subnets** → **+ Subnet** → name **`AzureFirewallSubnet`** (exact name required) → `10.0.2.0/26` → **Save**.

**Step 2: Deploy Azure Firewall**
**Firewalls** → **+ Create**: name `JPAZFW01`, tier **Standard**, policy → create new `JPAZFW01-Policy`, VNet `JPVNetHub`, public IP → new `JPAZFW01-PIP` (Standard SKU). **Create** (5–10 min). Note the **private IP** shown on the firewall's Overview page afterward — expected `10.0.2.4`, but confirm the actual value.

**Step 3: Configure the policy**
`JPAZFW01-Policy` → **Threat intelligence** → mode **Alert** → **Save**. Then **Rule Collection Groups** → **+ Add**: name `rcg-spoke-egress`, priority 200. Inside it:
- Network rule collection `net-allow-required`, priority 100, Allow: source `10.1.0.0/16,10.2.0.0/16` → TCP 443 → destination `*`
- Application rule collection `app-allow-updates`, priority 200, Allow: source `10.1.0.0/16,10.2.0.0/16` → FQDN Tag **WindowsUpdate**

**Step 4: Create route tables**
**Route tables** → **+ Create** → `RT-Spoke1` and `RT-Spoke2`, both in `rg-az500-doit-cus` / Central US.

**Step 5: Add routes**

| Route table | Route name | Prefix | Next hop |
|---|---|---|---|
| RT-Spoke1 | to-Internet | 0.0.0.0/0 | Virtual appliance, firewall private IP |
| RT-Spoke1 | to-Spoke2 | 10.2.0.0/16 | Virtual appliance, firewall private IP |
| RT-Spoke2 | to-Internet | 0.0.0.0/0 | Virtual appliance, firewall private IP |
| RT-Spoke2 | to-Spoke1 | 10.1.0.0/16 | Virtual appliance, firewall private IP |

Don't skip the `/16` routes — without them spoke-to-spoke traffic keeps using the automatic peering route and bypasses the firewall.

**Step 6: Associate route tables**
`RT-Spoke1` → **Subnets** → **Associate** → `JPVNetSpoke1` / `Spoke1Subnet`. `RT-Spoke2` → associate to `JPVNetSpoke2` / `Spoke2Subnet`.

**Step 7: Verify**
**Network Watcher** → **Next Hop**: `JPAZVM12`, source `10.1.0.4`, destination `10.2.0.4` → expect **Virtual Appliance**, matching the firewall's IP. **IP Flow Verify**: `JPAZVM12` outbound to `8.8.8.8:443` → expect **Allow**.

**Cost reminder:** ~$1.25/hr + data processing starts the moment the firewall finishes deploying.

---

## Phase 3 — Secure VPN Connectivity

Nothing to do here — already documented. Your S2S connection (`JPVPNGW` → `JPLNGW`, custom IPsec policy AES256/SHA256/DHGroup14/PFS2048) and P2S (Entra ID auth, OpenVPN, `172.16.20.0/24` client pool) already satisfy this domain skill from the AZ-700 build. Full writeup is in `AZ-500-Lab-Phase3-VPN-Connectivity.md`.

---

## Phase 4 — Visibility & Validation

**Note:** this phase doesn't deploy anything. VNet Flow Logs were evaluated and dropped from the build — raw flow log JSON is painful to review by hand, and the specific IP Flow Verify tests below don't even show up in it (IP Flow Verify simulates a rule evaluation, it never sends a real packet). Network Watcher's diagnostic tools validate the same enforcement more directly and read far better live. Full detail in `AZ-500-Phase4-GUI-Walkthrough.md`; run `Validate-AZ500-Phase4-NetworkWatcher.ps1` to automate all five checks below.

**Step 1: Effective Security Rules**
**Network Watcher** → **Effective security rules** → NIC `JPAZVM12-nic` → confirm `Deny-VirtualNetwork-Inbound`/`Deny-Internet-Inbound` rank above the platform `AllowVnetInBound` default in the combined view — proves Phase 1 actually took on the NIC, not just in the NSG's own rule list.

**Step 2: Next Hop test**
**Network Watcher** → **Next hop**: VM `JPAZVM12`, source `10.1.0.4`, destination `10.2.0.4` → expect **Virtual Appliance** (re-confirms Phase 2).

**Step 3: IP Flow Verify tests**

| Test | Direction | Local | Remote | Expect |
|---|---|---|---|---|
| Outbound internet | Outbound | 10.1.0.4, any port | 8.8.8.8:443 | Allow |
| RDP from non-on-prem | Inbound | 10.1.0.4:3389 | 203.0.113.10 | Deny |
| RDP from on-prem | Inbound | 10.1.0.4:3389 | 192.168.20.50 | Allow |

**Step 4: NSG Diagnostics**
Re-run the same three flows from Step 3 through **Network Watcher** → **NSG diagnostics**. Results should match IP Flow Verify exactly, but this tool also names the specific rule that matched — useful when a result is unexpected and you need to know *which* rule to go fix.

**Step 5: Connection Troubleshoot — the one real-traffic test**
**Network Watcher** → **Connection troubleshoot**: source `JPAZVM12`, destination `JPAZVM13`, port 3389. Expect **Unreachable** — `JPAZVM13`'s NSG only allows RDP from the hub subnet and on-prem, not from Spoke1, so this should get caught by `Deny-VirtualNetwork-Inbound`. Unlike every other test in this phase, this one sends actual packets rather than simulating a rule evaluation — it's the strongest evidence in the whole validation pass that the rule is really enforcing, not just configured.

**Note:** Phase 2's firewall and route tables need to be live for these tests to return the expected results — if Phase 2 has been torn down (`Remove-AZ500-Phase2-Firewall.ps1`) since it was last validated, redeploy it (`Deploy-AZ500-Phase2-Firewall.ps1`) before running Phase 4.

---

## After Phase 4

Report back results (especially anything that didn't match expected — that's often the most useful part to document). That's the full in-scope build — next up is the portfolio write-up and topology diagram update.
