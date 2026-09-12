# Project Engineer III Interview Prep — Mytech Partners

*Job posted: Thursday, July 16, 2026 | Interview: TBD*

---

## Job Focus Areas (from JD)

- Active Directory internals (replication, GPOs, DFS, FSMO, system state recovery)
- M365/Azure migration and management, PowerShell
- Network audits, wireless site surveys, WLAN optimization
- Virtualization/hardware: VMware, SAN/NAS support, RAID recovery, VM recovery
- Reviewing SOWs (written by SE), creating execution plans, solution designs
- Client-facing communication, supporting sales
- On-site role, New Brighton, MN

**Org structure note:** SOWs are written by the Solutions Engineer (SE). As PE, you review the SOW and build the execution plan. The PE assigned to a project *is* the lead engineer — sign-off is your own technical judgment, not escalation to someone above you.

---

## Q&A Review

### 1. Storage design for a new virtualization host
**Q:** "Walk me through how you'd design storage for a new virtualization host you're deploying for a client — what factors go into your decision?"

**Your answer (strong):** Separate OS (RAID 1) from VM workloads (RAID 10 on SSD) from bulk/cold storage (RAID 1 HDD).

**Key reasoning to voice:**
- RAID 10 over RAID 5/6 for active VM storage: no parity rebuild penalty, mirrors handle rebuilds directly, better IOPS under load.
- Tier storage by workload behavior — active/high-I/O (VMs, databases) → SSD tier; cold/idle (backups, file archives) → HDD tier.
- **Growth/headroom:** don't provision to 100% capacity at deployment. Leave room for snapshots, thin-provision overcommit, and future expansion. Mention this proactively if asked about future-proofing.

---

### 2. Troubleshooting two VLANs that can't communicate
**Q:** "A client calls saying two VLANs on their network can't communicate with each other. Walk me through how you'd troubleshoot this."

**Structure to use (escalation-ladder style, not checklist):**
1. **Clarify scope first** — what exactly fails (ping? specific app/port? one-way or both directions? new or long-standing issue?)
2. **Layer 1/2** — switchport VLAN assignment; if VLANs span multiple switches, verify **trunk ports** allow both VLANs (this is easy to forget — flagged as a gap in practice).
3. **Layer 3** — confirm VLAN interfaces (SVIs) exist on the firewall/router for inter-VLAN routing. VLANs are broadcast domains; something has to route between them.
4. **IP/gateway check** — confirm devices have correct IP and default gateway for their VLAN.
5. **Firewall policy** — confirm policy exists to permit the specific traffic between VLANs.

**Say explicitly:** "I'd set up VLAN interfaces on the FortiGate to handle inter-VLAN routing" — name the L3 concept out loud rather than assuming it's implied.

---

### 3. Disk witness vs. cloud witness for cluster quorum
**Q:** "You're deploying a new Windows Server failover cluster for a client. What's your process for choosing between a disk witness and a cloud witness for quorum?"

**Your answer (good, keep as-is):**
> "It depends on the topology of the cluster. I'd choose a disk witness for a single-site cluster — it's simple and doesn't depend on internet connectivity. I'd choose a cloud witness for multi-site clusters."

**Optional add-on for credibility:** "I actually used a disk witness in a workgroup failover cluster I built in my home lab, backed by iSCSI storage."

**Concept refresher:** Quorum is a tiebreaker mechanism so an even split of nodes doesn't deadlock during a network partition. A witness (disk/cloud/file share) provides an extra vote.

---

### 4. FSMO roles
**Q:** "What are FSMO roles, and what happens if a domain controller holding one of them goes offline?"

**Your working answer (good — concept-level, no rote memorization needed):**
> "FSMO roles are specific AD functions that only one domain controller handles at a time — things like creating new accounts, editing group policy safely, and keeping password/lockout info accurate. If that DC goes down, general login still works fine off other DCs, but those specific functions get stuck or unreliable until it's back."

**If pressed for "why only one DC":** Prevents conflicts — e.g., if any DC could hand out new account IDs independently, two DCs could assign the same ID at the same time. Restricting it to one DC avoids that collision.

**If you can't recall role names live:** It's fine to say "I don't remember all five by name off the top of my head, but I understand what they're for and the operational impact if one goes offline."

---

### 5. Veeam — scope check
**Q:** "What's the difference between a backup and a replica in Veeam, and when would you use each?" (Context question, scope narrowed after discussion below.)

