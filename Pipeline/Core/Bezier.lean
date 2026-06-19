import Pipeline.Core.Vec3
/-! # Poly-Bézier evaluation and tangents (dependency-free core)

A poly-Bézier is stored as a flat `Array Vec3` of control points:
  1 segment  → 4 pts  [P0 P1 P2 P3]
  2 segments → 7 pts  [P0 P1 P2 P3 P4 P5 P6]
  k segments → 3k+1 pts
-/
namespace Pipeline.Core
open Vec3

/-- Evaluate one cubic Bézier segment at parameter `t ∈ [0,1]`. -/
def cubicAt (p0 p1 p2 p3 : Vec3) (t : Float) : Vec3 :=
  let mt := 1.0 - t
  let a := mt*mt*mt; let b := 3.0*mt*mt*t
  let c := 3.0*mt*t*t; let d := t*t*t
  add (add (scale a p0) (scale b p1)) (add (scale c p2) (scale d p3))

/-- Tangent of one cubic Bézier at `t` (un-normalised). -/
def cubicTangent (p0 p1 p2 p3 : Vec3) (t : Float) : Vec3 :=
  let mt := 1.0 - t
  let a := 3.0*mt*mt; let b := 6.0*mt*t; let c := 3.0*t*t
  add (add (scale a (sub p1 p0)) (scale b (sub p2 p1))) (scale c (sub p3 p2))

namespace PolyBezier

/-- Number of cubic segments in a control-point array. -/
def nSegs (ctrl : Array Vec3) : Nat := (ctrl.size - 1) / 3

/-- Evaluate poly-Bézier at global parameter `u ∈ [0,1]`. -/
def eval (ctrl : Array Vec3) (u : Float) : Vec3 :=
  if ctrl.size < 4 then ctrl.getD 0 Vec3.zero
  else
    let n := nSegs ctrl
    let su := u * Float.ofNat n
    let si := Nat.min (n - 1) (Float.toUInt64 su |>.toNat)
    let t  := su - Float.ofNat si
    let i  := 3 * si
    cubicAt ctrl[i]! ctrl[i+1]! ctrl[i+2]! ctrl[i+3]! t

/-- Tangent of poly-Bézier at `u` (normalised). -/
def tangent (ctrl : Array Vec3) (u : Float) : Vec3 :=
  if ctrl.size < 4 then Vec3.zero
  else
    let n := nSegs ctrl
    let su := u * Float.ofNat n
    let si := Nat.min (n - 1) (Float.toUInt64 su |>.toNat)
    let t  := su - Float.ofNat si
    let i  := 3 * si
    normalize (cubicTangent ctrl[i]! ctrl[i+1]! ctrl[i+2]! ctrl[i+3]! t)

/-- Dense polyline samples from a poly-Bézier (for proximity queries). -/
def densify (ctrl : Array Vec3) (perSeg : Nat := 16) : Array Vec3 := Id.run do
  if ctrl.size < 4 then return ctrl
  let n := nSegs ctrl
  let mut out : Array Vec3 := #[]
  for s in [:n] do
    let i := 3 * s
    let lo := if s == 0 then 0 else 1
    for k in [lo : perSeg + 1] do
      let t := Float.ofNat k / Float.ofNat perSeg
      out := out.push (cubicAt ctrl[i]! ctrl[i+1]! ctrl[i+2]! ctrl[i+3]! t)
  return out

/-- Parallel-transport `v` along the poly-Bézier from param `u0` to `u1`.
    Uses 20 steps per segment (matches Unity implementation). -/
def parallelTransport (ctrl : Array Vec3) (v : Vec3) (u0 u1 : Float) : Vec3 := Id.run do
  let n := 20 * Nat.max 1 (nSegs ctrl)
  let dt := (u1 - u0) / Float.ofNat n
  let mut vt := v
  let mut prevT := normalize (tangent ctrl u0)
  for i in [1 : n + 1] do
    let u := u0 + Float.ofNat i * dt
    let t := normalize (tangent ctrl u)
    vt := transport vt prevT t
    prevT := t
  return vt

end PolyBezier
end Pipeline.Core
