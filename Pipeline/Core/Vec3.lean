namespace Pipeline.Core
/-! # 3D vector primitives (dependency-free core) -/

abbrev Vec3 := Float × Float × Float

namespace Vec3

@[inline] def mk (x y z : Float) : Vec3 := (x, y, z)
@[inline] def x (v : Vec3) : Float := v.1
@[inline] def y (v : Vec3) : Float := v.2.1
@[inline] def z (v : Vec3) : Float := v.2.2

@[inline] def add (a b : Vec3) : Vec3 := (a.x + b.x, a.y + b.y, a.z + b.z)
@[inline] def sub (a b : Vec3) : Vec3 := (a.x - b.x, a.y - b.y, a.z - b.z)
@[inline] def scale (s : Float) (v : Vec3) : Vec3 := (s * v.x, s * v.y, s * v.z)
@[inline] def neg (v : Vec3) : Vec3 := (-v.x, -v.y, -v.z)

@[inline] def dot (a b : Vec3) : Float := a.x*b.x + a.y*b.y + a.z*b.z

@[inline] def cross (a b : Vec3) : Vec3 :=
  (a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)

@[inline] def mag2 (v : Vec3) : Float := dot v v
@[inline] def mag  (v : Vec3) : Float := Float.sqrt (mag2 v)
@[inline] def dist2 (a b : Vec3) : Float := mag2 (sub a b)
@[inline] def dist  (a b : Vec3) : Float := Float.sqrt (dist2 a b)

def normalize (v : Vec3) : Vec3 :=
  let m := mag v
  if m > 1e-12 then scale (1.0 / m) v else v

/-- Rodrigues rotation of `v` around unit `axis` by `theta` radians. -/
def rotate (v axis : Vec3) (theta : Float) : Vec3 :=
  let c := Float.cos theta; let s := Float.sin theta
  let d := dot axis v
  add (add (scale c v) (scale s (cross axis v))) (scale (d * (1.0 - c)) axis)

/-- Parallel-transport `v` from tangent `t0` to tangent `t1` (unit vectors). -/
def transport (v t0 t1 : Vec3) : Vec3 :=
  let ax := cross t0 t1
  let m  := mag ax
  if m < 1e-12 then v
  else
    let axis := scale (1.0/m) ax
    let theta := Float.acos (max (-1.0) (min 1.0 (dot t0 t1)))
    rotate v axis theta

/-- Project `v` onto the plane with unit normal `n`. -/
def projectOnPlane (v n : Vec3) : Vec3 :=
  sub v (scale (dot v n) n)

/-- Point-to-segment squared distance. `a` and `b` are segment endpoints. -/
def ptSegDist2 (p a b : Vec3) : Float :=
  let ab := sub b a; let ap := sub p a
  let d := mag2 ab
  let t := if d > 1e-12 then max 0.0 (min 1.0 (dot ap ab / d)) else 0.0
  dist2 p (add a (scale t ab))

def zero : Vec3 := (0.0, 0.0, 0.0)

end Vec3
end Pipeline.Core
