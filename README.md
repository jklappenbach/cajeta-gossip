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
- **Status:** designed; Phase 0 (library build) done — builds as
  `dev.cajeta.gossip` 0.1.0; the protocol is not yet implemented.
- **Spec:** [`docs/CajetaGossip.md`](docs/CajetaGossip.md)
- **Plan:** [`plans/cajeta-gossip-plan.md`](plans/cajeta-gossip-plan.md)

> **Build note:** this repo builds as a Cajeta *library* (cajeta ≥ 0.9.2 —
> the first toolchain with the library project kind): `cajeta build` emits
> `build/archive/dev.cajeta.gossip-<version>.cja`. `test/phase0.sh` pins the
> Phase 0 acceptance (library build + a throwaway consumer resolving it from
> a filesystem repository).
