/-! # Pipeline library root

This file is the Lake lib entry-point for the `Pipeline` library.
Sub-modules are imported individually by consumers:

  Pipeline.Core.Vec3
  Pipeline.Core.Bezier
  Pipeline.Core.RDP
  Pipeline.Core.G1Sections
  Pipeline.Core.Graph
  Pipeline.Core.GraphBuilder
  Pipeline.Core.CycleDetect
  Pipeline.Ports.StrokeSource
  Pipeline.Ports.PatchSink
  Pipeline.Ports.TriangulationPort
  Pipeline.Adapters.JsonStroke
  Pipeline.Adapters.GroundTruth
  Pipeline.Adapters.DmwtAdapter
-/
