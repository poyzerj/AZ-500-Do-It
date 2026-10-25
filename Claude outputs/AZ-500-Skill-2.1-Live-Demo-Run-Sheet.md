# Live Demo Run Sheet: Slide 13 — Lab Demo

**Companion to:** `AZ-500-Skill-2.1-Teach-It.pptx` (Slide 13 — "Lab Demo")
**Session length:** ~1 hour, demo as centerpiece
**Estimated demo block time:** ~12–14 minutes (up from the guide's original 2-minute recap treatment)
**Prerequisite:** Environment redeployed and standing *before* the session — see "Prep the night before" below. Do not attempt any part of this cold.

**Reference VMs:** `JPAZVM12` = Spoke1 (already fully configured — your "end state" reference). `JPAZVM13` = Spoke2 (deliberately left unconfigured — your live-build target). Firewall private IP throughout: `10.0.2.4`.

---



## Prep the night before (not live)

Redeploy the normal way, but stop short on Spoke2 specifically:

- Deploy everything through Phase 1 + Phase 2 as usual for the **hub** and **Spoke1** (`JPNSGHub`, `JPNSGSpoke1` retargeted to `JPASGHub`/`JPASGSpoke1`, deny rules added, `RT-Spoke1` created with both routes and associated).
- **Do not** create `JPASGSpoke2`, retarget `JPNSGSpoke2`'s rules, or add its deny rules.
- **Do not** create `RT-Spoke2` or associate any route table to `Spoke2Subnet`.
- Deploy the Firewall as usual — that's shared infrastructure, not per-spoke, so it needs to be live and stable going into the session. Phase 4 itself deploys nothing — it's validation-only against Phases 1–2, so there's nothing to pre-stage for it specifically.
- Have all portal tabs pre-navigated and left open in the background (see tab list below) so you're only ever switching tabs, never searching, during the live segments.
- Have this file open on a second screen, or print it.

**Tabs to pre-open** (in this order, so tab-switching matches the run order):

1. `JPNSGSpoke1` — Inbound security rules (reference)
2. `JPASGSpoke2` create blade (Application security groups → + Create) — *don't submit yet*
3. `JPAZVM13-nic` — IP configurations
4. `JPNSGSpoke2` — Inbound security rules
5. Network Watcher → Effective Security Rules
6. Route tables → + Create (for `RT-Spoke2`) — *don't submit yet*
7. Network Watcher → Next Hop
8. Network Watcher → IP Flow Verify
9. VPN Gateway → Point-to-site configuration

**Values to have copy-pasteable** (typed in a scratch note, not memorized):

```
JPASGSpoke2
Deny-VirtualNetwork-Inbound | 4000 | Service Tag: VirtualNetwork | Deny
Deny-Internet-Inbound       | 4010 | Service Tag: Internet       | Deny
RT-Spoke2
to-Internet | 0.0.0.0/0    | Virtual appliance | 10.0.2.4
to-Spoke1   | 10.1.0.0/23  | Virtual appliance | 10.0.2.4
192.168.20.50   (on-prem test source — expect Allow)
8.8.8.8         (non-on-prem test source / outbound dest — expect Deny inbound, Allow outbound)
```

---



## Segment 1 — Point at the reference (~30–45 sec)

Tab 1 (`JPNSGSpoke1`). Say: "Spoke1 already has this locked down — here's the end state we're about to build on Spoke2." Point at `Allow-RDP-From-Home` with destination = `JPASGSpoke1`. Don't linger — this is context-setting, not the demo.

## Segment 2 — Build the NSG/ASG live on Spoke2 (~3–4 min)

1. Tab 2: create `JPASGSpoke2` (Resource group `rg-az500-doit-cus`, region Central US). Submit, wait for it to land (few seconds).
2. Tab 3 (`JPAZVM13-nic` → IP configurations → `ipconfig1`): set Application security groups → `JPASGSpoke2` → Save.
3. Tab 4 (`JPNSGSpoke2` → Inbound security rules): edit `Allow-RDP-From-Hub`, `Allow-RDP-From-Home`, `Allow-Ping-From-Home` → Destination → Application security group → `JPASGSpoke2` → Save, for each.
4. + Add twice: `Deny-VirtualNetwork-Inbound` (priority 4000, source Service Tag VirtualNetwork, destination Service Tag VirtualNetwork, Deny) and `Deny-Internet-Inbound` (priority 4010, source Service Tag Internet, destination Any, Deny).

Narrate as you go — this is the "watch me actually do it" payoff, don't rush through the clicks silently.

## Segment 3 — Effective Security Rules check (~1–1.5 min) — NEW

Tab 5: Network Watcher → Effective Security Rules → target `JPAZVM13-nic`. Show the combined rule set — this is the moment to land the point from your Network Watcher slide: "this is the *combined* result of subnet + NIC rules, not just what one NSG says." Confirms Segment 2 actually took.

## Segment 4 — UDR: show the bug, then fix it (~3–4 min) — EXPANDED

1. Tab 6: create `RT-Spoke2` (same resource group/region). Add **only** the `to-Internet` route (`0.0.0.0/0` → Virtual appliance → `10.0.2.4`). Associate to `JPVNetSpoke2` / `Spoke2Subnet`.
2. Tab 7 (Next Hop): VM `JPAZVM13`, source = its own IP, destination = `JPAZVM12`'s IP. Run it. **Expect it to still return** `Virtual network` — the automatic peering route is still winning. Name this explicitly: "Nothing errored. Nothing warned me. It's just silently wrong." This is the exact bug your design doc and speaker guide call out as the trickiest thing you found.
3. Go back to `RT-Spoke2` → Routes → + Add: `to-Spoke1` (`10.1.0.0/23` → Virtual appliance → `10.0.2.4`).
4. Re-run Next Hop with the same source/destination. **Now expect** `Virtual Appliance`**,** `10.0.2.4`**.** Land it: "That's the fix — and the only way to know it was broken, or that it's fixed now, is to check."



## Segment 5 — Network Watcher verification pass (~1.5–2 min)

Tab 8 (IP Flow Verify), all against `JPAZVM13`:

- Inbound TCP 3389 from `8.8.8.8` (or any IP outside `192.168.20.0/24`/`192.168.40.0/24`) → expect **Deny**.
- Inbound TCP 3389 from `192.168.20.50` → expect **Allow**.
- Outbound TCP 443 to `8.8.8.8` → expect **Allow** (proves traffic is actually flowing through the firewall now that the route exists).



## Segment 6 — VPN P2S config peek (~1–1.5 min) — NEW

Tab 9: VPN Gateway → Point-to-site configuration. Not a live connection attempt — just show the config: Entra ID (Azure AD) authentication, OpenVPN protocol, `172.16.20.0/24` client address pool. One sentence on why: "Entra ID ties this to a real identity instead of a shared cert — access can be revoked centrally without redistributing anything."

---



## If something doesn't cooperate

Have a screenshot of each expected end state (Segments 2, 3, 4-before, 4-after, 5, 6) ready as a fallback in a side folder. If a step stalls, narrate from the screenshot rather than troubleshooting live: "Here's what that looks like when it lands" and move on — don't let the room watch you debug the portal.

## After the session

Tear down what you don't want left running: undo the Spoke2 changes if you want the environment back to a clean baseline, and if you deployed the Firewall/Gateway fresh for this, run the Remove scripts once you're done to avoid ongoing cost (~$1.25/hr for the Firewall alone).