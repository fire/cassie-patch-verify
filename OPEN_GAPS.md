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

The gap is a script or Lean program that loads `patches_mesh.json` alongside the
C++ mesh dump (e.g. exported from the Godot scene or `CassiePolylinesJson`) and
reports per-patch vertex/topology differences above a threshold.

### B. Boundary triangulation — 186/234 (oracle incomplete)

`TriangulatePatches` walks each patch's recorded `strokesID` in order (CASSIE
writes them in cycle order), determines per-stroke direction by comparing endpoint
distances, emits a flat xyz polyline, then calls geogram CDT2d. The score is
**186/234**; the 48 failures mean those 48 patches have no reference mesh to diff
against C++, so C++ bugs in those patches are invisible to the oracle.

**Group A — k=2 lens patches (patches 0, 1, 2, 93):** both strokes share the same
two endpoint positions (axis of symmetry x≈0.125). The distance comparison ties at
0 for both ends simultaneously, so both strokes emit in the same direction,
producing a figure-8 self-intersection that CDT2d rejects. The missing piece is a
tie-breaking rule: a symmetric tie identifies a lens boundary, and the second
stroke traverses opposite to the first.

**Group B — k=4+ patches (44 patches):** geogram reports "bad input" or "no
solution." The polyline self-intersects because the `exitPt` direction check
(`walkBoundary`, `TriangulatePatches.lean:44`) picks the wrong end when a stroke
belongs to multiple overlapping patches and both ends sit near different junction
candidates. Two candidate paths exist: (a) threading the previous stroke's actual
exit point through the loop (chaining), which a naive implementation worsens to
150/234 by propagating bootstrap errors — see TOMBSTONES; (b) seeding direction
from `appliedPositionConstraints` junction positions already present in `hat.json`.

### C. Mesh → inventory item — no wiring

No code converts a triangulated CASSIE patch mesh into a V-Sekai inventory item.
The content-creation pipeline's differentiator is that a VR drawing becomes a
tradeable item; this conversion step has no implementation or specification in
this repo or in the V-Sekai codebase as far as is known here.

The gap includes: a schema for what an "item" is (mesh + metadata), the Godot
code that registers the mesh output as an item in the inventory system, and a
round-trip test that a drawn hat patch appears in a player's inventory.

### D. OpenUSD export — no implementation

No code archives a CASSIE mesh to OpenUSD format for CDN storage. The 1Password
priority poll records `inventory ↔ OpenUSD I/O` as a high-priority item (voted by
Lyuma), and the architecture note describes "OpenUSD archival → scn(zstd) → uro
CDN," but no implementation exists in this repo.

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
