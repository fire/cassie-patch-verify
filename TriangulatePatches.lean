import Lean.Data.Json
import Timeline
import CassieGeogram

/-! # TriangulatePatches

Drives the CASSIE triangulation pipeline on the hat session:
  boundary cycle → ordered polyline → geogram CDT2d → JSON mesh

Outputs `data/patches_mesh.json` with vertices + triangle indices for all
234 patches. The Blender visualizer loads this instead of using a bespoke fill.
-/

open Lean CassieTimeline CassieGeogram

namespace CassieTriangulate

/-- Index of the point in `poly` closest to `target`. -/
private def closestIdx (poly : Array Vec3) (target : Vec3) : Nat := Id.run do
  let vd2 (a b : Vec3) : Float :=
    let dx := a.1 - b.1; let dy := a.2.1 - b.2.1; let dz := a.2.2 - b.2.2
    dx*dx + dy*dy + dz*dz
  let mut best := 0; let mut bestD := 1.0e308
  for i in [:poly.size] do
    let d := vd2 poly[i]! target
    if d < bestD then best := i; bestD := d
  return best

/-- Closest xnode in `xns` to any point in `refPoly`; returns the xnode or `none`. -/
private def closestXnode (xns : Array Vec3) (refPoly : Array Vec3) : Option Vec3 := Id.run do
  if xns.isEmpty || refPoly.isEmpty then return none
  let vd2 (a b : Vec3) : Float :=
    let dx := a.1 - b.1; let dy := a.2.1 - b.2.1; let dz := a.2.2 - b.2.2
    dx*dx + dy*dy + dz*dz
  let mut bestXn : Vec3 := xns[0]!; let mut bestD := 1.0e308
  for xn in xns do
    for rp in refPoly do
      let d := vd2 xn rp
      if d < bestD then bestXn := xn; bestD := d
  return some bestXn

/-- Walk the ordered boundary strokes into a flat xyz FloatArray for CDT2d.
    For strokes with recorded intersection positions (`xnodes[si]`), clips to the
    sub-segment between entry and exit junctions to avoid self-intersections when a
    stroke spans multiple overlapping patches.  Falls back to full-poly endpoint
    direction for strokes with no xnodes. -/
