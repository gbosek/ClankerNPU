# AN7581 three-board deployment and validation

This is a test plan, not a claim that ClankerNPU has run on any board.
The three devices currently run a custom ImmortalWrt 6.18.52 image with
the Airoha Linux NPU driver and vendor NPU firmware version 1456.62.
As of the 2026-09-28 live check, TF has an operational Telecom PON
link and XG2010G has a Telecom PPPoE session through TF. MD and the
XG2010G PON port still have no optical signal. All observations below
use the **vendor** NPU firmware, not ClankerNPU.

## Intended topology

| Board | Role | Data path |
|---|---|---|
| XG-040G-TF | Active China Telecom optical gateway | Telecom PON to Internet bridge on its 2.5G `lan1`; IPTV service bridge to `lan2` and set-top box |
| XG2010G | Main router | Telecom PPPoE on 2.5G `lan3` from TF; China Unicom PON/PPPoE on `pon0`; `lan1` and `lan2` (10G) plus `lan4` (1G) are LAN |
| XG-040G-MD | Spare optical gateway and first recoverable NPU test board | Keep production PON settings independent of TF and XG2010G |

The XG2010G port names above are from the device tree and current Linux
enumeration, **not** from connector labels. Before moving cables, check
the physical connector-to-interface mapping on the actual board. XG2010G
`lan3` is now outside `br-lan` and is the lower device of the active
`pppoe-wanb` Telecom session. TF places `lan1` in its Internet bridge
and `lan2` in its IPTV bridge. TF's PON has reached O5 and IPTV multicast
packets arrive on a PON virtual interface, but TF `lan2` has no carrier;
IPTV playback and hardware replication remain untested.
The IPTV set-top box on TF `lan2` bypasses XG2010G entirely.

## What “offload” means here

The target for established eligible unicast flows is host flowtable
hardware offload into the Airoha PPE/FE/QDMA datapath. NPU firmware
participates in the platform's control and special datapaths; it is
not a replacement for Linux policy routing or a requirement that every
packet execute on an NPU hart. PPPoE setup, initial connection packets,
dynamic route selection, exceptions, local traffic, IGMP/MLD control
and some multicast/fragmented flows remain on the CPU. Do not declare
success merely because `flow_offloading_hw=1`, `flags offload`, the NPU
version log, or eight watchdog IRQ labels are present.

The checked-in Airoha PPE driver supports PPPoE and VLAN actions and
bridge-type flow entries, but support in source does not prove a live
Telecom or Unicom path will bind. The current local host-driver tree
does not establish an IPTV MDB-to-PPE/QDMA multicast replication path.
Thus TF IPTV hardware replication is a separate, unverified feature;
do not advertise that *all* IPTV traffic is on the NPU. Likewise, a
Linux routed flowtable's ingress-device list does not by itself decide
whether a bridge or multicast packet uses a separate hardware path.

## Bring-up gates

1. Preserve the known-working vendor firmware and a recovery route.
   Boot ClankerNPU first on the spare MD via a recoverable RAM/initramfs
   path. Verify the host version mailbox, absence of traps, hart liveness
   using real telemetry, and basic Ethernet forwarding. A build alone
   is not enough.
2. On TF with the vendor firmware, validate optical registration,
   Telecom Internet bridge, and IPTV separately. Optical O5 and a
   working downstream PPPoE session are now observed; PPE bridge
   binding and IPTV egress are still open. Record optical and
   thermal health before sustained load. For the Internet bridge,
   observe a bound L2 flow with learned nonzero MAC addresses and
   increasing PPE counters. For IPTV, verify IGMP/MLD joins, MDB
   entries, playback and channel changes; hardware replication needs
   separate driver/counter evidence.
3. On XG2010G, `lan3` has already been moved out of `br-lan` and
   configured as the Telecom PPPoE WAN. Continue testing LAN isolation,
   NAT and hardware offload under controlled traffic before enabling
   the second WAN.
4. Add Unicom optical registration and PON/PPPoE on XG2010G `pon0`.
   The PON host driver must supply the correct GEM/T-CONT/service
   metadata for offload. Validate each WAN in isolation, then both
   simultaneously with `mwan3` policy and failover. Check route and
   egress for every test flow; a fast but misrouted flow fails.
5. Only after equivalent vendor-firmware baselines pass, compare
   ClankerNPU with the vendor 1456.62 image on the same Linux image,
   board, traffic mix and physical links. Use rollback if mailbox,
   forwarding, IPTV or temperature regresses.

### First ClankerNPU RAM-boot acceptance gate

After a recoverable 040GMD RAM boot, run
`scripts/clanker-boot-snapshot.sh` before generating traffic. The script is
read-only: it reads the NDBG SRAM block with `devmem`, takes two heartbeat
samples two seconds apart, checks the exact CI firmware hashes and build ID,
scans the bounded NPU boot log, and reads the per-PPE enable bits exposed by
the diagnostic kernel. It does not alter UCI, routes, flash, firmware memory,
PPE tables or NDBG command fields.

