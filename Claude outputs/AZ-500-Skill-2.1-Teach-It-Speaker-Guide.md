# Speaker Guide: Secure Azure Networks (AZ-500 Skill 2.1)

**Companion to:** `AZ-500-Skill-2.1-Teach-It.pptx`
**Audience:** Team / peers
**Suggested total time:** ~20 minutes talk + Q&A
**Format note:** This isn't a script to read verbatim — it's what to have in your head for each slide, plus the questions you're most likely to get. The slides already carry the on-screen bullets, so use this for the *why* behind each point and the follow-up you're likely to field. Each slide also has a **Draw** line — a quick hand-sketch cue for that moment, using a consistent shorthand throughout: box = VNet/subnet, shield = NSG, diamond = firewall/NVA, solid line = actual traffic path, dashed line = peering/connectivity only.

---

## Before you start

One-sentence frame for the room: *"Secure Networking is the single largest domain on AZ-500 — 20 to 25% of the exam — and this is the sub-skill I leaned on most: securing traffic inside and between virtual networks."* That tells people up front why a whole talk is justified on one sub-skill instead of a shallow tour of the whole exam.

---

## Slide 1 — Secure Azure Networks

**~30 seconds.** Title card. State the cert (AZ-500, Azure Security Engineer Associate) and that today is one slice of it — virtual network security — not the whole exam. Don't linger.

**Draw:** Nothing — you're on this slide 30 seconds. If you want one mark, underline "Secure Networking" on the title as you name the domain.

## Slide 2 — The Problem: Peering Isn't Segmentation

**~1.5 minutes — this is your hook, spend real time here.**

- Lead with the misconception: most people assume peering two VNets together isolates them the way separate networks would be. It doesn't.
- `AllowVNetInBound` (priority 65000) is a platform default that allows everything inside the VNet address space — and you can't delete it, only out-prioritize it with your own lower-numbered rule.
- Land the punchline: nothing in the portal warns you this is open. You find out by knowing the default rule exists, not by Azure telling you.
- Second half: peering also adds a route automatically, and routing a packet somewhere isn't the same as inspecting it — no firewall sits in that path unless you put one there yourself.

**Draw:** Build it live, don't show it finished. Two boxes, VNet A and VNet B, dashed line between them for the peering connection — stop there for a beat. Then write `AllowVNetInBound` right on the dashed line and underline it. Draw nothing that looks like a firewall or filter anywhere near it — the blank space is the point.

**Likely question:** *"So is peering itself insecure?"* — No — peering is just connectivity, not a security boundary. The point is that people conflate the two. Segmentation is something you add on top with NSGs (and ASGs), not something peering gives you for free.

## Slide 3 — NSGs: Where They Apply & Evaluation Order

**~1.5 minutes.**

- Two attachment points: subnet (one rule set for everyone in it) and NIC (per-VM). They can stack.
- The order matters and it's asymmetric: inbound checks the subnet NSG first, then the NIC; outbound is the reverse — NIC first, then subnet.
- Traffic stops evaluating the instant one rule matches — first match wins, not "most specific" or "most restrictive."

**Draw:** A subnet box with a shield wrapped around its outside edge (subnet NSG), and a VM inside it with its own small shield (NIC NSG). Then two short arrow chains below: inbound arrow passing through the subnet shield first, then the NIC shield, into the VM — outbound arrow leaving the VM through the NIC shield first, then the subnet shield. Drawing the order reversed between the two arrows is the whole payoff.

**Likely question:** *"Why would you ever use both a subnet and a NIC NSG?"* — Subnet NSG for the baseline policy everyone in that subnet should follow, NIC NSG for the one VM that needs a tighter or looser exception. Same idea as a building-wide policy plus a lock on one specific office door.

## Slide 4 — NSG Rules: Parameters & Defaults

**~2 minutes — the densest slide, don't rush the priority point.**

- Left side is the 5-tuple + metadata: name, priority, source/destination, protocol, port range, action. Priority is doing all the work — 100 to 4096, lower number wins, and evaluation stops at the first match.
- Right side: the three rules Azure creates automatically and won't let you delete — `AllowVNetInBound`, `AllowAzureLoadBalancerInBound`, `DenyAllInbound` — same pattern on the outbound side. You only ever *override* them with a lower-priority rule of your own.
- Close on the one people get wrong in practice: removing a rule that allowed an existing connection doesn't kill it instantly. The interruption only shows up once there's no traffic in either direction for a few minutes — so "I removed the rule and nothing broke" doesn't mean it worked.

