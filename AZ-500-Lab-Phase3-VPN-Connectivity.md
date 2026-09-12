# Phase 3 — Secure VPN Connectivity

**Status:** No new build required. This phase documents existing infrastructure against the AZ-500 Secure Networking domain skill: *"Secure VPN connectivity, including point-to-site and site-to-site."*
**Artifact:** `Deploy-AZ500-Gateway.ps1`

---

## Site-to-Site VPN

| Component | Configuration |
|---|---|
| Virtual Network Gateway | `JPVPNGW` — SKU `VpnGw1AZ` (zone-redundant), route-based, Generation1 |
| Gateway Public IP | `JPVPNGW-PIP` — Standard SKU, zone-redundant (zones 1, 2, 3) |
| Local Network Gateway | `JPLNGW` — represents the on-premises FortiGate, covering both home VLANs (`192.168.20.0/24`, `192.168.40.0/24`) |
| Connection | `JPAZ-to-JPHome` — IPsec, custom policy (not platform defaults) |

**IPsec/IKE policy** — deliberately hardened rather than left at Azure's defaults:

| Setting | Value |
|---|---|
| IKE Encryption | AES256 |
| IKE Integrity | SHA256 |
| IPsec Encryption | AES256 |
| IPsec Integrity | SHA256 |
| DH Group | DHGroup14 |
| PFS Group | PFS2048 |
| SA Lifetime | 27,000 seconds / 102,400,000 KB |

Using a custom policy here — rather than accepting Azure's default proposal — is itself a Secure Networking-relevant decision: it guarantees a known-strong cipher suite on both ends rather than whatever the platform negotiates by default.

## Point-to-Site VPN

| Setting | Value |
|---|---|
| Protocol | OpenVPN |
| Authentication | Microsoft Entra ID (Azure AD), via an Azure VPN enterprise app |
| Client address pool | `172.16.20.0/24` |

Entra ID authentication means P2S access is tied to individual sign-in and whatever Conditional Access/MFA policies apply at the tenant level, rather than a static pre-shared certificate or key distributed out-of-band — a meaningfully stronger posture for remote admin access than certificate-based P2S auth would be.

## How this satisfies the domain skill

The AZ-500 Secure Networking domain explicitly calls out securing both P2S and S2S VPN connectivity. This environment already does both, with a non-default IPsec policy on the S2S side and identity-based authentication on the P2S side — this phase's only work is recognizing and documenting that, not building anything new.

## Security Note (from build review, not this phase's design)

While pulling the gateway script for this write-up: the S2S connection's IPsec pre-shared key is hardcoded as `K1pe3kjt!0729` — the same value used as the domain admin password in `Deploy-Domain-Join.ps1`. Reusing one secret across two unrelated trust boundaries (VPN tunnel auth and AD admin access) means a leak of either script compromises both. Recommend rotating to two distinct secrets, and continuing to avoid hardcoding either in scripts going forward (the domain-join script was already fixed to prompt at runtime — worth applying the same pattern to the gateway script's `SharedKey` parameter).

**Before publishing anything from this document to the public portfolio page:** redact the FortiGate's public IP address, the Entra tenant ID, and the enterprise app audience ID that appear in the underlying script — none of those need to be public, and there's no benefit to disclosing them.
