# Changelog

## Conventions

- **The verifier is independent of the C++/Godot build.** `cassie-patch-verify`
  is a standalone Lean package; it reads the C++ cassie module's *output* (JSON)
  and never links into it — no `@[extern]`/FFI in either direction, nothing in
  the Godot SCons build, the engine never depends on Lean.
- **Verification is temporal, driven off the VR session timeline.** The graph is
  built by replaying `raw_data/hat.json`'s `systemStates` (1095 VR frames) in
  `time` order, not by batch arrangement. The goal is to prove the construction
  is valid frame-by-frame and therefore runnable live in VR.
- **Data interchange only.** Strokes and patches cross the C++/Lean boundary as
  JSON (`CASSIE_DUMP_PATCHES_JSON`, `CassiePolylinesJson`), never as linked code.
- **Toolchain is v4.30.0** (matches `plausible-witness-dag`). No Python for
  Lean/Godot work; fixtures and tools are Lean (`HatDump`).
- **Three pipelines triangulate correctness:** (1) C++ production, (2) AVBD
  Lean→Slang→Vulkan numeric solve, (3) this plausible witness oracle for the
  combinatorial detection.

## Detection parity (cassie-lean CycleDetect) — 29 → 50/234

- **Lever 3 — clockwise minimal-face turn (48 → 50).** `findCyclesPort`'s
  smooth-node turn stepped ±1 in the CCW neighbor ring toggled by the
  normal-driven `reversed` flag. That flip (Unity's logic for genuinely 3D
  sheets) mis-fires on the near-planar hat and closes *superset* loops. Forcing
  a consistent clockwise (−1) step traces the minimal planar face: parity
  48 → 50, producedSuperset **137 → 102**, off≥3 84 → 74. (Measured: CCW/+1 = 47,
  the `reversed` toggle = 48.) Tradeoff: the fixed turn abandons the 3D-sheet
  `reversed` logic — correct for the near-planar hat target, may need
  per-region normals for fully 3D sketches. Two earlier walk levers rejected
  first (4-variant union neutral; manifold cap 48→47) — see TOMBSTONES.

## Detection parity (cassie-lean CycleDetect) — 29 → 48/234

