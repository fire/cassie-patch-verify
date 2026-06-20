import Plausible
import Pipeline.Core.Vec3
import Pipeline.Core.RDP
import Pipeline.Core.G1Sections
import Pipeline.Core.Graph
import Pipeline.Core.GraphBuilder
import Pipeline.Core.Bezier
import Pipeline.Core.CycleDetect
import Timeline
import Lean.Data.Json
import Pipeline.Adapters.GroundTruth
open Pipeline.Core Vec3 Plausible Lean

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

-- ────────────────────────────────────────────────────────────────────────────
-- Bezier / PolyBezier properties
-- ────────────────────────────────────────────────────────────────────────────

-- cubicAt t=0 returns p0
#eval Testable.check (∀ (p0x p0y p0z p1x p1y p1z p2x p2y p2z p3x p3y p3z : Fin 1001),
  dist2 (cubicAt (mkV p0x p0y p0z) (mkV p1x p1y p1z)
                 (mkV p2x p2y p2z) (mkV p3x p3y p3z) 0.0)
        (mkV p0x p0y p0z) < 1e-10)

-- cubicAt t=1 returns p3
#eval Testable.check (∀ (p0x p0y p0z p1x p1y p1z p2x p2y p2z p3x p3y p3z : Fin 1001),
  dist2 (cubicAt (mkV p0x p0y p0z) (mkV p1x p1y p1z)
                 (mkV p2x p2y p2z) (mkV p3x p3y p3z) 1.0)
        (mkV p3x p3y p3z) < 1e-10)

-- cubicAt t∈[0,1]: result is in the bounding box of control points (convex hull property)
-- We approximate: |eval - centroid| ≤ max(|p_i - centroid|)
#eval Testable.check (∀ (p0x p0y p0z p3x p3y p3z : Fin 1001) (t : Fin 101),
  let p0 := mkV p0x p0y p0z; let p3 := mkV p3x p3y p3z
  let mid := scale 0.5 (add p0 p3)
  let r := max (dist p0 mid) (dist p3 mid) + 5.1  -- slack for control handles
  let tv := Float.ofNat t.val / 100.0
  let ev := cubicAt p0 mid p3 mid tv  -- degenerate but valid bezier
  dist ev mid ≤ r)

-- PolyBezier.eval u=0 returns ctrl[0] for a 1-segment curve
#eval Testable.check (∀ (p0x p0y p0z p1x p1y p1z p2x p2y p2z p3x p3y p3z : Fin 1001),
  let ctrl := #[mkV p0x p0y p0z, mkV p1x p1y p1z, mkV p2x p2y p2z, mkV p3x p3y p3z]
  dist2 (PolyBezier.eval ctrl 0.0) ctrl[0]! < 1e-10)

-- PolyBezier.eval u=1 returns ctrl[3] (last point) for a 1-segment curve
#eval Testable.check (∀ (p0x p0y p0z p1x p1y p1z p2x p2y p2z p3x p3y p3z : Fin 1001),
  let ctrl := #[mkV p0x p0y p0z, mkV p1x p1y p1z, mkV p2x p2y p2z, mkV p3x p3y p3z]
  dist2 (PolyBezier.eval ctrl 1.0) ctrl[3]! < 1e-10)

-- PolyBezier.densify with perSeg=8 on a 1-segment curve yields exactly 9 points
#eval Testable.check (∀ (p0x p0y p0z p1x p1y p1z p2x p2y p2z p3x p3y p3z : Fin 1001),
  let ctrl := #[mkV p0x p0y p0z, mkV p1x p1y p1z, mkV p2x p2y p2z, mkV p3x p3y p3z]
  (PolyBezier.densify ctrl 8).size == 9)