The first boot passes only when all of these are true:

- Linux reports `NPU fw version: 7.8`, not the stock `1456.62`.
- NDBG magic is present and the build ID is exactly
  `TLB7.8.0.0_v003.NOWIFI.da0d0dc`.
- NDBG reports eight harts; every loop tag is nonzero, every heartbeat changes
  across the two samples, and every trap count remains zero.
- There is no NPU firmware probe failure or host mailbox timeout.
- The embedded RV32/data files match the CI SHA-256 values.
- `ppe0_enabled` and `ppe1_enabled` are both `1`. These flags prove only that
  both engines are enabled; they do not prove that either engine processed a
  test flow.

If debugfs is unavailable, the result is `INCOMPLETE`, not a pass. If any
firmware, hart, trap or mailbox check fails, stop before traffic testing and
return to the stock image through the already-validated RAM-boot recovery
path. Flow ownership, hardware offload, PPPoE, PON and IPTV remain later
gates even when this first-boot script prints `overall=PASS`.

## Evidence required for each flow class

| Flow class | Proof to collect | Current status |
|---|---|---|
| TF PON-to-2.5G Internet bridge | PON service up, correct VLAN, bound PPE L2 entry with learned MAC, counters increasing while traffic crosses TF | O5 and downstream PPPoE observed; TF bridge PPE binding not proven |
| TF PON-to-`lan2` IPTV | Correct bridge/MDB and stable playback; for hardware claim, matching multicast replication entry and hardware counters | Multicast ingress observed; `lan2` has no carrier; egress/offload not proven |
| XG Telecom PPPoE `lan3` to LAN | Correct WAN egress, conntrack `[HW_OFFLOAD]` rather than only `[OFFLOAD]`, PPE bound entry/counters, bidirectional throughput and CPU | Vendor-firmware IPv4 TCP download reached `[HW_OFFLOAD]` and two PPE BND entries during one run; repeat 2 MB sample remained `[OFFLOAD]`, so coverage/stability still open |
| XG Unicom PON PPPoE to LAN | Same evidence, plus PON GEM/T-CONT mapping and optical registration | Not testable yet: no fiber |
| Both WANs with `mwan3` | Per-flow policy/egress, hardware entries on both WANs, failover and reconnection without stale routes or leaks | Not configured yet |
| MD standby | Vendor firmware boot and normal gateway functions; Clanker pilot only through recoverable path | Vendor 1456.62 boot/version response observed; no forwarding path or Clanker run yet |

For each run record image/firmware hash, board, port/link speed, flow
direction, IPv4/IPv6, packet size, concurrency, throughput, CPU and
temperature. Keep the baseline and after-load PPE/flowtable snapshots.
Router-local `iperf3` is a CPU endpoint test, not forwarding-offload
proof. A short speed result is not a thermal or stability qualification.

## Present observations and known gaps

- All three boards report vendor NPU firmware 1456.62 at boot. On MD,
  with no eligible forwarded traffic, `npu_attached: 0` and empty PPE
  bind tables are expected from lazy PPE initialization. XG2010G now
  reports `npu_attached: 1` with active Telecom PPPoE.
- XG2010G's current `nft` routed flowtable lists `lan1`, `lan2`,
  `lan3`, `lan4`, and `pppoe-wanb` with `flags offload`. TF's routed
  flowtable lists `lan1`, `lan3`, `lan4`, and `pon0`, not `lan2`; this
  alone cannot establish its bridge or multicast hardware path.
- A Windows host with several NICs normally uses Ethernet 4 for its
  default Internet route. Merely binding curl to the Ethernet 6 IPv4
  address did **not** guarantee egress over Ethernet 6. The bounded
  `scripts/windows-interface-download.ps1` probe uses Windows
  `IP_UNICAST_IF` to pin only the test socket to Ethernet 6, without
  changing the PC's default route. One 3 MB IPv4 TCP download through
  XG2010G showed a matching conntrack `[HW_OFFLOAD]`, two PPE `BND`
  entries, and an approximately 3.47 MB Ethernet 6 receive delta.
  A later 2 MB transfer was sampled as `[OFFLOAD]` with no BND entry;
  this is evidence of at least one successful hardware-offloaded flow,
  **not** a claim that all flows or all packets offload reliably.
- TF now reports `lifecycle: operational`, `optical_signal: 1`, ONU
  state O5, and multicast receive traffic on `ct-iptv-mc`. TF `lan2`
  is disconnected, so neither IPTV egress nor hardware multicast
  replication has been verified. XG2010G and MD still report no PON
  optical signal.
