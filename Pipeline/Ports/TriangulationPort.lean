import Pipeline.Core.Vec3
import Pipeline.Ports.PatchSink
/-! # TriangulationPort — abstract triangulation back-end

Decouples the core pipeline from the DMWT / Geogram FFI.
-/
namespace Pipeline.Ports

structure TriangulationPort where
  /-- Triangulate a single planar-ish closed boundary loop.
      Returns (verts, tris) or an error string. -/
  triangulate : Array Pipeline.Core.Vec3 → IO (Except String Patch)

end Pipeline.Ports
