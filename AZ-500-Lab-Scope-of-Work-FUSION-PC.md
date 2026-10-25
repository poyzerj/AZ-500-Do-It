# Scope of Work: Securing the Hub-Spoke — AZ-500 Network Security Lab

**Prepared by:** Joe Poyzer
**Date:** August 16, 2026
**Environment:** `rg-az500-doit-cus` (Microsoft Azure)
**Related certification:** Microsoft Certified: Azure Security Engineer Associate (AZ-500)

---

## 1. Background

In preparation for the AZ-700 (Azure Network Engineer Associate) certification, a hub-spoke virtual network environment was built and documented, consisting of a hub VNet with a Virtual Network Gateway, two peered spoke VNets, Site-to-Site VPN connectivity to an on-premises FortiGate firewall, and Point-to-Site VPN access authenticated through Microsoft Entra ID.

This project reuses that environment as the foundation for a second, security-focused build: applying the Secure Networking domain of the AZ-500 (Azure Security Engineer Associate) exam — the largest single domain within that certification at 20–25% of exam weight — to a real, previously-built topology rather than a standalone lab exercise. The resource group and supporting deployment scripts have been renamed from the AZ-700 naming convention to reflect this project (`rg-az700-doit-cus` → `rg-az500-doit-cus`).

## 2. Objectives

- Apply defense-in-depth network security controls to an existing hub-spoke topology
- Demonstrate hands-on proficiency with the AZ-500 Secure Networking domain, specifically: NSGs and ASGs, Azure Firewall and Firewall Manager, user-defined routes, VPN connectivity security, and Network Watcher
- Produce a documented, portfolio-ready case study suitable for technical interviews and professional review

## 3. Scope

### 3.1 In Scope

| Phase | Work |
|---|---|
| 1. Segmentation | Apply deny-by-default Network Security Group rules to `JPNSGHub`, `JPNSGSpoke1`, and `JPNSGSpoke2`; introduce Application Security Groups to group VMs by role instead of hardcoded IP references; restrict management ports (RDP/SSH) to on-premises VPN source ranges only |
| 2. Centralized Firewall & Egress Control | Deploy Azure Firewall in the hub VNet; manage configuration through Azure Firewall Manager and a firewall policy (network rules, application/FQDN rules, threat intelligence filtering); update spoke user-defined routes so spoke-to-internet and spoke-to-spoke traffic routes through the firewall |
| 3. Secure VPN Connectivity | Document the existing Site-to-Site (on-premises FortiGate) and Point-to-Site (Entra ID–authenticated) VPN connections established during the AZ-700 project, mapped explicitly to this domain's requirements — no new build required |
| 4. Visibility & Validation | Use Network Watcher's diagnostic tools — IP Flow Verify, Next Hop, Effective Security Rules, NSG Diagnostics, and Connection Troubleshoot — to confirm segmentation and firewall rules are enforcing as intended. Validation-only: nothing is deployed in this phase |

**Additional deliverable:** a portfolio write-up published at poyzerj.com, following the existing site's lab-documentation format, plus an updated topology diagram reflecting the AZ-500 naming and new components.

### 3.2 Out of Scope

The following AZ-500 domains and features were deliberately excluded to keep this project focused on network security specifically, rather than a general security survey:

- **Secure identity and access** — Conditional Access, Privileged Identity Management, Identity Protection
- **Microsoft Defender for Cloud and Microsoft Sentinel** — SOC/security-operations tooling
- **Data protection** — Key Vault, secrets management
- **Private access to PaaS resources** — Private Endpoints, Service Endpoints, Private Link (a valid AZ-500 topic, intentionally deferred to keep scope centered on the core network-perimeter controls above)
- **Web-facing workload protection** — WAF, Application Gateway, Azure Front Door (no public-facing web workload exists in this environment)
- **Virtual WAN / secured virtual hub** — considered as a scale-out extension; not included in this phase of work
- **DDoS Protection evaluation** — originally scoped as Phase 5; descoped as it doesn't align with AZ-500 exam objective 2.1, the specific skill this project is built to demonstrate
- **VNet Flow Logs** — evaluated for Phase 4, then dropped from the build after actually running it: the raw flow log JSON is painful to review by hand (deeply nested, no simple allow/deny field — VNet flow logs fold that into a single flow-state value instead), and it doesn't even capture IP Flow Verify's own test traffic, since IP Flow Verify never sends a real packet. Network Watcher's other diagnostic tools (IP Flow Verify, Next Hop, Effective Security Rules, NSG Diagnostics, Connection Troubleshoot) validate the same enforcement just as directly and present far better live, so flow logging was left out rather than added as a sixth validation method

## 4. Approach

Work proceeds sequentially through the four in-scope phases. Each phase is executed directly against the live Azure environment, with configuration decisions, unexpected behavior, and troubleshooting captured as they occur — consistent with how the AZ-700 and AVD lab projects on this portfolio were documented. Phase 3 is a documentation-only phase, since the underlying VPN connectivity already exists from prior work.

## 5. Environment & Prerequisites

- Resource group: `rg-az500-doit-cus`
- Existing resources: `JPVNetHub` (hub), `JPVNetSpoke1`, `JPVNetSpoke2` (spokes), Virtual Network Gateway, `JPNSGHub`/`JPNSGSpoke1`/`JPNSGSpoke2`, VMs `JPAZVM11`/`JPAZVM12`/`JPAZVM13`
- On-premises: FortiGate firewall (`JPHOMEFW`) and FortiSwitch (`JPHOMESW`), Hyper-V host running domain controller `POYZERJDC10` and workstations, domain `poyzerj.local`
- Tooling: Azure PowerShell (Az module) or Azure CLI, deployment/teardown scripts maintained under `AZ-500 Do-It\Deploy` and `AZ-500 Do-It\Remove`

## 6. Deliverables

1. Hardened NSG/ASG configuration across the hub and both spokes
2. Deployed Azure Firewall with centralized egress and inter-spoke traffic filtering
3. Updated UDRs enforcing firewall-routed traffic
4. Written mapping of existing VPN connectivity to AZ-500 Secure Networking requirements
5. Network Watcher–based validation evidence (IP Flow Verify, Next Hop, Effective Security Rules, NSG Diagnostics, and Connection Troubleshoot results)
6. Published portfolio case study at poyzerj.com/portfolio, matching existing site format
7. Updated topology diagram (`AZ500-Do-It-Topology`)

## 7. Success Criteria

- NSGs/ASGs enforce least-privilege segmentation, confirmed via Network Watcher rather than assumed from configuration alone
- Azure Firewall actively filters and logs egress and inter-spoke traffic; UDRs confirmed to route traffic through it rather than directly
- Management access (RDP/SSH) confirmed reachable only from on-premises VPN source ranges
- Portfolio page is published and linked from the site's Portfolio index

## 8. Assumptions & Constraints

- This is a self-directed, self-funded home/cloud lab; cost-conscious decisions are evaluated explicitly rather than deployed by default
- The existing AZ-700 hub-spoke environment is reused as-is rather than rebuilt from scratch
- Work is self-paced around full-time employment, with no fixed delivery date
- The AZ-500 exam is scheduled to retire August 31, 2026; this project supports the underlying skill set regardless of exam timing and is not contingent on exam scheduling

## 9. Estimated Effort

| Phase | Estimate |
|---|---|
| 1. Segmentation | 2–3 hours |
| 2. Centralized Firewall & Egress Control | 3–4 hours |
| 3. Secure VPN Connectivity (documentation only) | 0.5–1 hour |
| 4. Visibility & Validation | 1–2 hours |
| Portfolio write-up & diagram update | 2–3 hours |
| **Total** | **~8.5–13 hours** |
