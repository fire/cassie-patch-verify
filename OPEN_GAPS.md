# Open Gaps

(Resolved and moved to CHANGELOG: the temporal constructor — `Timeline.lean`,
234/234 — and the verifier-stand-in gap — the frame-budget ladder now drives
real patches.)

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
