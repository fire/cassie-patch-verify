# cassie-patch-verify

An **independent** Lean witness-DAG oracle that verifies CASSIE patch detection
from the C++ module's output (JSON only — it never links into the C++/Godot
build). One dependency: [`plausible-witness-dag`](https://github.com/fire/plausible-witness-dag).

**Project state lives in the three SSOT docs — read these first:**

- [CHANGELOG.md](CHANGELOG.md) — decided/verified work, with the Conventions header
- [OPEN_GAPS.md](OPEN_GAPS.md) — open problems, each with its next lever
- [TOMBSTONES.md](TOMBSTONES.md) — dead ends, with why and where knowledge survives

## Build & run

```
lake exe cassie-patch-verify
```

Toolchain `v4.30.0` (matches `plausible-witness-dag`). First build fetches the
dep + `plausible` (no Mathlib). The current `Main.lean` is a prototype: it
exercises the ladder's `found` / `budgetHit` escalation on a stand-in.

## Data

`data/hat.json` is the canonical CASSIE session (`raw_data/hat.json` from
`fire/cassie-data`): `allSketchedStrokes` (120), `allCreatedPatches` (234; each
`foundByAlgo, id, strokesID`), and `systemStates` (1095 VR frames). Each frame
carries `time`, head/hand poses, canvas transform, `interactionType`,
`elementID`. The action enum:

| type | meaning | frames |
|---|---|---|
| 1 | add stroke (applies its `appliedPositionConstraints`) | 120 |
| 2 | delete | 59 |
| 3 | create patch | 234 |
| 4 | rare op (undo/redo) | 6 |
| 0 | idle / camera | 295 |
| 5 | canvas transform | 381 |

## Next (OPEN_GAPS top item): the temporal constructor

Fold the 1095 `systemStates` in `time` order, dispatch on `interactionType`
(1 add-stroke with replayed constraints, 2 delete, 3 assert-the-patch-just-closed,
0/5 pose-only), maintain the incremental arrangement, and emit a patch the moment
a cycle closes — proving the construction is valid frame-by-frame and runnable
live in VR. The verifier's `readback` / `candidateIsWitness` plug into it.
