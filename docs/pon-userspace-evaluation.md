# PON userspace / LuCI update assessment

Status: source and package-build review only, 2026-09-29. No router was modified, and this is not a firmware-integration or runtime-compatibility claim.

## Compared sources and build evidence

- The pbs05 validation build tree pins `pon_userspace` at `8b9e99921e7380f6f117cf6464d903b2b76e48c6`.
- The current `naoki66/openwrt-pon-userspace` head is `e5ceb401b7640a9a2be20c3f902a7ecb0a7e77db`, nine commits ahead and zero behind that pin. The changes consolidate and extend LuCI/IPTV userspace. `airoha-ponctl`, `airoha-pond`, and the board-identification/calibration helpers are unchanged; the IPTV UCI schema and `iptv-apply` are changed.
- The latest `luci-app-pon` compiled successfully against the local aarch64 Cortex-A53 pbs05 build tree and produced `luci-app-pon-0.1.0-r6.apk` (34,499 bytes; SHA-256 `8198f1ba07cc8c4941909a5e993b2741d7bc9a4f040f748db94b4bd32af3471a`). This was a package build, not a full image build. The package was not installed and no device was flashed.
- A local static UI preview exists at `XG2010G/_tmp/naoki66-pon-ui-preview-20260929/index.html`, rendered with synthetic data from the prior `e783f8f` view. It does not yet include the latest IPTV tab/relay-VLAN changes. The preview is a layout aid, not LuCI runtime validation.

## What changed

- The menu changes from **PON** to **ONU** and moves earlier in the menu. The pages are organized as status, hardware identity, authentication configuration, IPTV, voice configuration, and diagnostics.
- The status page uses metric tiles, line-detail rows, and grouped/collapsible counters. The latest commit puts GTC/XGTC synchronization in line details alongside PHY state, rather than treating frame synchronization as an ONU registration tile.
- Board identity and calibration functions are consolidated, and the hardware-identity file upload is restored.
- The separate `luci-app-iptv` is removed and IPTV controls are folded into `luci-app-pon`. The helper adds bridge/trunk/VLAN and IPv4/IPv6 IGMP/MLD configuration, with `omcproxy` for proxy mode and optional `rtp2httpd` multicast-to-unicast support.
- A voice page and voice UCI defaults are added for H.248/SIP and two FXS ports. These UI/config changes alone do not prove a voice daemon or hardware-application path; keep the page out of the production image until that backend is identified and tested.
- The latest IPTV update adds a relay-VLAN override for single-cable/trunk mode. It validates that the selected VLAN is actually handed over before binding the relay to its `br-iptv-<vid>` bridge; otherwise an `rtp2httpd` process could start normally but receive no traffic. The page now keeps service, multicast, and IGMP VLANs together, reduces the IPTV tabs from five to four, and derives the relay's upstream device in step with `iptv-apply`, including proxy termination. Links to `udpxy` and `msd_lite` are shortcuts only; this page configures `rtp2httpd`.

## Relevance to the AN7581 project

The status, identity, authentication, and diagnostics UI is useful for the 040GTF/040GMD/XG2010G PON-management work. The IPTV page may improve setup and visibility on the 040GTF. Since the helper backends did not change in the reviewed range, their ABI appears unchanged at source level; runtime compatibility on our exact pbs05 image remains unverified.

This is management-plane work, not a ClankerNPU or PPE fast-path change. It does not establish that routed unicast, PPPoE, bridge traffic, or IPTV traverses hardware. The IPTV page and `iptv-apply` configure Linux bridge, IGMP/MLD, proxy, and relay behavior; they do not implement NPU/PPE multicast replication. The optional `rtp2httpd` path is a userspace multicast-to-HTTP relay, not evidence of hardware multicast forwarding.

The upstream `luci-app-pon/DESIGN.md` says its inspected mainline Airoha driver has no multicast-offload path and that netfilter flowtable does not offload multicast. In our local 6.18 patch set, the `PCE_MC_EN_MASK` patch describes that bit as making a CPU copy of multicast packets when hardware traffic is offloaded; it is not evidence of egress replication. The Airoha forwarding manual in the project notes separately mentions `FP_QDMA_MCAST` for a LAN+HSGMII multicast path. These statements concern potentially different mechanisms. We have not reconciled the manual's path with the exact pbs05 driver, firmware, DTS, and port mapping, so the correct status is **multicast hardware replication unverified**, not “impossible” and not “working.”

## Integration gates

1. Before a full image build, remove stale `luci-app-iptv` / standalone IPTV translation selections that no longer exist in this userspace feed, and resolve the new hard package dependencies: `firewall4`, `kmod-nft-bridge`, and `omcproxy`. `rtp2httpd` is optional unless multicast-to-unicast is wanted.
2. Keep the original pbs05 firmware and vendor NPU 1456.62 as the rollback baseline. Do not apply the IPTV helper on the live 040GTF until its actual bridge, VLAN, and DSA port names are confirmed and a recovery procedure is ready; the helper changes network and firewall topology.
3. Treat voice as unavailable until the matching service backend and board support are demonstrated.
4. For IPTV hardware-offload claims, first prove stable multicast ingress, IGMP/MLD membership, bridge MDB state, correct LAN2 egress/playback, and then a matching PPE/QDMA replication entry or counter. A LuCI toggle, flowtable setting, CPU-copy bit, or multicast MIB counter alone is insufficient.
5. Continue to test ordinary eligible unicast hardware offload separately from multicast. The project target remains Linux/mwan3 policy with PPE/PSE/QDMA carrying eligible stable data-plane flows; ClankerNPU telemetry and special paths must be independently verified.

## NPU status-page telemetry correction (2026-09-29)

The pbs05-selected `luci-app-airoha-npu` package (`1.2.1-r9`) was reviewed and rebuilt locally after correcting several labels that overstated what the collected counters prove:

- Host-driver binding is now shown as **Driver bound**, not “NPU active.” The kernel's `NPU fw version` log is identified as probe-time mailbox evidence, not a live heartbeat; the configured firmware image's extracted version marker is kept separate.
- `/proc/interrupts` watchdog rows are reported as **WDT IRQ lines**, not a count of NPU harts.
- PPE `BND` and table counts are labeled as PPE table counters, with an explicit note that they do not prove NPU traffic handling. The reader accepts both indexed debugfs table output and the single-number counter format.
- Old RPC field names remain as compatibility aliases, but the UI consumes the explicit semantic fields.

Validation: JavaScript syntax, shell syntax, and Chinese PO validation passed. The pbs05 package target compiled successfully to `luci-app-airoha-npu-1.2.1-r9.apk`; the build printed a pre-existing “configuration is out of sync” warning but exited successfully. This was a package-only offline build, not a full firmware build, install, or hardware test. The package remains local to the validation/build trees and has not been installed on a router.