- The XG2010G 10G `lan1` PCS has shown a `No FBCK Lock` boot warning.
  Link training and sustained traffic must be checked with an actual
  10G peer before counting both 10G ports as validated.
- **FLOW_STATS_SETUP compatibility gate:** the host's
  `airoha_ppe_offload_setup()` calls `ppe_init_stats()` when
  `CONFIG_NET_AIROHA_FLOW_STATS=y`. The host sends PPE mailbox function
  ID 4 and aborts offload setup on failure. The current ClankerNPU source
  now answers this request with a 64 KiB reserved DRAM window at
  `0x84900000`, matching 8,192 entries of 8 bytes, and clears the window
  before publishing it. CI now checks the linked base and size against
  `0x84900000` and `0x10000`, protecting the two-PPE / 8,192-entry host ABI
  from accidental linker-layout changes. The AN7581 target kernel config in the XG2010G
  build tree enables flow stats, but the running devices do not expose
  `/proc/config.gz`, so their compiled setting is not yet proven.
  The current PBS05 040GMD diagnostic FIT is a separate build: its resolved
  Linux 6.18.52 `.config` explicitly has
  `# CONFIG_NET_AIROHA_FLOW_STATS is not set`. That image therefore does not
  call the host's function-4 `FLOW_STATS_SETUP` handshake and cannot validate
  that ABI. Keep the current FIT's result scoped to kernel build and PPE
  enable-state observability; a separate recoverable test build must enable
  flow stats before function 4 can be exercised.
  **Source-level size cross-check (PBS05 Linux 6.18.52):**
  `PPE_STATS_NUM_ENTRIES` is 4,096 per PPE, `en7581_soc_data.num_ppe` is 2,
  and `struct airoha_foe_stats` is two 32-bit words. The host therefore passes
  8,192 entries and maps 65,536 bytes, exactly the size ClankerNPU advertises.
  The target Kconfig defaults the option on, but PBS05's AN7581 config fragment
  explicitly turns it off; the resolved `.config` confirms the fragment wins.
  This proves the size arithmetic only, not unique coverage of every FOE hash
  or valid counter production.
  **This is initialization compatibility only:** ClankerNPU does not yet
  maintain the NPU-side counter words. The host mapping, PPE writes,
  reported counter values, memory lifetime and cache behavior all need
  on-board verification. Do not use these counters as offload proof yet.
  The NDBG `FSTA` symbol and `NDBG_PPE` status line expose the setup result,
  the two buffer addresses, and `counter_producer_registered=0`; a
  successful setup still is not evidence of live packet/byte accounting.
  A recoverable **test** kernel with flow stats disabled can still
  isolate basic PPE compatibility without validating NPU flow statistics.
- **Host flow-stat path audit:** the 6.18.52 PPE driver calls
  `airoha_ppe_foe_flow_stats_update()` as it commits routed FOE entries and
  resets the host and NPU counter halves for the selected flow-stat index.
  The same function deliberately returns early for AN7581 native bridge
  entries because that counter layout is not verified. The host driver source
  contains allocation, per-entry reset, and read/combination of the two
  counter halves, but no software per-packet increment path. This narrows the
  next investigation to the PPE/NPU hardware event/update mechanism; it is not
  safe to synthesize increments in ClankerNPU without identifying that event
  and its index/ownership semantics.
- **Single-flow evidence tooling:** the Windows HTTPS probe now reports the
  exact client source port, validates HTTP 200 and the requested body length,
  and reports payload throughput separately from adapter byte deltas. Pass
  its server IPv4, port, source port, and source IPv4 to
  `sh scripts/offload-snapshot.sh <peer-ipv4> <peer-port> <source-port> <source-ipv4>`
  on XG2010G to print the matching conntrack row and PPE `BND` candidate.
  The candidate output suppresses the unverified per-flow packet/byte values.
  This is a read-only correlation helper, not proof by itself; correlate the
  row with `[HW_OFFLOAD]`, actual Ethernet egress, and the selected WAN.
- XG2010G bridge L2 binding and PON offload host-driver fixes have
  been developed separately, but the latest test image with the bridge
  fix has not been flashed or validated on the live board.
- Avoid production cutover or flash changes until optical links,
  recovery procedure and end-to-end traffic generation are available.

## XG-040G-MD ClankerNPU preflight (2026-09-28)

- Live SoC ID reads are `0x000E0000` and `0x0204B006`, matching the
  existing ClankerNPU AN7581 family/revision capability entry. The
  driver loads the vendor RV32/data images from `/lib/firmware/airoha/`.
- The vendor firmware version mailbox replies `1456.62`; no NPU WDT
  interrupt was observed. Eight WDT labels are not eight live hart
  heartbeats. The local `AN7581_NOWIFI` image builds and contains the
  no-Wi-Fi version handler, PPE handler and core-7 entry. This remains
  static evidence only: the board has **not** run ClankerNPU.
