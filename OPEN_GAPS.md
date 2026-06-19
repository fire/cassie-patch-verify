# Open Gaps

## Temporal constructor (the core deliverable)

The constructor that replays `systemStates` does not exist yet. Its shape is
decided: fold over the 1095 frames in `time` order and dispatch on
`interactionType` — **1** add the stroke `elementID`, applying that stroke's
recorded `appliedPositionConstraints` (replay the snaps, do not recompute
intersections); **2** delete `elementID`; **3** a patch was created, assert our
construction just closed it; **4** rare op; **0/5** no graph change (pose/canvas
only). Maintain the incremental arrangement and emit a patch the moment a cycle
closes. Decisive next lever: write the Lean fold and assert that at every type-3
frame the construction has just closed the patch `elementID` records.

## Verifier domain is a stand-in

`cassie-patch-verify` certifies a `targetSteps` placeholder, not real geometry.
Decisive next lever: make `readback walkSteps` the budgeted temporal construction
up to a frame, and `candidateIsWitness` the "expected patch present" test, so the
ladder's `walkSteps` models the per-VR-frame budget.

## Undo/redo semantics are undecided

`interactionType` 2 (delete, 59 frames) and 4 (rare, 6 frames) carry the
delete/undo/redo history; how a delete rewinds the incremental graph (and how the
9 hard-deleted strokes 1, 3, 11, 13, 15, 17, 37, 45, 51 leave) is unspecified.
Decisive next lever: read the type-2/4 frames' `elementID`s in sequence and
define the inverse of each construction step.

## The fixture is not regenerated from the timeline

`hat_polylines.json` / `HatStrokes.lean` came from a Python codegen that inflated
120→138 strokes (18 resurrected from the edit history) and is not temporal.
Decisive next lever: regenerate both strokes and the patch sequence by replaying
`systemStates` in Lean (`HatDump`), so the fixture *is* the timeline rather than a
batch snapshot.

## VR frame-budget validation

"Can we do it in VR" needs a per-frame cost bound. Decisive next lever: once the
temporal constructor exists, measure per-frame construction cost against a VR
budget and tie it to the ladder rung at which each patch resolves.
