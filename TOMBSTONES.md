# Tombstones

## Batch arrangement + `cyclesUnion` as the verification model — dead

`buildArrangement` over all strokes at once plus `cyclesUnion` reading off final
faces is not what we verify. Patches form *incrementally* as the user draws; VR
cannot batch-recompute every intersection per frame. The batch `cycle_sweep`
survives only as a parity microscope (it lives in the cassie Lean tree); the live
model is the temporal constructor (see OPEN_GAPS).

## Loading `sketch_graph/hat.json` directly — dead

Feeding cycle-detection the resolved `sketch_graph` (69 strokes / 98 nodes / 169
segments) matches the patches but skips the construction we must prove. It is the
*answer*, not the *process*; VR has to build it. Surviving use: it is still a
valid end-state oracle to check the constructor's final output against.

## "Drop the 18 inflated strokes to fix parity" — disproven

Hypothesis: the fixture's 138-vs-canonical-120 stroke inflation depressed batch
parity. Filtered ids 5,7,9,19,21,23,25,27,29,31,33,35,39,47,49,53,55,57 and
re-ran: parity went 32→29/234 (slightly worse), node count ~213→~189. The 18
phantoms are connected (they add nodes) but are not the cause. The inflation
remains a real fixture bug (see OPEN_GAPS regeneration), just not the parity
lever. **Update:** those 18 ids are now identified as *mirror strokes* (`r+1` of
a real stroke; `mirroring` is on session-wide) — the temporal constructor needs
them present to close patches, so they are not phantoms to drop but real boundary
participants. See CHANGELOG (temporal constructor).

## "The walker is the parity bottleneck" — superseded

The stage-2 framing blamed `findCyclesPort` for non-minimal faces (153/234
supersets, a ceiling at 4 boundary strokes). The augment+port fix was real and
landed (28→32, see CHANGELOG), but chasing the walker further is the wrong
altitude: batch parity is the wrong yardstick because the model should be
temporal. Surviving knowledge: the `MISS-NEAREST` / `PATCH-CLASS` diagnostics in
`cycle_sweep`.

## "T7 (15k samples) is too dense for interpreted Lean, skip it" — dead

The comment in `CycleSweep.lean`. The witness-DAG ladder escalates `walkSteps` on
`budgetHit` rather than enumerating everything, so density is a rung, not a wall —
demonstrated by `cassie-patch-verify` resolving a 6-step boundary at L1 after an
L0 budget-hit. Do not reason about "too dense to walk."
