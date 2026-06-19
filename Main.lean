import PlausibleWitnessDag
open PlausibleWitnessDag

/-! # cassie-patch-verify (prototype)

An **independent** Lean oracle that reads the C++ cassie module's patch output
(data only — no FFI, never linked into the Godot/C++ build) and certifies each
patch via the `plausible-witness-dag` ladder.

This first cut proves the v4.30.0 + `plausible-witness-dag` pipeline and the
budget-escalation behaviour that rebuts "T7 is too dense to walk": a patch whose
boundary needs a 6-step walk `budgetHit`s at L0 (4 steps) and resolves at L1
(8 steps) instead of being declared impossible. The deterministic walk and the
candidate predicate are the only domain inputs; the driver owns the ladder.
-/

/-- Tiny escalation ladder for the demo (L0 cheap, L1 wider). -/
def demoLadder : Array Level := #[
  { idx := 0, walkSteps := 4, finBound := 256, numInst := 200 },
  { idx := 1, walkSteps := 8, finBound := 256, numInst := 200 } ]

/-- Stand-in patch certification: the witness is a boundary walk of `targetSteps`
    steps. `candidateIsWitness` poses existence to `plausible`; `readback` is the
    deterministic budgeted walk that reports `found` / `budgetHit`. -/
def verifyPatch (name : String) (targetSteps : Nat) : IO Unit := do
  let candidateIsWitness : Level → Nat → Bool := fun _ k => k == targetSteps
  let readback : Nat → Readback Nat := fun budget =>
    if budget ≥ targetSteps then
      { value := targetSteps, found := true, witnessIdx := targetSteps, budgetHit := false }
    else
      { value := 0, found := false, budgetHit := true }
  let (val, lvl, tr) ← resolve name candidateIsWitness readback demoLadder
  IO.println s!"  {name}: boundary={val}  resolved@L{lvl}  outcome={repr tr.outcome}"

def main : IO Unit := do
  IO.println "cassie-patch-verify — independent witness-DAG oracle (prototype)"
  verifyPatch "patch:small(3)" 3   -- resolves at L0
  verifyPatch "patch:brim(6)"  6   -- L0 budgetHit -> escalate -> L1 found
  verifyPatch "patch:huge(9)"  9   -- both rungs budget-hit -> needs a deeper rung
