import Lean.Data.Json
/-! # GroundTruth adapter — verify patches against allCreatedPatches

Reads the ground-truth patch ids from the session JSON and checks that
the pipeline produced at least the same patch count.
-/
open Lean

namespace Pipeline.Adapters

structure GroundTruthResult where
  expectedPatchCount : Nat
  producedPatchCount : Nat
  matched            : Bool   -- produced ≥ expected
  deriving Repr

/-- Parse allCreatedPatches from a session JSON. -/
def expectedPatchCount (j : Json) : Nat :=
  match j.getObjVal? "allCreatedPatches" with
  | .ok (.arr a) => a.size
  | _            => 0

/-- Compare produced count against ground truth from a JSON session file. -/
def verifySession (sessionPath : System.FilePath) (produced : Nat)
    : IO GroundTruthResult := do
  let text ← IO.FS.readFile sessionPath
  match Json.parse text with
  | .error e =>
      throw (IO.userError s!"GroundTruth: parse error {sessionPath}: {e}")
  | .ok j =>
      let expected := expectedPatchCount j
      return { expectedPatchCount := expected
               producedPatchCount := produced
               matched            := produced ≥ expected }

end Pipeline.Adapters
