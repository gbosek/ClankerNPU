# AN7581 NPU project charter

**Status:** active; reconciled with the design and field records on 2026-09-29.

## Mission

Make XG2010G a policy-correct dual-WAN router that sends the maximum set of
hardware-supported, established flows through the AN7581 PPE/PSE/QDMA fast
path. Linux remains responsible for connection setup, mwan3 policy decisions,
control traffic and exceptions. ClankerNPU supplies a board-neutral AN7581
NOWIFI image and the NPU control, tunnel, bridge and observability functions
that are actually part of its firmware ABI.

“All eligible traffic is hardware accelerated” does **not** mean every packet
must execute on one of the eight NPU harts. PPE/PSE/QDMA are the bulk forwarding
datapath. An enabled setting, a firmware version string, `npu_attached`, or a
low CPU reading alone is not proof of offload.

## Intended deployment

| Device | Intended role | Validation boundary |
|---|---|---|
| XG-040G-TF | Telecom PON/LOID, Internet bridge to XG2010G 2.5G Ethernet WAN; IPTV service to LAN2 | Its IPTV path terminates on the TF and bypasses XG2010G. Prove bridge and multicast forwarding separately. |
| XG2010G | Main router; Telecom PPPoE over the TF bridge, China Unicom PON/PPPoE when optical service is available, mwan3, PPE and LAN | Confirm physical connector-to-interface mapping. Target LAN is two 10G ports plus one 1G port; the 2.5G Ethernet port is the Telecom WAN. |
| XG-040G-MD | Spare/standby optical gateway and first ClankerNPU test candidate | Preserve stock operation. No experimental firmware boot or flash until a tested recovery path exists. |

The design goal for XG2010G is connection-level WAN selection by mwan3, not
combining two WANs into one faster TCP connection. Each tested flow must use
the policy-selected WAN in both directions; eligible established traffic may
then bind into PPE hardware. PON bearer mapping, PPPoE, routed NAT, native L2
bridge and IPTV multicast are separate flow classes and need separate proof.

## Execution phases

| Phase | Work and exit evidence | Current state |
|---|---|---|
| 0. Baseline and safety | Record board/firmware hashes, port map, stock NPU version, temperatures, recovery method and read-only snapshots. Keep the vendor 1456.62 image as the comparison baseline. | Most device identity and stock-NPU data are recorded; MD recovery is unresolved. |
| 1. Generic profile and ABI | Build `AN7581_NOWIFI`; verify chip-capability entries, version-query mailbox behavior, PPE mailbox layouts and linker/memory bounds. | Version query and function-4 setup build are present; PPE handlers now validate the host's byte-counted payload lengths. Runtime ABI is not yet proven. |
| 2. Recoverable NPU bring-up | On a spare board with a demonstrated RAM-boot/recovery route, verify firmware load, real hart liveness, traps, mailbox replies and PPE initialization. | Blocked until MD recovery and a second traffic endpoint are available. |
| 3. Single-WAN routed baseline | On XG2010G, repeat IPv4/IPv6 PPPoE forwarding tests; correlate the exact test flow with conntrack `[HW_OFFLOAD]`, PPE BND/bind evidence, throughput, CPU and temperature. | One short flow showed hardware-offload evidence; repeatability and coverage remain open. |
| 4. Native L2 bridge | Validate the 930 native-L2B driver fix with a second physical host. Check learned nonzero MACs, BND state, bind/TC evidence and traffic crossing the bridge. | Fix is in the r16 source/image; live bridge acceptance is open. The driver intentionally has no verified BRIDGE packet counter. |
| 5. TF IPTV | Verify IGMP/MLD membership, LAN2 link, playback/channel changes, then prove hardware replication with the corresponding PPE/QDMA evidence. | PON reaches O5 and multicast is seen ingress-side; LAN2 egress/playback and replication are unverified. |
| 6. Dual WAN and mwan3 | With both optical services present, test each WAN alone, policy routing, simultaneous multi-flow load, failover/recovery and hardware binding on each egress. | XG2010G PON is currently without optical signal; dual-WAN acceptance is blocked. |
| 7. A/B and release | Compare stock 1456.62 and ClankerNPU under the same image, board, links and traffic mix. Report throughput, PPS (including 64-byte packets), CPU, drops, temperature and stability; publish the evidence and rollback image hashes. | Not started; do not claim release readiness. |

## Consolidated implementation backlog

1. Maintain a per-board compatibility matrix for device-tree identity, raw SoC
   IDs, capability-table match, host driver and stock NPU observations.
2. Preserve stock images and record a tested recovery procedure before any
   experimental boot or firmware replacement.
3. Audit every host-to-NPU mailbox operation used by AN7581 NOWIFI, including
   message length, field offsets, result semantics and unsupported calls.
4. Complete the `FLOW_STATS_SETUP` contract: prove the reserved window is safe,
   mapped as expected, and populated with valid counters before treating stats
   as evidence.
5. Keep a reproducible NOWIFI build and CI checks for required entry points,
   memory layout and generated artifacts.
6. Prove ClankerNPU boot, mailbox, traps and live hart progress on a recoverable
   spare board.
7. Establish repeatable single-WAN PPPoE routed-offload results on XG2010G.
8. Validate native L2 bridge offload separately from routed flow offload.
9. Validate the TF IPTV egress and hardware multicast replication path.
10. Add and verify XG2010G Unicom PON plus mwan3 policy/failover only when the
    optical path is available.
11. Run controlled stock-versus-Clanker performance/stability tests and keep
    the sanitized results, code and conclusions synchronized to GitHub.

## Definition of done

- ClankerNPU boots on each claimed AN7581 board revision through a recoverable
  procedure, answers the host ABI correctly, shows live hart progress and no
  unexplained trap/reset loop, and does not break Ethernet/PON host operation.
- For each claimed routed flow class, the selected WAN is correct and repeated
  traffic evidence shows hardware binding/forwarding, not merely an enabled
  flowtable. CPU and PPE/QDMA counters must be internally consistent.
- Native bridge acceptance uses learned MACs, bind/TC evidence and traffic
  across two physical endpoints; it does not require the deliberately
  unsupported native-L2B `packets` counter.
- IPTV hardware acceleration is claimed only with multicast hardware-path
  evidence; working playback or PON ingress alone is insufficient.
- Dual-WAN acceptance covers each WAN independently, simultaneous connections,
  mwan3 policy and failover without route leaks or stale-flow misrouting.
- A/B reports use the same test conditions and include throughput, small-packet
  PPS, multi-flow behavior, CPU, drops, temperature and sustained stability.
- Every result is labeled as source/build evidence, live device evidence, or
  still unverified. No unsupported promise that literally every packet uses an
  NPU hart is part of acceptance.

## Safety and rollback rules

- Do not flash or replace NPU firmware until the exact device has a proven
  recovery path and the stock firmware/hash is retained.
- Do not change PON, QDMA, PPE ageing/bind thresholds, or register mappings as a
  performance guess. Establish a baseline and isolate one variable first.
- Never publish LOID, PPPoE/IPTV credentials, private keys, or unredacted
  customer identifiers in source control or test logs.
- A compile, a version string, `flow_offloading_hw=1`, or a single transient
  `[HW_OFFLOAD]` observation is not a release pass.

## Source of truth

- [Three-board compatibility matrix](compatibility-matrix.md)
- [Detailed deployment, field evidence and validation gates](an7581-deployment-validation.md)
- [Generic AN7581 NOWIFI profile](an7581-nowifi.md)
- [Mailbox ABI notes](mailbox.md)
