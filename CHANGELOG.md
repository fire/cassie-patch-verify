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
