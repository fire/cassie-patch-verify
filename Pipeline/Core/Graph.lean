import Pipeline.Core.Vec3
import Pipeline.Core.Bezier
/-! # Patch-graph types (dependency-free core)

Mirrors the Unity CASSIE `DrawingGraph` / `GraphNode` / `GraphSegment` model.

A **node** is a junction where two or more stroke ends meet within `snapRadius`.
A **segment** is one G1 section of a stroke, stored as a poly-Bézier control
point array.  Segments are directed; each has a head-node and a tail-node.
-/
namespace Pipeline.Core
open Vec3

/-- Index into `Graph.nodes`. -/
abbrev NodeId := Nat
/-- Index into `Graph.segments`. -/
abbrev SegId  := Nat

structure Node where
  id       : NodeId
  pos      : Vec3
  /-- Indices of segments whose *start* touches this node. -/
  outSegs  : Array SegId := #[]
  /-- Indices of segments whose *end* touches this node. -/
  inSegs   : Array SegId := #[]
  deriving Repr, Inhabited

structure Segment where
  id      : SegId
  /-- Poly-Bézier control points (4, 7, 10, … pts). -/
  ctrl    : Array Vec3
  headId  : NodeId
  tailId  : NodeId
  deriving Repr, Inhabited

structure Graph where
  nodes    : Array Node    := #[]
  segments : Array Segment := #[]
  deriving Repr, Inhabited

namespace Graph

def addNode (g : Graph) (pos : Vec3) : Graph × NodeId :=
  let id := g.nodes.size
  ({ g with nodes := g.nodes.push { id, pos } }, id)

def addSegment (g : Graph) (ctrl : Array Vec3) (hId tId : NodeId) : Graph × SegId :=
  let id := g.segments.size
  let seg := { id, ctrl, headId := hId, tailId := tId }
  -- wire into head/tail nodes
  let nodes' := g.nodes
    |>.modify hId (fun n => { n with outSegs := n.outSegs.push id })
    |>.modify tId (fun n => { n with inSegs  := n.inSegs.push  id })
  ({ nodes := nodes', segments := g.segments.push seg }, id)

def nodePos (g : Graph) (id : NodeId) : Vec3 :=
  (g.nodes.getD id { id, pos := Vec3.zero }).pos

/-- All segment ids incident to a node (in or out). -/
def incident (g : Graph) (id : NodeId) : Array SegId :=
  let n := g.nodes.getD id { id, pos := Vec3.zero }
  n.outSegs ++ n.inSegs

/-- Entry tangent at the head of a segment (first chord direction). -/
def entryTangent (g : Graph) (sid : SegId) : Vec3 :=
  let s := g.segments.getD sid default
  PolyBezier.tangent s.ctrl 0.0

/-- Exit tangent at the tail of a segment (last chord direction). -/
def exitTangent (g : Graph) (sid : SegId) : Vec3 :=
  let s := g.segments.getD sid default
  PolyBezier.tangent s.ctrl 1.0

end Graph
end Pipeline.Core
