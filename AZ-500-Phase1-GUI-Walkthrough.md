# Phase 1 (Segmentation) — Azure Portal Walkthrough

Portal-only equivalent of `Deploy-AZ500-Phase1-Segmentation.ps1`. Follow in order — later steps assume the ASGs from Step 1 already exist. Resource group throughout: `rg-az500-doit-cus`.

---

## Step 1: Create the three Application Security Groups

1. Portal search bar → **Application security groups** → **+ Create**
2. Fill in for each of the three:

   | Field | ASG 1 | ASG 2 | ASG 3 |
   |---|---|---|---|
   | Resource group | rg-az500-doit-cus | rg-az500-doit-cus | rg-az500-doit-cus |
   | Name | `asg-hub-infra` | `asg-spoke1-workload` | `asg-spoke2-workload` |
   | Region | Central US | Central US | Central US |

3. **Review + create** → **Create** for each.

## Step 2: Associate each ASG to its VM's NIC

1. Portal search bar → **Network interfaces** → select `JPAZVM11-nic`
2. Left menu → **IP configurations**
3. Click the `ipconfig1` row to expand it
4. Under **Application security groups**, click the dropdown and select `asg-hub-infra`
5. **Save**
6. Repeat for `JPAZVM12-nic` → `asg-spoke1-workload`, and `JPAZVM13-nic` → `asg-spoke2-workload`

## Step 3: Retarget existing rules on JPNSGHub

1. Portal search bar → **Network security groups** → `JPNSGHub`
2. Left menu → **Inbound security rules**
3. For each rule below, click it → **Edit** → change **Destination** from *Any* to **Application security group** → select `asg-hub-infra` in the field that appears → **Save**:
   - `Allow-RDP-From-Hub`
   - `Allow-RDP-From-Home`
   - `Allow-Ping-From-Home`
   - `Allow-DNS-From-Home`

## Step 4: Add deny-by-default rules to JPNSGHub

Still on `JPNSGHub` → **Inbound security rules** → **+ Add**, twice:

**Rule A**
| Field | Value |
|---|---|
| Source | Service Tag |
| Source service tag | VirtualNetwork |
| Source port ranges | * |
| Destination | Service Tag |
| Destination service tag | VirtualNetwork |
| Destination port ranges | * |
| Protocol | Any |
| Action | Deny |
| Priority | 4000 |
| Name | `Deny-VirtualNetwork-Inbound` |

**Rule B**
| Field | Value |
|---|---|
| Source | Service Tag |
| Source service tag | Internet |
| Source port ranges | * |
| Destination | Any |
| Destination port ranges | * |
| Protocol | Any |
| Action | Deny |
| Priority | 4010 |
| Name | `Deny-Internet-Inbound` |

## Step 5: Repeat Steps 3–4 for JPNSGSpoke1, with one difference

1. `Network security groups` → `JPNSGSpoke1` → **Inbound security rules**
2. Retarget destination to **Application security group → `asg-spoke1-workload`** for:
   - `Allow-RDP-From-Hub`
   - `Allow-RDP-From-Home`
   - `Allow-Ping-From-Home`
3. **Delete** `Allow-DNS-From-Home` entirely (right-click the rule → Delete) — it's unused on the spokes
4. Add the same two deny rules as Step 4 (`Deny-VirtualNetwork-Inbound` priority 4000, `Deny-Internet-Inbound` priority 4010)

## Step 6: Repeat Step 5 for JPNSGSpoke2

Same as Step 5, but target `JPNSGSpoke2` and `asg-spoke2-workload`.

## Step 7: Verify

1. Portal search bar → **Network Watcher** → **IP Flow Verify** (left menu, under "Network diagnostic tools")
2. Pick `JPAZVM12`, direction Inbound, protocol TCP, remote IP = an address **not** in `192.168.20.0/24` or `192.168.40.0/24`, port 3389 → **Check** → should return **Deny** (rule `Deny-VirtualNetwork-Inbound` or `Deny-Internet-Inbound`, depending on the test IP)
3. Repeat with a remote IP inside `192.168.20.0/24` → should return **Allow** (rule `Allow-RDP-From-Home`)

If both checks come back as expected, Phase 1 is done — move on to Phase 2 (Azure Firewall + UDRs) when ready.

---

**To undo everything in this walkthrough:** run `Remove-AZ500-Phase1-Segmentation.ps1`, or reverse Steps 1–6 manually (delete the two deny rules, retarget the four rules back to "Any", re-add `Allow-DNS-From-Home` to both spokes, remove the ASG associations from each NIC, then delete the three ASGs).
