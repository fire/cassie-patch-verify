import Pipeline.Core.Vec3
/-! # PatchSink port — abstract patch output

A patch is a triangulated surface represented as a vertex array and an
index array (triples of vertex indices).
-/
namespace Pipeline.Ports

structure Patch where
  id       : String
  boundary : Array (Array Pipeline.Core.Vec3)   -- ordered boundary loops
  verts    : Array Pipeline.Core.Vec3
  tris     : Array (Nat × Nat × Nat)
  deriving Repr, Inhabited

structure PatchSink where
  emit : Patch → IO Unit

end Pipeline.Ports
