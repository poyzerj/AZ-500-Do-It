# AZ-500 Lab — Screenshot Checklist

Screenshots to capture during tomorrow's Do-It re-run, to add to the AZ-500 Lab portfolio page (`portfolio/AZ-500-Lab/index.md`). Organized by the page's existing sections — everything above "The Three-Layer RDP Mystery" is currently text-only.

## 🔒 Segmentation: NSGs & ASGs
- One NSG's inbound rules list (e.g. `JPNSGSpoke2`) showing the `Deny-VirtualNetwork-Inbound` (4000) and `Deny-Internet-Inbound` (4010) rules layered above the narrow allows — visual proof that peering doesn't segment by default.
- The ASG definitions/membership view (`asg-hub-infra`, `asg-spoke1-workload`, `asg-spoke2-workload`) showing a rule that references an ASG instead of a hardcoded IP.

## 🔥 Centralized Firewall & Egress Control
- The Azure Firewall policy's rule collections: the network rule for HTTPS egress and the application rule allowing Windows Update by FQDN tag.
- The Threat Intelligence setting showing Alert mode.

## ⚠️ The UDR Precedence Gotcha
- Spoke1's (or Spoke2's) effective routes / route table, captured twice if reproducible live:
  - Before the fix: Next Hop showing `VirtualNetwork` (the peering route winning).
  - After the fix: Next Hop showing `VirtualAppliance` (after adding the explicit `/16` UDR).
  - This before/after pair is the whole point of the section.

## 🔐 Secure VPN Connectivity
- Site-to-Site VPN connection status showing Connected, with the IPsec/IKE policy (AES256/SHA256/DH Group 14/PFS2048) visible.
- Point-to-Site configuration showing Entra ID authentication.

## 🔍 Visibility & Validation
- Effective Security Rules output for one VM/NIC.
- IP Flow Verify result (Access: Allow).
- NSG Diagnostics result.
- Next Hop result — clean pass, distinct from the UDR-gotcha before/after pair above (this is the "all five tools returned expected results" validation pass).

## 🚧 The Three-Layer RDP Mystery
Already fully covered by the existing 5 screenshots — no changes needed.