- Only MD `lan1` has a physical link; `pon0` has no optical signal.
  Router-local traffic cannot prove forwarding offload. No second
  physical traffic endpoint is currently connected to MD.
- MD exposes one UBI `fit` system-image volume and no `kexec` command.
  A validated serial/U-Boot RAM-boot or equivalent recovery method is
  required before replacing firmware and rebooting. Do not assume an
  A/B rollback slot. Keep the vendor image and hashes intact.

For repeatable, read-only baseline collection on an Airoha OpenWrt
device, run `sh scripts/offload-snapshot.sh` on the device (or pipe this
file to `ssh root@DEVICE sh -s`). The script reports only interface,
flowtable, PPE and thermal summaries; it does not read LOID, PPPoE
credentials or packet payloads. Run it before and during controlled
forwarding traffic and compare the two outputs.

## Live field log (2026-09-28)

- **040GTF:** optical registration reached O5 and the Telecom Internet
  bridge fed the XG2010G PPPoE session. The IPTV bridge received
  multicast traffic, but `lan2` had no carrier, so playback and hardware
  replication were not tested.
- **XG2010G:** Telecom PPPoE ran over `lan3` from TF. A Windows test
  socket was explicitly pinned to Ethernet 6 while the PC's normal
  Internet route remained on Ethernet 4. One 3 MB download showed the
  vendor-firmware flow as `[HW_OFFLOAD]` with two PPE BND entries; a
  later 2 MB sample showed `[OFFLOAD]` without BND. This confirms one
  observed hardware-offloaded flow, not consistent offload coverage.
  XG2010G `pon0` still had no optical signal, so Unicom and dual-WAN
  tests remain open.
- **040GMD:** stock NPU firmware 1456.62 booted and answered the version
  query. SoC IDs were `0x000E0000` and `0x0204B006`, matching the
  existing AN7581 capability entry. Only `lan1` was connected to the
  Windows test host; PON had no optical signal and no forwarding flow
  existed. The device has one UBI `fit` volume and no `kexec` utility;
  serial/U-Boot RAM recovery has not been established. ClankerNPU has
  **not** run on this board. A captured 70.1 °C CPU reading also means
  sustained load should wait until temperatures are rechecked.
## Source work (2026-09-29)

- **ClankerNPU:** `AN7581_NOWIFI` built locally. The image files were
  `npu_rv32.bin` (29,580 bytes, SHA-256
  `1ccf37f394334ec97d4f97818f6b676caf3796163996a438c03bbb614b3837a4`)
  and `npu_data.bin` (128 bytes, SHA-256
  `2ce4e2568962c752f079e53ce35810d2de5271bbbabd8e50ef10cd9e5358af79`).
  Function-4 stats setup now publishes the reserved window described
  above, but the firmware does not yet update NPU-side counters and no
  board has booted this image.
- **Post-merge rebuild (`GITREV=7841433`):**
  `make an7581-nowifi` passed in local WSL. The linker reported DRAM
  `30,084 B / 2 MiB` and SRAM `6,816 B / 64 KiB`. The ELF contains
  `core7_main`, `nowifi_mail_dispatch`, `hwnat_mail_dispatch`, and
  `npu_flow_stats_setup`; the linked stats window remains
  `0x84900000` with size `0x10000`, and the image contains the
  `producer_registered` diagnostic marker. SHA-256:
  `npu_rv32.bin` =
  `464d25d0b036d55eeb2ab3bcad255f36aae91a4bc88aa5b381122727deb8778b`;
  `npu_data.bin` =
  `b1d0f6c37ee282838ab237f68e8416ca6bc2f7fe8c131f7e1e1caa89e3e0a`.
  This verifies a local build and static layout/symbol checks only; it does
  not prove mailbox compatibility at runtime, live stats production, PPE
  traffic, or a successful boot. No device was modified.
- The Linux PPE source audit confirmed the AN7581 native-L2B counter path is
  intentionally skipped by the host driver, while routed-flow setup rewrites
  the FOE entry and resets the indexed counter storage. No live flow test was
  performed in this work session because Windows Ethernet 6 (the designated
  XG2010G test interface) reported **Not Present**. The test scripts passed
  PowerShell and POSIX-shell syntax validation only; no hardware result is
  implied.
- A fresh host-side check on 2026-09-29 again showed Ethernet 4 up at 10 Gbps
  and Ethernet 6 **Not Present**. No router SSH snapshot or traffic test was
  attempted, and no interface/default-route settings were changed.

Next: establish a recoverable RAM-boot path for MD, attach a second
traffic endpoint, recheck temperature, then verify Clanker mailbox,
hart/trap telemetry, PPE setup and real forwarded flows. Continue with
TF IPTV egress and XG2010G Unicom PON only when those links are present.

