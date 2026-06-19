import Pipeline.Core.Vec3
/-! # StrokeSource port — abstract stroke input

A `StrokeSource` provides raw input samples as `Array Vec3` arrays,
each array being one controller stroke (all positions in session order).
-/
namespace Pipeline.Ports

structure StrokeSource where
  /-- Load all strokes.  Returns (strokeId, positions[]) pairs. -/
  load : IO (Array (String × Array Pipeline.Core.Vec3))

end Pipeline.Ports
