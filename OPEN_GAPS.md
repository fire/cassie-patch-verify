# Open Gaps

(Resolved and moved to CHANGELOG: the temporal constructor — `Timeline.lean`,
234/234 — and the verifier-stand-in gap — the frame-budget ladder now drives
real patches. Surfacing parity — refine_patch synced to cassie-triangulation.)

## Detection parity: Lean port vs C++ vs upstream (the core verification)

The three pipelines must agree on *which patches the algorithm detects* on
`hat.json`. Targets: `foundByAlgo = !userCreated` splits patches into **208**
auto-detected (segment+node angular walk) and **26** manual (input-position
walk); 208 is the parity target. **Live Lean number is 48/234** (up from 29;
grand union 309 unique cycle-sets). Still well short of 208.

**Progress (landed, see CHANGELOG):** (1) the sweep fed no cubic data, so the
fallback emitted one split per stroke pair — rewrote it to emit every coalesced
near-crossing (29→43, nodes ~189→~228); (2) `dropPhantom` was removing the 18
mirror strokes that 68 patches reference, capping parity at 166 — kept them
(43→48, ceiling now 234).

**The bottleneck has shifted (next lever).** Miss profile went from
`off≥3=134` (faces not formed) to `off0=2 off1=26 off2=74 off≥3=84` with
`producedSuperset=137`. So "not formed" dropped, and the dominant failure is now
that the walk closes a *superset* loop (boundary + extra strokes) instead of the
minimal inner face — 137 patches have a produced superset, and 100 are within
1–2 strokes (`off1+off2`). This is a **minimal-face-selection** problem in the
walk, not arrangement resolution. Two cap/union levers tested and **rejected**
(see TOMBSTONES): unioning all 4 legacy walk variants was *neutral* (0 new sets);
porting the C++ per-edge manifold cap to `findCyclesPort` was *negative* (48→47,
order-dependent pruning blocked minimal faces). So the gap is **not** the cap and
**not** coverage — it is the per-step **turn rule**: `nextEdgePort`'s smooth-node
"±1 in CCW neighbor order" closes the wrong (superset) face from every seed on
137 patches. Decisive next lever: make the turn pick the minimal face directly —
i.e. the next edge in rotational order taken as *most-clockwise from the reversed
incoming direction* (standard planar minimal-cycle traversal), and verify
`neighborsCcw` (`NodeAugment`) is sorted consistently with that convention. This
is a turn-rule change inside `nextEdgePort`, measured on `cycle_sweep`.

Research findings (file:line in the cassie-lean Lean tree unless noted):

- **The per-node-normal machinery already exists in Lean** but isn't the one
  being measured. `Walk.lean:102 findCycles` is the legacy walk that reuses one
  global PCA plane normal (`Walk.lean:71`), the analog of C++
  `find_cycles` (`cassie_sketch_graph.cpp:878`, which seeds `graph_plane_normal`
  and uses the per-node normal only for the reverse-flip). `Walk.lean:219
  findCyclesPort` is the faithful upstream port: per-node `nodeMeta.normal`
  (`Graph.lean:37-48`, populated by `NodeAugment.augment`) + `isSharp` /
  `getInPlane` / `shouldReverse`. So lever-3 below ("restore per-node normals")
  is really "make the sweep/C++ use the port walk, not the legacy one."

- **Root cause #1 — arrangement under-resolution (biggest lever; partially
  landed).** The sweep feeds no cubic data (`CycleSweep.lean` passes `#[]`), so
  every pair went through the fallback split path that emitted *one* split per
  pair. **Fixed:** the fallback now emits every coalesced near-crossing
  (`Arrangement.lean`), lifting nodes ~189→~228 and parity 29→43. Remaining
  under-resolution to close the rest of the gap: feed the real per-stroke cubic
  data (the `ctrlPts` in `HatRawData`) so the exact `intersectCubics` path runs
  instead of the polyline fallback, and/or finer `samplesPerCubic`.

- ~~Root cause #2 — transport-sign bug~~ **tested and rejected** (see
  TOMBSTONES). Negating `tPrev` to match upstream's literal sign moved parity
  29→27 (worse), so it is not the lever.

Order of attack: (0) pin the C++ ground truth — once Godot builds, dump
`find_cycles()` and confirm it reproduces 208; (1) **arrangement resolution** —
fallback multi-crossing fix landed (29→43); next feed real cubic data from
`ctrlPts` / finer tessellation; (2) make the sweep + C++ production path use the
per-node-normal port walk (`findCyclesPort`) rather than the legacy global-PCA
`findCycles`.

## Boundary membership is replayed, not geometrically reconstructed

`Timeline.replay` proves a patch's `strokesID` are all live at its create-patch
frame (membership, 234/234), not that they form a closed cycle. Research shows
**almost all the machinery to upgrade this already exists**:

- `appliedPositionConstraints` suffice to reconstruct node incidence with no 3D
  intersection recompute: each constraint records the snap `position` (shared
  between both strokes) and `isIntersection` flags inter-stroke junctions
  (218/237 in hat.json are intersections). Schema: `StudyLog.cs:222-238`,
  written only by `ConstraintSolver.cs:261-287`.
- `Arrangement.lean:228 buildArrangementFromSplits` was written for exactly this
  "temporal record" input; `CyclePatch.lean:289-318` already wires
  splits → augmented arrangement → `findCyclesPort` → stroke-id sets via
  `Edge.src` (`Graph.lean:28-29`, `CyclePatch.lean:256-265`).
- The **one net-new piece** is a `appliedPositionConstraints → Array Split`
  adapter (map each `isIntersection` constraint to a `Split` at its arc-length
  on the stroke). Then at each type-3 frame, build the arrangement from the live
  set and assert ∃ a cycle whose `src`-set equals the recorded boundary — real
  incidence, replacing the membership check (keep membership as a precondition).
  Incremental graph state is an optimization, not needed for correctness (a few
  hundred strokes rebuilds fine).

Note: `Timeline.lean` currently parses only frame fields + `strokesID`
(`:42-52`); it never reads `ctrlPts`/constraints. This gap needs that geometry
loaded.

## Delete semantics (no longer "undo/redo")

Enum pinned (`StudyUtils.cs:46`): 0 Idle, 1 StrokeAdd, 2 StrokeDelete,
3 SurfaceAdd, 4 SurfaceDelete, 5 CanvasTransform. Research nailed both deletes:

- **Type-4 SurfaceDelete (6 frames) = delete one patch.** Every elementID is a
  patch id created by an earlier type-3 (verified pairs in
  `meta/verification.jsonld`). Upstream `Graph.ManualDeletePatch`
  (`Graph.cs:249-267`, `userTriggered:true`) removes only that cycle — no
  cascade, strokes untouched. Inverse-step: remove 2-cell `elementID`.
- **Type-2 StrokeDelete (59 frames) must cascade.** Upstream `GraphUpdate`
  (`DrawingCanvas.cs:393-408`) + `DeleteCycles` (`Graph.cs:646-658`) destroy
  *every* patch bound by the removed stroke. 37 of 59 deleted stroke ids appear
  in some patch's `strokesID` (e.g. stroke 20 bounds patches 11–42; stroke 93
  bounds 33 patches). The constructor currently removes the stroke (with mirror
  r+1) but does **not** cascade-delete those patches. This doesn't break the
  234/234 create-frame assertion (patches close before their boundary is erased)
  but is required for a correct end-state.
- **Caveat:** stroke-id and patch-id spaces collide numerically (stroke 113 ≠
  patch 113). Type-2 cascade matches on stroke id within `strokesID`; type-4
  matches on patch id. Do not unify them.

## The fixture is not regenerated from the timeline

`HatStrokes.lean` (138 strokes via `hatStrokeIds`, the 18 extras = mirror
partners) + `hat_polylines.json` came from `codegen_hat_strokes.py` — which is
**missing from disk** (full-fs search finds nothing). So the fixture is
currently un-regenerable except by the batch path we want to retire, and
`HatDump.lean` is only the inverse roundtrip check, not the generator. Decisive
next lever: add `Timeline.emitFixture` that reuses `replay`'s ordering — extend
`Frame`/`parseFrame` to carry each stroke's flattened `ctrlPts` polyline (port
`_flatten_ctrl_pts`, `test_cassie_pipeline_bench.h:811`), synthesize mirror
partners explicitly (X-reflection about ~0.125, killing the phantom ids), and
emit `hatStrokes`/`hatStrokeIds`/`hatPatches` ordered by `closeFrame`. Validate:
emitted `hatPatches` still 234, and the polylines pass the existing `_bench`
parity harness.

## VR frame-budget validation

Real per-stage timing exists only in C++ (`test_cassie_pipeline_bench.h`:
`Time::get_ticks_usec()` around populate/find_cycles/sample_boundary/
manager_update, warmed; a 2 s *batch* soft budget at `:281-291`; Quest 3 /
Steam Deck target named at `:359`). No frame budget anywhere; the Lean ladder's
`walkSteps` (`Timeline.lean:135-138`) is a frame *count*, not a cost. Decisive
next lever, two moves: (1) add a C++ bench mode that replays `systemStates` in
`time` order (same order as `Timeline.replay`) and times each gesture's
*incremental* add_stroke→find_cycles→sample→triangulate per frame; (2) re-express
the Lean ladder rungs against a real VR budget (90 Hz = 11.1 ms, 72 Hz =
13.9 ms) using the measured per-frame µs, so the rung a patch resolves on
reflects measured headroom. Store the per-frame µs beside the Lean `_bench`
JSONs. Both this and fixture-regen share the lever: replay `systemStates` in
`time` order, already implemented in `Timeline.replay`.
