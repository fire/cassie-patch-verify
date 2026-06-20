# Open Gaps

Ranked by impact on V-Sekai delivery:

```
draw in VR (CASSIE) → correct mesh → inventory item → shop trade → OpenUSD archive
```

The oracle in this repo verifies the first step. Its value depends on the
downstream connections existing. Gaps are ordered from delivery-blocking to
housekeeping.

---

## Delivery blockers

### A. Oracle ↔ C++ mesh diff — no comparison mechanism

`patches_mesh.json` is the oracle's output and the Blender viewport is the only
consumer. No code reads both the Lean oracle mesh and the C++ production mesh and
reports divergences. A divergence is evidence of a C++ bug; without the diff, the
oracle's triangulation work has no path to fix production.

The near-term path is a JSON comparison: load `patches_mesh.json` alongside the
C++ mesh dump (exported from Godot or `CassiePolylinesJson`) and report per-patch
vertex/topology differences above a threshold.

A GPU-accelerated path exists via `lean-slang` (vendored at
`vendor/lean-slang/`): lean-slang emits Slang compute shaders from a Lean AST.
Slang supports `[Differentiable]` functions and `fwd_diff`/`bwd_diff`, which
enable differentiable mesh comparison kernels (e.g. Chamfer distance between
oracle and C++ vertex sets). The lean-slang AST (`LeanSlang/AST.lean`) has no
`[Differentiable]` node yet — extending it is the prerequisite. The `declarePrecise`
statement (maps to SPIR-V `NoContraction`) is already present, which is the
correct foundation for numerically stable distance computation.

### B. Boundary triangulation — 231/234 (oracle incomplete)

`TriangulatePatches` walks each patch's recorded `strokesID` in order (CASSIE
writes them in cycle order), clips each stroke to its junction sub-segment using
recorded `appliedPositionConstraints` (`isIntersection`) positions from `hat.json`
(`xnodes`), then calls geogram CDT2d. The score is **231/234**; the 3 failures
mean those patches have no reference mesh to diff against C++.

**k=2 patches:** handled with endpoint-distance direction (full-stroke emission).
k=2 patches correctly triangulate because they form simple two-arc closed curves.