def walkBoundary (B : Array Nat) (inc : Array StrokeIncidence)
    (polys : Array (Array Vec3)) (xnodes : Array (Array Vec3)) : Array Float := Id.run do
  let k := B.size
  if k == 0 then return #[]

  -- k=1: single closed-loop stroke — emit all points
  if k == 1 then
    let poly := polys.getD (B.getD 0 0) #[]
    let mut out : Array Float := #[]
    for p in poly do
      out := out.push p.1; out := out.push p.2.1; out := out.push p.2.2
    return out

  let vd2 (a b : Vec3) : Float :=
    let dx := a.1 - b.1; let dy := a.2.1 - b.2.1; let dz := a.2.2 - b.2.2
    dx*dx + dy*dy + dz*dz

  -- k=2: prev and next are the same stroke, so xnode search collapses to the same
  -- junction for entry and exit — emit full strokes with endpoint-distance direction.
  if k == 2 then
    let s0 := B.getD 0 0; let s1 := B.getD 1 0
    let poly0 := polys.getD s0 #[]; let poly1 := polys.getD s1 #[]
    let p00 := poly0.getD 0 (0.0,0.0,0.0)
    let p0L := poly0.getD (poly0.size - 1) (0.0,0.0,0.0)
    let q10 := poly1.getD 0 (0.0,0.0,0.0)
    let q1L := poly1.getD (poly1.size - 1) (0.0,0.0,0.0)
    let d0near := min (vd2 p00 q10) (vd2 p00 q1L)
    let dLnear := min (vd2 p0L q10) (vd2 p0L q1L)
    let fwd0 := dLnear ≤ d0near
    let exitPt0 : Vec3 := if fwd0 then p0L else p00
    let mut out : Array Float := #[]
    -- stroke 0: emit all except last
    let pts0 := if fwd0 then poly0 else poly0.reverse
    for pi in [:pts0.size - 1] do
      let p := pts0.getD pi (0.0,0.0,0.0)
      out := out.push p.1; out := out.push p.2.1; out := out.push p.2.2
    -- stroke 1: entry is whichever end is closer to exitPt0
    let fwd1 := vd2 q10 exitPt0 ≤ vd2 q1L exitPt0
    let pts1 := if fwd1 then poly1 else poly1.reverse
    for pi in [:pts1.size - 1] do
      let p := pts1.getD pi (0.0,0.0,0.0)
      out := out.push p.1; out := out.push p.2.1; out := out.push p.2.2
    return out

  let mut out : Array Float := #[]

  for oi in [:k] do
    let si     := B.getD oi 0
    let poly   := polys.getD si #[]
    let xns    := xnodes.getD si #[]
    let prevSi := B.getD ((oi + k - 1) % k) 0
    let nextSi := B.getD ((oi + 1) % k) 0
    let prevPoly := polys.getD prevSi #[]
    let nextPoly := polys.getD nextSi #[]

    -- Junction-based clipping when the stroke has recorded intersection positions.
    -- Entry xnode: junction closest to previous stroke's polyline.
    -- Exit xnode:  junction closest to next stroke's polyline.
    let entryIdx : Nat :=
      match closestXnode xns prevPoly with
      | some xn => closestIdx poly xn
      | none =>
        -- Fallback: use whichever endpoint is closer to previous stroke's endpoints
        let p0 := poly.getD 0 (0.0, 0.0, 0.0)
        let pL := poly.getD (poly.size - 1) (0.0, 0.0, 0.0)
        let pp0 := prevPoly.getD 0 (0.0, 0.0, 0.0)
        let ppL := prevPoly.getD (prevPoly.size - 1) (0.0, 0.0, 0.0)
        let d0 := min (vd2 p0 pp0) (vd2 p0 ppL)
        let dL := min (vd2 pL pp0) (vd2 pL ppL)
        if d0 ≤ dL then 0 else poly.size - 1

    let exitIdx : Nat :=
      match closestXnode xns nextPoly with
      | some xn => closestIdx poly xn
      | none =>
        let p0 := poly.getD 0 (0.0, 0.0, 0.0)
        let pL := poly.getD (poly.size - 1) (0.0, 0.0, 0.0)
        let np0 := nextPoly.getD 0 (0.0, 0.0, 0.0)
        let npL := nextPoly.getD (nextPoly.size - 1) (0.0, 0.0, 0.0)
        let d0 := min (vd2 p0 np0) (vd2 p0 npL)
        let dL := min (vd2 pL np0) (vd2 pL npL)
        if dL ≤ d0 then poly.size - 1 else 0

    -- Emit the sub-segment from entryIdx to exitIdx (exclusive of exitIdx,
    -- which is shared with the next stroke).
    if entryIdx ≤ exitIdx then
      for pi in [entryIdx : exitIdx] do
        let p := poly.getD pi (0.0, 0.0, 0.0)
        out := out.push p.1; out := out.push p.2.1; out := out.push p.2.2
    else
      -- Reverse sub-segment
      let mut pi := entryIdx
      while pi > exitIdx do
        let p := poly.getD pi (0.0, 0.0, 0.0)
        out := out.push p.1; out := out.push p.2.1; out := out.push p.2.2
        pi := pi - 1

  return out

/-- Triangulate one patch boundary via geogram CDT2d.
    Returns `(verts_flat_xyz, tris_flat_abc)` or empty arrays on failure. -/