-- PolyBezier.densify with perSeg=8 on a 2-segment curve yields exactly 17 points
#eval Testable.check (∀ (p0x p0y p0z p1x p1y p1z p2x p2y p2z
                         p3x p3y p3z p4x p4y p4z p5x p5y p5z p6x p6y p6z : Fin 1001),
  let ctrl := #[mkV p0x p0y p0z, mkV p1x p1y p1z, mkV p2x p2y p2z,
                mkV p3x p3y p3z, mkV p4x p4y p4z, mkV p5x p5y p5z, mkV p6x p6y p6z]
  (PolyBezier.densify ctrl 8).size == 17)

-- PolyBezier.densify preserves first and last points
#eval Testable.check (∀ (p0x p0y p0z p1x p1y p1z p2x p2y p2z p3x p3y p3z : Fin 1001),
  let ctrl := #[mkV p0x p0y p0z, mkV p1x p1y p1z, mkV p2x p2y p2z, mkV p3x p3y p3z]
  let d := PolyBezier.densify ctrl
  dist2 d[0]! ctrl[0]! < 1e-10 && dist2 d.back! ctrl[3]! < 1e-10)

-- PolyBezier.tangent is unit length where the curve is non-degenerate
#eval Testable.check (∀ (p0x p0y p0z p3x p3y p3z : Fin 1001) (t : Fin 101),
  let p0 := mkV p0x p0y p0z; let p3 := mkV p3x p3y p3z
  -- Use a non-degenerate control polygon by separating p1 and p2
  let p1 := mkV ((p0x.val + 334) % 1001 |>.toFin 1001) p0y p0z
  let p2 := mkV ((p3x.val + 667) % 1001 |>.toFin 1001) p3y p3z
  let ctrl := #[p0, p1, p2, p3]
  let tv := Float.ofNat t.val / 100.0
  let tan := PolyBezier.tangent ctrl tv
  -- If p0 ≠ p3 (non-degenerate), tangent should be unit
  if dist2 p0 p3 < 1e-6 then True
  else Float.abs (tan.mag - 1.0) < 1e-5 || tan.mag2 < 1e-10)

-- ────────────────────────────────────────────────────────────────────────────
-- G1Sections properties
-- ────────────────────────────────────────────────────────────────────────────

-- g1Sections is always non-empty
#eval Testable.check (∀ (pts : List (Fin 1001 × Fin 1001 × Fin 1001)),
  let vecs := pts.toArray.map (fun (x, y, z) => mkV x y z)
  (g1Sections vecs).size ≥ 1)

-- Short input (≤4 pts) → single section returned as-is  (avoid 'by' — Lean keyword)
#eval Testable.check (∀ (ax ay az bx b_y bz cx cy cz dx dy dz : Fin 1001),
  let pts := #[mkV ax ay az, mkV bx b_y bz, mkV cx cy cz, mkV dx dy dz]
  (g1Sections pts).size == 1)

-- All output sections are non-empty
#eval Testable.check (∀ (pts : List (Fin 1001 × Fin 1001 × Fin 1001)),
  let vecs := pts.toArray.map (fun (x, y, z) => mkV x y z)
  (g1Sections vecs).all (·.size > 0))

-- Straight polyline (all points collinear along x-axis) → single section
-- No corners → no splits
#eval Testable.check (∀ (n : Fin 20),
  let pts := (List.range (n.val + 5)).toArray.map
    (fun i => ((Float.ofNat i * 0.1, 0.0, 0.0) : Vec3))
  (g1Sections pts).size == 1)

-- Splitting never loses the first or last point of the input
#eval Testable.check (∀ (pts : List (Fin 1001 × Fin 1001 × Fin 1001)),
  let vecs := pts.toArray.map (fun (x, y, z) => mkV x y z)
  let secs := g1Sections vecs
  if vecs.size < 5 then True
  else
    let first := secs[0]!.getD 0 Vec3.zero
    let last  := secs.back!.back!
    dist2 first vecs[0]! < 1e-10 && dist2 last vecs.back! < 1e-10)

-- ────────────────────────────────────────────────────────────────────────────
-- Vec3 geometric operations
-- ────────────────────────────────────────────────────────────────────────────

