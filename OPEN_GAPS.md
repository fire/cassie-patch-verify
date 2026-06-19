# Open Gaps

(Resolved and moved to CHANGELOG: the temporal constructor — `Timeline.lean`,
234/234 — and the verifier-stand-in gap — the frame-budget ladder now drives
real patches. Surfacing parity — refine_patch synced to cassie-triangulation.)

## Detection parity: Lean port vs C++ vs upstream (the core verification)

The three pipelines must agree on *which patches the algorithm detects* on
`hat.json`. Targets: `foundByAlgo = !userCreated` splits patches into **208**
auto-detected (segment+node angular walk) and **26** manual (input-position
walk); 208 is the parity target. **Live Lean number is 29/234** (ran the
prebuilt `cycle_sweep` binary in `cassie-climb/.../lean`; the docs' "32" was
stale — grand union: 168 unique cycle-sets, 29 exact, best per-config 26).

Research findings (file:line in the cassie-climb Lean tree unless noted):

- **The per-node-normal machinery already exists in Lean** but isn't the one
  being measured. `Walk.lean:102 findCycles` is the legacy walk that reuses one
  global PCA plane normal (`Walk.lean:71`), the analog of C++
  `find_cycles` (`cassie_sketch_graph.cpp:878`, which seeds `graph_plane_normal`
  and uses the per-node normal only for the reverse-flip). `Walk.lean:219
  findCyclesPort` is the faithful upstream port: per-node `nodeMeta.normal`
  (`Graph.lean:37-48`, populated by `NodeAugment.augment`) + `isSharp` /
  `getInPlane` / `shouldReverse`. So lever-3 below ("restore per-node normals")
  is really "make the sweep/C++ use the port walk, not the legacy one."

- **Root cause #1 — arrangement under-resolution (biggest lever).** The Lean
  arrangement yields only ~175–189 nodes / ~252–310 edges, far short of what 208
  faces needs; 134 of 205 missed patches differ from any produced cycle by ≥3
  strokes (not "almost found" — *not formed*), and 77 produced cycles are
  supersets (outer loops closed instead of small inner faces).
  `Arrangement.lean:126-220 findAllSplitsByCubic` coalesces ~one split per
  cubic-pair where upstream splits at every crossing. Decisive lever: raise
  intersection resolution (more splits per cubic, finer `samplesPerCubic`) until
  node/edge counts approach upstream — no walk fix can reach 208 until the faces
  exist.

- ~~Root cause #2 — transport-sign bug~~ **tested and rejected** (see
  TOMBSTONES). Negating `tPrev` to match upstream's literal sign moved parity
  29→27 (worse), so it is not the lever.

Order of attack: (0) pin the C++ ground truth — once Godot builds, dump
`find_cycles()` and confirm it reproduces 208; (1) **fix arrangement resolution
(biggest lever)** — `findAllSplitsByCubic` (`Arrangement.lean:126-220`) produces
~175–189 nodes where 208 faces need more; raise splits-per-cubic /
`samplesPerCubic` until node/edge counts and the 134 "not formed" misses drop;
(2) make the sweep + C++ production path use the per-node-normal port walk
(`findCyclesPort`) rather than the legacy global-PCA `findCycles`.

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
