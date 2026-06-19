import Pipeline.Core.Vec3
import Pipeline.Core.Graph
/-! # Graph builder — stroke sections → nodes + segments (dependency-free core)

Takes an array of strokes (each a poly-Bézier `Array Vec3`) that have already
been through RDP + G1-section splitting + Bézier fitting, and:

1. Clusters stroke endpoints into nodes using a proximity threshold.
2. Adds one segment per stroke section.

Proximity detection is O(n²) over endpoints — acceptable for typical CASSIE
session sizes (< 2000 sections).
-/
namespace Pipeline.Core
open Vec3

/-- Find or create a node within `snapRadius` of `pos`. -/
private def snapNode (g : Graph) (pos : Vec3) (snapRadius : Float) : Graph × NodeId :=
  let sr2 := snapRadius * snapRadius
  -- linear scan for an existing node within radius
  let found := g.nodes.findIdx? (fun n => dist2 n.pos pos ≤ sr2)
  match found with
  | some id => (g, id)
  | none    => g.addNode pos

structure BuildParams where
  snapRadius : Float := 0.01

/-- Build a `Graph` from an array of stroke sections.
    Each section is a poly-Bézier `Array Vec3` (≥4 control points).
    Returns the graph plus a mapping from (sectionIdx → segId). -/
def buildGraph (sections : Array (Array Vec3)) (p : BuildParams := {}) : Graph :=
  sections.foldl (init := Graph.mk #[] #[]) fun g ctrl =>
    if ctrl.size < 4 then g
    else
      let headPos := ctrl[0]!
      let tailPos := ctrl[ctrl.size - 1]!
      let (g1, hId) := snapNode g  headPos p.snapRadius
      let (g2, tId) := snapNode g1 tailPos p.snapRadius
      (g2.addSegment ctrl hId tId).1

end Pipeline.Core
