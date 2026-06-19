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

## Temporal constructor (`Timeline.lean`) — landed

`main` folds the 1095 `systemStates` in `time` order and asserts that at every
create-patch frame the construction has *just closed* the patch the data records:
**234/234**. Frames sharing a `time` are one gesture (adds apply before the
group's patch checks), and `mirroring` brings in each stroke's `r+1` partner — the
two fixes that took a naive replay from 37/234 to 234/234. The frame-budget ladder
then drives real patches: `walkSteps` is the per-VR-frame budget, so a late patch
`budgetHit`s a shallow rung and resolves on a deeper one. See CHANGELOG; remaining
work (real cycle incidence vs. mere membership) is in OPEN_GAPS.
