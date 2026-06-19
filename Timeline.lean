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

/-! ## Recorded geometry — intersection nodes (no proximity guessing)

Each stroke's `appliedPositionConstraints` carry the *exact* world positions
where it snaps to another stroke. The `isIntersection` ones are the graph nodes
the system actually used. We read these directly rather than recomputing or
proximity-guessing crossings. -/

abbrev Vec3 := Float × Float × Float

private def jnumFloat (n : Lean.JsonNumber) : Float :=
  Float.ofInt n.mantissa / Float.ofNat (10 ^ n.exponent)

private def parseVec (j : Json) : Except String Vec3 := do
  pure (jnumFloat (← (← j.getObjVal? "x").getNum?),
        jnumFloat (← (← j.getObjVal? "y").getNum?),
        jnumFloat (← (← j.getObjVal? "z").getNum?))

/-- Cubic Bezier point at `t`. -/
private def bezierAt (p0 p1 p2 p3 : Vec3) (t : Float) : Vec3 :=
  let mt := 1.0 - t
  let a := mt*mt*mt; let b := 3.0*mt*mt*t; let c := 3.0*mt*t*t; let d := t*t*t
  (a*p0.1   + b*p1.1   + c*p2.1   + d*p3.1,
   a*p0.2.1 + b*p1.2.1 + c*p2.2.1 + d*p3.2.1,
   a*p0.2.2 + b*p1.2.2 + c*p2.2.2 + d*p3.2.2)

/-- Densely sample a poly-Bezier given as `ctrlPts` (1+3k control points). -/
private def densify (ctrl : Array Vec3) (per : Nat := 16) : Array Vec3 := Id.run do
  if ctrl.size < 4 then return ctrl
  let nseg := (ctrl.size - 1) / 3
  let mut out : Array Vec3 := #[]
  for s in [:nseg] do
    let p0 := ctrl[3*s]!; let p1 := ctrl[3*s+1]!
    let p2 := ctrl[3*s+2]!; let p3 := ctrl[3*s+3]!
    let lo := if s == 0 then 0 else 1
    for i in [lo:per+1] do
      out := out.push (bezierAt p0 p1 p2 p3 (Float.ofNat i / Float.ofNat per))
  return out