def triangulatePatch (B : Array Nat) (inc : Array StrokeIncidence)
    (polys : Array (Array Vec3)) (xnodes : Array (Array Vec3)) : IO (Array Float × Array Nat) := do
  let bd := walkBoundary B inc polys xnodes
  let n := bd.size / 3
  if n < 3 then return (#[], #[])
  let fa := FloatArray.mk bd
  let dh ← delaunayFromBoundary n.toUSize fa 0.0
  let nv ← nVertices dh
  let nt ← nTriangles dh
  if nv.toNat == 0 || nt.toNat == 0 then
    delaunayFree dh; return (#[], #[])
  let vbuf ← getPositions dh  -- raw bytes: 8 bytes per double
  let tbuf ← getTriangles dh  -- raw bytes: 4 bytes per uint32 index
  delaunayFree dh
  -- Decode doubles from raw bytes (little-endian IEEE 754)
  let decodeDbl (ba : ByteArray) (i : Nat) : Float :=
    let b := i * 8
    let bits : UInt64 :=
      (ba.get! b).toUInt64 ||| ((ba.get! (b+1)).toUInt64 <<< 8) |||
      ((ba.get! (b+2)).toUInt64 <<< 16) ||| ((ba.get! (b+3)).toUInt64 <<< 24) |||
      ((ba.get! (b+4)).toUInt64 <<< 32) ||| ((ba.get! (b+5)).toUInt64 <<< 40) |||
      ((ba.get! (b+6)).toUInt64 <<< 48) ||| ((ba.get! (b+7)).toUInt64 <<< 56)
    Float.ofBits bits
  let mut verts : Array Float := #[]
  for i in [:nv.toNat * 3] do verts := verts.push (decodeDbl vbuf i)
  -- Decode little-endian uint32 triangle indices
  let mut tris : Array Nat := #[]
  for i in [:nt.toNat * 3] do
    let b := i * 4
    tris := tris.push ((tbuf.get! b).toNat ||| ((tbuf.get! (b+1)).toNat <<< 8) |||
      ((tbuf.get! (b+2)).toNat <<< 16) ||| ((tbuf.get! (b+3)).toNat <<< 24))
  return (verts, tris)

/-- Build a JSON number from a Float (finite values only). -/
def jf (x : Float) : Json :=
  let scaled := x * 1000000.0
  let m : Int :=
    if scaled >= 0.0 then Int.ofNat scaled.toUInt64.toNat
    else -Int.ofNat (-scaled).toUInt64.toNat
  Json.num { mantissa := m, exponent := 6 }

end CassieTriangulate

def main : IO Unit := do
  let (_, boundary, inc, polys, xnodes) ← CassieTimeline.loadSession
  let mut patchJsons : Array Json := #[]
  let mut nTriangulated := 0
  for pid in [:boundary.size] do
    let B := boundary[pid]!
    if B.size == 0 then continue
    let (verts, tris) ← CassieTriangulate.triangulatePatch B inc polys xnodes
    if verts.size == 0 then do
      let bd := CassieTriangulate.walkBoundary B inc polys xnodes
      IO.eprintln s!"FAIL patch {pid} k={B.size} bdPts={bd.size / 3}"
      continue
    nTriangulated := nTriangulated + 1
    let nv := verts.size / 3
    let nt := tris.size / 3
    let mut vertsArr : Array Json := #[]
    for i in [:nv] do
      vertsArr := vertsArr.push (Json.arr #[CassieTriangulate.jf (verts[3*i]!),
        CassieTriangulate.jf (verts[3*i+1]!), CassieTriangulate.jf (verts[3*i+2]!)])
    let mut trisArr : Array Json := #[]
    for i in [:nt] do
      trisArr := trisArr.push (Json.arr #[Json.num ⟨tris[3*i]!, 0⟩,
        Json.num ⟨tris[3*i+1]!, 0⟩, Json.num ⟨tris[3*i+2]!, 0⟩])
    patchJsons := patchJsons.push (Json.mkObj [("id", Json.num ⟨pid, 0⟩),
      ("verts", Json.arr vertsArr), ("tris", Json.arr trisArr)])
  IO.FS.writeFile "data/patches_mesh.json" (toString (Json.mkObj [("patches", Json.arr patchJsons)]))
  IO.println s!"triangulated {nTriangulated}/{boundary.size} patches → data/patches_mesh.json"
