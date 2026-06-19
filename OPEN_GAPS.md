# Open Gaps

(Resolved and moved to CHANGELOG: the temporal constructor — `Timeline.lean`,
234/234 — and the verifier-stand-in gap — the frame-budget ladder now drives
real patches. Surfacing parity — refine_patch synced to cassie-triangulation.)

## Detection parity: Lean port vs C++ vs upstream (BATCH DIAGNOSTIC)

> **Caveat (temporal coherence).** Everything in this section is the **batch**
> `cycle_sweep`: it builds one arrangement from *all* strokes and checks every
> patch, so a patch created early is "detected" using strokes drawn much later —
> i.e. it *time-travels*. This is the dead batch model (see TOMBSTONES); it
> survives only as a parity microscope. The **canonical** verification is
> temporal (next section): detect each patch using only the strokes live at its
> create frame. Two governing principles for the real work: **(1) use the
> recorded data** — `appliedPositionConstraints` are the exact junctions, so do
> not proximity-guess crossings; **(2) no time-travel** — per-frame, live strokes
> only.

The three pipelines must agree on *which patches the algorithm detects* on
`hat.json`. Targets: `foundByAlgo = !userCreated` splits patches into **208**
auto-detected (segment+node angular walk) and **26** manual (input-position
walk); 208 is the parity target. **Live Lean number is 50/234** (up from 29; grand union 242 unique
cycle-sets). Still well short of 208.

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
1–2 strokes (`off1+off2`). This was a **minimal-face-selection** problem in the walk. **Lever 3 landed
(48→50):** `nextEdgePort`'s smooth-node turn toggled ±1 with the normal-driven
`reversed` flag, which mis-fires on the near-planar hat and closes supersets;
forcing a consistent clockwise (−1) turn cut supersets 137→102. (Earlier
rejected, see TOMBSTONES: 4-variant union neutral; manifold cap 48→47.)

**Remaining gap (50→208) — cheap knobs exhausted; next is a build.** Miss
profile `off0=2 off1=28 off2=80 off≥3=74`, producedSuperset 102. Tested *neutral*
this round (none moved 50): neutralizing the `reversed` toggle, fixing the
sharp-node `wantNext`, and tightening `clusterEps` 0.05→0.02. So the residual gap
is **not** a walk/coalescing parameter — it is the arrangement *topology*: the
proximity-guessed crossings don't match the system's real graph (the off1/off2
near-misses are chords/extra-or-missing splits, and the resolved upstream
sketch_graph has only ~98 nodes vs our ~228, i.e. we over-segment with noise).

**Decisive next lever (a real build, not a one-liner): constraint-based
arrangement.** `HatRawData` carries each stroke's `appliedConstraints` with
`isIntersection` world positions — the *exact* junctions the system used. Build
the arrangement from those (project each onto the stroke → `Split`,
`buildArrangementFromSplits`) instead of proximity. To clear the 166 ceiling this
also needs the 18 mirror strokes synthesized (X-reflect geometry *and*
constraints about x≈0.125). This replaces guessed topology with recorded
topology and should both kill the near-miss noise and lift the ceiling — but it
is ~50–80 lines of new sweep code (a focused session), not a tick experiment.

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

## Boundary incidence — LANDED 54/234, refinement open

`Timeline.replay` now checks real **cycle incidence** (not just membership): at
each `SurfaceAdd` frame, among live strokes, the boundary must form a single
closed cycle, with adjacency confirmed geometrically from recorded
`appliedPositionConstraints` + `inputSamples` (no proximity, no time-travel).
**54/234** close a genuine temporal cycle (membership stays 234/234). Remaining
work to raise 54: tune the geometric eps and the mirror reflection plane (x≈0.125
is inferred), handle `k=1` closed-loop strokes, and relax the strict degree-2
simple-cycle test where a boundary stroke is legitimately crossed mid-span.

(Historical note — the machinery this reused already existed in cassie-lean;
the verify-repo version is self-contained since it can't import that tree.)

`Timeline.replay` proves a patch's `strokesID` are all live at its create-patch
frame (membership, 234/234). The cycle-incidence upgrade above uses:

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

**This is THE canonical next lever (supersedes the batch sweep above).** Done
temporally and from recorded data:
- At each `SurfaceAdd` frame, restrict to the strokes **live at that frame**
  (the `live` set `replay` already maintains, with mirror `r+1`) — *no
  time-travel*: never use a stroke added later.
- Build incidence from the **recorded** `appliedPositionConstraints`
  (`isIntersection` world positions) — *not* proximity. Two live strokes are
  adjacent iff they share an intersection position (cluster positions into nodes
  within a small eps; the partner stroke-id is dropped on serialize, so recover
  adjacency by coincident position). Synthesize the mirror strokes' constraints
  by reflecting the partner's about x≈0.125.
- Assert the patch's boundary `strokesID` forms a single closed cycle in that
  per-frame incidence graph (every boundary stroke degree 2, connected) — real
  incidence, replacing the membership check (keep membership as a precondition).
- **Architecture:** `cassie-patch-verify` depends only on `plausible-witness-dag`
  (not on the cassie-lean arrangement code), so the incidence check is
  implemented self-contained in `Timeline.lean`. The witness-DAG ladder is the
  natural driver: pose "patch P's boundary closes a cycle among live strokes" as
  the existence query, with the deterministic per-frame cycle-check as the
  `readback` (brute-force guess-and-check, escalating the search budget).

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