- **Lever 2 — keep the mirror strokes (43 → 48).** The sweep's `dropPhantom`
  removed the 18 mirror ("phantom") strokes (`5,7,9,19,…`) before building the
  arrangement. But 68 of 234 patches reference a mirror id, so dropping them
  capped parity at **166/234** and stripped nodes other patches' faces need.
  Keeping them (the 138-stroke fixture already carries their geometry) raised the
  ceiling to 234 and parity 43 → 48, unique cycle-sets 258 → 309. This also
  resolves a latent inconsistency: the sweep had been dropping exactly the 18
  ids the TOMBSTONE flagged as wrong-to-drop. (Working-tree change; the godot
  mirror's older `CycleSweep` never dropped them.)

## Detection parity (cassie-lean CycleDetect) — lever 1 — 29 → 43/234

- **Arrangement resolution was the lever** (transport-sign was not — see
  TOMBSTONES). The Lean sweep feeds no cubic data
  (`CycleSweep.lean` passes `#[]`), so every stroke pair went through the
  fallback split path, which emitted **one split per pair** (the single global
  nearest point) even on pairs that truly cross multiple times — starving the
  arrangement of nodes. Rewrote the fallback in
  `CassieAvbd/CycleDetect/Arrangement.lean` to collect **every** near-crossing
  per polyline pair (coalesced by world position), not just the global minimum.
- Measured on `hat.json` via `cycle_sweep`: grand-union exact parity **29 →
  43/234**, unique cycle-sets **168 → 258**, node counts ~189 → ~228. Per-config
  best 26 → 30. Applied to both the working tree (cassie-lean) and the
  git-tracked mirror (godot module). Still short of the 208 auto-detected target
  — the arrangement is less under-resolved but not yet complete (next: feed real
  cubic data / finer tessellation, and use the per-node-normal port walk).

## Upstream ground truth (V-Sekai CASSIE Unity C#)

- Located the original port at
  `loot-action-vertical-slice/cassie/Assets/Scripts` and read the authoritative
  source. Findings recorded as JSON-LD in `meta/verification.jsonld` (extends the
  cassie vocab + PROV-O, with source file:line provenance).
- **Schema is authoritative now** (`Study/StudyLog.cs`): `hat.json` is written by
  `StudyLog.SaveData`; every Vec3/Quat passes through `Utils.ChangeHandedness` on
  export, so coordinates are handedness-flipped from in-engine values — geometry
  checks must account for this.
- **InteractionType enum pinned** (`Study/StudyUtils.cs:46`): 0 Idle, 1 StrokeAdd,
  2 StrokeDelete, 3 SurfaceAdd, 4 **SurfaceDelete**, 5 CanvasTransform. Corrects
  the docs' "type 4 = rare/undo-redo."
- **`foundByAlgo = !userCreated`** (`Internal/Cycle.cs:127`), and the two
  `CycleDetection.DetectCycle` overloads decide it: the (segment,node) angular
  walk → `userCreated=false` → the **208** auto patches; the (inputPos)
  closest-segment walk (user points at a region) → `userCreated=true` → the **26**
  manual patches. So 208/234 is the real algorithmic-detection target, not 234.
- **Divergence located:** the C++ `find_cycles()` seeds one global PCA plane
  normal reused at every node, where upstream uses per-node `Normal` plus the
  `IsSharp`/`GetInPlane`/`ShouldReverse` machinery — the likely root of the Lean
  port's 32-vs-208 parity gap, and the next thing to reconcile.

## Temporal cycle-incidence (Timeline.lean) — 54/234, the first VALID score

- Upgraded the temporal verifier from boundary **membership** (234/234, a
  necessary condition) to real **cycle incidence**: at each `SurfaceAdd` frame,
  among only the strokes live then, assert the patch boundary forms a single
  closed cycle. Result: **54/234** patches close a genuine temporal cycle.
- **Uses recorded data, not proximity guessing.** Reads each stroke's
  `appliedPositionConstraints` (`isIntersection` world positions) + `inputSamples`
  polyline from `hat.json`. Crossings are recorded *asymmetrically* (only the
  later-drawn stroke logs a junction), so adjacency is confirmed *geometrically*:
  two boundary strokes are adjacent iff a recorded junction of either lies on the
  other's polyline (`nearPoly`). This fixed a first cut that found only 4/234.
- **Temporally coherent — no time-travel.** Only strokes live at the frame
  participate; since membership guarantees the whole boundary is live by the
  create frame, every boundary–boundary junction is already present. Mirror
  strokes synthesized by reflecting the partner's geometry about x≈0.125.
- This is the **canonical** verification (unlike the batch `cycle_sweep`, which
  time-travels). Valid score is now: 234/234 membership, **54/234 incidence**.
  Remaining gap (54→) is future refinement of the geometric eps / mirror plane /
  degree-2 simple-cycle rigor.

## Temporal constructor (Timeline.lean) — landed, 234/234

- The constructor exists and verifies. `Timeline.lean` folds the 1095
  `systemStates` frames in recorded (`time`-ascending) order and asserts that at
  every create-patch (type-3) frame the construction has *just closed* the patch
  the data records: **234/234**. `main` throws if any patch is unclosed, so the
  build is a real frame-by-frame check, not a print.
- **Corrected the action model the SSOT docs had wrong** (a naive replay closed
  only 37/234). Two fixes, both validated against all 234 patches:
  - *Mirroring.* `mirroring` is on for the whole hat session. Adding stroke `r`
    also brings in mirror `r+1`; deleting removes both. The 18 odd "phantom"
    stroke ids patches reference (`5,7,9,19,21,23,25,27,29,31,33,35,39,47,49,53,
    55,57`) are exactly these mirror partners — never in `allSketchedStrokes`
    because only user-drawn strokes are stored. (This also resolves what
    TOMBSTONES called the "18 inflated strokes": they are mirrors, not codegen
    phantoms.)
  - *Same-timestamp grouping.* A create-patch event is logged at the *same*
    `time` as the add-stroke that closes it (type-3 just before type-1). Frames
    sharing a `time` are one gesture; adds/deletes apply before that group's
    patch checks. We replay recorded membership and never recompute intersections.
- **Frame-budget ladder on real patches.** `walkSteps` now models the per-VR-frame
  budget (OPEN_GAPS item 2): `readback budget` replays the budgeted prefix and
  reports the patch's closing frame; `candidateIsWitness` is "patch closes within
  budget." Demonstrated escalation on real data: patch 0 (closeFrame 21) resolves
  @L0, patch 50 (138) @L1 after an L0 budgetHit, patch 230 (1081) @L2 — density is
  a rung, not a wall.
- Packaging: `Timeline` added as a `lean_lib` so Lake builds it; `Main` drives it.

## Verifier (cassie-patch-verify)

- Scaffold the package on v4.30.0 with the single dep `plausible-witness-dag`
  (which pulls `plausible`; 34 build steps, no Mathlib). It reads patch JSON and
  certifies via the iterative-deepening ladder.
- Prototype runs and exercises all three outcomes: `found@L0`, `found@L1` after
  an L0 `budgetHit` (escalation), and `budgetHit` (needs a deeper rung) — proving
  a boundary L0 cannot walk escalates rather than being declared impossible.
- Name chosen to match fire's Lean repos: `cassie-*` family (cassie-data,
  cassie-triangulation), `-verify` role (onnx-lean-verify), witness-oracle
  sibling (gltf-crease-detector).

## Oracle (cassie `CycleDetect`, branch feat/module-cassie)

- Land commit `9ae548423f` `cassie: augment cycle_sweep arrangement and union
  findCyclesPort`: `runOne` uses `buildArrangementAugmented` so `nodeMeta` is
  populated and the parallel-transport `findCyclesPort` engages instead of
  silently falling back to the legacy single-global-PCA-plane walk. Batch hat
  parity 28→32/234, unique cycle-sets 96→220. (Canonical home: the cassie repo;
  noted here as verification context.)
- Bump the cassie Lean oracle to v4.30.0: `CassieAvbd.CycleDetect.*` is
  dependency-light (no LeanSlang/Mathlib), compiles clean, and reports the
  identical 32/234 — no regression from the toolchain change.

## Data / timeline (raw_data/hat.json)

- Decode `systemStates` as the VR frame timeline. Each frame carries `time`,
  head/hand poses, canvas transform, `mirroring`, `interactionType`, `elementID`.
  Action enum (derived by correlating type→element counts against
  strokes=120/patches=234): **1 add-stroke** (120 frames, ids 0–146), **3
  create-patch** (234, ids 0–233), **2 delete** (59), **4 rare op** (6), **0
  idle/camera** (295), **5 canvas transform** (381).
- Confirm the canonical ground truth is `raw_data/hat.json` =
  `allSketchedStrokes` (120) + `allCreatedPatches` (234; each
  `foundByAlgo, id, strokesID`) + `systemStates` (1095). `large_hat.json` is
  byte-identical; `sketch_graph/hat.json` (69 strokes / 98 nodes / 169 segments)
  is the resolved end-state.
