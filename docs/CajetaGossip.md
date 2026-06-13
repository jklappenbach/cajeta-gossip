# Cajeta Gossip — SWIM-style cluster membership & dissemination

`cajeta-gossip` is an **external sibling library** (not part of the Cajeta
standard library) that maintains an **eventually-consistent** view of a dynamic
set of peer nodes — who is alive, suspect, or dead — and spreads small updates
epidemically across the cluster. It implements **SWIM** (Scalable
Weakly-consistent Infection-style process group Membership) with the standard
suspicion/incarnation refinement.

It is a library, not stdlib, by design: gossip is an *opinionated, higher-level
protocol* (probe cadence, suspicion policy, dissemination strategy), not a
universal primitive — the near-universal precedent is to ship it as a library
(Go `serf`/`memberlist`, Java JGroups/Akka Cluster, Rust crates), and being a
library lets the protocol evolve at its own pace. It builds **on** the
`cajeta.net` stdlib transport (`UdpSocket`, plus multicast for discovery) the
same way Toffee builds on the GPU stack.

- **Package:** `gossip.*`
- **Status:** designed, not implemented. Build plan: [`../plans/cajeta-gossip-plan.md`](../plans/cajeta-gossip-plan.md).
- **Upstream transport:** the `cajeta.net` stdlib in the [cajeta repo](https://github.com/jklappenbach/cajeta) (`docs/Net.md` — `UdpSocket`/NET-1.5, multicast/NET-14).

## What it is (and is not)

Gossip answers *"which nodes are in my cluster, and which just failed?"* cheaply
and at scale — SWIM keeps per-node failure-detection cost and message load
roughly constant as the cluster grows, unlike all-to-all heartbeating.

| Use gossip for | Don't use gossip for |
|----------------|----------------------|
| Cluster membership / node discovery | Consensus, leader election, total ordering (use Raft/Paxos — not provided) |
| Failure detection (who died) | Reliable, ordered delivery (gossip is best-effort, epidemic) |
| Disseminating small metadata cluster-wide | Bulk data transfer / RPC (use TCP / HTTP) |
| Decentralized, no single coordinator | In-process fan-out (use `cajeta.lang.stream.Channel`) |

It is **eventually consistent and best-effort**: an update converges to all live
nodes with high probability in O(log N) protocol periods, but there is no
delivery guarantee for any single message.

## How SWIM works (the model implemented)

Each node runs a fixed **protocol period** `T`. Every period:

1. **Direct probe.** Pick a random member, send it a `ping`; expect an `ack`
   within the probe timeout.
2. **Indirect probe.** No ack? Ask `k` random members to `ping-req` the target
   on your behalf; if any relays an `ack`, the target is alive (the original
   path was just lossy).
3. **Suspect → Dead.** Still no ack? Mark the target **suspect** and gossip
   that. If no refutation arrives within the suspicion timeout, promote it to
   **dead** and gossip that.

**Incarnation numbers** make suspicion refutable: a node that hears it is
suspected re-announces itself **alive** with a higher incarnation, which
overrides the suspicion everywhere — this is what keeps SWIM from flapping on
transient slowness.

**Dissemination is infection-style**: membership updates (join / alive /
suspect / dead / leave) are **piggybacked** on `ping`/`ack` traffic — no
separate broadcast — each riding along until sent roughly `λ·log(N)` times. A
graceful `leave` is gossiped so peers mark the node gone immediately.

**Join** contacts one or more **seeds** (a static unicast list, or a multicast
discovery group via `cajeta.net` multicast), pulls a full membership snapshot,
then settles into normal gossip.

## Surface

```cajeta
package gossip;

import cajeta.net.SocketAddress;
import cajeta.net.IpAddress;
import cajeta.lang.stream.Channel;
import cajeta.time.Duration;

public final class GossipConfig {
    public SocketAddress    bind;                  // local UDP endpoint
    public SocketAddress[]  seeds;                 // initial unicast contacts
    public IpAddress        discoveryGroup;        // optional multicast discovery; null = unicast seeds only
    public String           nodeName;              // stable node id (defaults to host:port)
    public Duration         protocolPeriod;        // T (default 1s)
    public int32            indirectProbes;        // k (default 3)
    public Duration         probeTimeout;          // direct/indirect ack wait (default 500ms)
    public Duration         suspectTimeout;        // suspect → dead (default 5s)
    public int32            gossipFanout;          // updates piggybacked per message (default 3)
}

public final class Cluster {
    // Bind the UDP endpoint, contact seeds, pull state, start the protocol +
    // receive fibers, and return once the local node has joined.
    @capability("network")
    public static Cluster join(GossipConfig cfg);

    public Member   self();
    public Member[] members();                       // snapshot of the current ALIVE view
    public Channel<MembershipEvent> events();        // joined / suspected / recovered / left / dead

    public void broadcast(int8[] payload);           // gossip an app-level message to the cluster
    public Channel<UserMessage> messages();          // app payloads received from peers

    public void leave();                             // graceful departure (gossips a `leave`)
    public void close();
}

public final class Member {
    public String        name;
    public SocketAddress address;
    public MemberState   state;
    public int64         incarnation;
}

public enum MemberState { ALIVE, SUSPECT, DEAD, LEFT }

public final class MembershipEvent { public EventKind kind; public Member member; }
public enum EventKind { JOINED, SUSPECTED, RECOVERED, LEFT, DEAD }

public final class UserMessage { public Member from; public int8[] payload; }
```

`events()` and `messages()` are `Channel`s so a consumer fiber reacts to cluster
changes and inbound payloads without polling.

## Wire format

A compact binary message defined as a `view` (the `cajeta.net`/stdlib view +
codec layer) so encoding/decoding is zero-copy and endianness-pinned:

- **Header** — magic + version, message type (`PING` / `ACK` / `PING_REQ` /
  `SYNC` / `LEAVE` / `USER`), sender name + incarnation.
- **Piggyback list** — a bounded set of membership deltas
  `{ name, address, state, incarnation }`, capped to keep each datagram inside a
  conservative UDP MTU (~1400 bytes; no IP fragmentation).
- **Payload** (USER messages only) — the app bytes; oversized payloads are
  rejected (gossip is for small updates — use TCP for bulk).

## Runtime integration

- One **protocol fiber** drives the period timer (the fiber timer wheel) and
  runs the probe/suspect cycle.
- One **receive fiber** drains the `UdpSocket` via `recvFromAsync` and feeds the
  state machine; it parks on the reactor between datagrams (no busy-spin).
- The membership table + SWIM state machine is a **pure, deterministic** core
  (clock + transport injected) so it is unit-testable without sockets.
- Probes are **unicast**; `cajeta.net` multicast is used only for the optional
  discovery group, so a node can find seeds without a static list.

## Deferred / non-goals

- **Consensus / ordering** — explicitly not provided; gossip is membership +
  best-effort dissemination only.
- **Security** — authenticated/encrypted gossip (a keyed MAC over messages, or
  DTLS) is a follow-up; v1 assumes a trusted network.
- **Lifeguard** (SWIM refinements: local health multiplier, dynamic timeouts) —
  a post-v1 robustness add-on.

## Upstream dependencies (in the cajeta repo)

- `UdpSocket` send/recv + `recvFromAsync` — `cajeta.net` (NET-1.5 / NET-3.3).
- UDP multicast for optional seed discovery — `cajeta.net` (NET-14).
- `Channel<T>`, the fiber timer, and the `view`/codec layer — `cajeta` stdlib.
