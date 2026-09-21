# cajeta-gossip

SWIM-style cluster membership and dissemination for [Cajeta](https://github.com/jklappenbach/cajeta).

An **external sibling library** — not part of the Cajeta standard library. It
builds on the `cajeta.io.net` stdlib transport (`UdpSocket`, and multicast for
discovery) to maintain an eventually-consistent view of a dynamic set of peer
nodes (alive / suspect / dead) and to spread small updates epidemically.

It is a library rather than stdlib by design: gossip is an opinionated,
evolving protocol, and the universal precedent (serf/memberlist, JGroups, Akka
Cluster) is to ship membership as a library. Stdlib owns the transport
primitives; gossip rides on top. (Same relationship Toffee has to the GPU stack.)

- **Package:** `dev.cajeta.gossip` (reverse-DNS, per the `dev.cajeta.http` ecosystem convention)
- **Status:** 0.1.2, v1 core complete. Wire codec, SWIM membership core, UDP
  transport binding, join/leave, epidemic dissemination with incarnation-bump
  refutation, and the 5-node cluster suite: 133 checks green under both
  `CAJETA_CARRIERS=1` and the default pool. Developed and gated against
  cajeta v0.29.0. The floor is cajeta ≥ 0.11.0, which is where the NET-14
  multicast surface discovery needs first shipped, and the suite still
  reports 133/133 there.
- **Spec:** [`docs/CajetaGossip.md`](docs/CajetaGossip.md)
- **Plan:** [`plans/cajeta-gossip-plan.md`](plans/cajeta-gossip-plan.md)

> **Build note:** this repo builds as a Cajeta *library* (cajeta ≥ 0.9.2 —
> the first toolchain with the library project kind): `cajeta build` emits
> `build/archive/dev.cajeta.gossip-<version>.cja`. `test/phase0.sh` pins the
> Phase 0 acceptance (library build + a throwaway consumer resolving it from
> a filesystem repository).