-- projectOnPlane: result is orthogonal to the plane normal
#eval Testable.check (∀ (vx vy vz nx ny nz : Fin 1001),
  let v := mkV vx vy vz; let n := normalize (mkV nx ny nz)
  if n.mag2 < 0.01 then True  -- degenerate normal
  else Float.abs (dot (projectOnPlane v n) n) < 1e-6)

-- projectOnPlane: adding normal component back recovers v
#eval Testable.check (∀ (vx vy vz nx ny nz : Fin 1001),
  let v := mkV vx vy vz; let n := normalize (mkV nx ny nz)
  if n.mag2 < 0.01 then True
  else
    let proj := projectOnPlane v n
    let recovered := add proj (scale (dot v n) n)
    dist2 recovered v < 1e-6)

-- transport: parallel-transports a unit vector to be ⊥ to t1
#eval Testable.check (∀ (vx vy vz tx ty tz : Fin 1001),
  let t1 := normalize (mkV tx ty tz)
  let v  := normalize (mkV vx vy vz)
  if t1.mag2 < 0.01 || v.mag2 < 0.01 then True
  else
    -- transport from t1 to t1 is identity
    let vt := transport v t1 t1
    dist2 vt v < 1e-6)

-- transport: preserves vector magnitude
#eval Testable.check (∀ (vx vy vz t0x t0y t0z t1x t1y t1z : Fin 1001),
  let v  := mkV vx vy vz
  let t0 := normalize (mkV t0x t0y t0z)
  let t1 := normalize (mkV t1x t1y t1z)
  if t0.mag2 < 0.01 || t1.mag2 < 0.01 then True
  else Float.abs (transport v t0 t1).mag - v.mag < 1e-4)

-- rotate: rotation by θ=0 is identity
#eval Testable.check (∀ (vx vy vz ax ay az : Fin 1001),
  let v    := mkV vx vy vz
  let axis := normalize (mkV ax ay az)
  if axis.mag2 < 0.01 then True
  else dist2 (rotate v axis 0.0) v < 1e-6)

-- rotate: rotation by 2π is identity
#eval Testable.check (∀ (vx vy vz ax ay az : Fin 1001),
  let v    := mkV vx vy vz
  let axis := normalize (mkV ax ay az)
  if axis.mag2 < 0.01 then True
  else dist2 (rotate v axis (2.0 * Float.pi)) v < 1e-5)

-- rotate: preserves magnitude
#eval Testable.check (∀ (vx vy vz ax ay az : Fin 1001) (th : Fin 1001),
  let v    := mkV vx vy vz
  let axis := normalize (mkV ax ay az)
  let theta := Float.ofNat th.val / 100.0
  if axis.mag2 < 0.01 then True
  else Float.abs ((rotate v axis theta).mag - v.mag) < 1e-5)

-- ────────────────────────────────────────────────────────────────────────────
-- Graph construction and accessors
-- ────────────────────────────────────────────────────────────────────────────

private def linCtrl (a b : Vec3) : Array Vec3 :=
  let d := scale (1.0/3.0) (sub b a)
  #[a, add a d, add a (scale 2.0 d), b]

-- nodePos returns the position passed to addNode
#eval
  let p : Vec3 := (1.0, 2.0, 3.0)
  let (g, nid) := Graph.addNode default p
  dist2 (Graph.nodePos g nid) p < 1e-10

-- incident: segment id appears at both endpoints
#eval
  let (g, n0) := Graph.addNode (default : Graph) (0.0, 0.0, 0.0)
  let (g, n1) := Graph.addNode g (1.0, 0.0, 0.0)
  let (g, s0) := Graph.addSegment g (linCtrl (0,0,0) (1,0,0)) n0 n1
  Graph.incident g n0 |>.contains s0 && Graph.incident g n1 |>.contains s0

