# WorkBuddy to Codex handoff: XG2010G hardware offload

> Captured from the WorkBuddy handoff prepared on 2026-09-29 at 23:42 (local time).
> This is a status record, not a claim that the proposed comparison test passed.

## Summary

WorkBuddy investigated why some XG2010G forwarded flows showed software
`[OFFLOAD]` without PPE binding. It observed a PPPoE logical WAN interface
with `hw-tc-offload: off [fixed]`, while physical Ethernet ports reported
offload capability. It also recorded runs with an active NPU attachment but
only unbound (`UNB`) FOE entries and no `[HW_OFFLOAD]` flows.

The report proposed PPPoE membership as the cause. That remains **unproven**:
another same-day XG2010G record reports a 3 MB TCP transfer while PPPoE was
active with a matching conntrack `[HW_OFFLOAD]` entry and two PPE `BND`
entries. The observations conflict and must be reconciled with a controlled,
repeatable flow test before assigning a root cause.

## Evidence from the handoff

- The board was identified as Gemtek XG2010G (`gemtek,xg2010g`, chip ID
  `0x0404B002`) running Linux 6.18.52.
- With PPPoE active, `npu_attached` was `1`. WorkBuddy found real forwarded
  IPv6 TCP traffic carrying software `[OFFLOAD]`, while its later snapshot
  showed no `BND` entries and an empty PPE bind view.
- In a subsequent non-dialing static-WAN comparison setup, the flowtable
  listed physical interfaces only and `npu_attached` remained `1`; the
  recorded snapshot still had no `[HW_OFFLOAD]`, no `BND`, and no bind entry.
  This comparison did not include a completed, valid TCP/UDP cross-port flow.
- The captured `inet fw4 forward` rule added only TCP and UDP flows to the
  flowtable. ICMP/ping results therefore cannot establish whether those
  flows were hardware-offloaded.
- The handoff reports that the WAN had been changed to a temporary static
  configuration and was offline at 23:42. A reboot removed temporary runtime
  addresses and nft rules, but did not restore the persistent WAN setting.
  Recheck the live device state before any further test and restore normal
  service through the locally held recovery material when appropriate. No
  credentials or private endpoint addresses are included here.

## Corrections and test requirements

1. `hw-tc-offload: off [fixed]` on the PPP logical interface is a relevant
   observation, but by itself does not prove that PPPoE flowtable offload is
   structurally impossible. The reported successful PPPoE `[HW_OFFLOAD]`
   sample contradicts that categorical conclusion. Check the exact flow,
   ingress/egress devices, kernel build, PPE binding and conntrack state for
   both observations.
2. A packet addressed to an IP assigned to the router itself is locally
   delivered to the router; it is not a valid LAN-to-WAN forwarded flow.
   The proposed UDP test targeting the router's own address must not be used
   as proof of cross-port forwarding. Use two distinct endpoints on different
   routed interfaces, then confirm the connection is forwarded in both
   directions and reaches the expected egress.
3. For a hardware-offload pass, collect the same-flow evidence together:
   conntrack `[HW_OFFLOAD]`, a matching PPE `BND`/bind entry, expected route
   and egress, and traffic counters that are known to be produced by the
   active firmware/driver. `npu_attached=1`, an `UNB` entry, or an enabled
   flowtable alone is not a pass.
4. Keep the XG040GMD DSA/GSW topology findings separate from this XG2010G
   PPPoE investigation; they are different board paths and need independent
   evidence.

## Next steps

1. When the device is reachable, identify it by board name and chip ID, then
   record its live WAN protocol and link state before touching configuration.
2. Reconcile the earlier PPPoE success with the later non-binding snapshots
   using repeatable TCP/UDP forwarded flows and matched PPE/conntrack reads.
3. Use a real second endpoint on the opposite routed port. Do not target an
   address owned by the router or rely on router-originated traffic.
4. Only after the baseline is repeatable, compare PPPoE and non-PPPoE paths.
   Keep the vendor 1456.62 firmware as the control until the host/NPU firmware
   and flow-counter producer are also held constant.


