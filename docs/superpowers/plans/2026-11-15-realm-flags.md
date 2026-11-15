# National flags implementation plan

**Goal:** Install the seven approved flags and show physical national standards at settlements and on one figure per visible land unit.

**Architecture:** An editor-authored ArtTable binds realm slots to approved textures. One reusable flag scene supplies pole, two-sided cloth and restrained wind. Settlement presentation reads live province ownership. A read-only army helper decorates exactly one existing figure, including saved battle groups, without changing personnel, positions, animation timing, sight or saves.

**Constraints:** Existing assets and unrelated workspace edits remain intact. No billboard, counters or extra soldier. Authored look resources are saved through the Godot editor. Hidden armies remain hidden. Cities use the same building visibility budget and ground placement. Unknown realm art fails closed.

- [x] Install approved originals and create flag scene/material/table through editor.
- [x] Add settlement flag placement and one bearer per ordinary/physical group unit.
- [x] Test realm mapping, conquest, bearer uniqueness and visibility; run affected map tests.
- [x] Capture actual city and army shots at near/far zoom; independent visual critique.