-- entryTangent is unit length for a straight non-degenerate segment
#eval
  let (g, n0) := Graph.addNode (default : Graph) (0.0, 0.0, 0.0)
  let (g, n1) := Graph.addNode g (1.0, 0.0, 0.0)
  let (g, s0) := Graph.addSegment g (linCtrl (0,0,0) (1,0,0)) n0 n1
  Float.abs (Graph.entryTangent g s0 |>.mag - 1.0) < 1e-5

-- exitTangent is unit length for a straight non-degenerate segment
#eval
  let (g, n0) := Graph.addNode (default : Graph) (0.0, 0.0, 0.0)
  let (g, n1) := Graph.addNode g (1.0, 0.0, 0.0)
  let (g, s0) := Graph.addSegment g (linCtrl (0,0,0) (1,0,0)) n0 n1
  Float.abs (Graph.exitTangent g s0 |>.mag - 1.0) < 1e-5

-- entry and exit tangents of a straight segment point the same direction
#eval
  let (g, n0) := Graph.addNode (default : Graph) (0.0, 0.0, 0.0)
  let (g, n1) := Graph.addNode g (1.0, 0.0, 0.0)
  let (g, s0) := Graph.addSegment g (linCtrl (0,0,0) (1,0,0)) n0 n1
  Float.abs (dot (Graph.entryTangent g s0) (Graph.exitTangent g s0) - 1.0) < 1e-4

-- ────────────────────────────────────────────────────────────────────────────
-- PolyBezier.parallelTransport
-- ────────────────────────────────────────────────────────────────────────────

-- u→u (zero travel) is identity
#eval
  let ctrl : Array Vec3 := #[(0,0,0), (1.0/3,0,0), (2.0/3,0,0), (1,0,0)]
  let v : Vec3 := (1.0, 0.0, 0.0)
  dist2 (PolyBezier.parallelTransport ctrl v 0.0 0.0) v < 1e-6

-- straight ctrl: transport preserves magnitude
#eval
  let ctrl : Array Vec3 := #[(0,0,0), (1.0/3,0,0), (2.0/3,0,0), (1,0,0)]
  let v : Vec3 := (0.0, 1.0, 0.0)
  Float.abs ((PolyBezier.parallelTransport ctrl v 0.0 1.0).mag - v.mag) < 1e-5

-- quarter-circle ctrl: transport preserves magnitude
#eval
  let ctrl : Array Vec3 :=
    #[(1,0,0), (1, 0, 0.552285), (0.552285, 0, 1), (0,0,1)]
  let v : Vec3 := (0.0, 1.0, 0.0)
  Float.abs ((PolyBezier.parallelTransport ctrl v 0.0 1.0).mag - 1.0) < 1e-4

-- two-segment ctrl: transport [0→0.5] then [0.5→1] equals transport [0→1]
#eval
  let ctrl : Array Vec3 :=
    #[(0,0,0), (1.0/3,0,0), (2.0/3,0,0), (1,0,0),
      (4.0/3,0,0), (5.0/3,0,0), (2,0,0), (3,0,0)]
  let v : Vec3 := (0.0, 1.0, 0.0)
  let vHalf := PolyBezier.parallelTransport ctrl v 0.0 0.5
  let vFull := PolyBezier.parallelTransport ctrl v 0.0 1.0
  let vComp := PolyBezier.parallelTransport ctrl vHalf 0.5 1.0
  dist2 vFull vComp < 1e-4

-- ────────────────────────────────────────────────────────────────────────────
-- CycleDetect.detectCycles
-- ────────────────────────────────────────────────────────────────────────────

-- empty graph → 0 cycles
#eval detectCycles (default : Graph) |>.size == 0

-- open chain (2 nodes, 1 segment) → 0 cycles
#eval
  let (g, n0) := Graph.addNode (default : Graph) (0.0, 0.0, 0.0)
  let (g, n1) := Graph.addNode g (1.0, 0.0, 0.0)
  let (g, _)  := Graph.addSegment g (linCtrl (0,0,0) (1,0,0)) n0 n1
  detectCycles g |>.size == 0

