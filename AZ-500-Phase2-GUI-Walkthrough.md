# Phase 2 (Centralized Firewall & Egress Control) — Azure Portal Walkthrough

Portal-only equivalent of `Deploy-AZ500-Phase2-Firewall.ps1`. Resource group throughout: `rg-az500-doit-cus`. This phase bills hourly once the firewall is deployed — see the cost note at the end.

---

## Step 1: Add the AzureFirewallSubnet

1. Portal search bar → **Virtual networks** → `JPVNetHub`
2. Left menu → **Subnets** → **+ Subnet**
3. Name: **`AzureFirewallSubnet`** (must be this exact name — Azure Firewall requires it)
4. Address range: `10.0.2.0/26`
5. **Save**

## Step 2: Deploy Azure Firewall

1. Portal search bar → **Firewalls** → **+ Create**
2. Fill in:

   | Field | Value |
   |---|---|
   | Resource group | rg-az500-doit-cus |
   | Name | `jpaz500fw` |
   | Region | Central US |
   | Firewall tier | Standard |
   | Firewall management | Use a Firewall Policy to manage this firewall |
   | Firewall policy | Create new → name `jpaz500fw-policy` |
   | Virtual network | Use existing → `JPVNetHub` |
   | Public IP address | Add new → name `jpaz500fw-pip`, Standard SKU |

3. **Review + create** → **Create**. This takes 5–10 minutes to provision.
4. Once deployed, open the firewall resource → **Overview** → note the **Private IP address** shown (expected `10.0.2.4`, but confirm the actual value — you'll need it in Step 4).

## Step 3: Configure the firewall policy rules

1. Portal search bar → **Firewall Policies** → `jpaz500fw-policy`
2. Left menu → **Settings** → **Threat intelligence** → set mode to **Alert** → **Save**
3. Left menu → **Rules** → **Rule Collection Groups** → **+ Add a rule collection group**
   - Name: `rcg-spoke-egress`
   - Priority: `200`
4. Inside it, **+ Add rule collection** (first one):
   - Rule collection type: **Network**
   - Name: `net-allow-required`, Priority: `100`, Action: **Allow**
   - Rule: Name `allow-https-egress`, Source type IP Address, Source `10.1.0.0/16,10.2.0.0/16`, Protocol TCP, Destination Ports `443`, Destination Type IP Address, Destination `*`
5. **+ Add rule collection** (second one):
   - Rule collection type: **Application**
   - Name: `app-allow-updates`, Priority: `200`, Action: **Allow**
   - Rule: Name `allow-windows-update`, Source `10.1.0.0/16,10.2.0.0/16`, Rule type **FQDN Tag**, Target: **WindowsUpdate**
6. **Add** to save the rule collection group.

## Step 4: Create the route tables

Repeat for both:

| Field | rt-spoke1 | rt-spoke2 |
|---|---|---|
| Resource group | rg-az500-doit-cus | rg-az500-doit-cus |
| Name | `rt-spoke1` | `rt-spoke2` |
| Region | Central US | Central US |

1. Portal search bar → **Route tables** → **+ Create** → fill in table above → **Review + create** → **Create**

## Step 5: Add routes

Open `rt-spoke1` → left menu **Routes** → **+ Add**, twice:

| Field | Route 1 | Route 2 |
|---|---|---|
| Route name | `to-Internet` | `to-Spoke2` |
| Address prefix | `0.0.0.0/0` | `10.2.0.0/16` |
| Next hop type | Virtual appliance | Virtual appliance |
| Next hop address | *(firewall private IP from Step 2)* | *(firewall private IP from Step 2)* |

Open `rt-spoke2` → **Routes** → **+ Add**, twice:

| Field | Route 1 | Route 2 |
|---|---|---|
| Route name | `to-Internet` | `to-Spoke1` |
| Address prefix | `0.0.0.0/0` | `10.1.0.0/16` |
| Next hop type | Virtual appliance | Virtual appliance |
| Next hop address | *(firewall private IP)* | *(firewall private IP)* |

**Don't skip the `/16` routes** — without them, spoke-to-spoke traffic keeps using the automatic peering route (same prefix length, and a system route without a competing UDR wins), silently bypassing the firewall even with the `0.0.0.0/0` route in place.

## Step 6: Associate route tables to the spoke subnets

1. Still on `rt-spoke1` → left menu **Subnets** → **Associate**
2. Virtual network: `JPVNetSpoke1`, Subnet: `Spoke1Subnet` → **OK**
3. Repeat on `rt-spoke2` → associate to `JPVNetSpoke2` / `Spoke2Subnet`

## Step 7: Verify

1. Portal search bar → **Network Watcher** → **Next Hop**
2. VM: `JPAZVM12`, Source IP: `10.1.0.4`, Destination IP: `10.2.0.4` → **Next hop** should return **Virtual Appliance**, IP matching the firewall's private IP
3. Repeat for `JPAZVM13` → `10.1.0.4` — same expected result
4. **IP Flow Verify**: from `JPAZVM12`, outbound TCP to `8.8.8.8:443` → should return **Allow**, routed through the firewall

If both come back as expected, Phase 2 is done. On-premises-bound traffic hasn't changed — it still goes over the existing Gateway Transit path.

---

**Cost note:** Azure Firewall Standard bills roughly $1.25/hour plus data processing charges, starting from the moment it finishes deploying — this is unlike Phase 1's free ASGs/NSGs. When you're done working with it, run `Remove-AZ500-Phase2-Firewall.ps1` or tear it down manually (delete the route table associations and route tables, delete the firewall, then its policy, then its public IP, then remove `AzureFirewallSubnet`) rather than leaving it running.
