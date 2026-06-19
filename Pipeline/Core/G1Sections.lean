import Pipeline.Core.Vec3
/-! # G1 section detection (dependency-free core)

Port of `InputStroke.GetG1sections()` from the Unity CASSIE codebase.
Splits a raw sample polyline into G1-continuous sections by detecting
sharp corners and removing hooks at start/end.

Parameters match `CassieBeautifierParams` defaults:
  discontinuityAngularThreshold = 0.7 rad
  hookDiscontinuityAngularThreshold = 0.5 rad
  minSectionLength = 0.05 / maxHookLength = 0.06 / maxHookStrokeRatio = 0.15
-/
namespace Pipeline.Core
open Vec3

structure G1Params where
  discontinuityAngThr     : Float := 0.7
  hookDiscontinuityAngThr : Float := 0.5
  minSectionLength        : Float := 0.05
  maxHookLength           : Float := 0.06
  maxHookStrokeRatio      : Float := 0.15

/-- Total chord length of a polyline. -/
def polylineLength (pts : Array Vec3) : Float := Id.run do
  let mut len : Float := 0.0
  for i in [1 : pts.size] do
    len := len + dist pts[i-1]! pts[i]!
  return len

/-- Detect hook clip index from the start (returns # of points to skip at start). -/
private def detectHookStart (pts : Array Vec3) (totalLen : Float) (p : G1Params) : Nat := Id.run do
  if pts.size < 5 then return 0
  let cosHook := Float.cos p.hookDiscontinuityAngThr
  let mut curLen : Float := dist pts[0]! pts[1]!
  let mut result := 0
  let mut i := 2
  while i + 2 < pts.size &&
        curLen < p.maxHookLength &&
        curLen < totalLen * p.maxHookStrokeRatio do
    let u := normalize (sub pts[i]! pts[i-1]!)
    let v := normalize (sub pts[i+1]! pts[i]!)
    if u.mag2 > 0.01 && v.mag2 > 0.01 && dot u v < cosHook then
      result := i
    curLen := curLen + dist pts[i]! pts[i-1]!
    i := i + 1
  return result

/-- Detect hook clip index from the end (returns first index to keep at end). -/
private def detectHookEnd (pts : Array Vec3) (totalLen : Float) (p : G1Params) : Nat := Id.run do
  if pts.size < 5 then return (pts.size - 1)
  let cosHook := Float.cos p.hookDiscontinuityAngThr
  let n := pts.size
  let mut curLen : Float := dist pts[n-1]! pts[n-2]!
  let mut result := n - 1
  let mut i := n - 3
  while i > 1 &&
        curLen < p.maxHookLength &&
        curLen < totalLen * p.maxHookStrokeRatio do
    let u := normalize (sub pts[i]! pts[i+1]!)
    let v := normalize (sub pts[i-1]! pts[i]!)
    if u.mag2 > 0.01 && v.mag2 > 0.01 && dot u v < cosHook then
      result := i
    curLen := curLen + dist pts[i]! pts[i+1]!
    i := i - 1
  return result

/-- Split `pts` into G1-continuous sections.
    Returns at least one section (the full polyline if no corners found). -/
def g1Sections (pts : Array Vec3) (p : G1Params := {}) : Array (Array Vec3) := Id.run do
  if pts.size <= 4 then return #[pts]
  let totalLen := polylineLength pts
  let cosAngThr := Float.cos p.discontinuityAngThr
  -- clip hooks
  let hookS := detectHookStart pts totalLen p
  let hookE := detectHookEnd   pts totalLen p
  let safe :=
    if hookE > hookS + 4 then pts.extract hookS (hookE + 1)
    else pts
  if safe.size <= 4 then return #[safe]
  -- walk and split at corners
  let mut sections : Array (Array Vec3) := #[]
  let mut cur : Array Vec3 := #[safe[0]!, safe[1]!]
  let mut curLen : Float := dist safe[0]! safe[1]!
  for i in [2 : safe.size - 2] do
    cur := cur.push safe[i]!
    curLen := curLen + dist safe[i]! safe[i-1]!
    if i >= 2 && i + 1 < safe.size then
      let u := normalize (sub safe[i]!   safe[i-1]!)
      let v := normalize (sub safe[i+1]! safe[i]!)
      if u.mag2 > 0.01 && v.mag2 > 0.01 &&
         dot u v < cosAngThr && cur.size >= 4 && curLen > p.minSectionLength then
        sections := sections.push cur
        cur := #[safe[i]!]
        curLen := 0.0
  cur := cur.push safe[safe.size - 2]!
  cur := cur.push safe[safe.size - 1]!
  if sections.isEmpty || (cur.size >= 4 &&
      curLen + dist safe[safe.size-2]! safe[safe.size-1]! > p.minSectionLength) then
    sections := sections.push cur
  return if sections.isEmpty then #[safe] else sections

end Pipeline.Core