Per your org: PEs use Veeam specifically for **VM migration** (P2V/V2V to Hyper-V), not backup/DR strategy — that's owned by Shared Technical Services. Keep Veeam answers focused on migration tooling, not backup job design.

**P2V vs. V2V:**
- **P2V** — physical server → VM (what you did: FUSION-DT → Proxmox)
- **V2V** — VM on one hypervisor → VM on another (your next lab phase: ESXi → Proxmox)

---

### 6. Scope creep discovered on-site (strong answer — keep this structure)
**Q:** "A client's SOW calls for migrating their file server to a new Windows Server, but when you show up on-site, you discover their existing server has some old shares with broken permissions and undocumented drive mappings that weren't part of the original scope. What do you do?"

**Your answer:**
> "I'd stop and document exactly what I found — the broken permissions, the undocumented mappings — rather than trying to fix it under the original scope. I'd take notes, screenshots, and photos if it's a physical device. Then I'd loop in the PM and SE so they can determine if this needs a change order before I proceed, since it wasn't part of what the client agreed to."

**Why this lands well:** Shows judgment to pause rather than absorb scope creep silently or improvise a fix, and ties directly into your existing documentation strength.

---

### 7. Execution planning (SOW review → execution plan)
**Honest framing (use this — don't overstate SOW experience):**
> "I haven't reviewed a formal SOW before, but I'm used to breaking my own projects into phases with dependencies and validation checkpoints. For example, when I set up my UCS server as a lab host: Phase 1 was RAID configuration (RAID 1 boot, RAID 10 for VM storage, RAID 1 for bulk/backup), Phase 2 was installing and configuring Proxmox, Phase 3 was setting up storage pools, and Phase 4 was deploying a test VM to validate the host before building anything else on it. That's the same discipline I'd bring to reviewing a SOW and turning it into a phased execution plan."

**If asked what else goes into an execution plan beyond your own technical steps:** client dependencies (access, approvals), external dependencies (hardware/licensing arrival), and checkpoints where you'd sign off before moving to the next phase.

---

### 8. Wireless — weak signal in a conference room
**Q:** "A client says WiFi is weak in their conference room, which is at the far end of the building from where their single AP is mounted near the front desk. What would you check first, and what's your likely recommendation?"

**Your answer (solid):**
> "First, I'd measure how far the conference room is from the access point. Then I'd measure the signal strength (RSSI) at the location where the WiFi is weak, and consider any obstructions such as walls. If the signal strength is really weak — like -70 dBm — I'd recommend a second access point for more coverage."

**Follow-up if asked about second AP setup:**
> "I'd place it to cover the gap without excessive overlap with the first AP, and set it on a different channel to avoid interference, using the same network name so devices switch between them automatically."

**Channel reference:** 2.4GHz has 3 non-overlapping channels — 1, 6, 11. If the existing AP is on channel 6, place the new one on 1 or 11. 5GHz has many more available channels and most enterprise APs auto-select the best one, so channel planning is mainly a 2.4GHz consideration.

**Note on terminology:** Using "signal strength" instead of "RSSI" and "different channel" instead of "non-overlapping channel" is a deliberate, good choice given the PS Manager (non-technical) will be in the room — same accuracy, more accessible.

---

### 9. M365 migration — Exchange on-prem to Exchange Online
**Q:** "A client wants to migrate 50 users from an on-prem Exchange server to Exchange Online as part of a project. At a high level, what would your approach look like?"

**Your answer (strong):**
> "I'd take a count of items that migrate to M365 — users, mailboxes, distribution lists, rules, connectors, public folders, etc. Then plan the migration and set up M365, making sure licenses are purchased. Create the M365 users in the new tenant. Use a migration tool such as MigrationWiz to migrate everything from Exchange server to M365. Once migrated, plan the cutover — removing the domain from Exchange server, setting it up on the new tenant, and planning DNS changes to minimize downtime."

**Additions worth mentioning if it comes up:**
- Native Microsoft options exist too: **cutover migration** (good fit for ~50 users, moves everything at once) vs. **hybrid migration** (Azure AD Connect, phased/staged, coexistence during transition) — MTP's standard practice is MigrationWiz for consistency and reduced manual troubleshooting.
- **Pilot/test batch** — migrate a small group first (IT team or volunteers) before the full migration to catch issues early.
- **Post-migration Outlook reconfiguration** — end-user Outlook profiles typically need reconnecting after cutover; worth planning for as a known support step, not a surprise.

---

### 10. Email deliverability — partner emails landing in spam
**Q:** "A client on Exchange Online reports that some external emails from a specific partner company keep landing in Junk/Spam instead of the inbox. As the PE handling this during a project (say, right after a migration), what would you check?"

**Your answer (strong, tool-specific):**
> "I'd run a mail trace in both Exchange Online and Avanan. I'd check Microsoft Defender anti-spam rules to make sure they're configured correctly. I'd check if the partner's domain needs whitelisting — maybe the whitelist didn't migrate from the old Exchange server, so I'd check both Defender and Avanan for that. I run the mail trace in Avanan specifically because it will tell me if SPF/DKIM/DMARC on the partner's domain failed, so I don't need to check DNS records separately."

**Why this is a strong answer:** Names your actual tool stack (Avanan alongside Defender) and shows awareness that migrations can silently drop allow-list entries — a real, specific insight beyond generic troubleshooting steps.

---

### 11. Planning an RDS-to-AVD migration
**Q:** "A client currently has an on-prem RDS environment and wants to migrate to Azure Virtual Desktop. How would you approach planning that migration?"

**Suggested approach (build from your RDS + AVD lab experience):**

1. **Assess the current RDS environment** — how many users, what apps are published (full desktop vs. RemoteApp), session host sizing/load, FSLogix or roaming profile setup currently in use, and any GPOs governing the RDS experience that would need to carry over.
2. **Decide host pool type** — pooled (multi-session, shared hosts, cost-efficient) vs. personal (dedicated VM per user). Most RDS-style deployments map naturally to pooled with Windows 11 multi-session.
3. **Networking and identity** — confirm hybrid connectivity (VPN/ExpressRoute) between Azure and the client's on-prem AD if it's not already cloud-native, and confirm Entra Connect sync is healthy so users can authenticate against the same identities.
4. **Storage for FSLogix profiles** — plan where profile containers live (Azure Files with the right tier, or Azure NetApp Files for larger/performance-sensitive environments) — this replaces whatever file share was serving FSLogix or roaming profiles on-prem.
5. **Licensing check** — confirm the client's Microsoft licensing (M365/Windows licensing) actually entitles them to AVD; this is a common gap since it's not automatically included with every plan.
6. **Pilot group** — migrate a small test group first (mirrors the same instinct used in the M365 mailbox migration answer) to validate the app feed, FSLogix profiles, and printing/peripheral behavior before rolling out broadly.
7. **Cutover plan** — coexistence period if needed, user communication on the change, and a clear decommission plan for the old RDS environment once AVD is validated and adopted.

**Personal example to bring in:** "I actually built an AVD lab from scratch recently — host pool, session hosts, FSLogix — and hit some real issues along the way, like a licensing checkbox for Windows 11 multi-session and a tricky RemoteApp feed issue caused by conflicting application group assignments. That hands-on experience is directly relevant here, especially since I know the project team has an actual client moving from RDS to AVD."

---

## STAR Stories

### Story 1: Root-cause troubleshooting (SCSI-3 PR validation failure)
**Likely question type:** "Tell me about a time you diagnosed a difficult technical problem."

**Situation:** Migrating a Windows Server 2025 failover cluster from a nested Hyper-V lab environment to a Proxmox host, using Linux-based iSCSI storage (LIO) as the shared cluster storage.

**Task:** Windows requires the shared disk to pass SCSI-3 Persistent Reservation validation — a check that both cluster nodes can properly reserve and coordinate access to the shared disk. Cluster validation was failing at this step.

**Action:** Investigated the iSCSI target configuration on the Linux side and found the issue in the TPG (target portal group) attributes. `generate_node_acls` needed to be enabled so the target would properly authenticate the initiators, and `auth_attr_enforcing` needed to be disabled since strict authentication enforcement was interfering with the reservation handshake. Adjusted both settings on the LIO target.

**Result:** Cluster validation passed cleanly and the cluster came online with proper shared storage. Gained a deeper understanding of how Windows clustering interacts with Linux-based iSCSI targets at a protocol level, and documented the fix in the lab guide for future reference.

---

### Story 2: Adapting when something went wrong mid-project (SMR drive / failing SSD)
**Likely question type:** "Tell me about a time a project didn't go as planned and how you adapted."

**Situation:** While building out the failover cluster lab environment, one of the physical drives in the storage setup was a Seagate ST4000DM004 — an SMR (Shingled Magnetic Recording) drive — being used for VM/cluster storage.

**Task:** The environment started experiencing significant I/O saturation and performance degradation under the cluster workload, which wasn't expected from a standard hard drive of that capacity.

**Action:** Investigated the performance issue and traced it back to the drive's SMR technology — SMR drives use overlapping tracks for higher density, which makes them poor for sustained random write workloads like active VM storage, since writes can trigger costly internal re-shingling operations. Around the same time, a Samsung 860 EVO SSD in the environment also began throwing Event ID 51 errors, indicating it was failing. Rather than trying to work around either issue, decided to replace both drives — moving VM/cluster storage off the SMR drive entirely and replacing the failing SSD before continuing the build.

**Result:** Once the failing/unsuitable drives were replaced, I/O performance stabilized and the cluster build continued without further storage-related issues. This reinforced a lesson carried into later phases: drive technology (SMR vs. CMR) matters as much as raw capacity when planning storage for latency-sensitive workloads like clustering — a consideration now baked into how I approach storage design for new deployments.

---

### Story 3: Documentation practices
**Likely question type:** "Tell me about a time you had to document something complex so someone else could follow it."

**Situation:** After completing a multi-week project — building a Windows Server 2025 failover cluster and then migrating it from a physical Hyper-V lab environment to a Proxmox host — needed to turn that work into a clear, reusable guide.

**Task:** The environment involved a lot of lab-specific workarounds — nested virtualization settings, MAC spoofing — that wouldn't apply in a real production deployment. The documentation needed to be usable by someone else, clearly separating lab-only steps from what would carry over to a real-world build.

**Action:** Worked through the project step by step, describing each part of what was done — configuration, issues hit, and how they were resolved. Used AI to help draft the initial write-up quickly, saving significant time versus writing everything from scratch. Then went through and edited it personally — verifying technical accuracy, correcting anything that didn't match what was actually done, and clearly flagging lab-only steps so they wouldn't be mistaken for production guidance.

**Result:** A complete, accurate lab guide that clearly distinguishes lab-specific steps from real-world-applicable ones — usable for handoff or personal reference later. Using AI to accelerate drafting freed up time to focus on technical accuracy and organization rather than formatting and phrasing.

**Note if asked directly about AI use in documentation:** "I do the hands-on work and decide what needs to be documented and how it should be structured. I use AI tools to help me write it up efficiently, but I always review and verify the technical accuracy myself before it's final."

---

### Story 4: Complex root-cause troubleshooting under uncertainty (AVD RemoteApp feed issue)
**Likely question type:** "Tell me about a time you had to troubleshoot something where the obvious checks didn't reveal the problem."

**Situation:** While building an Azure Virtual Desktop lab deployment — host pool, session hosts, application groups, and FSLogix profile containers — published RemoteApps (like Chrome and Word) weren't showing up in the feed for test users, even though the deployment appeared fully configured.

**Task:** Needed to figure out why the RemoteApp feed wasn't reaching users when every visible setting looked correct, so the deployment could actually be validated end-to-end.

**Action:** Went past the GUI and checked every layer directly via PowerShell — application definitions, application group membership, role assignments, and workspace configuration — using cmdlets like `Get-AzWvdApplication`, `Get-AzWvdApplicationGroup`, `Get-AzRoleAssignment`, and `Get-AzWvdWorkspace`. All of it came back clean, which meant the problem wasn't a misconfiguration in any single place — it had to be an interaction between settings. Kept digging and found that a user assigned to both a Desktop application group and a RemoteApp application group on the *same* host pool caused the broker to suppress the RemoteApp feed entirely. Removing the user's direct assignment wasn't enough on its own — the group-based assignment also had to be cleared, since either path alone still caused the conflict.

**Result:** Once both assignment paths were cleared, the RemoteApp feed worked correctly for test users. This was a good example of a problem that couldn't be solved by checking settings individually — it required understanding how two valid-looking configurations could conflict with each other at the broker level. That systematic, layer-by-layer diagnostic approach (rather than guessing or restarting services) is the same instinct I'd bring to a client environment where the fix isn't obvious from the first few checks.

---

## General Interview Notes

- You're strongest on: virtualization, storage design, RAID reasoning, documentation habits, escalation judgment.
- Solutions Engineer will likely be in the room to gauge technical depth; PS Manager is non-technical — practice explaining things accurately without jargon overload, not "dumbed down."
- When unsure of a term or haven't been hands-on with something: say so plainly and pivot to the adjacent thing you *do* know. Interviewers respond better to honest gaps + clear reasoning than to bluffing.
- You already work at Mytech — use that. You know the tools (IT Glue, Fortinet stack, Avanan), the client base, and the team's current priorities (AVD demand, RDS-to-AVD client migration).
- Prepare 2-3 questions to ask them (e.g., "What does a typical handoff from Sales/SE to PE look like?").
- Send a brief thank-you note within 24 hours referencing something specific discussed.

---

## Project Management Questions

### PM-1. Competing priorities across multiple projects
**Q:** "You're managing three active projects at once, and two clients both want their work prioritized this week. How do you decide what gets done first?"

**Core idea (don't memorize the script — rebuild from these beats):**
- Figure out what's actually driving urgency for each: hard deadlines, dependencies blocking others, client-impacting issues vs. "nice to have sooner"
- If not obvious, loop in your PM — they may have existing commitments with the client
- Time-block your day accordingly once priority is clear, but still make some progress on the lower-priority project
- Communicate proactively if a timeline needs to shift — don't let it be a surprise

---

### PM-2. Project running behind schedule
**Q:** "A project is running behind schedule — you're two weeks into a four-week timeline and only about 25% complete. What do you do?"

**Core idea — four beats, rebuild in your own words each time:**
1. Figure out *why* it's behind (bad estimate, technical issues, client dependency)
2. Tell your PM early — not at the deadline
3. Adjust the plan: timeline, scope, or bring in another engineer to help
4. Don't just quietly grind it out after-hours/weekends — that doesn't fix the root cause and leads to burnout

**Your own restated version (good — use this as your anchor, not a script to recite verbatim):**
> "First, I would figure out why the project is behind. Maybe there were some technical issues that caused the delays. Second, I would tell my project manager as soon as possible, not late. Next, I would see if we, as a team, can adjust timelines and bring in another project engineer to help me get caught back up. Honestly, I wouldn't want to spend time after hours and on the weekend to get caught up because that isn't going to solve the root issue — that would just cause burnout quicker. So, talking to the PM and adjusting timelines or bringing in help is a better outcome than grinding it out alone."

---

---

## Universal Framework: "How Would You Plan..." Questions

Use this same 7-step shape for any planning question — migrations, network equipment setup, deployments, etc. It's the same skeleton every time, just filled in with different specifics. (You already used this shape unconsciously in your M365 migration answer and your UCS lab phases.)

1. **Assess / Discover** — What exists today? Current environment, pain points, scope vs. out of scope (ties to SOW review).
2. **Plan the design** — Target end-state, dependencies (licensing, hardware, access, other teams), order of operations.
3. **Prepare / de-risk** — Backup/rollback plan, change window (low-impact timing), client communication on what to expect.
4. **Pilot / test small** — Small group, one device, or one segment first before going broad.
5. **Execute** — Do the work, following the established order.
6. **Validate** — Confirm it actually works, not just that it's technically done.
7. **Document and hand off** — Update documentation (IT Glue), hand off to support/help desk or client with clear notes.

**Practice goal for next session:** run through this framework live with a new scenario (e.g., new firewall deployment, switch replacement) until it feels automatic.

---

---

## AZ-305 Refresher (2022 cert — concepts likely overlap with AZ-104/700/500/800/801)

**If the SE asks about AZ-305 directly:**
> "I got AZ-305 in 2022, so some of the deeper design-pattern specifics have faded since I don't design Azure architectures day-to-day — but the core concepts around identity, networking, and resource design have stuck with me, and I've kept hands-on with Azure more recently through my AVD lab build."

**What AZ-305 covers, for quick recall:**
- Identity, governance, monitoring — Entra ID design, RBAC, management groups/subscriptions, Azure Policy, Azure Monitor/Log Analytics
- Data storage — storage types (Blob, Files, managed disks), redundancy options (LRS/ZRS/GRS)
- Business continuity — backup strategies, Azure Site Recovery, availability zones vs. regions
- Infrastructure — compute selection (VMs vs. App Service vs. containers), networking (VNets, peering, hybrid connectivity via VPN/ExpressRoute)

**Azure Backup & Recovery:**
- **Azure Backup** — protects VMs, files/folders, SQL, Azure Files via Recovery Services vaults; policies define frequency/retention.
- **Azure Site Recovery (ASR)** — disaster recovery/replication, not backup — keeps a VM continuously replicated to another region for failover.
- **Key distinction:** Backup = point-in-time restore after data loss/corruption. ASR = near-continuous replication for failover during an outage (same RPO/RTO concept as the Veeam discussion, Azure-native version).

**Azure Migrate:**
- Free, Microsoft-native hub for discovering and assessing on-prem workloads before migrating to Azure — discovery, right-sizing recommendations, cost estimates.
- Includes agent-based/agentless migration tooling to move VMs into Azure.
- **Good parallel to draw:** "Azure Migrate is essentially Microsoft's own version of what I did with Veeam for my P2V migration, just targeting Azure as the destination instead of Proxmox."

**Recall-check practice (completed):**

**Q1 — Backup vs. Site Recovery:** "Backup is point-in-time — you restore from a saved copy after something goes wrong. Site Recovery is continuous replication — you fail over to an already-running copy in another region, so it's much faster." *(Say "fail over to" rather than "recover from" for ASR.)*

**Q2 — Azure Migrate role in a server migration:**
> "You'd create a project in Azure, then do a discovery — servers, applications, and dependencies — using a virtual appliance installed on the host (Hyper-V or ESXi). Once discovery is done, create an assessment to determine sizing, cost, and migration readiness. Then create a storage account, download/install/register the Azure Site Recovery tool on the VM, and perform replication to Azure. Always do a test migration before the real cutover.
>
> After migration, plan the cutover with the client — find a time/day with no downtime impact. Notify the Service department via email or Teams so they're aware the migration is happening. After cutover: next-day support and documentation, then plan the project-to-service handoff once everything in scope is verified complete."

**Note:** This answer was stronger than expected from memory — Azure Migrate and Azure Site Recovery work together (ASR is the underlying replication engine for Migrate's VM migration), and the full lifecycle (discovery → assessment → replication → test migration → cutover → Service notification → handoff) mirrors the same pattern used consistently across the M365 and AVD answers in this doc.



### PM-3. Client changes requirements mid-project
**Q:** "A client keeps changing their mind mid-project about requirements. How do you handle that without derailing the timeline?"

**Core idea:**
- Determine if the change is in-scope or out-of-scope
- **In scope:** assess timeline impact even if scope/budget isn't affected, document what changed, keep moving
- **Out of scope:** pause that specific piece, go talk to the PM directly (not a full project halt) so they can loop in the SE and work it out with the client, possibly with a change order
- **Document the change either way** — what changed, when, what was agreed

**Your restated version:** "I'd go talk to the PM directly rather than deciding on my own change requests. I'd check if it's still in scope — if so, we can usually accommodate it with minimal issues. If it's out of scope, I'd loop in the PM and SE and we'd work it out with the client together."

---

### PM-4. Project handoff to support/help desk
**Q:** "You're wrapping up a project and need to hand it off to the support/help desk team. What do you make sure happens before handoff?"

**Your answer (strong — no changes needed):**
> "First, I'd make sure everything is in working order and the client is happy with what they're getting. I want to make sure all users have no more questions and are fully trained. Then I'd make sure documentation is up to date in IT Glue — documents, passwords, access, etc. Once that's complete, I'd do the project-to-service handoff with the Service Desk Engineer III."

**Credibility point to say out loud:** "I'm actually a Service Desk Engineer III currently, so I know exactly what a clean handoff needs to include from the receiving side." Known issues/watch-items are covered as part of the documentation itself.

---

### PM-5. Documentation continuity if out sick
**Q:** "How do you keep a project's documentation and status updated so a PM or teammate could pick it up if you were out sick unexpectedly?"

**Your answer (excellent — no changes needed):**
> "I'd keep project documentation and status updated by writing detailed ticket notes on each project ticket — what I've completed, any troubleshooting that came up, and what's next on the project plan. I'd keep all documentation in IT Glue rather than on my laptop, and link to it from my ticket notes. That way another project engineer can pick it up the next day if I'm out, without risking the deadline."

---

### PM-6. Genuine gap in the original SOW (not scope creep)
**Q:** "You realize partway through a project that the original SOW is missing something the client actually needs — not scope creep, but a genuine gap in what was originally scoped. How do you handle it?"

**Core idea:**
- Recognize this is different from scope creep — a gap in the original plan, not an added client request
- Escalate to PM and SE for re-scoping/billing
- **Document specifically what's missing and why it's needed** — gives the SE what they need to re-scope quickly without back-and-forth
- Keep working on in-scope items in parallel to avoid stalling the whole project on the deadline

**Your restated version:** "I'd talk to the PM and SE. If something's missing from the SOW, that additional work needs to be billed, so I'd get it escalated to the SE to get scoped. While that's happening, I'd continue on the items that are in scope to avoid being late on the deadline." *(Add when restating live: document specifically what's missing and why it's needed.)*

---

**Note:** Still have the AZ-305 study book on hand — could skim if time allows, but recall on backup/recovery and Azure Migrate is now solid.

---

---

## RDS Framing (haven't built it hands-on yet — honest, confident answer)

**Likely question:** "Have you worked with Remote Desktop Services?"

**Your answer:**
> "I haven't built an RDS environment hands-on yet, but I've troubleshot it during my time as a Service Desk Engineer III. I actually have it planned out for my lab — a five-server topology including a domain controller, RD Gateway, a broker, and two session hosts, using FSLogix profiles and OneDrive for folder redirection. I prioritized learning AVD first since my free trial was expiring, and I know the project team has an upcoming RDS-to-AVD migration using Azure Migrate."

**Why this works well:**
- Leads with real troubleshooting credibility from the Service Desk role before mentioning what hasn't been built yet
- Shows a specific, real plan (exact topology) rather than vague intent
- Reframes the AVD-first sequencing as deliberate prioritization tied to business need
- Directly connects to the live client project

**Note on Azure Migrate detail:** Confirmed via the actual SOW that the team is using Azure Migrate for the RDS-to-AVD project. Keep this mention light in the interview — it shows awareness without over-explaining a project that isn't yours. (Azure Migrate handles discovery/assessment and underlying VM/infrastructure migration; the AVD-side desktop delivery config — host pools, FSLogix, app groups — still gets rebuilt separately, not "migrated" as such.)

---

---

## Questions to Ask the Interviewers

**Final picks — ask in this order:**

1. "How are projects typically split or prioritized when the team has multiple things in flight at once?"
2. "What's the biggest technical or process challenge the PS team is currently working through?"
3. "If you hire me, what do you see me contributing or accomplishing six months into the role?"
4. "Given everything we've covered, how do you see my background lining up with what you need for this role?" *(closing question — surfaces objections without a blunt "can I have the job" ask. If they name a real gap, acknowledge it honestly and point to how you're already closing it, e.g., VMware/VCP is already on your lab roadmap.)*

**Strategy notes:**
- These four flow naturally: team/practical -> team challenges -> your future impact -> direct fit check
- Skip salary/benefits questions here — handled separately at offer stage
- Skip generic "what's it like working here" questions — already know this since you work there

---

## Compensation

**Posted range:** $70,000–$90,000/year
**Current salary:** $80,337.50/year (floor)

**Target range to state if asked:** $82,000–$88,000/year — anchored slightly above current salary to account for added scope/responsibility, with room to negotiate down to a number that's still comfortable.

**If asked directly:**
> "Given my current salary and the added scope of this role, I'd be looking at something in the $82,000 to $88,000 range, depending on the full responsibilities."

**If asked before ready to answer:**
> "I'd love to understand the full scope of the role and expectations first — but I'm confident we can find a number that works for both of us."

**Worth doing before the interview:** Have a quiet, separate conversation with HR or your manager about what a typical promotion bump looks like at Mytech — internal equity/promotion policies sometimes cap increases at a certain percentage, which would help calibrate a realistic number rather than guessing blind.

---

## Follow-Up Topics for Next Prep Session
- DFS (Distributed File System) — named in JD, not yet covered
- Network audits — what the process looks like (troubleshooting covered, audits not)
- AD replication troubleshooting — beyond FSMO
- System state recovery — named in JD
- Pre-sales/client-facing scenario — presenting a technical recommendation alongside sales
- Behavioral: conflict with a coworker/teammate on a project
- Behavioral: a time you had to say no to a client or push back on an unreasonable ask
- Behavioral: why you want this specific role
- Mock full run-through (technical + behavioral back to back, timed) — planned for Day 4