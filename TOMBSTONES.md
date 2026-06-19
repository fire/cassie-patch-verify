# Tombstones

## Batch arrangement + `cyclesUnion` as the verification model — dead

`buildArrangement` over all strokes at once plus `cyclesUnion` reading off final
faces is not what we verify. Patches form *incrementally* as the user draws; VR
cannot batch-recompute every intersection per frame. The batch `cycle_sweep`
survives only as a parity microscope (it lives in the cassie Lean tree); the live
model is the temporal constructor (see OPEN_GAPS).

## Loading `sketch_graph/hat.json` directly — dead

Feeding cycle-detection the resolved `sketch_graph` (69 strokes / 98 nodes / 169
segments) matches the patches but skips the construction we must prove. It is the
*answer*, not the *process*; VR has to build it. Surviving use: it is still a
valid end-state oracle to check the constructor's final output against.

## "Drop the 18 inflated strokes to fix parity" — disproven

Hypothesis: the fixture's 138-vs-canonical-120 stroke inflation depressed batch
parity. Filtered ids 5,7,9,19,21,23,25,27,29,31,33,35,39,47,49,53,55,57 and
re-ran: parity went 32→29/234 (slightly worse), node count ~213→~189. The 18
phantoms are connected (they add nodes) but are not the cause. The inflation
remains a real fixture bug (see OPEN_GAPS regeneration), just not the parity
lever. **Update:** those 18 ids are now identified as *mirror strokes* (`r+1` of
a real stroke; `mirroring` is on session-wide) — the temporal constructor needs
them present to close patches, so they are not phantoms to drop but real boundary
participants. See CHANGELOG (temporal constructor).

## "The walker is the parity bottleneck" — superseded

The stage-2 framing blamed `findCyclesPort` for non-minimal faces (153/234
supersets, a ceiling at 4 boundary strokes). The augment+port fix was real and
landed (28→32, see CHANGELOG), but chasing the walker further is the wrong
altitude: batch parity is the wrong yardstick because the model should be
temporal. Surviving knowledge: the `MISS-NEAREST` / `PATCH-CLASS` diagnostics in
`cycle_sweep`.

## "The transportAcrossNode sign is the parity lever" — disproven

Research flagged that the Lean port passes `tPrev = tangentAwayFrom(...)` where
upstream `CycleDetection.cs:349` uses `-prevSegment.GetTangentAt(node)`, and
`GetTangentAt` (`Segment.cs:131-137`) always points away from the node — so the
Lean `tPrev` is the literal negation of upstream's. Negating it to match
upstream was a clean, faithful one-line change. Measured: grand-union parity
went **29→27** and unique cycle-sets **168→148** — strictly *worse*. Reverted.
The away-from-node convention the Lean port already used produces more correct
cycles, so either a compensating orientation exists elsewhere in the port or the
sign is washed out because the arrangement is too coarse to exercise non-trivial
nodes. Either way the transport sign is not the lever; arrangement
under-resolution is (see OPEN_GAPS). Surviving knowledge: `cycle_sweep` is the
fast oracle for testing any walk-logic change — rebuild + run, read `GRAND…
exact=N/234`.

## "The manifold cap (≤2 cycles/edge) recovers minimal faces in findCyclesPort" — disproven

`findCyclesPort` enumerates a cycle from every (seed-edge, start-node) and dedups
by edge-set — no per-edge manifold cap, unlike the C++ `find_cycles`. Hypothesis:
porting the cap (each edge in ≤2 cycles + a consumed half-edge set, bumped on
close) would stop the walk closing supersets and yield the minimal planar faces.
Implemented faithfully and measured: parity **48→47**, unique cycle-sets
**309→277**, supersets 137→131. So the cap *did* cut supersets slightly, but it
is **order-dependent** — when a superset closes first it consumes an edge's two
slots and blocks the minimal faces that share that edge, pruning more good cycles
than bad. The enumerate-all-then-dedup approach finds strictly more faces.
Reverted. The cap is not the lever; the lever is the per-step **turn selection**
(make the walk trace the minimal face from the start), which the cap can't fix
after the fact. Also tested neutral: unioning all 4 legacy walk variants instead
of 1 added zero unique sets (orientation flips collapse under sorted-edge dedup).

## "T7 (15k samples) is too dense for interpreted Lean, skip it" — dead

The comment in `CycleSweep.lean`. The witness-DAG ladder escalates `walkSteps` on
`budgetHit` rather than enumerating everything, so density is a rung, not a wall —
demonstrated by `cassie-patch-verify` resolving a 6-step boundary at L1 after an
L0 budget-hit. Do not reason about "too dense to walk."
