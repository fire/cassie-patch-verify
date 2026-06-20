import Plausible
import Pipeline.Core.Vec3
import Pipeline.Core.Graph
import Pipeline.Core.CycleDetect
import Timeline
import Lean.Data.Json
import Pipeline.Adapters.GroundTruth
open Pipeline.Core Vec3 Plausible Lean

-- Smoke: Vec3 dot is symmetric (avoid 'by' as binder name — it's a keyword)
#eval Testable.check (∀ (ax ay az bx b_y bz : Fin 1001),
  let finF (n : Fin 1001) : Float := (n.val.toFloat - 500.0) / 100.0
  let mkV (x y z : Fin 1001) : Vec3 := (finF x, finF y, finF z)
  dot (mkV ax ay az) (mkV bx b_y bz) == dot (mkV bx b_y bz) (mkV ax ay az))

-- Smoke: detectCycles on empty graph
-- (explicit IO Unit annotation to resolve 'throw')
#eval (do
  let cycles := detectCycles (default : Graph)
  unless cycles.size == 0 do
    throw (IO.userError s!"expected 0 cycles, got {cycles.size}") : IO Unit)

-- Smoke: patchReadback
#eval (do
  let r : CassieTimeline.Replay :=
    { closeFrame := #[some 3], livePatchFinal := #[true],
      patchFrames := 1, closedOk := 1, incidenceOk := 1 }
  let rb := CassieTimeline.patchReadback r 0 64
  unless rb.found && rb.value == 3 do
    throw (IO.userError "patchReadback failed") : IO Unit)

-- Smoke: expectedPatchCount
#eval (do
  let j := Json.mkObj [("allCreatedPatches", Json.arr #[Json.str "p0", Json.str "p1"])]
  let n := Pipeline.Adapters.expectedPatchCount j
  unless n == 2 do
    throw (IO.userError s!"expectedPatchCount: expected 2, got {n}") : IO Unit)
