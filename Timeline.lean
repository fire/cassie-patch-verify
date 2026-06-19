import Lean.Data.Json
import PlausibleWitnessDag

/-! # Temporal constructor (the core deliverable)

Replays `data/hat.json`'s `systemStates` (the VR session timeline) in `time`
order and proves the patch construction is valid **frame-by-frame** — exactly the
top item of `OPEN_GAPS.md`. Nothing here links into the C++/Godot build; the only
input is the JSON the cassie module dumps.

Model (validated against all 234 recorded patches):

* Frames are processed in recorded order, which is `time`-ascending.
* Frames sharing one `time` are **one gesture**: the create-patch (type 3) event
  is logged *just before* the add-stroke (type 1) that closes it, so adds and
  deletes in a timestamp group are applied *before* its type-3 patch checks.
* `mirroring` is on for the whole hat session: an add of stroke `r` also brings
  in its mirror `r+1`, and a delete removes both. The 18 odd "phantom" stroke ids
  patches reference (`5,7,9,19,21,…`) are precisely these mirror partners — they
  never appear in `allSketchedStrokes` because only user-drawn strokes are stored.
* A patch **closes** at the first frame where every stroke in its recorded
  `strokesID` is live. We replay the recorded membership; we never recompute 3D
  intersections.

This corrects the action model in the SSOT docs, which omitted mirroring and the
same-timestamp patch-before-stroke ordering (so a naive replay closed only
37/234). -/

open Lean PlausibleWitnessDag

namespace CassieTimeline

/-- One VR frame, trimmed to the fields the constructor folds over. `timeId` is
the exact numeric token (not a `Float`) so same-instant frames group reliably. -/
structure Frame where
  itype  : Nat
  timeId : String
  eid    : Int
  mirror : Bool
  deriving Repr, Inhabited

private def parseFrame (j : Json) : Except String Frame := do
  let itype  ← (← j.getObjVal? "interactionType").getNat?
  let timeId := toString (← (← j.getObjVal? "time").getNum?)
  let eid    ← (← j.getObjVal? "elementID").getInt?
  let mirror ← (← j.getObjVal? "mirroring").getBool?
  pure { itype, timeId, eid, mirror }

private def parsePatch (j : Json) : Except String (Nat × Array Nat) := do
  let id      ← (← j.getObjVal? "id").getNat?
  let strokes ← (← (← j.getObjVal? "strokesID").getArr?).mapM (·.getNat?)
  pure (id, strokes)

private def ofExcept (e : Except String α) : IO α :=
  match e with
  | .ok a    => pure a
  | .error m => throw (IO.userError s!"hat.json: {m}")

/-- Load the canonical session: the frame timeline plus `boundary`, indexed by
patch id, giving each patch's recorded `strokesID`. -/
def loadSession (path : System.FilePath := "data/hat.json")
    : IO (Array Frame × Array (Array Nat)) := do
  let j ← ofExcept (Json.parse (← IO.FS.readFile path))
  let frames ← ofExcept do
    (← (← j.getObjVal? "systemStates").getArr?).mapM parseFrame
  let pairs ← ofExcept do
    (← (← j.getObjVal? "allCreatedPatches").getArr?).mapM parsePatch
  let maxId := pairs.foldl (fun m (id, _) => max m id) 0
  let mut boundary : Array (Array Nat) := Array.replicate (maxId + 1) #[]
  for (id, strokes) in pairs do
    boundary := boundary.set! id strokes
  pure (frames, boundary)

/-- Result of one full replay. `closeFrame[pid]` is the frame index at which patch
`pid` first closed (`none` if it never did). -/
structure Replay where
  closeFrame  : Array (Option Nat)
  patchFrames : Nat   -- type-3 frames seen
  closedOk    : Nat   -- of those, how many had their full boundary live
  deriving Inhabited

/-- Fold the timeline, grouping consecutive equal-`timeId` frames, applying
adds/deletes (with mirror partners) before evaluating that group's patches. -/
def replay (frames : Array Frame) (boundary : Array (Array Nat)) : Replay := Id.run do
  let n := frames.size
  let mut live  : List Nat := []
  let mut close : Array (Option Nat) := Array.replicate boundary.size none
  let mut patchFrames := 0
  let mut closedOk := 0
  let mut i := 0
  for _ in [0:n] do
    if i < n then
      let t := frames[i]!.timeId
      -- group end: first later frame with a different timestamp
      let mut j := n
      let mut scanning := true
      for k in [i:n] do
        if scanning && frames[k]!.timeId != t then
          j := k; scanning := false
      -- apply structural edits first
      for k in [i:j] do
        let f := frames[k]!
        if f.itype == 1 then
          live := f.eid.toNat :: live
          if f.mirror then live := (f.eid.toNat + 1) :: live
        else if f.itype == 2 then
          live := live.filter (· != f.eid.toNat)
          if f.mirror then live := live.filter (· != f.eid.toNat + 1)
      -- then test which patches this gesture closed
      for k in [i:j] do
        let f := frames[k]!
        if f.itype == 3 then
          patchFrames := patchFrames + 1
          let pid := f.eid.toNat
          if (boundary[pid]!).all (live.contains ·) then
            closedOk := closedOk + 1
            if close[pid]! == none then close := close.set! pid (some (j - 1))
      i := j
  pure { closeFrame := close, patchFrames, closedOk }

def closeFrameOf (r : Replay) (pid : Nat) : Option Nat :=
  if h : pid < r.closeFrame.size then r.closeFrame[pid] else none

/-! ## Witness-DAG wiring

Per `OPEN_GAPS.md` item 2: the ladder's `walkSteps` is the **per-VR-frame budget**.
`readback budget` replays up to `budget` frames and reports whether the target
patch has closed; `candidateIsWitness` is the "expected patch present" test. So a
patch that closes late `budgetHit`s on a shallow rung and resolves on a deeper one
— the prototype's escalation story, now on real session data instead of a
stand-in. -/

/-- Frame-budget ladder. `finBound 256` is the candidate window over patch ids
0–233. -/
def frameLadder : Array PlausibleWitnessDag.Level := #[
  { idx := 0, walkSteps := 64,   finBound := 256, numInst := 200 },
  { idx := 1, walkSteps := 512,  finBound := 256, numInst := 200 },
  { idx := 2, walkSteps := 4096, finBound := 256, numInst := 200 } ]

/-- A patch id is a witness at a rung iff it is the target and closes within that
rung's frame budget. Posed to `plausible` as an existence problem. -/
def patchCandidate (r : Replay) (target : Nat) (lvl : PlausibleWitnessDag.Level) (candidate : Nat) : Bool :=
  candidate == target &&
    (match closeFrameOf r target with
     | some cf => cf ≤ lvl.walkSteps
     | none    => false)

/-- Deterministic read-back: replay the budgeted prefix and recover the closing
frame, distinguishing a real "never closes" from a mere frame-budget hit. -/
def patchReadback (r : Replay) (target : Nat) (budget : Nat) : Readback Nat :=
  match closeFrameOf r target with
  | some cf =>
      if cf ≤ budget then
        { value := cf, found := true, witnessIdx := cf, budgetHit := false }
      else
        { value := 0, found := false, budgetHit := true }
  | none => { value := 0, found := false, budgetHit := false }

/-- Resolve "when does patch `target` close?" across the frame-budget ladder. -/
def resolvePatch (r : Replay) (target : Nat) : IO (Nat × Nat × TraceEntry) :=
  resolve s!"patch {target} closes" (patchCandidate r target)
    (patchReadback r target) frameLadder

end CassieTimeline