**Two-pass strategy:** `triangulatePatch` tries pass-1 (xnode-to-poly: find the
xnode in `xnodes[si]` closest to any point on the neighboring stroke's poly) and
on CDT2d rejection retries with pass-2 (xnode-to-xnode: find the xnode in
`xnodes[si]` closest to any xnode in the neighboring stroke's `xnodes`, which
better disambiguates strokes with ≥2 xnodes from different patches). CASSIE
records junctions asymmetrically (only the later-drawn stroke logs the junction),
so xnode-to-poly is more robust for strokes with symmetric recording while
xnode-to-xnode is more discriminating for multi-junction strokes.

**Remaining 3 failures:** 120 (k=5, bdPts=80), 178, 182 (k=10, bdPts=128). Both
passes fail CDT2d. The sub-segment is still self-intersecting after clipping — the
xnode world position doesn't land exactly on the densified Bézier polyline, so the
closest poly index may overshoot or undershoot the true junction, leaving a kink.

### C. Mesh → inventory item — deferred pending OpenUSD readiness

The intended path: CASSIE mesh → `.usd` file → `idtx-flow` imports it into
Godot as a `UsdMeshInstanceNode3D` → inventory item. `idtx-flow`
(https://github.com/v-sekai-multiplayer-fabric/idtx-flow) is the Godot plugin
that provides the import side; it handles `.usd`/`.usda`/`.usdc`/`.usdz` files
and maps `Mesh` prims to `ArrayMesh`. The CASSIE-side export (mesh → `.usd`) is
not started. Once the oracle reliably produces 234/234 correct meshes, the export
step is the next piece.

### D. OpenUSD → CDN — out of scope for this repo

A separate process is assumed to take the OpenUSD file produced by CASSIE and
deliver it to the zone backend / CDN (`OpenUSD archival → scn(zstd) → uro CDN`).
This repo has no responsibility for that step.

---

## Enablers

### E. Pipeline end-to-end — no recorded run against real data

The hexagonal ports-and-adapters `Pipeline/` library (Core/Ports/Adapters) builds
and passes 12 plausible property tests. `RunPipeline.lean` fully wires:
`jsonStrokeSource` → `samplestoSections` (RDP + G1) → `buildGraph` →
`detectCycles` → `verifySession` against `allCreatedPatches`. The `run-pipeline`
executable compiles and is declared in `lakefile.lean`. No successful run against
`hat.json` or any training session has been recorded, so the adapter layer and
graph/cycle integration have no observed output to verify.

### F. VR frame-budget validation

`walkSteps` in `frameLadder` (`Timeline.lean:367-370`) is a frame count, not a
cost in microseconds. No mapping from ladder rung to real VR-frame headroom exists.

Real per-stage timing lives in C++ (`test_cassie_pipeline_bench.h`:
`Time::get_ticks_usec()` around populate/find_cycles/sample_boundary/
manager_update). The gap has two parts: a C++ bench mode that replays
`systemStates` in `time` order and measures each gesture's incremental
add_stroke→find_cycles→sample→triangulate per frame; and ladder rungs expressed
against a real VR budget (90 Hz = 11.1 ms, 72 Hz = 13.9 ms) using measured
per-frame µs.

---

## Housekeeping

### G. Determinism — clusterIncidence is the remaining float boundary

`formsCycle` operates entirely on integer node ids from `StrokeIncidence`. The
single floating-point boundary is `clusterIncidence`, called once at load time
from `loadSession`. Within `clusterIncidence`, IEEE 754 variance can affect which
positions cluster together across platforms (FMA contraction, compiler reordering),
changing `hosted` and `endpts` sets and therefore the adjacency graph. The result
is stable on the one tested platform (x86-64 Linux, Lean v4.30.0, no `-O`). The
gap closes when `vdist2` is proven monotone in the relevant range for `hat.json`
coordinates, or float comparisons are replaced with exact rational arithmetic using
the JSON-parsed `mantissa / 10^exponent` values already available in `jnumFloat`.

### H. Fixture not regenerable from the timeline

`HatStrokes.lean` (138 strokes, 18 mirror partners) and `hat_polylines.json`
originate from `codegen_hat_strokes.py`, which is absent from disk. `HatDump.lean`
is an inverse roundtrip check, not a generator. `Timeline` has no path to emit
`hatStrokes`/`hatStrokeIds`/`hatPatches` from the recorded timeline. A
`Timeline.emitFixture` function closes it: `Frame`/`parseFrame` need each stroke's
flattened `ctrlPts` polyline (port of `_flatten_ctrl_pts`,
`test_cassie_pipeline_bench.h:811`), mirror partners by X-reflection about
x≈0.125, and output ordered by `closeFrame`.

### I. Detection parity: batch sweep 50/234 vs 208 target (diagnostic only)

> **Not on the delivery critical path.** `cycle_sweep` is a time-travelling
> diagnostic that checks all patches at once; the canonical verification is
> temporal (gap closed, see §Closed). This gap tracks oracle completeness, not
> production correctness.

`cycle_sweep` matches **50/234** patches. The algorithmic target is **208**
(`foundByAlgo = !userCreated`). The arrangement uses proximity-guessed crossings
instead of recorded `appliedPositionConstraints`, so the topology diverges from
the system's real graph (~98 nodes vs ~228 in the sweep). The gap is a
constraint-based arrangement: project each stroke's `appliedConstraints`
(`isIntersection` world positions) onto arc-length to get splits, then call
`buildArrangementFromSplits` (in `Arrangement.lean` in the cassie-lean tree).
Mirror strokes need their constraints reflected about x≈0.125.

Research findings (file:line in the cassie-lean Lean tree unless noted):
- **`findCyclesPort`** (`Walk.lean:219`) has per-node-normal machinery unused by
  the sweep. `Walk.lean:102 findCycles` reuses one global PCA normal (`Walk.lean:71`).
- **Arrangement resolution** partially closed: fallback emits every coalesced
  near-crossing per polyline pair, but no real `ctrlPts` cubic data feeds
  `intersectCubics`.
- **C++ ground truth unconfirmed:** `find_cycles()` on `hat.json` has no recorded
  dump; 208 derives from `foundByAlgo = !userCreated` (`Cycle.cs:127`), not a
  C++ run.

---

## Closed

### §1. Boundary incidence — 234/234

`Timeline.replay` verifies real **cycle incidence**: at each `SurfaceAdd` frame,
among strokes live at that frame, the boundary forms a single closed cycle.
**234/234** patches close a genuine temporal cycle (membership 234/234 as
precondition). The score is tolerance-free. Progression: 165 → 177 → 222 → 234.
