import PlausibleWitnessDag
import Timeline
open PlausibleWitnessDag CassieTimeline

/-! # cassie-patch-verify

An **independent** Lean oracle that reads the C++ cassie module's patch output
(JSON only — no FFI, never linked into the Godot/C++ build) and certifies each
patch by replaying the VR session timeline.

`main` runs the temporal constructor (`Timeline.lean`): it folds the 1095
`systemStates` frames of `data/hat.json` in `time` order and asserts that at
every create-patch frame the construction has *just closed* the patch the data
records — proving the build is valid frame-by-frame and therefore runnable live
in VR. It then drives the `plausible-witness-dag` frame-budget ladder on real
patches, where `walkSteps` models the per-VR-frame budget: a patch that closes
late `budgetHit`s on a shallow rung and resolves on a deeper one, rebutting "T7
is too dense to walk." -/

def main : IO Unit := do
  IO.println "cassie-patch-verify — independent witness-DAG oracle"

  -- 1. Temporal construction: replay the timeline and assert frame-by-frame validity.
  let (frames, boundary) ← loadSession
  let r := replay frames boundary
  IO.println s!"  timeline: {frames.size} frames, {boundary.size} patches"
  IO.println s!"  create-patch frames closed on construction: {r.closedOk}/{r.patchFrames}"
  if r.closedOk != r.patchFrames then
    throw <| IO.userError
      s!"temporal constructor invalid: {r.patchFrames - r.closedOk} patch(es) not closed when created"
  IO.println "  ✓ every patch closed exactly at its create-patch frame"

  -- 2. Drive the frame-budget ladder on real patches that close at different times.
  IO.println "  frame-budget ladder (walkSteps = per-VR-frame budget):"
  for target in #[0, 50, 230] do
    let (cf, lvl, tr) ← resolvePatch r target
    IO.println s!"    patch {target}: closeFrame={cf}  resolved@L{lvl}  outcome={repr tr.outcome}"
