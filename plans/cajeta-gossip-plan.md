# Plan: `cajeta-gossip` — SWIM cluster membership (external library)

Status: **v1 core COMPLETE (2026-07-20)** — Phase 0 + G1–G6 all green
(130 checks, both carrier modes). Open: the `Cluster`/`GossipConfig`
public facade, PING_REQ relay, random probe selection, epidemic USER
relay, piggyback compaction, owning-channel `events()`/`messages()`
(all registered inline below); security + Lifeguard post-v1. GOSSIP-4b
multicast discovery landed 2026-07-29 (cajeta NET-14). Toolchain: cajeta ≥ 0.9.4 (re-cut — element
arrays + view forward-reference fix + `recvFromAsync` + `sleepMillis`). Spec: [`../docs/CajetaGossip.md`](../docs/CajetaGossip.md).
External sibling library (package `dev.cajeta.gossip`, following the
`dev.cajeta.http` ecosystem naming) built on the `cajeta.io.net` stdlib
transport — *not* part of stdlib.

Ids are `GOSSIP-N`; `- [ ]` todo, `- [x]` shipped, `- [~]` deferred / blocked
(with an inline note). Each acceptance checkbox names the TDD test that pins it
(test-first).

## Context

SWIM membership over UDP: a fixed protocol period probes a random peer (`ping`),
falls back to `k` indirect probes (`ping-req`), then suspects → declares dead,
with incarnation numbers refuting false suspicion; membership deltas spread
infection-style (piggybacked on ping/ack). See the spec for the model.