**Draw:** A short vertical list of rule rows numbered by priority, arrow pointing down the list labeled "lower number wins," and a stop sign at the first row that matches — nothing below it gets drawn as "evaluated." Underneath, the three default rules each with a small padlock (can't delete, only out-prioritize).

**Likely question:** *"What happens if two rules have the same priority?"* — Azure won't let you create that in the first place; priority has to be unique per direction within an NSG.

## Slide 5 — Creating & Associating an NSG

**~1.5 minutes.**

- Portal path first (Network Security Groups → Add → the usual Sub/RG/Name/Region → Review + Create), then the PowerShell equivalents on screen for both creating the NSG and adding a rule.
- Land on the one thing people skip: an NSG does *nothing* until it's associated to a subnet or a NIC. Creating it is step one of two.

**Draw:** The shield floating by itself first, dotted outline, labeled "does nothing yet." Then an arrow connecting it to a subnet or NIC box, redrawing the outline solid once it lands — two steps, not one.

**Likely question:** *"Can one NSG be associated to multiple subnets?"* — Yes, that's actually the efficient pattern — one NSG can cover several subnets, and you use ASGs (next slide) to handle the finer-grained differences instead of spinning up a new NSG per subnet.

## Slide 6 — Application Security Groups

**~1.5 minutes.**

- The pitch: group VMs by application role instead of hardcoded IPs, then reference that group in an NSG rule.
- The constraint people trip on: one ASG as source and one ASG as destination *per rule* — you can't put multiple ASGs on either side of the same rule.
- A VM can belong to multiple ASGs if it runs multiple workloads (web + SQL, say), and each workload gets its own access rules that way.

**Draw:** One VM box sitting inside two overlapping rounded shapes labeled ASG: Web and ASG: SQL, to show a VM in two ASGs at once. Then one rule arrow from a single ASG source to a single ASG destination, with a second ASG icon crossed out on either side to flag the one-per-side constraint.

**Likely question:** *"How is this different from just tagging VMs?"* — Tags are metadata for organization/billing; ASGs are a first-class object NSG rules can actually reference as source or destination. A tag can't go in a rule's source field — an ASG can.

## Slide 7 — User-Defined Routes

**~1.5 minutes.**

- Azure creates default routes for you automatically — one per VNet address range, a default `0.0.0.0/0 → Internet` route, plus routes added whenever you create a peering, a gateway, or a service endpoint.
- You only build a custom route to *override* that default behavior — the classic case is pointing `0.0.0.0/0` at a firewall or NVA so it inspects traffic before it goes anywhere.
- `Next Hop Type = None` is a deliberate drop — useful, not a mistake, when you actually want traffic blackholed.
- Close on the tie-break: a subnet only ever has one route table, and user-defined routes win over the automatic ones on conflict.

**Draw:** One subnet box, one route table icon attached — emphasize "one" by not drawing a second. Thin gray arrows for the automatic defaults (VNet range, `0.0.0.0/0 → Internet`), then a bold arrow overriding it toward a firewall diamond instead of the internet cloud. Separately, a small sketch for `Next Hop Type = None`: an arrow that just stops dead against a solid black square.

**Likely question:** *"What if I want default AND custom behavior on the same subnet?"* — You can't split it — one route table per subnet, so your custom table has to explicitly include (or intentionally omit) anything the defaults would otherwise handle.

## Slide 8 — VNet Peering & Hub-Spoke

**~2 minutes — slow down for the diagram.**

- Peered traffic never touches a gateway or the public internet — it's routed directly over the Microsoft backbone. That's the performance and security story in one sentence.
- Walk the diagram: hub is the central connectivity point to on-prem, spokes peer to the hub and gain isolation *from each other* — spoke-to-spoke isn't automatic just because both are peered to the hub.
- A site-to-site connection needs a dedicated GatewaySubnet living in the hub, not in a spoke.

**Draw:** Build it in order: hub box, on-prem cloud with a solid S2S line into it, then spoke 1 and spoke 2 each dashed-peered to the hub only — no line drawn between the two spokes. Trace the missing gap with your pointer when you hit the likely question below.

**Likely question:** *"Do the spokes in this diagram talk to each other by default?"* — No — that's the whole point of hub-spoke. Each spoke peers to the hub, but spoke-to-spoke traffic needs its own explicit path (another peering, or routing through an NVA in the hub) — it isn't automatic just because both sides are peered to the same hub.

## Slide 9 — VPN Gateway & Authentication

**~2 minutes.**

- Left side: the four connection types — P2S for individual users, S2S for on-prem, VNet-to-VNet, and Multi-Site as an extension of S2S. One gateway per VNet, and it's VPN *or* ExpressRoute, never both.
- Right side: PSK is auto-generated at creation; P2S auth has three real options — Azure certificate, RADIUS (only on VpnGw1–3 SKUs), or Azure AD/Entra ID (OpenVPN protocol only).
- The scenario cue is the exam-relevant takeaway: existing RADIUS infrastructure → use RADIUS. Gateway itself has to validate the cert → native Azure certificate auth. That's usually what the question is actually testing.

**Draw:** One gateway box in the hub, four lines fanning out to four labeled endpoints (a laptop for P2S, an on-prem cloud for S2S, another VNet box for VNet-to-VNet, multiple clouds for Multi-Site) — drawing the gateway box only once makes "never both VPN and ExpressRoute" visual. Separately, three small auth icons — certificate, RADIUS server, Entra ID — with "OpenVPN only" written next to the Entra ID one.

**Likely question:** *"Why would you pick RADIUS over Azure AD auth?"* — RADIUS is the right call when you already have that infrastructure (and you need SKU support to match — VpnGw1–3 only). Azure AD/Entra ID is the newer, identity-centric path, but it's OpenVPN-only, so client OS and protocol support factor in too.

## Slide 10 — Virtual WAN

**~1.5 minutes.**

- Hub-and-spoke at global scale — the hubs themselves connect in a full mesh over the Microsoft backbone, so you're not manually wiring up every path between regions.
- Hit two or three planning notes that actually matter: a spoke on a hub can't also carry its own gateway or route server; 1,000 connections per hub; default egress favors ExpressRoute over VPN but it's customizable.

**Draw:** Three or four hub boxes, each with its own spokes, then connect every hub to every other hub directly — a small mesh, in contrast to Slide 8's single hub. Label it "hub of hubs" as you draw the mesh lines.

**Likely question:** *"When would you reach for Virtual WAN instead of just peering VNets together?"* — Once you're past a handful of VNets and multiple regions/branch offices — manually meshing peering connections doesn't scale, and Virtual WAN's hubs handle that automatically.

## Slide 11 — Encryption & PaaS Firewalls

**~1.5 minutes — two topics, don't let either one run long.**

- ExpressRoute encryption: MACsec (Layer 2, encrypts everything including BGP control traffic, requires ExpressRoute Direct) vs. IPsec (Layer 3, end-to-end, no Direct requirement). Flag the operational gotcha: a MACsec key update touches both sides — get it wrong and you break the circuit, not just weaken it.
- PaaS firewalls, Storage as the example: default configuration allows all networks, which is the thing to actually go fix. `Public Network Access` has three settings, and it's enforced across every protocol that reaches the account, not just the one you were thinking about.

**Draw:** Two mini-sketches. First, a line for ExpressRoute drawn thick and fully shaded for MACsec (covers everything, even BGP) next to a second line with a lock icon only on the payload for IPsec (end-to-end, lighter shading). Second, a storage account box with a three-position dial for Public Network Access.

**Likely question:** *"Can you run MACsec and IPsec together?"* — Yes — they're independent layers (Layer 2 vs Layer 3), so you can stack them for defense in depth if the circuit needs it.

## Slide 12 — Network Watcher

**~1.5 minutes.**

- Scope check first: built for IaaS — VMs, VNets, load balancers — not PaaS resources and not web analytics.
- Walk the short list of tools that actually get used day to day: IP Flow Verify (did this packet get through), Next Hop (which route is actually winning), Effective Security Rules (what's the combined rule set on this NIC), plus NSG Diagnostics/Connection Troubleshoot and Flow Logs/Traffic Analytics for the "what actually happened" record.
- Close on the exam framing: the question is almost always "which tool answers this," not "does this tool exist."

**Draw:** A magnifying glass over VM/VNet/load-balancer boxes only, with a PaaS box drawn grayed-out or crossed beside it to mark scope. List the five tools as tiny icons in a row: a checkmark/X arrow for IP Flow Verify, a fork in the road for Next Hop, two shields merging into one for Effective Security Rules, then Diagnostics/Troubleshoot and a small ledger for Flow Logs.

**Likely question:** *"What's the difference between Effective Security Rules and just looking at the NSG?"* — A NIC can have both a subnet-level and NIC-level NSG applied — Effective Security Rules shows you the *combined* result of both, which is what's actually enforced, not just one half of the picture.

## Slide 13 — Bringing It Back to My Own Lab (live demo)

**~2 minutes recap, ~12–14 minutes with the live demo — this is the credibility slide, don't rush it.** Full step-by-step demo mechanics live in `AZ-500-Skill-2.1-Live-Demo-Run-Sheet.md` — this section is the narrative frame around it.

- Walk the four phases briefly and point at the exact mechanic each one used: Phase 1 was the `AllowVNetInBound` override plus ASG-as-destination, hands-on. Phase 2 was the UDR precedence fight — needed both a `0.0.0.0/0` route and an explicit per-spoke route, or the automatic peering route silently won. Phase 3 was the VPN Gateway work — custom IPsec/IKE policy, Entra ID P2S auth, OpenVPN-only. Phase 4 used Network Watcher's diagnostic tools — IP Flow Verify, Next Hop, Effective Security Rules, NSG Diagnostics, and Connection Troubleshoot — to prove enforcement live instead of logging it after the fact; flow logs were evaluated and deliberately left out since the diagnostics alone do the job and read far better live.
- The message underneath all four: everything on the earlier slides is a real mechanic you can hit in a real environment, not just exam trivia.

**Draw:** A four-box timeline strip left to right — Phase 1 (ASG + override), Phase 2 (UDR fight), Phase 3 (gateway/cert/Entra), Phase 4 (magnifying glass) — circle Phase 2 when you give the "longest to get right" answer below. Then, for the live demo's UDR segment specifically, a two-panel before/after sketch: panel one, Spoke2 → Spoke1 with the peering line winning and the firewall box sitting off to the side unused, route table showing only `to-Internet`; panel two, same boxes, but the new `to-Spoke1` route added and the traffic line now running through the firewall instead of the direct peering line. Leave both panels up side by side rather than erasing panel one — the before/after pairing is what sells "nothing errored, it was just silently wrong."

**Likely question:** *"Which of these took the longest to actually get right?"* — Good, honest answer to have ready: the UDR precedence issue (Phase 2) is a strong one — it's the kind of thing that fails silently, with no error and no warning, so you only catch it by deliberately validating with Next Hop.

## Slide 14 — Questions???

Open it up. If the room's quiet, a couple of prompts:

- *"Which of these controls took the longest to get right?"* (Phase 2's UDR precedence is a strong, honest answer if you haven't already used it on Slide 13.)
- *"What's still out of scope that you'd want to tackle next?"* — good opening to mention identity/Conditional Access, Defender for Cloud, Key Vault, Private Endpoints, or WAF as deliberate exclusions from this talk, not gaps you missed.

The slide itself also carries your own next-up plans — CCNP, having taken a swing at ENCOR already, ENARSI next, then probably a cert hiatus. Fine to share that plainly if it comes up; it's an honest, low-pressure way to close.

**Draw:** Nothing planned. If the cert roadmap comes up, a simple left-to-right arrow strip works: ENCOR (done) → ENARSI (next) → hiatus.

---

## If you're short on time

Cut to five slides and it still holds together: **2 (the problem) → 3 (NSG order) → 8 (hub-spoke) → 13 (my own lab) → 14 (questions).** That's the throughline — implicit trust exists by default, controls have to be deliberately layered on top, and it's not just exam material, it's a real environment you've actually run.

## If you get a skeptical question about scope

This talk is one sub-skill — "Plan and implement security for virtual networks" — out of three under Secure Networking, which is itself one of several AZ-500 domains. If someone asks why not cover more: it was scoped deliberately to stay focused rather than becoming a shallow tour of the whole exam. Private access to Azure resources and public access (Azure Firewall, WAF) are the other two Secure Networking sub-skills, left out on purpose — and identity/Conditional Access, Defender for Cloud, Key Vault, and Private Endpoints are other domains entirely. Say it that way, not apologetically — it's a defensible, deliberate choice.
