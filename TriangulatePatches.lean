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

/-- Walk the ordered boundary strokes into a flat xyz FloatArray for CDT2d.
    Uses the same `allNodes`/shared-node logic as `formsCycle`.
    Direction: the exit end of stroke A is the end that shares a node with the
    next stroke B; the entry end of B is that same shared node. -/
def walkBoundary (B : Array Nat) (inc : Array StrokeIncidence)
    (polys : Array (Array Vec3)) : Array Float := Id.run do
  let k := B.size
  if k == 0 then return #[]

  -- CASSIE records strokesID in cycle order — walk B as given.
  -- Direction: chain from previous stroke's exit so the boundary is non-self-intersecting.

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

  -- Bootstrap direction for stroke 0: which end exits toward stroke 1?
  let s0 := B.getD 0 0; let s1 := B.getD 1 0
  let p00 := (polys.getD s0 #[]).getD 0 (0.0, 0.0, 0.0)
  let p0L := let p := polys.getD s0 #[]; p.getD (p.size - 1) (0.0, 0.0, 0.0)
  let q10 := (polys.getD s1 #[]).getD 0 (0.0, 0.0, 0.0)
  let q1L := let p := polys.getD s1 #[]; p.getD (p.size - 1) (0.0, 0.0, 0.0)
  -- Stroke 0 is forward if its LAST point is close to an endpoint of stroke 1.
  let d0near := min (vd2 p00 q10) (vd2 p00 q1L)
  let dLnear := min (vd2 p0L q10) (vd2 p0L q1L)
  let fwd0 := dLnear ≤ d0near
  -- exitPt0 = the actual end of stroke 0 (not the last point, but the junction toward s1)
  let exitPt0 : Vec3 := if fwd0 then p0L else p00

  let mut exitPt := exitPt0
  let mut out : Array Float := #[]

  for oi in [:k] do
    let si   := B.getD oi 0
    let poly := polys.getD si #[]
    let p0 := poly.getD 0 (0.0, 0.0, 0.0)
    let pL := poly.getD (poly.size - 1) (0.0, 0.0, 0.0)

    -- For stroke 0: use bootstrap direction.
    -- For subsequent strokes: entry is whichever end is closer to the previous exitPt.
    let fwd : Bool :=
      if oi == 0 then fwd0
      else vd2 p0 exitPt ≤ vd2 pL exitPt

    -- Update exitPt: the opposite end from entry (= junction with next stroke)
    exitPt := if fwd then pL else p0

    -- Emit all points except the last (= junction with next stroke)
    let pts := if fwd then poly else poly.reverse
    let nEmit := if pts.size > 0 then pts.size - 1 else 0
    for pi in [:nEmit] do
      let p := pts.getD pi (0.0, 0.0, 0.0)
      out := out.push p.1; out := out.push p.2.1; out := out.push p.2.2

  return out

/-- Triangulate one patch boundary via geogram CDT2d.
    Returns `(verts_flat_xyz, tris_flat_abc)` or empty arrays on failure. -/
def triangulatePatch (B : Array Nat) (inc : Array StrokeIncidence)
    (polys : Array (Array Vec3)) : IO (Array Float × Array Nat) := do
  let bd := walkBoundary B inc polys
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
  let (_, boundary, inc, polys) ← CassieTimeline.loadSession
  let mut patchJsons : Array Json := #[]
  let mut nTriangulated := 0
  for pid in [:boundary.size] do
    let B := boundary[pid]!
    if B.size == 0 then continue
    let (verts, tris) ← CassieTriangulate.triangulatePatch B inc polys
    if verts.size == 0 then do
      let bd := CassieTriangulate.walkBoundary B inc polys
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
