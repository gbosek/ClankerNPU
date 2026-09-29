# PON userspace / LuCI update assessment

Status: source and package-build review only, 2026-09-29. No router was modified, and this is not a firmware-integration or runtime-compatibility claim.

## Compared sources and build evidence

- The pbs05 validation build tree pins `pon_userspace` at `8b9e99921e7380f6f117cf6464d903b2b76e48c6`.
- The reviewed `naoki66/openwrt-pon-userspace` head is `e783f8fa824560f66bddfa967e54fdc38b7848c3`, seven commits ahead and zero behind that pin. The seven commits are LuCI/application changes; `airoha-ponctl`, `airoha-pond`, and the board-identification/calibration helper implementations were not changed in this range.
- `luci-app-pon` compiled successfully against the local aarch64 Cortex-A53 pbs05 build tree and produced `luci-app-pon-0.1.0-r6.apk` (33,648 bytes; SHA-256 `abffd4a2235e8f80eb011ac0d07715dc02257416b1cc1e7a8697c49053ca5bb9`). This was a package build, not a full image build. The package was not installed and no device was flashed.
- A local static UI preview was generated from the latest view sources with synthetic data. Status markup uses the view renderer; form controls and browser-only event behavior are approximated. It is a layout aid, not LuCI runtime validation.

## What changed

- The menu changes from **PON** to **ONU** and moves earlier in the menu. The pages are organized as status, hardware identity, authentication configuration, IPTV, voice configuration, and diagnostics.
- The status page uses metric tiles, line-detail rows, and grouped/collapsible counters. The latest commit puts GTC/XGTC synchronization in line details alongside PHY state, rather than treating frame synchronization as an ONU registration tile.
- Board identity and calibration functions are consolidated, and the hardware-identity file upload is restored.
- The separate `luci-app-iptv` is removed and IPTV controls are folded into `luci-app-pon`. The helper adds bridge/trunk/VLAN and IPv4/IPv6 IGMP/MLD configuration, with `omcproxy` for proxy mode and optional `rtp2httpd` multicast-to-unicast support.
- A voice page and voice UCI defaults are added for H.248/SIP and two FXS ports. These UI/config changes alone do not prove a voice daemon or hardware-application path; keep the page out of the production image until that backend is identified and tested.

## Relevance to the AN7581 project

The status, identity, authentication, and diagnostics UI is useful for the 040GTF/040GMD/XG2010G PON-management work. The IPTV page may improve setup and visibility on the 040GTF. Since the helper backends did not change in the reviewed range, their ABI appears unchanged at source level; runtime compatibility on our exact pbs05 image remains unverified.

This is management-plane work, not a ClankerNPU or PPE fast-path change. It does not establish that routed unicast, PPPoE, bridge traffic, or IPTV traverses hardware. The IPTV page configures Linux bridge, IGMP/MLD, proxy, and relay behavior; it does not implement NPU/PPE multicast replication.

The upstream `luci-app-pon/DESIGN.md` says its inspected mainline Airoha driver has no multicast-offload path and that netfilter flowtable does not offload multicast. In our local 6.18 patch set, the `PCE_MC_EN_MASK` patch describes that bit as making a CPU copy of multicast packets when hardware traffic is offloaded; it is not evidence of egress replication. The Airoha forwarding manual in the project notes separately mentions `FP_QDMA_MCAST` for a LAN+HSGMII multicast path. These statements concern potentially different mechanisms. We have not reconciled the manual's path with the exact pbs05 driver, firmware, DTS, and port mapping, so the correct status is **multicast hardware replication unverified**, not “impossible” and not “working.”

## Integration gates

1. Before a full image build, remove stale `luci-app-iptv` / standalone IPTV translation selections that no longer exist in this userspace feed, and resolve the new hard package dependencies: `firewall4`, `kmod-nft-bridge`, and `omcproxy`. `rtp2httpd` is optional unless multicast-to-unicast is wanted.
2. Keep the original pbs05 firmware and vendor NPU 1456.62 as the rollback baseline. Do not apply the IPTV helper on the live 040GTF until its actual bridge, VLAN, and DSA port names are confirmed and a recovery procedure is ready; the helper changes network and firewall topology.
3. Treat voice as unavailable until the matching service backend and board support are demonstrated.
4. For IPTV hardware-offload claims, first prove stable multicast ingress, IGMP/MLD membership, bridge MDB state, correct LAN2 egress/playback, and then a matching PPE/QDMA replication entry or counter. A LuCI toggle, flowtable setting, CPU-copy bit, or multicast MIB counter alone is insufficient.
5. Continue to test ordinary eligible unicast hardware offload separately from multicast. The project target remains Linux/mwan3 policy with PPE/PSE/QDMA carrying eligible stable data-plane flows; ClankerNPU telemetry and special paths must be independently verified.


