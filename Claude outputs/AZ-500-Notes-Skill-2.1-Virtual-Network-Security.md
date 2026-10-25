# AZ-500 Study Notes — Skill 2.1: Virtual Network Security

*Source: Chapter 2, "Secure Azure Networks" — covers NSGs/ASGs, UDRs, VNet peering, VPN Gateway, Virtual WAN, VPN connectivity types, ExpressRoute encryption, PaaS firewalls, and Network Watcher.*

---

## Context: Shared Responsibility Model

- CSP (Microsoft) and customer split security responsibility differently depending on service category.
- **IaaS** → customer owns a long list of responsibilities (OS, network config, etc.).
- **PaaS** → customer still has some responsibilities, but far fewer than IaaS.
- Azure's native platform security capabilities exist to help cover both, while keeping the management layer secure.

---

## Network Security Groups (NSGs)

An NSG filters traffic with allow/deny rules — think of it as a modern VLAN equivalent.

**Where you can apply an NSG:**
- On a **subnet** — secures everything in that subnet with one rule set.
- On a **network interface (NIC)** — per-VM control.
- Both can be used together.

**Evaluation order:**
- **Inbound traffic:** subnet NSG rules evaluated first, then NIC NSG rules.
- **Outbound traffic:** NIC NSG rules evaluated first, then subnet NSG rules.

**Rule parameters (5-tuple + metadata):**

| Parameter | Notes |
|---|---|
| Name | Rule identifier |
| Priority | 100–4096; **lower number = higher priority = evaluated first**; traffic stops evaluating once a match is found |
| Source | IP, CIDR block, Service Tag, or ASG |
| Destination | IP, CIDR block, Service Tag, or ASG |
| Protocol | TCP, UDP, ICMP, or Any |
| Port Range | Single port or range |
| Action | Allow or Deny |

### Default rules (auto-created, cannot be deleted — only overridden with a lower-numbered rule)

**Inbound:**

| Name | Priority | Source | Destination | Action |
|---|---|---|---|---|
| AllowVNetInBound | 65000 | VirtualNetwork | VirtualNetwork | Allow |
| AllowAzureLoadBalancerInBound | 65001 | AzureLoadBalancer | 0.0.0.0/0 | Allow |
| DenyAllInbound | 65500 | 0.0.0.0/0 | 0.0.0.0/0 | Deny |

**Outbound:**

| Name | Priority | Source | Destination | Action |
|---|---|---|---|---|
| AllowVnetOutBound | 65000 | VirtualNetwork | VirtualNetwork | Allow |
| AllowInternetOutBound | 65001 | 0.0.0.0/0 | Internet | Allow |
| DenyAllOutBound | 65500 | 0.0.0.0/0 | 0.0.0.0/0 | Deny |

> **Key exam point:** `AllowVNetInBound` is exactly the rule that makes peered VNets *not* segmented by default — anything inside the virtual network address space is allowed in unless you add your own lower-priority deny rule above it.

> **Traffic interruption note:** removing a security rule that allowed an *existing* connection doesn't necessarily kill it immediately — an interruption only happens once there's no traffic in either direction for a few minutes.

### Creating an NSG

**Portal:** Network Security Groups → Add → set Subscription / Resource Group / Name / Region → Review + Create.

**PowerShell:**
```powershell
New-AzNetworkSecurityGroup -Name "AZ500NSG" -ResourceGroupName "AZ500RG" -Location "westus"
```

**Adding an inbound rule (portal):** NSG → Inbound Security Rules → Add → set Source / Source Port Range / Destination / Destination Port Range / Protocol / Action / Priority / Name.

**PowerShell equivalent:**
```powershell
$MyRule1 = New-AzNetworkSecurityRuleConfig -Name ftp-rule -Description "Allow FTP" `
  -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix * `
  -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 21
```

An NSG does nothing until it's **associated** to a subnet or NIC (Portal: NSG → Subnets → Associate → pick VNet, then subnet).

---

## Application Security Groups (ASGs)

- Group VMs by **application role/workload** instead of hardcoded IPs — an extra micro-segmentation layer.
- Used as the source and/or destination in an NSG rule.
- **You can only specify one ASG as source and one ASG as destination per rule** — not multiple ASGs on either side.
- Benefits: fewer NSGs needed overall (one NSG can cover multiple subnets, with ASGs doing the fine-grained split); supports a Zero Trust posture by only permitting explicitly defined application flows.
- A VM with multiple workloads (e.g., web + SQL) can belong to multiple ASGs — each workload gets its own access rules.

**Creating an ASG (portal):** Application Security Groups → Create → Subscription / Resource Group / Name / Region → Review + Create.

