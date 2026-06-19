# Open Gaps

Ranked by impact on system correctness. The canonical temporal-incidence score is **234/234 — closed**.

---

## 1. Boundary incidence — CLOSED 234/234

`Timeline.replay` verifies real **cycle incidence**: at each `SurfaceAdd`
frame, among strokes live at that frame, the boundary forms a single closed
cycle. **234/234** patches close a genuine temporal cycle (membership 234/234
as precondition). The score is tolerance-free. See CHANGELOG for the full
progression: 165 → 177 → 222 → 234.

---

## 2. Determinism — clusterIncidence is the remaining float boundary

`formsCycle` is now eps-free: it operates entirely on integer node ids from
`StrokeIncidence`. The single floating-point boundary is `clusterIncidence`,
called once at load time from `loadSession`.

Within `clusterIncidence`, IEEE 754 variance can affect which positions cluster
together: if two positions are within eps² = 1e-4 on one platform but differ
by one ULP across the threshold on another (due to FMA contraction or
compiler reordering), they get different node ids. This would change the
`hosted` and `endpts` sets and therefore the adjacency graph.

On the one tested platform (x86-64 Linux, Lean v4.30.0, no `-O`) the result is
stable across runs. The decisive lever: prove the `vdist2` computation is
monotone in the relevant range for the positions in `hat.json` (all coordinates
are bounded and well-separated), or replace the float comparisons with exact
rational arithmetic using the JSON-parsed mantissa and exponent values (already
available via `JsonNumber.mantissa / 10^exponent`).

## 3. Fixture not regenerable from the timeline

`HatStrokes.lean` (138 strokes, 18 extras = mirror partners) and
`hat_polylines.json` originate from `codegen_hat_strokes.py`, which is absent
from disk. The fixture is not regenerable except by the batch path the temporal
model replaces. `HatDump.lean` is an inverse roundtrip check, not a generator.

`Timeline.emitFixture` closes this gap: extend `Frame`/`parseFrame` to carry
each stroke's flattened `ctrlPts` polyline (port `_flatten_ctrl_pts`,
`test_cassie_pipeline_bench.h:811`), synthesize mirror partners by X-reflection
about x≈0.125, and emit `hatStrokes`/`hatStrokeIds`/`hatPatches` ordered by
`closeFrame`. Validation: emitted `hatPatches` count is 234 and polylines pass
the existing `_bench` parity harness.

---

## 4. Detection parity: batch sweep 50/234 vs 208 target (DIAGNOSTIC)

> **Caveat (temporal coherence).** `cycle_sweep` builds one arrangement from
> *all* strokes and checks every patch — a time-travelling diagnostic, not a
> temporal verifier. The **canonical** verification is temporal (gap 1 above):
> each patch is checked using only the strokes live at its create frame.
> **(1) use the recorded data** — `appliedPositionConstraints` hold the exact
> junctions; **(2) no time-travel** — per-frame, live strokes only.

`cycle_sweep` matches **50/234** patches against `allCreatedPatches`. The
algorithmic target is **208** (`foundByAlgo = !userCreated`). The arrangement
is built from proximity-guessed crossings rather than the recorded
`appliedPositionConstraints`, so the topology diverges from the system's real
graph: `sketch_graph/hat.json` resolves to ~98 nodes; the sweep arrangement
carries ~228 (over-segmented with noise), and 102 produced cycles are supersets
of the target boundary.

The constraint-based arrangement closes this gap: each stroke's
`appliedConstraints` (`isIntersection` world positions) are the exact junctions
the system uses. Projecting each onto its stroke's arc-length yields a `Split`,
and `buildArrangementFromSplits` (already in `Arrangement.lean`) builds the
correct topology. Mirror strokes require their constraints reflected about
x≈0.125. This path is ~50–80 lines in `CycleSweep.lean` and replaces proximity
guessing with recorded topology.

Research findings (file:line in the cassie-lean Lean tree unless noted):

- **Per-node-normal machinery exists in `findCyclesPort`** (`Walk.lean:219`) and
  is not used by the sweep. `Walk.lean:102 findCycles` reuses one global PCA
  normal (`Walk.lean:71`), the analog of C++ `find_cycles`
  (`cassie_sketch_graph.cpp:878`). `findCyclesPort` is the faithful upstream
  port with per-node `nodeMeta.normal` (`Graph.lean:37-48`) +
  `isSharp`/`getInPlane`/`shouldReverse`.
- **Arrangement resolution gap (partially closed).** `CycleSweep.lean` passes
  `#[]` for cubic data, so every pair runs the fallback split path. The fallback
  emits every coalesced near-crossing per polyline pair. Remaining gap: no real
  per-stroke cubic data (`ctrlPts`) feeds `intersectCubics`.
- **C++ ground truth unconfirmed.** `find_cycles()` on `hat.json` is not yet
  dumped; the 208 figure derives from `foundByAlgo = !userCreated`
  (`Cycle.cs:127`), not from a C++ run.

---

## 5. VR frame-budget validation

`walkSteps` in `Timeline.lean:135-138` is a frame count, not a cost in
microseconds. No mapping from ladder rung to real VR-frame headroom exists.

Real per-stage timing lives in C++ (`test_cassie_pipeline_bench.h`:
`Time::get_ticks_usec()` around populate/find_cycles/sample_boundary/
manager_update). Two additions close this gap: (1) a C++ bench mode that
replays `systemStates` in `time` order and times each gesture's incremental
add_stroke→find_cycles→sample→triangulate per frame; (2) ladder rungs expressed
against a real VR budget (90 Hz = 11.1 ms, 72 Hz = 13.9 ms) using measured
per-frame µs, so the rung a patch resolves on reflects measured headroom.
