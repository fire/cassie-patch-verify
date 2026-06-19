import Pipeline.Core.Vec3
import Pipeline.Core.Graph
import Pipeline.Core.Bezier
/-! # Cycle detection — CCW graph walk (dependency-free core)

Port of `CycleDetection.cs` from the Unity CASSIE codebase.
-/
namespace Pipeline.Core
open Vec3

-- ────────────────────────────────────────────────────────────────────────────
-- Node normal computation
-- ────────────────────────────────────────────────────────────────────────────

/-- Collect all tangent directions incident to a node (in = reversed, out = forward). -/
private def incidentTangents (g : Graph) (nid : NodeId) : Array Vec3 :=
  let nd := g.nodes.getD nid default
  let outs := nd.outSegs.map (fun sid => g.entryTangent sid)
  let ins  := nd.inSegs.map  (fun sid => Vec3.neg (g.exitTangent sid))
  outs ++ ins

/-- Best-fit plane normal from a set of unit vectors (sum → normalise). -/
private def fitNormal (dirs : Array Vec3) (fallback : Vec3) : Vec3 :=
  if dirs.size < 2 then fallback
  else
    -- iterative cross-product accumulation
    let sum := dirs.foldl (init := Vec3.zero) fun acc d => Vec3.add acc d
    let n   := Vec3.normalize sum
    if n.mag2 < 0.01 then
      -- degenerate: cross first two
      let c := Vec3.cross dirs[0]! dirs[1]!
      if c.mag2 > 0.01 then Vec3.normalize c else fallback
    else n

/-- Whether a node is "sharp" — max tangent error > 0.5 rad. -/
private def isSharpNode (g : Graph) (nid : NodeId) : Bool :=
  let dirs := incidentTangents g nid
  if dirs.size < 2 then false
  else
    let n := fitNormal dirs (0.0, 1.0, 0.0)
    dirs.any (fun d =>
      let proj := Vec3.normalize (Vec3.projectOnPlane d n)
      proj.mag2 > 0.01 &&
        Float.acos (max (-1.0) (min 1.0 (Vec3.dot d proj))) > 0.5)

-- ────────────────────────────────────────────────────────────────────────────
-- CCW segment ordering at a node
-- ────────────────────────────────────────────────────────────────────────────

/-- Angle of `dir` projected onto the plane of `normal`, with `ref` as the
    zero-angle direction. -/
private def projectedAngle (dir normal ref : Vec3) : Float :=
  let d := Vec3.normalize (Vec3.projectOnPlane dir normal)
  if d.mag2 < 0.01 then 0.0
  else
    let perp := Vec3.cross normal ref
    Float.atan2 (Vec3.dot d perp) (Vec3.dot d ref)

/-- Sort incident segment ids at `nid` in CCW order around the node normal,
    starting from `refDir` in the plane.  Returns `(segId, outgoing?)` pairs
    where `outgoing = true` means this half-edge *leaves* the node. -/
private def ccwOrder (g : Graph) (nid : NodeId) (refDir normal : Vec3)
    : Array (SegId × Bool) :=
  let nd := g.nodes.getD nid default
  let pairs : Array (Float × SegId × Bool) :=
    (nd.outSegs.map (fun sid =>
        let t := g.entryTangent sid
        (projectedAngle t normal refDir, sid, true))) ++
    (nd.inSegs.map (fun sid =>
        let t := Vec3.neg (g.exitTangent sid)
        (projectedAngle t normal refDir, sid, false)))
  let sorted := pairs.toList.mergeSort (fun a b => a.1 < b.1) |>.toArray
  sorted.map (fun (_, sid, out) => (sid, out))

-- ────────────────────────────────────────────────────────────────────────────
-- Walk one face starting from half-edge (srcNode, seg, outgoing)
-- ────────────────────────────────────────────────────────────────────────────

private structure WalkState where
  visited : Array (NodeId × SegId) := #[]  -- to detect cycles
  cycle   : Array SegId             := #[]
  normal  : Vec3                            -- transported plane normal