**PowerShell:**
```powershell
New-AzApplicationSecurityGroup -ResourceGroupName "MyRG" -Name "MyASG" -Location "West US"
```

Associating to a VM: VM → Networking → Network Settings → Configure (Application Security Group) → Add Application Security Groups → select ASG.

---

## User-Defined Routes (UDRs)

### VNet / subnet fundamentals
- A VNet is scoped to a **single region**. Cross-region connectivity needs VNet Peering.
- VNets are subdivided into **subnets**, each of which can carry its own NSG.
- NSG rules use 5-tuple matching (source addr, source port, dest addr, dest port, protocol) and track flow state for existing connections.

### Default system routes (auto-created per subnet, cannot be removed)
- When you create a VNet, Azure creates a route for **each address range defined in the VNet's address space** — if the VNet has multiple address ranges, that's an individual route per range, not just one route for the whole VNet.
- These routes are what make **inter-subnet routing automatic**: you never have to define routes between subnets within the same VNet yourself, and — unlike a physical network — you don't need to configure gateways for Azure to route traffic between subnets. It's handled for you.
- In the Azure route table UI, this route shows as: **Source** = `Default`, **Address prefix** = unique to the virtual network, **Next hop type** = `Virtual network`.
- **Internet default route:** `0.0.0.0/0` → Internet, *unless* the destination is an Azure service, in which case Azure routes over its backbone instead.
- Azure also auto-adds routes when:
  - **VNet peering is created** — a route per peered address range.
  - **A Virtual Network Gateway is added** — route(s) with next hop = the gateway.
  - **A Service Endpoint is enabled** — the service's public IPs get added to the route table.
- `Next Hop Type = None` → traffic is silently dropped (useful as a deliberate block).
- Default routes are also auto-created for `10.0.0.0/8`, `192.168.0.0/16` (RFC 1918), and `100.64.0.0/10` (RFC 6598).

### When to create a custom route
Only when you need to **override** default behavior — classic example: point the default route (`0.0.0.0/0`) at a **network virtual appliance (NVA)** or **Azure Firewall** so it can inspect traffic before it's forwarded or dropped. Also used to keep certain traffic from ever reaching the Internet.

**Valid next-hop types for a UDR:**
- Virtual appliance
- Virtual network gateway
- None (drop)
- Virtual network
- Internet

**Creating a custom route (PowerShell), 3 steps:**
```powershell
# 1. Create the route table
$routeTableAZ500 = New-AzRouteTable -Name 'AZ500RouteTable' -ResourceGroupName ContosoCST -location EastUS

# 2. Add a route to it
Get-AzRouteTable -ResourceGroupName "ContosoCST" -Name "AZ500RouteTable" `
  | Add-AzRouteConfig -Name "ToAZ500Subnet" -AddressPrefix 10.0.1.0/24 `
  -NextHopType "MyVirtualAppliance" -NextHopIpAddress 10.0.2.4 `
  | Set-AzRouteTable

# 3. Associate the route table with a subnet
Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $virtualNetwork -Name 'CustomAZ500Subnet' `
  -AddressPrefix 10.0.0.0/24 -RouteTable $routeTableAZ500 | Set-AzVirtualNetwork
```

- A subnet can be linked to **only one route table**.
- **On conflict, user-defined routes win over default system routes.** (This is the exact mechanic behind "the more specific explicit route beats the automatic one" — matches what you validated in Phase 2.)

> **Exam tip:** expect routing scenario questions that hinge on a missing or misconfigured route — read carefully for what's *not* configured.

### VNet Peering
- Connects VNets — same region, or cross-region (**Global VNet Peering**).
- Same-region peered traffic has the same latency as within a single VNet.
- Traffic between peered VNets does **not** go through a gateway or the public Internet — it's routed over the Microsoft backbone directly.

**Peering options (each is a checkbox when creating the peering):**

| Option | What it does |
|---|---|
| Allow [VNet] to access the peered VNet | Default on; enables basic bidirectional reachability (hub-spoke communication) |
| Allow [VNet] to receive forwarded traffic from the peered VNet | Lets traffic that arrived at the peered VNet *from somewhere else* continue on into this VNet. Doesn't create UDRs or NVAs itself — those are separate. |
| Allow gateway/route server in [VNet] to forward traffic to the peered VNet | Only relevant if this VNet has a gateway/route server |
| Enable [VNet] to use the peered VNet's remote gateway/route server | Only usable if the *peered* VNet has a gateway and has enabled the option above; can only be enabled on one side of a peering |

**PowerShell:**
```powershell
Add-AzVirtualNetworkPeering -Name 'NameOfTheVNetPeering' -VirtualNetwork SourceVNet -RemoteVirtualNetworkId RemoteVNet
```