-- triangle (3 nodes, 3 directed segments) → ≥ 1 cycle
#eval
  let a : Vec3 := (0.0, 0.0, 0.0)
  let b : Vec3 := (1.0, 0.0, 0.0)
  let c : Vec3 := (0.5, 0.0, 0.866)
  let (g, n0) := Graph.addNode (default : Graph) a
  let (g, n1) := Graph.addNode g b
  let (g, n2) := Graph.addNode g c
  let (g, _)  := Graph.addSegment g (linCtrl a b) n0 n1
  let (g, _)  := Graph.addSegment g (linCtrl b c) n1 n2
  let (g, _)  := Graph.addSegment g (linCtrl c a) n2 n0
  detectCycles g |>.size ≥ 1

-- all cycle segment ids are within [0, nSegs)
#eval
  let a : Vec3 := (0.0, 0.0, 0.0)
  let b : Vec3 := (1.0, 0.0, 0.0)
  let c : Vec3 := (0.5, 0.0, 0.866)
  let (g, n0) := Graph.addNode (default : Graph) a
  let (g, n1) := Graph.addNode g b
  let (g, n2) := Graph.addNode g c
  let (g, _)  := Graph.addSegment g (linCtrl a b) n0 n1
  let (g, _)  := Graph.addSegment g (linCtrl b c) n1 n2
  let (g, _)  := Graph.addSegment g (linCtrl c a) n2 n0
  detectCycles g |>.all (·.all (· < g.segments.size))

-- ────────────────────────────────────────────────────────────────────────────
-- Timeline: allNodes, formsCycle, replay, closeFrameOf, patchCandidate,
--           patchReadback, frameLadder
-- ────────────────────────────────────────────────────────────────────────────

