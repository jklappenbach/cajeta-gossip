# Plan: `cajeta-gossip` — SWIM cluster membership (external library)

Status: **Planned, blocked on Phase 0.** Spec: [`../docs/CajetaGossip.md`](../docs/CajetaGossip.md).
External sibling library (package `gossip.*`) built on the `cajeta.net` stdlib
transport — *not* part of stdlib.

Ids are `GOSSIP-N`; `- [ ]` todo, `- [x]` shipped, `- [~]` deferred / blocked
(with an inline note). Each acceptance checkbox names the TDD test that pins it
(test-first).

## Context

SWIM membership over UDP: a fixed protocol period probes a random peer (`ping`),
falls back to `k` indirect probes (`ping-req`), then suspects → declares dead,
with incarnation numbers refuting false suspicion; membership deltas spread
infection-style (piggybacked on ping/ack). See the spec for the model.

**Upstream dependencies (in the [cajeta repo](https://github.com/jklappenbach/cajeta), must exist first):**
- A **library build kind** in the Cajeta build tool — see Phase 0.
- `UdpSocket` send/recv executing end-to-end — `cajeta.net` NET-1.5 (gated on the
  NET-1.3 receiver-lowering keystone).
- Async datagram I/O — NET-3.3 (`recvFromAsync`/`sendToAsync`).
- (Optional) multicast seed discovery — NET-14.
- `Channel<T>`, the fiber timer, and the `view`/codec layer — present.

## Scope

- **v1:** membership table + SWIM failure detection + infection-style
  dissemination + graceful join/leave + a small user-broadcast channel, over
  unicast UDP, with optional multicast seed discovery.
- **Out of scope:** consensus/ordering; reliable/ordered delivery; security
  (authenticated/encrypted gossip); SWIM Lifeguard; anti-entropy beyond the
  join-time full sync.

---

## Phase 0 — Cajeta library build (PREREQUISITE, blocked upstream)

**This is the first element and currently a blocker.** The Cajeta build tool
builds *executables* (a `settings.build.binaries` entry with an `entryMethod`);
there is **no library build kind** — a target with no entry point that produces
a reusable, dependable package artifact. `cajeta-gossip` cannot build or publish
as a dependency until that exists.

- [~] **GOSSIP-0.1** A **library** project kind in `cajeta build-tool` — a
      manifest/target that produces a consumable library artifact (no entry
      method), resolvable as a dependency by other Cajeta projects.
      *BLOCKED → owned upstream (build-tool + manifest schema).*
- [~] **GOSSIP-0.2** A **library `cajeta init` archetype/template** (the
      `cajeta init library` form) that scaffolds this shape.
      *BLOCKED → owned upstream (init templates).*
- [ ] **GOSSIP-0.3** Once 0.1/0.2 land, add this repo's library manifest +
      build config and confirm `cajeta build` produces the library artifact and
      that a sample consumer can depend on it.

> Until GOSSIP-0.1/0.2 ship, this repo carries only the spec (`docs/`) and this
> plan (`plans/`) — no build config. The maintainer is adding the library build
> to `cajeta build-tool` and the templates; this plan tracks it as the gate.

### Acceptance

- [ ] `cajeta init library` scaffolds a buildable library project.
- [ ] `cajeta build` in this repo emits a library artifact (no entry method).
- [ ] A throwaway consumer project resolves + links `cajeta-gossip` as a dep.

---

## 1. TDD (gossip — unblocked once Phase 0 lands)

a. **Wire format (G1)**

   1. [ ] Golden encode/decode round-trip for each message type (`PING`/`ACK`/
      `PING_REQ`/`SYNC`/`LEAVE`/`USER`) incl. a piggyback delta list. →
      `GossipWireTests.roundTripAllMessageTypes`.
   2. [ ] Oversized payload / delta list is rejected (stays inside the MTU cap). →
      `GossipWireTests.rejectsOverMtu`.

b. **Membership state machine (G2) — pure, no sockets**

   1. [ ] A missed direct + indirect probe moves ALIVE→SUSPECT, and the
      suspicion timeout moves SUSPECT→DEAD (injected clock). →
      `GossipMembershipTests.suspectThenDeadOnTimeout`.
   2. [ ] An `alive` with a higher incarnation refutes a SUSPECT. →
      `GossipMembershipTests.higherIncarnationRefutesSuspect`.
   3. [ ] A stale (lower/equal-incarnation) update is ignored. →
      `GossipMembershipTests.staleUpdateIgnored`.

c. **Transport binding (G3)**

   1. [ ] Over a real loopback `UdpSocket` pair, a `ping` draws an `ack` and the
      prober marks the peer ALIVE; the receive fiber parks between datagrams. →
      `GossipTransportTests.pingAckOverLoopback`.
   2. [ ] An unanswered direct ping triggers `k` `ping-req`s to other peers. →
      `GossipTransportTests.indirectProbeOnDirectTimeout`.

d. **Join / leave (G4)**

   1. [ ] A joining node contacts a unicast seed, receives a `SYNC` snapshot,
      and appears in the seed's ALIVE view. → `GossipJoinLeaveTests.joinViaSeedConverges`.
   2. [ ] `leave()` gossips a graceful departure; peers mark it LEFT. →
      `GossipJoinLeaveTests.gracefulLeave`.
   3. [~] Join via multicast discovery group. *DEFERRED → needs NET-14.* →
      `GossipJoinLeaveTests.joinViaMulticastDiscovery`.

e. **Dissemination + user data (G5)**

   1. [ ] A membership change at one node reaches all N nodes within O(log N)
      periods. → `GossipDisseminationTests.updateConvergesLogN`.
   2. [ ] `broadcast(bytes)` is delivered to peers' `messages()` channels. →
      `GossipDisseminationTests.userBroadcastDelivered`.

f. **Cluster convergence / failure (G6)**

   1. [ ] An N-node loopback cluster fully converges after staggered joins. →
      `GossipClusterTests.nNodeConverges`.
   2. [ ] Killing a node → the rest report it DEAD via `events()` within bounded
      time; no false positives for a merely-slow node. →
      `GossipClusterTests.deadDetectedNoFalsePositive`.

---

## 2. Deliverables

a. **Wire format** · `gossip` (G1)

   1. [ ] `view`-based message codec: header + bounded membership-delta list +
      optional user payload. `GOSSIP-1`.

b. **Membership core** · `gossip` (G2) — pure/deterministic

   1. [ ] `MembershipTable` + the SWIM state machine (ALIVE/SUSPECT/DEAD/LEFT,
      incarnation rules, random peer selection) with injected clock + transport.
      `GOSSIP-2`.

c. **Transport + protocol loop** · `gossip` (G3)

   1. [ ] Bind the core to `UdpSocket`: a protocol-period fiber + a receive
      fiber (`recvFromAsync` → core). `GOSSIP-3`. `depends-on:` cajeta NET-1.5,
      NET-3.3.

d. **Join / leave / discovery** · `gossip` (G4)

   1. [ ] `Cluster.join(cfg)` (unicast seed contact + `SYNC`) and `leave()`.
      `GOSSIP-4`.
   2. [~] Multicast discovery group. *DEFERRED → on cajeta NET-14.* `GOSSIP-4b`.

e. **Dissemination + app API** · `gossip` (G5)

   1. [ ] Piggyback dissemination with the `λ·log N` retransmit budget;
      `events()` / `broadcast()` / `messages()` channels. `GOSSIP-5`.

f. **Spec** — [x] `docs/CajetaGossip.md` (present).

---

## 3. Acceptance Criteria

a. [ ] **Phase 0 cleared:** the library build kind exists and this repo builds +
   publishes as a Cajeta library dependency.
b. [ ] The pure membership core passes its state-machine suite (§1.b) with no
   sockets.
c. [ ] Over real loopback UDP, ping/ack + indirect probe + join/leave behave per
   §1.c–d.
d. [ ] An N-node cluster converges and detects a killed node without false
   positives (§1.f) under both `CAJETA_CARRIERS=1` and the default pool.

---

## Phasing

0. [~] **Phase 0 — library build** (blocked upstream; the gate for everything).
1. [ ] **G1 wire** → **G2 core** (socket-free; can be written/tested as soon as
   the library build exists, before the net keystone lands).
2. [ ] **G3 transport** + **G4 join/leave** — gated on cajeta **NET-1.5**
   executing.
3. [ ] **G5 dissemination** + **G6 cluster tests** — the full epidemic + the
   multi-node convergence suite.
4. [~] Multicast discovery (G4b) once cajeta **NET-14** ships; security +
   Lifeguard are post-v1.