**Hub-spoke topology:** the hub VNet is the central connectivity point to on-prem; spokes peer to the hub, gaining isolation/security boundaries from each other. A site-to-site connection requires a dedicated **gateway subnet** in the hub, and all on-prem traffic flows through it.

---

## VPN Gateway / Virtual Network Gateway

- A gateway = two or more VMs deployed into a dedicated **GatewaySubnet** — fully managed, no direct OS access.
- **One virtual network gateway per VNet**, and the gateway type is either **VPN** or **ExpressRoute** (not both). You *can* create multiple connections off the same gateway.

**Connection types:**

| Type | Use case | Protocol |
|---|---|---|
| Point-to-Site (P2S) | Individual remote users connecting to the VNet | SSTP or IKEv2; no VPN device needed |
| Site-to-Site (S2S) | On-prem network to Azure | IPsec (IKEv1 or IKEv2) |
| VNet-to-VNet | Encrypt connectivity between two VNets | IPsec (IKEv1 or IKEv2) |
| Multi-Site | Multiple on-prem sites into one VNet | Extension of S2S |

**ExpressRoute** is the alternative to VPN — private WAN connection to Azure, not over the public Internet.

### VPN authentication
- Azure auto-generates a **pre-shared key (PSK)** at tunnel creation — ASCII, ≤128 characters. Applies to both policy-based and route-based VPNs.
  ```powershell
  Get-AzVirtualNetworkGatewayConnectionSharedKey   # view
  Set-AzVirtualNetworkGatewayConnectionSharedKey   # change
  ```
- **P2S authentication options:**
  - **Azure certificate** — client cert from an enterprise CA or a self-signed root cert.
  - **RADIUS** — also supports IKEv2/SSTP; **only available on VpnGw1/2/3 SKUs**.
  - **Azure AD (Entra ID)** — **OpenVPN protocol only**; Windows 10 requires the Azure VPN Client.
- Can layer **MFA via Conditional Access** scoped just to VPN users, without requiring MFA org-wide.
- Config fields differ by method: Azure cert → root/revoked cert data; RADIUS → server IP + secret; Azure AD → tenant URL, Audience, Issuer, tenant selection.

> **Scenario cue from the book:** "needs to integrate with an existing RADIUS/certificate infrastructure" → RADIUS authentication. "Azure VPN gateway itself must perform cert validation" → native Azure certificate authentication.

### Point-to-Site protocol comparison

| Protocol | Advantages | Limitations |
|---|---|---|
| **OpenVPN** | TLS-based, traverses most firewalls; broad OS support (Android, iOS 11+, Windows, Linux, macOS 10.13+) | No Basic SKU; not available on classic deployment model |
| **SSTP** | Traverses most firewalls (TCP 443) | Windows only; capped at 128 concurrent connections regardless of gateway SKU |
| **IKEv2** | Standards-based IPsec; supports macOS 10.11+ | No Basic SKU; not on classic deployment model; uses nonstandard UDP 500/4500 — must not be blocked on the client firewall |

> **Exam tip:** read VPN scenario questions closely for which protocol is *ruled out* by client OS, SKU, or firewall constraints — that's usually the actual test.

### Site-to-Site prerequisites
- Compatible on-prem VPN device (policy-based or route-based).
- Externally-facing public IPv4 address.
- On-prem address range that Azure can route to.

---

## Virtual WAN (including secured virtual hub)

- Hub-and-spoke architecture at global scale: branch offices (VPN/SD-WAN devices), end users (P2S/OpenVPN/IKEv2 clients), HQ (ExpressRoute), and VNets all connect into regional **hubs**.
- Hubs are connected in a **full mesh** over the Microsoft backbone in a standard Virtual WAN.

**Planning considerations:**
- Partner NVAs (Barracuda, Cisco, VMware, Versa Networks, Aruba) can deploy directly into a Virtual WAN hub — but a partner isn't required; any IKEv1/IKEv2-IPsec-compliant VPN device works.
- **1,000 connections per virtual hub** limit.
- One on-prem VPN device can connect to **multiple hubs** (via the closest Microsoft network edge, then to the hub).
- An NVA can be deployed **inside** a virtual hub.
- A spoke VNet connected to a virtual hub **cannot** also have its own VNet gateway, and **cannot** have a route server.
- BGP is supported for VPN connectivity.
- ExpressRoute per-site is **not** required.
- Multiple virtual hubs are allowed in the same region.
- Default hub routing preference favors **ExpressRoute over VPN** for egress (customizable).
- Portal-created hubs must share the Virtual WAN's resource group; cross-resource-group hubs require **PowerShell**.

---

## Encryption over ExpressRoute

Two independent encryption options — can be combined for both layers:

| | MACsec | IPsec |
|---|---|---|
| Layer | 2 (MAC-level) | 3 (IP-level) |
| Scope | Encrypts **everything** including BGP control traffic — all-or-nothing per circuit | End-to-end, e.g. on-prem to VNet |
| Requires | **ExpressRoute Direct** only; disabled by default | No ExpressRoute Direct requirement |
| Key management | Bring your own key, stored in **Azure Key Vault**; you own rotation | N/A |

> **Caution:** MACsec is pre-shared-key only, so a key update must happen on **both sides** — a mismatch breaks traffic, and connectivity is temporarily lost during rotation. Plan a maintenance window.

---

## Firewall Settings on PaaS Resources

Example used in the text: **Azure Storage firewall.**

- Network rules restrict which IPs/ranges/VNet subnets can reach the storage account.
- Enforced across **all protocols** used to reach the account (REST, SMB).
- **Default configuration allows all networks** — should be tightened.

**Portal:** Storage Account → Networking → Firewalls and Virtual Networks:
- **Public Network Access:** All networks (default) / Selected networks + IPs (for custom rules) / Disabled (most restrictive).
- **Network Routing:** Microsoft Network Routing (enters Microsoft's network near the client) vs. Internet Routing (enters near the storage endpoint).

**PowerShell (quick lockdown):**
```powershell
Update-AzStorageAccountNetworkRuleSet -ResourceGroupName "MyRG" -Name "mystorage" -DefaultAction Deny
```

---

## Network Watcher

**Scope:** built for **IaaS** monitoring/diagnostics (VMs, VNets, App Gateways, load balancers) — **not** for PaaS resources or web analytics.

| Capability | Category | What it does |
|---|---|---|
| Connection Monitor | Monitoring | End-to-end connection monitoring; hybrid + Azure-native |
| Topology | Monitoring | Visual map of network infrastructure across subscriptions/RGs/regions |
| NSG Diagnostics | Diagnostic | Debug traffic permission logic; verify NSG rule correctness; also suggests a fix (e.g., a higher-priority rule) when a flow is unexpectedly blocked |
| **IP Flow Verify** | Diagnostic | Answers allow/deny for a specific packet against NSG + AVNM admin rules — fast connectivity troubleshooting. Purely a rule-evaluation simulation; sends no real traffic |
| Effective Security Rules | Diagnostic | Shows the *combined* inbound/outbound rules actually enforced on a NIC (security + admin rules together) |
| Packet Capture | Diagnostic | Captures traffic to/from a VM or scale set — anomaly diagnosis, stats, intrusion ID, client-server debugging |
| VPN Troubleshoot | Diagnostic | Diagnose gateway/connection issues — Portal, PowerShell, CLI, or REST |
| **Next Hop** | Diagnostic | Shows next hop type, IP, and route table ID for a destination — confirms whether traffic is routed as intended or blocked |
| Connection Troubleshoot | Diagnostic | Streamlines root-cause diagnosis; distinguishes platform issues from user misconfiguration. Unlike IP Flow Verify/NSG Diagnostics, this one actually sends real probe traffic |
| Flow Logs | Traffic | Definitive record of all network activity — throughput, compliance, intrusion detection. NSG Flow Logs no longer accept new creation (retiring Sept 30, 2027); Virtual Network Flow Logs is the replacement |
| Traffic Analytics | Traffic | Analyzes flow logs for traffic pattern/dynamics insight |

> **Exam tip:** questions tend to hinge on picking the *right* diagnostic tool for the scenario — e.g., "did the packet get through" → IP Flow Verify; "which route is actually winning" → Next Hop; "what's the combined rule set on this NIC" → Effective Security Rules; "which rule should I add to fix this" → NSG Diagnostics; "is this actually reachable right now" → Connection Troubleshoot (the only one of these five that sends real traffic).

---

## Cross-references to your own Do-It project

- Your Phase 1 NSG/ASG work is a direct, hands-on application of the `AllowVNetInBound`-override pattern and the ASG-as-destination pattern described here.
- Your Phase 2 UDR work (the `/16` routes beating the automatic peering route) is the exact "user-defined routes take precedence over default routes" rule from the UDR section — and the reason it needed *both* a `0.0.0.0/0` route and an explicit per-spoke route to a virtual appliance next hop.
- Your Phase 3 documentation maps directly onto the P2S/S2S sections — custom IPsec/IKE policy, Entra ID P2S auth (OpenVPN-only, matching the book's note).
- Your Phase 4 Network Watcher work used five of the tools in the capability table above: **IP Flow Verify**, **Next Hop**, **Effective Security Rules**, **NSG Diagnostics**, and **Connection Troubleshoot** — deliberately skipping Flow Logs/Traffic Analytics, since the diagnostic tools alone proved enforcement live and flow log JSON doesn't review well by hand.
