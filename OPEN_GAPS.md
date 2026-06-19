# Open Gaps

(Resolved and moved to CHANGELOG: the temporal constructor — `Timeline.lean`,
234/234 — and the verifier-stand-in gap — the frame-budget ladder now drives
real patches.)

## Detection parity: Lean port vs C++ vs upstream (the core verification)

The three pipelines must agree on *which patches the algorithm detects*, but
currently report wildly different counts on `hat.json`: C++ `find_cycles` marks
**208** `foundByAlgo=true`, the Lean `findCyclesPort` reports a batch **32**
(docs figure), and the upstream auto path produced those 208. The 208 (not 234)
is the target: `foundByAlgo = !userCreated` splits the patches into **208**
auto-detected (segment+node angular walk) and **26** manual (input-position
walk). See `meta/verification.jsonld` for provenance.

Decisive next levers, in order:

1. **Pin the C++ ground truth.** Once the Godot module builds, run
   `CassieSketchGraph::find_cycles()` on `hat.json` and confirm it reproduces the
   208 `foundByAlgo=true` patch boundaries — turning 208 into an empirical
   reference, not just a recorded field.
2. **Get the Lean port's live number.** Build/run
   `CassieAvbd.CycleDetect.findCyclesPort` on the same strokes for the real
   current figure (the 32 is only the docs), and diff per-patch against the C++
   set keyed on the sorted `strokesID` signature.
3. **Chase the normal-seeding divergence.** C++ `find_cycles` seeds one global
   PCA plane normal reused at every node; upstream `CycleDetection.cs` uses
   per-node `Normal` plus the `IsSharp` / `GetInPlane` / `ShouldReverse`
   machinery, which the Lean port mirrors from the C++ simplification. This is
   the most probable cause of the parity gap — restore per-node normals and
   re-measure.

## Boundary membership is replayed, not geometrically reconstructed

The constructor proves each patch's recorded `strokesID` are *all live* at its
create-patch frame — a necessary condition that holds 234/234. It does **not**
yet prove the live strokes actually form a closed cycle in the incremental
arrangement (the boundary could be present but not yet topologically closed).
Decisive next lever: replay each added stroke's `appliedPositionConstraints`
(the recorded snaps) to maintain incidence, and at each type-3 frame assert the
boundary strokes form a cycle, not merely that they are present.

## Delete semantics (no longer "undo/redo")

The `interactionType` enum is now pinned from upstream (`StudyUtils.cs:46`):
**0** Idle, **1** StrokeAdd, **2** StrokeDelete, **3** SurfaceAdd (create patch),
**4** SurfaceDelete (delete patch), **5** CanvasTransform — so the old "type 4 =
rare op / undo-redo" guess was wrong; it deletes a patch. (Recorded in
`meta/verification.jsonld`.) The constructor already replays type-2 deletes as
stroke-set removal (with mirror partner) and still reaches 234/234, so deletes
are handled *for membership*. What is still undecided is how a delete should
**rewind the incremental arrangement** (incidence/cycles), and whether the 6
type-4 SurfaceDelete frames need to retract an emitted patch. Decisive next lever:
once boundary membership is replaced by real incidence (gap above), define the
inverse of each construction step for type-2/type-4 by their `elementID`s
(type-2 = stroke id, type-4 = patch id).

## The fixture is not regenerated from the timeline

`hat_polylines.json` / `HatStrokes.lean` came from a Python codegen that inflated
120→138 strokes and is not temporal. (The 18 extra ids are now known to be mirror
strokes — see CHANGELOG — not edit-history resurrections.) Decisive next lever:
regenerate both strokes and the patch sequence by replaying `systemStates` in
Lean — `Timeline.replay` already produces the per-patch closing frame, so it can
emit the temporal fixture directly rather than from a batch snapshot.

## VR frame-budget validation

"Can we do it in VR" needs a per-frame cost bound. Decisive next lever: once the
temporal constructor exists, measure per-frame construction cost against a VR
budget and tie it to the ladder rung at which each patch resolves.
