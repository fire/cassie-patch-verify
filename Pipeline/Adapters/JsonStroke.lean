import Lean.Data.Json
import Pipeline.Core.Vec3
import Pipeline.Ports.StrokeSource
/-! # JsonStroke adapter — reads hat_raw.json / train/*.json -/
open Lean Pipeline.Core Pipeline.Ports

namespace Pipeline.Adapters

private def jsonNum? (j : Json) : Option Float :=
  match j with
  | .num n => some n.toFloat
  | _ => none

private def parseVec3 (j : Json) : Option Vec3 :=
  match j with
  | .arr a =>
      if a.size < 3 then none
      else do
        let x ← jsonNum? a[0]!
        let y ← jsonNum? a[1]!
        let z ← jsonNum? a[2]!
        some (x, y, z)
  | _ => none

private def parseSamples (j : Json) : Array Vec3 :=
  match j with
  | .arr a => a.filterMap parseVec3
  | _      => #[]

private def parseStrokes (j : Json) : Array (String × Array Vec3) :=
  let strokeArr : Array Json :=
    match j.getObjVal? "strokes" with
    | .ok (.arr a) => a
    | _ => #[]
  strokeArr.filterMap fun s =>
    let id := match s.getObjVal? "id" with
              | .ok (.str v) => v
              | _ => ""
    let samples := match s.getObjVal? "inputSamples" with
                   | .ok arr => parseSamples arr
                   | _       => #[]
    if samples.size < 2 then none
    else some (id, samples)

/-- Load a single JSON session file as a `StrokeSource`. -/
def jsonStrokeSource (path : System.FilePath) : StrokeSource where
  load := do
    let text ← IO.FS.readFile path
    match Json.parse text with
    | .error e => throw (IO.userError s!"JSON parse error in {path}: {e}")
    | .ok j    => return parseStrokes j

end Pipeline.Adapters
