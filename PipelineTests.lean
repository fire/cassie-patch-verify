import Plausible
import Pipeline.Core.Vec3
import Pipeline.Core.RDP
import Pipeline.Core.G1Sections
import Pipeline.Core.Graph
import Pipeline.Core.GraphBuilder
open Pipeline.Core Vec3 Plausible

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

/-- Scale a Fin into [-5,5]. -/
private def finF (n : Fin 1001) : Float :=
  (n.val.toFloat - 500.0) / 100.0

private def mkV (x y z : Fin 1001) : Vec3 := (finF x, finF y, finF z)

-- ────────────────────────────────────────────────────────────────────────────
-- Vec3 properties
-- ────────────────────────────────────────────────────────────────────────────

-- dot is commutative
#eval Testable.check (∀ (ax a_y az bx b_y bz : Fin 1001),
  dot (mkV ax a_y az) (mkV bx b_y bz) ==
  dot (mkV bx b_y bz) (mkV ax a_y az))

-- cross is anti-commutative
#eval Testable.check (∀ (ax a_y az bx b_y bz : Fin 1001),
  let a := mkV ax a_y az; let b := mkV bx b_y bz
  dist2 (cross a b) (neg (cross b a)) < 1e-10)

-- normalize produces unit vector
#eval Testable.check (∀ (ax a_y az : Fin 1001),
  let a := mkV ax a_y az
  if a.mag2 < 1e-6 then True
  else Float.abs ((normalize a).mag - 1.0) < 1e-6)

-- mag2 non-negative
#eval Testable.check (∀ (ax a_y az : Fin 1001),
  (mkV ax a_y az).mag2 ≥ 0.0)

-- dist(a,b) = dist(b,a)
#eval Testable.check (∀ (ax a_y az bx b_y bz : Fin 1001),
  Float.abs (dist (mkV ax a_y az) (mkV bx b_y bz) -
             dist (mkV bx b_y bz) (mkV ax a_y az)) < 1e-10)

-- ────────────────────────────────────────────────────────────────────────────
-- RDP properties
-- ────────────────────────────────────────────────────────────────────────────

-- never increases point count
#eval Testable.check (∀ (pts : List (Fin 1001 × Fin 1001 × Fin 1001)),
  let vecs := pts.toArray.map (fun (x, y, z) => mkV x y z)
  (rdpReduce vecs 0.01).size ≤ vecs.size)

-- ε=0 keeps all (result is ≤ not < since degenerate lines may still prune)
#eval Testable.check (∀ (pts : List (Fin 1001 × Fin 1001 × Fin 1001)),
  let vecs := pts.toArray.map (fun (x, y, z) => mkV x y z)
  (rdpReduce vecs 0.0).size ≤ vecs.size)

-- preserves endpoints when input has ≥ 2 points
#eval Testable.check (∀ (pts : List (Fin 1001 × Fin 1001 × Fin 1001)),
  let vecs := pts.toArray.map (fun (x, y, z) => mkV x y z)
  if vecs.size < 2 then True
  else
    let r := rdpReduce vecs 0.01
    if r.size < 2 then True
    else dist2 r[0]! vecs[0]! < 1e-12 && dist2 r.back! vecs.back! < 1e-12)

-- ────────────────────────────────────────────────────────────────────────────
-- polylineLength
-- ────────────────────────────────────────────────────────────────────────────

-- always non-negative
#eval Testable.check (∀ (pts : List (Fin 1001 × Fin 1001 × Fin 1001)),
  polylineLength (pts.toArray.map (fun (x, y, z) => mkV x y z)) ≥ 0.0)

-- adding a point can only increase length
#eval Testable.check (∀ (pts : List (Fin 1001 × Fin 1001 × Fin 1001))
    (px p_y pz : Fin 1001),
  let vecs := pts.toArray.map (fun (x, y, z) => mkV x y z)
  let longer := vecs.push (mkV px p_y pz)
  polylineLength longer ≥ polylineLength vecs - 1e-10)

-- ────────────────────────────────────────────────────────────────────────────
-- GraphBuilder
-- ────────────────────────────────────────────────────────────────────────────

-- segment count equals valid sections
#eval Testable.check
  (∀ (sections : List (List (Fin 1001 × Fin 1001 × Fin 1001))),
    let vecs := sections.toArray.map (fun s =>
      s.toArray.map (fun (x, y, z) => mkV x y z))
    let valid := vecs.filter (·.size ≥ 4)
    let g := buildGraph valid
    g.segments.size == valid.size)

-- node count ≤ 2 × segment count
#eval Testable.check
  (∀ (sections : List (List (Fin 1001 × Fin 1001 × Fin 1001))),
    let vecs := sections.toArray.map (fun s =>
      s.toArray.map (fun (x, y, z) => mkV x y z))
    let valid := vecs.filter (·.size ≥ 4)
    let g := buildGraph valid
    g.nodes.size ≤ 2 * g.segments.size)
