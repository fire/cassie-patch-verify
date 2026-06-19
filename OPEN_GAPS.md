# Open Gaps

Ranked by impact on the canonical temporal-incidence score (222/234, 12 misses open).

---

## 1. Boundary incidence — 222/234, 12 misses open

`Timeline.replay` verifies real **cycle incidence**: at each `SurfaceAdd`
frame, among strokes live at that frame, the boundary forms a single closed
cycle. **222/234** patches close a genuine temporal cycle. Adjacency is
confirmed geometrically from recorded `appliedPositionConstraints` + densified
`ctrlPts` poly-Bezier. The score is tolerance-free (flat across eps²
2.5e-5–4e-4, operating at 1e-4 ≈ 1 cm). Membership stays 234/234 as a
precondition.

The 12 remaining misses, ranked by recoverability:

- **Mirror-stroke deg<2 (5 patches).** A boundary stroke whose mirror geometry
  is synthesized has only 1 recorded junction with a partner boundary stroke.
  The mirror plane is confirmed at x=0.125 (sweep mx=0.0–0.20). The missing
  junction is only logged on the mirror-stroke side, which is absent from
  `allSketchedStrokes`. A symmetric junction search — when a real stroke's
  xnode lands on a synthesized mirror polyline, also count the reflected position
  as a junction of the mirror — recovers these without adding a new data source.
- **Backtracking exhausted (3 patches).** All boundary strokes have degree≥2
  but the adjacency graph built from recorded junctions is not Hamiltonian.
  These patches share boundary strokes with neighbors such that the recorded
  junctions don't isolate a clean simple cycle. Widening eps per-stroke-pair
  (to admit junctions that just miss the polyline) or using the stroke
  `inputSamples` as a fallback polyline for the adjacency test may recover some.
- **Manual patches (4 of 12 misses, foundByAlgo=false).** User-drawn patches
  are located by an input-position walk, not the angular walk. Their `strokesID`
  may include strokes adjacent in the VR graph but whose recorded junctions
  don't form a Hamiltonian cycle at eps=1e-4. These may be structurally
  irrecoverable at the current eps without a per-patch eps heuristic.

---

## 2. Delete semantics — Timeline.lean does not cascade

`Timeline.lean` tracks stroke adds and removes but does not implement full
delete semantics.

**Type-2 StrokeDelete** must cascade: upstream `GraphUpdate`
(`DrawingCanvas.cs:393-408`) + `DeleteCycles` (`Graph.cs:646-658`) destroy
every patch whose `strokesID` contains the removed stroke. `Timeline.lean`
removes the stroke (and mirror r+1) but does not cascade-delete those patches.
37 of 59 deleted stroke ids appear in some patch's `strokesID`.

**Type-4 SurfaceDelete** removes one patch: upstream `Graph.ManualDeletePatch`
(`Graph.cs:249-267`) removes only that cycle, strokes untouched. `Timeline.lean`
does not track live patches, so the inverse step is absent.

The create-frame assertion (234/234) is unaffected — patches close before their
boundary is erased — but end-state correctness requires both cascades.
Stroke-id and patch-id spaces collide numerically (stroke 113 ≠ patch 113);
type-2 cascade matches on stroke id within `strokesID`, type-4 on patch id.

---

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
