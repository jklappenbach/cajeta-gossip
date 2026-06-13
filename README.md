# cajeta-gossip

SWIM-style cluster membership and dissemination for [Cajeta](https://github.com/jklappenbach/cajeta).

An **external sibling library** — not part of the Cajeta standard library. It
builds on the `cajeta.net` stdlib transport (`UdpSocket`, and multicast for
discovery) to maintain an eventually-consistent view of a dynamic set of peer
nodes (alive / suspect / dead) and to spread small updates epidemically.

It is a library rather than stdlib by design: gossip is an opinionated,
evolving protocol, and the universal precedent (serf/memberlist, JGroups, Akka
Cluster) is to ship membership as a library. Stdlib owns the transport
primitives; gossip rides on top. (Same relationship Toffee has to the GPU stack.)

- **Package:** `gossip.*`
- **Status:** designed, not implemented.
- **Spec:** [`docs/CajetaGossip.md`](docs/CajetaGossip.md)
- **Plan:** [`plans/cajeta-gossip-plan.md`](plans/cajeta-gossip-plan.md)

> **Build note:** this repo is intended to build as a Cajeta *library*. The
> Cajeta build tool does not yet have a library build kind (it builds
> executables via an entry method), so the library build is the **first item**
> in the plan and is blocked until `cajeta build-tool` + the init templates grow
> a library archetype. Until then there is no build config here.
