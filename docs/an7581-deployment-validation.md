# AN7581 three-board deployment and validation

This is a test plan, not a claim that ClankerNPU has run on any board.
The three devices currently run a custom ImmortalWrt 6.18.52 image with
the Airoha Linux NPU driver and vendor NPU firmware version 1456.62.
There is no optical connection yet, so PON, PPPoE, IPTV and dual-WAN
offload have not been measured on this deployment.

## Intended topology

| Board | Role | Data path |
|---|---|---|
| XG-040G-TF | Active China Telecom optical gateway | Telecom PON to Internet bridge on its 2.5G `lan1`; IPTV service bridge to `lan2` and set-top box |
| XG2010G | Main router | Telecom PPPoE on 2.5G `lan3` from TF; China Unicom PON/PPPoE on `pon0`; `lan1` and `lan2` (10G) plus `lan4` (1G) are LAN |
| XG-040G-MD | Spare optical gateway and first recoverable NPU test board | Keep production PON settings independent of TF and XG2010G |

The XG2010G port names above are from the device tree and current Linux
enumeration, **not** from connector labels. Before moving cables, check
the physical connector-to-interface mapping on the actual board. Today
all four XG2010G `lan*` interfaces are still members of `br-lan`, so
`lan3` is not yet a Telecom WAN. TF already places `lan1` in its
Internet bridge and `lan2` in its IPTV bridge, but both PON and IPTV
service behavior remain untested without the optical/service links.
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
   Telecom Internet bridge, and IPTV separately. Record optical and
   thermal health before sustained load. For the Internet bridge,
   observe a bound L2 flow with learned nonzero MAC addresses and
   increasing PPE counters. For IPTV, verify IGMP/MLD joins, MDB
   entries, playback and channel changes; hardware replication needs
   separate driver/counter evidence.
3. Move only XG2010G `lan3` out of `br-lan`, after confirming cabling
   and management access, and configure it as the Telecom PPPoE WAN.
   Validate LAN isolation, ordinary routing, NAT and then hardware
   offload before enabling the second WAN.
4. Add Unicom optical registration and PON/PPPoE on XG2010G `pon0`.
   The PON host driver must supply the correct GEM/T-CONT/service
   metadata for offload. Validate each WAN in isolation, then both
   simultaneously with `mwan3` policy and failover. Check route and
   egress for every test flow; a fast but misrouted flow fails.
5. Only after equivalent vendor-firmware baselines pass, compare
   ClankerNPU with the vendor 1456.62 image on the same Linux image,
   board, traffic mix and physical links. Use rollback if mailbox,
   forwarding, IPTV or temperature regresses.

## Evidence required for each flow class

| Flow class | Proof to collect | Current status |
|---|---|---|
| TF PON-to-2.5G Internet bridge | PON service up, correct VLAN, bound PPE L2 entry with learned MAC, counters increasing while traffic crosses TF | Not testable yet: no fiber |
| TF PON-to-`lan2` IPTV | Correct bridge/MDB and stable playback; for hardware claim, matching multicast replication entry and hardware counters | Not testable yet: no fiber/IPTV source |
| XG Telecom PPPoE `lan3` to 10G/1G LAN | Correct WAN egress, conntrack `[HW_OFFLOAD]` rather than only `[OFFLOAD]`, PPE bound entry/counters, bidirectional throughput and CPU | Not configured yet |
| XG Unicom PON PPPoE to LAN | Same evidence, plus PON GEM/T-CONT mapping and optical registration | Not testable yet: no fiber |
| Both WANs with `mwan3` | Per-flow policy/egress, hardware entries on both WANs, failover and reconnection without stale routes or leaks | Not configured yet |
| MD standby | Vendor firmware boot and normal gateway functions; Clanker pilot only through recoverable path | Vendor boot observed; Clanker untested |

For each run record image/firmware hash, board, port/link speed, flow
direction, IPv4/IPv6, packet size, concurrency, throughput, CPU and
temperature. Keep the baseline and after-load PPE/flowtable snapshots.
Router-local `iperf3` is a CPU endpoint test, not forwarding-offload
proof. A short speed result is not a thermal or stability qualification.

## Present observations and known gaps

- All three boards report NPU firmware 1456.62 at boot. With no eligible
  forwarded traffic, `npu_attached: 0` and empty PPE bind tables are
  expected from this driver's lazy PPE initialization; neither proves a
  broken NPU nor proves working offload.
- XG2010G's current `nft` routed flowtable lists `lan1`–`lan4` and
  `pon0` with `flags offload`; its network configuration still has only
  LAN. TF's corresponding routed flowtable lists `lan1`, `lan3`,
  `lan4`, not `pon0`/`lan2`; this alone cannot establish the status of
  its bridge or multicast hardware path.
- The XG2010G 10G `lan1` PCS has shown a `No FBCK Lock` boot warning.
  Link training and sustained traffic must be checked with an actual
  10G peer before counting both 10G ports as validated.
- XG2010G bridge L2 binding and PON offload host-driver fixes have
  been developed separately, but the latest test image with the bridge
  fix has not been flashed or validated on the live board.
- Avoid production cutover or flash changes until optical links,
  recovery procedure and end-to-end traffic generation are available.