**Upstream dependencies (in the [cajeta repo](https://github.com/jklappenbach/cajeta)) — status as of cajeta 0.9.2:**
- A **library build kind** in the Cajeta build tool — **shipped** (Phase 0 cleared).
- `UdpSocket` send/recv executing end-to-end — `cajeta.io.net` NET-1.5:
  **works** (sync surface; the receiver-lowering keystone landed 2026-06).
- Async datagram I/O — NET-3.3 (`recvFromAsync`/`sendToAsync`): **not on the
  `UdpSocket` surface yet** (TCP async + `Reactor.awaitReadable/awaitWritable`
  exist — interim: non-blocking `recvFrom` + reactor park).
- (Optional) multicast seed discovery — NET-14: **not started**.
- `Channel<T>`, the fiber timer, and the `view`/codec layer — present.

## Scope

- **v1:** membership table + SWIM failure detection + infection-style
  dissemination + graceful join/leave + a small user-broadcast channel, over
  unicast UDP, with optional multicast seed discovery.
- **Out of scope:** consensus/ordering; reliable/ordered delivery; security
  (authenticated/encrypted gossip); SWIM Lifeguard; anti-entropy beyond the
  join-time full sync.

---

## Phase 0 — Cajeta library build (CLEARED — cajeta 0.9.2, 2026-07-19)

**Cleared.** cajeta 0.9.2 (system-wide, `f8c601b3`) ships the library project
kind and archetype (upstream `agents/cajeta/library-archetype-plan.md`, spec
`docs/specification/buildtool/LibraryProjectType.md`): a manifest with no
`settings.build.entry-method` builds to `build/archive/<name>-<version>.cja`.
The ecosystem precedent is `dev.cajeta.http` 0.1.1 (first external lib on
Olla), whose reverse-DNS naming this repo now follows: **`dev.cajeta.gossip`**.

- [x] **GOSSIP-0.1** A **library** project kind in `cajeta build-tool`.
      *Shipped upstream in 0.9.2.*
- [x] **GOSSIP-0.2** A **library `cajeta init` archetype/template**.
      *Shipped upstream in 0.9.2 (`cajeta init --list` → `library`).*
- [x] **GOSSIP-0.3** This repo's library manifest + build config
      (`cajeta.json`, `dev.cajeta.gossip` 0.1.0, seed sources
      `MemberState`/`EventKind`); `cajeta build` emits the `.cja` and a
      throwaway consumer resolves + links it. Pinned by `test/phase0.sh`.

> Local-consumer note (0.9.2 resolver): a *direct* dependency resolves only
> from repositories — `{ "path": ... }` in `settings.overrides` applies to
> transitive deps only, and the path *dependency-source* form is Phase 6c
> (unlanded). `test/phase0.sh` therefore stages the built `.cja` into a
> `type: "filesystem"` repository layout
> (`<root>/<name>/<version>/<name>-<version>.cja` + sidecar `cajeta.json`).

### Acceptance

- [x] `cajeta init library` scaffolds a buildable library project.
      *(Verified upstream + against the scaffold; this repo's manifest derives
      from it.)*
- [x] `cajeta build` in this repo emits a library artifact (no entry method).
      → `test/phase0.sh`
- [x] A throwaway consumer project resolves + links `cajeta-gossip` as a dep.
      → `test/phase0.sh` (filesystem-repo staging)

---

## 1. TDD (gossip — unblocked once Phase 0 lands)

a. **Wire format (G1)**

   1. [x] Golden encode/decode round-trip for each message type (`PING`/`ACK`/
      `PING_REQ`/`SYNC`/`LEAVE`/`USER`) incl. a piggyback delta list. →
      `GossipWireTests.roundTripAllMessageTypes` (2026-07-20, green vs the
      view-element-arrays toolchain + the cross-file view-forward-reference
      fix `46f7b1db` — found HERE: GossipMessage.cajeta parses before
      Delta.cajeta in raw directory order, and forward-referenced views got
      propertyless class placeholders).
   2. [x] Oversized payload / delta list is rejected (stays inside the MTU
      cap; rejection leaves the writer intact; oversized payload rejected
      too). → `GossipWireTests.rejectsOverMtu`.

b. **Membership state machine (G2) — pure, no sockets**

   1. [x] A missed direct + indirect probe moves ALIVE→SUSPECT, and the
      suspicion timeout moves SUSPECT→DEAD (injected clock — explicit `now`
      params, no clock object). →
      `GossipMembershipTests.suspectThenDeadOnTimeout`.
   2. [x] An `alive` with a higher incarnation refutes a SUSPECT. →
      `GossipMembershipTests.higherIncarnationRefutesSuspect`.
   3. [x] A stale (lower/equal-incarnation) update is ignored — full SWIM
      tie rules pinned: suspect beats ALIVE at equal inc (the anti-flap
      refutation forcer); suspect-over-suspect and alive-over-anything need
      strictly greater. → `GossipMembershipTests.staleUpdateIgnored`.

c. **Transport binding (G3)**

   1. [x] Over a real loopback `UdpSocket` pair, a `ping` draws an `ack` and the
      prober marks the (previously unknown) peer ALIVE from the ack's sender
      identity; the receive fiber parks between datagrams (upstream
      `UdpSocket.recvFromAsync`, added for this — NET-3.3's UDP half). →
      `GossipTransportTests.pingAckOverLoopback`.
   2. [x] An unanswered direct ping triggers `k` `ping-req`s to other live
      peers (payload = target name) and, when the indirect window also
      misses, the failure detector's SUSPECT verdict. →
      `GossipTransportTests.indirectProbeOnDirectTimeout`.

d. **Join / leave (G4)**

   1. [x] A joining node contacts a unicast seed, receives a `SYNC` snapshot
      (the seed itself + everything it knew, with real learned addresses),
      and appears in the seed's ALIVE view. →
      `GossipJoinLeaveTests.joinViaSeedConverges`.
   2. [x] `leave()` gossips a graceful departure; peers mark it LEFT
      (authoritative — no suspicion round). →
      `GossipJoinLeaveTests.gracefulLeave`.
   3. [x] Join via multicast discovery group. *Un-deferred 2026-07-29 —
      cajeta NET-14 shipped.* → `GossipDiscoveryTests` (own suite, not the
      originally-sketched JoinLeave test name): seed answers a multicast SYNC
      request with the snapshot; no-seed times out clean; the seed keeps
      serving repeat joiners. All pinned to the loopback interface, the same
      recipe as cajeta's NetMulticastTests.

e. **Dissemination + user data (G5)**

   1. [x] A membership change at one node (a newcomer joining only n4)
      reaches all N nodes via deltas piggybacked on periodic probe traffic
      (6 nodes, 50ms periods, generous O(log N) poll bound). →
      `GossipDisseminationTests.updateConvergesLogN`.
   2. [x] `broadcast(bytes)` is delivered to peers' message inboxes (sender
      identity + exact payload). → `GossipDisseminationTests.userBroadcastDelivered`.

f. **Cluster convergence / failure (G6)**

   1. [x] An N-node loopback cluster fully converges after staggered joins
      (5 nodes, protocol loops live from the start, two joins via
      non-seeds; full N×(N-1) ALIVE matrix). → `GossipClusterTests.nNodeConverges`.
   2. [x] Killing a node → every survivor records a DEAD event for it within
      bounded time; no survivor ever records DEAD for a living node
      (transient SUSPECTs legal — the newly-implemented incarnation-bump
      refutation clears them; scheduling delays under load ARE the
      merely-slow scenario). → `GossipClusterTests.deadDetectedNoFalsePositive`.

---

## 2. Deliverables

a. **Wire format** · `gossip` (G1)

   1. [x] `view`-based message codec: header + bounded membership-delta list +
      optional user payload. `GOSSIP-1` — `Wire` (constants),
      `Delta`/`GossipMessage` (@BigEndian views, decode side),
      `WireWriter` (encode side; MTU-budgeted addDelta/setPayload).
      Requires a toolchain carrying upstream `46f7b1db`.

b. **Membership core** · `gossip` (G2) — pure/deterministic

   1. [x] `MembershipTable` + the SWIM state machine (ALIVE/SUSPECT/DEAD/LEFT,
      incarnation rules) with explicit-`now` injection; insertion-ordered
      name list ready for round-robin/random probe selection (G3 wires the
      selector + transport). `GOSSIP-2` — `Member`, `MembershipTable`
      (applyAlive/applySuspect/applyDead/applyLeft/probeFailed/tick).

c. **Transport + protocol loop** · `gossip` (G3)

   1. [x] Bind the core to `UdpSocket`: `GossipNode` — receive fiber
      (`recvFromAsync` → decode → dispatch; poke-to-stop), SWIM probe cycle
      (direct PING → k PING_REQs → probeFailed), ack signaling via
      `Channel<int64>` name-hashes drained under a `Tasks.sleepMillis`
      deadline (`Tasks.withTimeout` cannot interrupt a channel park —
      upstream gap, noted there). `GOSSIP-3`. Upstream deps landed for
      this: `UdpSocket.recvFromAsync` + `Tasks.sleepMillis` (both in the
      re-cut v0.9.4). G3 scope notes in the class doc: loopback-only
      addressing until G4; PING_REQ relay is the G5 refinement; the
      full protocol-period fiber (recurring tick loop) arrives with the
      Cluster API (G4/G5).

d. **Join / leave / discovery** · `gossip` (G4)

   1. [x] Join (unicast seed contact + `SYNC` request/response with a
      one-byte request-marker payload — responses are empty-marked so
      replies never re-reply) and `leave()` (LEAVE to every ALIVE member
      via the table's learned addresses — `addrOf` builds the socket
      address from the delta's v4-mapped word + port). `GOSSIP-4` on
      `GossipNode`; the spec's `Cluster`/`GossipConfig` facade lands with
      G5's `events()`/`broadcast()`/`messages()` channels, which complete
      its surface.
   2. [x] Multicast discovery group. `GOSSIP-4b` — done 2026-07-29 (NET-14
      shipped). `enableDiscovery` makes a node a discoverable seed: a second
      socket on the well-known discovery port, joined to the group, whose own
      fiber (own WireWriter — writers don't share across fibers) answers SYNC
      requests via the extracted `sendSnapshotVia`. `joinViaDiscovery`
      multicasts the same SYNC request unicast join sends. The discovery
      fiber never mutates the membership table — the joiner introduces
      itself through normal ping traffic. One discoverable seed per host
      port by design (plain bind, fails loudly; same-host multi-seed would
      need SO_REUSEPORT, out of v1 scope).

e. **Dissemination + app API** · `gossip` (G5)

   1. [x] Piggyback dissemination with the `λ·log N` retransmit budget
      (`PiggybackQueue`: λ=3, newest-wins per member, MTU-aware fill on
      every PING/ACK/USER frame; push-pull — acks piggyback back);
      `MembershipTable.events` (ordered transition log: JOINED/SUSPECTED/
      RECOVERED/LEFT/DEAD — the single bridge from state changes to
      gossiped deltas via `drainEvents`); `protocolLoop` (the protocol-
      period fiber: round-robin ALIVE probe + tick + drain);
      `broadcast()` + the `inbox` of owned `UserMessage`s. `GOSSIP-5`.
      *Deviations from the spec surface, recorded: `events()`/`messages()`
      are owned lists (+ cursor) rather than `Channel<T>` — Channel lends
      its slots, so heap payloads would dangle (upstream owning-channel
      conversion is the registered fix); probe selection is round-robin
      (deterministic coverage) with random selection a follow-up;
      user-broadcast is direct fan-out to ALIVE members (epidemic relay
      of USER frames = post-v1); PING_REQ relay remains open (folded into
      G6's robustness work or post-v1).*

f. **Spec** — [x] `docs/CajetaGossip.md` (present).

---

## 3. Acceptance Criteria

a. [x] **Phase 0 cleared:** the library build kind exists and this repo builds +
   publishes as a Cajeta library dependency. → `test/phase0.sh`
b. [x] The pure membership core passes its state-machine suite (§1.b) with no
   sockets.
c. [x] Over real loopback UDP, ping/ack + indirect probe + join/leave behave per
   §1.c–d.
d. [x] An N-node cluster converges and detects a killed node without false
   positives (§1.f) under both `CAJETA_CARRIERS=1` and the default pool
   (verified 2026-07-20, 130 checks each).

---

## Phasing

0. [x] **Phase 0 — library build** (cleared by cajeta 0.9.2; `test/phase0.sh`).
1. [x] **G1 wire** → **G2 core** (socket-free) — done 2026-07-20, 122 checks
   green (`cajeta test`).
2. [x] **G3 transport** + **G4 join/leave** — done 2026-07-20 (126 checks
   green; upstream gates NET-1.5 + the new `recvFromAsync` both landed).
3. [x] **G5 dissemination** + **G6 cluster tests** — done 2026-07-20
   (130 checks green under BOTH `CAJETA_CARRIERS=1` and the default pool).
4. [x] Multicast discovery (G4b) — done 2026-07-29; NET-14 shipped and
   `GossipDiscoveryTests` is green (133 checks total, both carrier modes).
   CI verified 2026-07-29 on the released cajeta v0.11.0 (pin bumped; 133/133
   in CI). Security + Lifeguard stay post-v1.