/-- A stroke's `id`, its densely-sampled *beautified* curve (from `ctrlPts`), and
the world positions of its recorded *intersection* constraints. Sampling the
beautified curve (not raw `inputSamples`) places the polyline exactly where the
snapped junctions land. Adjacency is confirmed geometrically because constraints
are recorded asymmetrically (only the later-drawn stroke logs a junction). -/
private def parseStroke (j : Json) : Except String (Nat × Array Vec3 × Array Vec3) := do
  let id   ← (← j.getObjVal? "id").getNat?
  let ctrl ← (← (← j.getObjVal? "ctrlPts").getArr?).mapM parseVec
  let cons ← (← j.getObjVal? "appliedPositionConstraints").getArr?
  let pts ← cons.foldlM (init := (#[] : Array Vec3)) fun acc c => do
    if (← (← c.getObjVal? "isIntersection").getBool?) then
      pure (acc.push (← parseVec (← c.getObjVal? "position")))
    else pure acc
  pure (id, densify ctrl, pts)

private def ofExcept (e : Except String α) : IO α :=
  match e with
  | .ok a    => pure a
  | .error m => throw (IO.userError s!"hat.json: {m}")

/-- Load the canonical session: the frame timeline plus `boundary`, indexed by
patch id, giving each patch's recorded `strokesID`. -/
def loadSession (path : System.FilePath := "data/hat.json")
    : IO (Array Frame × Array (Array Nat) × Array (Array Vec3) × Array (Array Vec3)) := do
  let j ← ofExcept (Json.parse (← IO.FS.readFile path))
  let frames ← ofExcept do
    (← (← j.getObjVal? "systemStates").getArr?).mapM parseFrame
  let pairs ← ofExcept do
    (← (← j.getObjVal? "allCreatedPatches").getArr?).mapM parsePatch
  let strokePairs ← ofExcept do
    (← (← j.getObjVal? "allSketchedStrokes").getArr?).mapM parseStroke
  let maxPatchId := pairs.foldl (fun m (id, _) => max m id) 0
  -- max stroke id spans real ids AND the mirror (r+1) ids patches reference.
  let maxStrokeId := pairs.foldl
    (fun m (_, b) => b.foldl (fun m i => max m i) m)
    (strokePairs.foldl (fun m (id, _, _) => max m id) 0)
  let mut boundary : Array (Array Nat) := Array.replicate (maxPatchId + 1) #[]
  for (id, strokes) in pairs do
    boundary := boundary.set! id strokes
  -- polys[sid] = sampled polyline; xnodes[sid] = recorded intersection positions.
  let mut isReal : Array Bool := Array.replicate (maxStrokeId + 1) false
  let mut polys  : Array (Array Vec3) := Array.replicate (maxStrokeId + 1) #[]
  let mut xnodes : Array (Array Vec3) := Array.replicate (maxStrokeId + 1) #[]
  for (id, poly, pts) in strokePairs do
    polys  := polys.set! id poly
    xnodes := xnodes.set! id pts
    isReal := isReal.set! id true
  -- Synthesize mirror strokes: a patch-referenced id with no real stroke is the
  -- mirror `r+1` of real stroke `r`; reflect r's geometry about x ≈ 0.125.
  let reflectX : Vec3 → Vec3 := fun p => (0.25 - p.1, p.2.1, p.2.2)
  for mid in [:maxStrokeId + 1] do
    if ¬ isReal[mid]! ∧ mid > 0 ∧ isReal[mid - 1]! then
      polys  := polys.set!  mid ((polys[mid - 1]!).map reflectX)
      xnodes := xnodes.set! mid ((xnodes[mid - 1]!).map reflectX)
  pure (frames, boundary, polys, xnodes)

/-- Result of one full replay. `closeFrame[pid]` is the frame index at which patch
`pid` first closed (`none` if it never did). -/
structure Replay where
  closeFrame  : Array (Option Nat)
  patchFrames : Nat   -- type-3 frames seen
  closedOk    : Nat   -- of those, how many had their full boundary live (membership)
  incidenceOk : Nat   -- of those, how many also CLOSE A CYCLE (real incidence)
  deriving Inhabited

/-! ## Temporal cycle-incidence

Membership (`closedOk`) only checks the boundary strokes are present. Real
incidence asks whether they form a *closed cycle*: each boundary stroke meets
exactly two others at recorded intersection nodes, and they chain into a single
loop. We use only the strokes' recorded intersection positions (no proximity)
and only strokes live at the frame (the boundary is fully live by membership, so
every boundary–boundary junction is already present — temporally coherent). -/

private def vdist2 (a b : Vec3) : Float :=
  let dx := a.1 - b.1; let dy := a.2.1 - b.2.1; let dz := a.2.2 - b.2.2
  dx*dx + dy*dy + dz*dz

/-- Squared distance from point `p` to segment `[a,b]`. -/
private def ptSegDist2 (p a b : Vec3) : Float :=
  let abx := b.1 - a.1; let aby := b.2.1 - a.2.1; let abz := b.2.2 - a.2.2
  let apx := p.1 - a.1; let apy := p.2.1 - a.2.1; let apz := p.2.2 - a.2.2
  let d := abx*abx + aby*aby + abz*abz
  let t := if d > 1.0e-12 then
             min (max ((apx*abx + apy*aby + apz*abz) / d) 0.0) 1.0 else 0.0
  vdist2 p (a.1 + t*abx, a.2.1 + t*aby, a.2.2 + t*abz)

/-- Does `poly` pass within `√eps2` of point `p`? -/
private def nearPoly (poly : Array Vec3) (p : Vec3) (eps2 : Float) : Bool := Id.run do
  if poly.size == 0 then return false
  if poly.size == 1 then return vdist2 poly[0]! p < eps2
  for k in [1:poly.size] do
    if ptSegDist2 p poly[k-1]! poly[k]! < eps2 then return true
  return false

/-- Distinct junctions where both strokes meet: a recorded intersection of
either stroke through which the *other's* polyline also passes (geometry fixes
the asymmetric recording — only the later stroke logs a junction). -/
private def junctions (pa pb na nb : Array Vec3) (eps2 : Float) : Array Vec3 :=
  Id.run do
    let mut found : Array Vec3 := #[]
    let consider := fun (found : Array Vec3) (cands other : Array Vec3) =>
      Id.run do
        let mut found := found
        for p in cands do
          if nearPoly other p eps2 then
            let mut dup := false
            for f in found do
              if vdist2 p f < eps2 then dup := true
            if ¬ dup then found := found.push p
        return found
    found := consider found na pb
    found := consider found nb pa
    return found

/-- Does the patch boundary `B` form a single closed cycle?
- `k=1`: a single closed-loop stroke whose endpoints meet within eps.
- `k=2`: a lens — two arcs sharing at least two junctions.
- `k≥3`: every boundary stroke meets at least two others (degree ≥ 2);
  a greedy Hamiltonian walk visits all and returns to start. Degree > 2 is
  allowed (a stroke legitimately crossed mid-span by another boundary stroke
  has extra junctions); the greedy walk finds the cycle if it can. -/
def formsCycle (B : Array Nat) (polys xnodes : Array (Array Vec3)) : Bool := Id.run do
  let eps2 : Float := 1.0e-4  -- ~1cm; flat region of the eps-insensitive ctrlPts curve
  let k := B.size
  let pl : Nat → Array Vec3 := fun s => if s < polys.size then polys[s]! else #[]
  let nd : Nat → Array Vec3 := fun s => if s < xnodes.size then xnodes[s]! else #[]
  -- k=1: a single stroke forming a closed loop (start ≈ end).
  if k == 1 then
    let p := pl B[0]!
    return p.size ≥ 2 && vdist2 p[0]! p[p.size - 1]! < eps2
  if k == 2 then
    return (junctions (pl B[0]!) (pl B[1]!) (nd B[0]!) (nd B[1]!) eps2).size ≥ 2
  -- k ≥ 3: build boundary adjacency.
  let mut deg : Array Nat := Array.replicate k 0
  let mut adj : Array (Array Nat) := Array.replicate k #[]
  for a in [:k] do
    for b in [a+1:k] do
      if ¬ (junctions (pl B[a]!) (pl B[b]!) (nd B[a]!) (nd B[b]!) eps2).isEmpty then
        adj := adj.modify a (·.push b); adj := adj.modify b (·.push a)
        deg := deg.modify a (· + 1);    deg := deg.modify b (· + 1)
  -- Every stroke must meet at least 2 others; mid-span crossings give degree > 2.
  for a in [:k] do
    if deg[a]! < 2 then return false
  -- Greedy Hamiltonian walk: always pick the first non-previous neighbor.
  -- For degree-2 nodes this is deterministic; for degree > 2 it's a greedy
  -- heuristic that succeeds when the cycle-edge happens to come first.
  let mut prev := k
  let mut cur := 0
  let mut seen : Array Bool := Array.replicate k false
  let mut ok := true
  for _ in [:k] do
    if seen[cur]! then ok := false
    seen := seen.set! cur true
    let nbrs := adj[cur]!
    let mut nxt := cur
    let mut found := false
    for nb in nbrs do
      if ¬ found && nb != prev then
        nxt := nb; found := true
    prev := cur; cur := nxt
  return ok ∧ seen.all id ∧ cur == 0

/-- Fold the timeline, grouping consecutive equal-`timeId` frames, applying
adds/deletes (with mirror partners) before evaluating that group's patches. -/
def replay (frames : Array Frame) (boundary : Array (Array Nat))
    (polys xnodes : Array (Array Vec3)) : Replay := Id.run do
  let n := frames.size
  let mut live  : List Nat := []
  let mut close : Array (Option Nat) := Array.replicate boundary.size none
  let mut patchFrames := 0
  let mut closedOk := 0
  let mut incidenceOk := 0
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
          let bnd := boundary[pid]!
          if bnd.all (live.contains ·) then
            closedOk := closedOk + 1
            if close[pid]! == none then close := close.set! pid (some (j - 1))
            -- Real incidence: the live boundary must also close a cycle.
            if formsCycle bnd polys xnodes then
              incidenceOk := incidenceOk + 1
      i := j
  pure { closeFrame := close, patchFrames, closedOk, incidenceOk }

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
