import Pipeline.Core.Vec3
/-! # Ramer-Douglas-Peucker polyline simplification (dependency-free core)

Pure Lean port of `RamerDouglasPeucker.cs` from the Unity CASSIE codebase.
Returns a bitmask array: `keep[i] = true` iff point i survives.
-/
namespace Pipeline.Core
open Vec3

private partial def rdpRecurse (pts : Array Vec3) (start stop : Nat)
    (eps2 : Float) (keep : Array Bool) : Array Bool :=
  if stop <= start + 1 then
    (keep.set! start true).set! stop true
  else
    let a := pts[start]!; let b := pts[stop]!
    let (maxD2, split) := Id.run do
      let mut maxD2 : Float := 0.0
      let mut split := start
      for i in [start + 1 : stop] do
        let d2 := ptSegDist2 pts[i]! a b
        if d2 > maxD2 then maxD2 := d2; split := i
      return (maxD2, split)
    if maxD2 > eps2 then
      let keep' := rdpRecurse pts start split eps2 keep
      rdpRecurse pts split stop eps2 keep'
    else
      (keep.set! start true).set! stop true

/-- Simplify `pts` keeping points whose removal would introduce > `epsilon`
    deviation.  Returns a bool array of the same length as `pts`. -/
def rdpKeep (pts : Array Vec3) (epsilon : Float) : Array Bool :=
  if pts.size <= 2 then Array.replicate pts.size true
  else
    let keep := Array.replicate pts.size false
    rdpRecurse pts 0 (pts.size - 1) (epsilon * epsilon) keep

/-- Apply `rdpKeep` and collect the surviving points. -/
def rdpReduce (pts : Array Vec3) (epsilon : Float) : Array Vec3 :=
  let mask := rdpKeep pts epsilon
  (Array.range pts.size).filterMap (fun i =>
    if mask.getD i false then some pts[i]! else none)

end Pipeline.Core
