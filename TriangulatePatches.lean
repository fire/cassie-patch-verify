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

  let ns := allNodes inc
  let sharedN (a b : Nat) : Array Nat :=
    let na := ns a; let nb := ns b
    na.foldl (fun acc nid =>
      if nb.contains nid && ¬ acc.contains nid then acc.push nid else acc) #[]

  -- k=1: single closed-loop stroke — emit all points
  if k == 1 then
    let poly := polys.getD B[0]! #[]
    let mut out : Array Float := #[]
    for p in poly do
      out := out.push p.1; out := out.push p.2.1; out := out.push p.2.2
    return out

  -- Build stroke-level adjacency
  let mut adj : Array (Array Nat) := Array.replicate k #[]
  for a in [:k] do
    for b in [a+1:k] do
      if ¬ (sharedN B[a]! B[b]!).isEmpty then
        adj := adj.modify a (·.push b)
        adj := adj.modify b (·.push a)

  -- Greedy Hamiltonian trace (valid because formsCycle already verified the cycle)
  let mut order : Array Nat := #[0]
  let mut visited := (Array.replicate k false).set! 0 true
  let mut cur := 0
  for _ in [1:k] do
    let next := (adj.getD cur #[]).foldl
      (fun acc nb => if acc.isNone && nb < k && !visited.getD nb false then some nb else acc)
      none
    match next with
    | some nb =>
      order := order.push nb; visited := visited.set! nb true; cur := nb
    | none => ()

  -- Determine direction of first stroke: exit toward order[1]
  let s0 := B[order[0]!]!
  let s1 := B[order[1]!]!
  let sh01 := sharedN s0 s1
  let exitNode0 := sh01.getD 0 0
  let inc0 := inc.getD s0 { hosted := #[], endpts := #[] }
  -- forward if the last endpoint is the exit; backward otherwise
  let fwd0 := inc0.endpts.size > 0 && inc0.endpts[inc0.endpts.size - 1]! == exitNode0

  let mut prevExitNode := exitNode0
  let mut out : Array Float := #[]

  for oi in [:k] do
    let si := B[order[oi]!]!
    let poly := polys.getD si #[]
    let sni := inc.getD si { hosted := #[], endpts := #[] }

    let fwd : Bool :=
      if oi == 0 then fwd0
      else sni.endpts.size > 0 && sni.endpts[0]! == prevExitNode

    -- Update exit node for next stroke
    prevExitNode :=
      if fwd then sni.endpts.getD (sni.endpts.size - 1) 0
      else sni.endpts.getD 0 0

    -- Emit all points except the last (it equals the first point of the next stroke)
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
    if verts.size == 0 then continue
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
