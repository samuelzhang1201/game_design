# War Table UI — implementation plan

Spec: `docs/superpowers/specs/2026-10-01-war-table-ui-design.md`. Branch
`feat/war-table-ui`. Each task: implement, run the touched tests, shoot
`--screen root --quiet --resolution 2560x1600`, compare against the approved
mock and the before shot.

1. **Data and switch.** `balance.csv` `ui_war_table` + `ui_table_*` keys;
   `data/ui_table_palette.csv` (paper ink roles, brass, wax, board);
   `data/ui_bookmarks.csv` (tab → colour); `UiPalette.war_table()`,
   `UiPalette.table_color(key)`, `UiPalette.ink(role)`.
2. **The table.** `WarTableBackdrop` (Control: tiled oak + light shaft +
   vignette) replaces `%Bg`'s flat colour on the court and conversation
   screens.
3. **Paper style.** `PaperStyle` (StyleBox): texture-mapped deckled polygon,
   optional rotation, layered soft shadow down-right, optional double inner
   rule and brass pin. Used for the map sheet (kind "sheet"), the report, the
   news slip and the seal's tag.
4. **Map sheet.** MapPanel wears `PaperStyle` with the inner rule and a margin
   wide enough for the vellum border.
5. **Top bar.** Under the war table: bar background cleared; `BrassDial`
   (the day) + season/year labels; clock buttons as brass studs; purses on a
   `TallyBoard` panel centred; Menu flat.
6. **The report.** LogPanel / MinisterPanel wear the paper style + pin; a
   ScrollContainer round the column's box (overlap fix, with a test that the
   column ends above the ticker); dashboard + charts + cards ink through
   `UiPalette.ink`; temper tally marks; people sentence; host line.
7. **The seal.** `WaxSeal` button replaces the council handle's look under the
   war table, tag beneath.
8. **Bookmarks and slip.** BottomBar tabs drawn as ribbons coloured from
   `ui_bookmarks.csv`, bar background cleared; NewsTicker as a paper slip
   placed between the groups.
9. **Conversation parity, tests, critic, shots.** Full suite; independent
   critic pass on before/after sheets; fix; final shots at 2560x1600 and
   1512x982; taste.md ruling; CLAUDE.md paragraph.