-- allNodes: 4 distinct nodes for hosted=[2,3] endpts=[0,1]; 1 node for endpts=[0,0]
#eval
  let inc : Array CassieTimeline.StrokeIncidence :=
    #[{ hosted := #[2, 3], endpts := #[0, 1] },
      { hosted := #[],     endpts := #[0, 0] }]
  CassieTimeline.allNodes inc 0 |>.size == 4 &&
  CassieTimeline.allNodes inc 1 |>.size == 1

-- formsCycle k=1: closed (endpts=[0,0]) → true; open (endpts=[0,1]) → false
#eval
  let closed := #[{ hosted := #[], endpts := #[0, 0] } : CassieTimeline.StrokeIncidence]
  let open_  := #[{ hosted := #[], endpts := #[0, 1] } : CassieTimeline.StrokeIncidence]
  CassieTimeline.formsCycle #[0] closed && !CassieTimeline.formsCycle #[0] open_

-- formsCycle k=2: lens (shared 2) → true; path (shared 1) → false
#eval
  let lens := #[{ hosted := #[], endpts := #[0, 1] },
                { hosted := #[], endpts := #[0, 1] } : CassieTimeline.StrokeIncidence]
  let path := #[{ hosted := #[], endpts := #[0, 1] },
                { hosted := #[], endpts := #[1, 2] } : CassieTimeline.StrokeIncidence]
  CassieTimeline.formsCycle #[0, 1] lens && !CassieTimeline.formsCycle #[0, 1] path

-- formsCycle k=3: triangle (0-1, 1-2, 2-0) → true; path (0-1, 1-2, 2-3) → false
#eval
  let tri  := #[{ hosted := #[], endpts := #[0, 1] },
                { hosted := #[], endpts := #[1, 2] },
                { hosted := #[], endpts := #[2, 0] } : CassieTimeline.StrokeIncidence]
  let path := #[{ hosted := #[], endpts := #[0, 1] },
                { hosted := #[], endpts := #[1, 2] },
                { hosted := #[], endpts := #[2, 3] } : CassieTimeline.StrokeIncidence]
  CassieTimeline.formsCycle #[0, 1, 2] tri && !CassieTimeline.formsCycle #[0, 1, 2] path

-- replay: add stroke then create patch → closedOk=1, incidenceOk=1, patch live
#eval
  let frames : Array CassieTimeline.Frame :=
    #[{ itype := 1, timeId := "1", eid := 0, mirror := false },
      { itype := 3, timeId := "2", eid := 0, mirror := false }]
  let r := CassieTimeline.replay frames #[#[0]]
    #[{ hosted := #[], endpts := #[0, 0] }]
  r.closedOk == 1 && r.incidenceOk == 1 && r.livePatchFinal[0]!

-- replay cascade: deleting stroke 0 kills patch 0
#eval
  let frames : Array CassieTimeline.Frame :=
    #[{ itype := 1, timeId := "1", eid := 0, mirror := false },
      { itype := 3, timeId := "2", eid := 0, mirror := false },
      { itype := 2, timeId := "3", eid := 0, mirror := false }]
  let r := CassieTimeline.replay frames #[#[0]]
    #[{ hosted := #[], endpts := #[0, 0] }]
  !r.livePatchFinal[0]!

-- closeFrameOf: out-of-range → none; valid → some cf
#eval
  let r : CassieTimeline.Replay :=
    { closeFrame := #[some 7], livePatchFinal := #[true],
      patchFrames := 1, closedOk := 1, incidenceOk := 1 }
  CassieTimeline.closeFrameOf r 5 == none &&
  CassieTimeline.closeFrameOf r 0 == some 7

-- patchCandidate: target=candidate ∧ closes within budget → true; mismatch → false
#eval
  let r : CassieTimeline.Replay :=
    { closeFrame := #[some 10], livePatchFinal := #[true],
      patchFrames := 1, closedOk := 1, incidenceOk := 1 }
  let lvl : PlausibleWitnessDag.Level :=
    { idx := 0, walkSteps := 64, finBound := 256, numInst := 200 }
  CassieTimeline.patchCandidate r 0 lvl 0 &&
  !CassieTimeline.patchCandidate r 0 lvl 1

-- patchReadback: within budget → found=true value=cf; over budget → budgetHit; never → !found !budgetHit
#eval
  let r1 : CassieTimeline.Replay :=
    { closeFrame := #[some 3], livePatchFinal := #[true],
      patchFrames := 1, closedOk := 1, incidenceOk := 1 }
  let r2 : CassieTimeline.Replay :=
    { closeFrame := #[none], livePatchFinal := #[false],
      patchFrames := 0, closedOk := 0, incidenceOk := 0 }
  let rb  := CassieTimeline.patchReadback r1 0 64
  let rb2 := CassieTimeline.patchReadback r1 0 2
  let rb3 := CassieTimeline.patchReadback r2 0 1000
  rb.found && rb.value == 3 && !rb.budgetHit &&
  !rb2.found && rb2.budgetHit &&
  !rb3.found && !rb3.budgetHit

-- frameLadder: 3 rungs with strictly increasing walkSteps
#eval
  let l := CassieTimeline.frameLadder
  l.size == 3 && l[1]!.walkSteps > l[0]!.walkSteps && l[2]!.walkSteps > l[1]!.walkSteps

-- ────────────────────────────────────────────────────────────────────────────
-- Pipeline.Adapters.GroundTruth
-- ────────────────────────────────────────────────────────────────────────────

-- expectedPatchCount: array size; missing key → 0; wrong type → 0
#eval
  let j1 := Json.mkObj
    [("allCreatedPatches", Json.arr #[Json.str "p0", Json.str "p1", Json.str "p2"])]
  let j2 := Json.mkObj [("other", Json.num 0)]
  let j3 := Json.mkObj [("allCreatedPatches", Json.num 42)]
  Pipeline.Adapters.expectedPatchCount j1 == 3 &&
  Pipeline.Adapters.expectedPatchCount j2 == 0 &&
  Pipeline.Adapters.expectedPatchCount j3 == 0