private def MAX_WALK : Nat := 64

/-- One step of the CCW face walk.  Returns the next (nodeId, segId, outgoing)
    or none if the face closed. -/
private def walkStep (g : Graph) (curNode : NodeId) (arrSeg : SegId)
    (arrOut : Bool) (norm : Vec3) : Option (NodeId × SegId × Bool × Vec3) :=
  -- transport normal from the segment we arrived on
  let nodNorm := fitNormal (incidentTangents g curNode) norm
  -- arrival tangent at curNode (direction INTO the node)
  let arrTan :=
    if arrOut then Vec3.neg (g.entryTangent arrSeg)
    else g.exitTangent arrSeg
  let ord := ccwOrder g curNode arrTan nodNorm
  -- find the arrived segment in the ordering, pick the next one CCW
  let idx? := ord.findIdx? (fun (sid, out) => sid == arrSeg && out == arrOut)
  match idx? with
  | none => none
  | some idx =>
      -- next CCW = previous in the array (we want the one just CCW after arrival)
      let nextIdx := (idx + ord.size - 1) % ord.size
      let (nextSeg, nextOut) := ord[nextIdx]!
      let nextNode :=
        if nextOut then (g.segments.getD nextSeg default).tailId
        else (g.segments.getD nextSeg default).headId
      -- transport normal along the next segment
      let exitTan :=
        if nextOut then g.exitTangent nextSeg
        else Vec3.neg (g.entryTangent nextSeg)
      let norm' := Vec3.transport nodNorm arrTan exitTan
      some (nextNode, nextSeg, nextOut, norm')

private partial def walkFace (g : Graph) (startNode : NodeId) (startSeg : SegId)
    (startOut : Bool) (norm : Vec3) (fuel : Nat)
    (seen : Array (NodeId × SegId)) (acc : Array SegId)
    : Option (Array SegId) :=
  if fuel == 0 then none
  else match walkStep g startNode startSeg startOut norm with
  | none => none
  | some (nextNode, nextSeg, nextOut, norm') =>
      -- closed?
      if nextNode == startNode && nextSeg == startSeg then some (acc.push nextSeg)
      -- already visited this half-edge?
      else if seen.any (fun (n, s) => n == nextNode && s == nextSeg) then none
      else
        walkFace g nextNode nextSeg nextOut norm'
          (MAX_WALK - fuel + 1) (seen.push (nextNode, nextSeg)) (acc.push nextSeg)

-- ────────────────────────────────────────────────────────────────────────────
-- Top-level: find all faces
-- ────────────────────────────────────────────────────────────────────────────

/-- Detect all minimal cycles in the graph.
    Returns each cycle as an ordered array of segment ids. -/
def detectCycles (g : Graph) : Array (Array SegId) := Id.run do
  let mut results : Array (Array SegId) := #[]
  -- de-duplication: a canonical cycle is identified by its sorted segment set
  let mut seen : Array (Array SegId) := #[]
  for nid in [:g.nodes.size] do
    let nd := g.nodes.getD nid default
    -- try every half-edge leaving this node
    for sid in nd.outSegs do
      let norm := fitNormal (incidentTangents g nid) (0.0, 1.0, 0.0)
      match walkFace g nid sid true norm MAX_WALK #[] #[sid] with
      | none       => pure ()
      | some cycle =>
          let key := cycle.toList.mergeSort.toArray
          if !seen.any (· == key) then
            seen    := seen.push key
            results := results.push cycle
    for sid in nd.inSegs do
      let norm := fitNormal (incidentTangents g nid) (0.0, 1.0, 0.0)
      match walkFace g nid sid false norm MAX_WALK #[] #[sid] with
      | none       => pure ()
      | some cycle =>
          let key := cycle.toList.mergeSort.toArray
          if !seen.any (· == key) then
            seen    := seen.push key
            results := results.push cycle
  return results

end Pipeline.Core
