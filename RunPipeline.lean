/-! # run-pipeline — end-to-end replay from raw inputSamples

Usage:
  run-pipeline <session.json>

Reads raw inputSamples, runs the full pipeline
(RDP → G1 sections → graph build → cycle detection → DMWT triangulation),
then verifies output against allCreatedPatches ground truth.
-/
import Pipeline

open Pipeline.Core Pipeline.Ports Pipeline.Adapters

/-- Convert raw sample positions → poly-Bézier sections via RDP + G1 split.

    We skip Bézier fitting (no ctrlPts available from raw input) and instead
    use the densified polyline itself as a degenerate degree-1 "Bézier" with
    one straight segment per pair of retained points.  The graph builder and
    cycle detector operate on Vec3 arrays directly.
-/
def samplestoSections (pts : Array Vec3) : Array (Array Vec3) :=
  let rdp     := rdpReduce pts 0.002  -- match CASSIE default tolerance
  let secs    := g1Sections rdp
  secs

/-- Full pipeline for one session file. -/
def runSession (path : System.FilePath) : IO Unit := do
  -- load strokes
  let src    := jsonStrokeSource path
  let strokes ← src.load
  IO.println s!"Loaded {strokes.size} strokes from {path}"

  -- RDP + G1 sections
  let sections : Array (Array Vec3) :=
    strokes.flatMap (fun (_, pts) => samplestoSections pts)
  IO.println s!"  {sections.size} sections after RDP+G1"

  -- build graph
  let graph := buildGraph sections
  IO.println s!"  Graph: {graph.nodes.size} nodes, {graph.segments.size} segments"

  -- cycle detection
  let cycles := detectCycles graph
  IO.println s!"  {cycles.size} cycles detected"

  -- triangulate each cycle via DMWT
  let mut patchCount := 0
  for cycle in cycles do
    -- collect boundary: last point of each segment in order
    let boundary := cycle.map (fun sid =>
      let s := graph.segments.getD sid default
      s.ctrl[s.ctrl.size - 1]!)
    match ← dmwtPort.triangulate boundary with
    | .error e => IO.println s!"  DMWT error: {e}"
    | .ok _    => patchCount := patchCount + 1
  IO.println s!"  {patchCount} patches triangulated"

  -- verify against ground truth
  let gt ← verifySession path patchCount
  IO.println s!"  Ground truth: {gt.expectedPatchCount} expected, {gt.producedPatchCount} produced, matched={gt.matched}"

def main (args : List String) : IO Unit := do
  match args with
  | []   => IO.println "Usage: run-pipeline <session.json> [session.json ...]"
  | paths =>
      for p in paths do
        runSession p
        IO.println ""
