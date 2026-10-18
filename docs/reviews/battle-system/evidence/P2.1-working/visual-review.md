# P2.1 personnel numeric-fit review

Reference: existing war-table UI; principles: clear book-face readings, names and values, fixed-width left column, sharp at real window sizes.

Real-window `snapshot_screen.gd --resolution` captures: full.png at 2560×1600, casualties.png at 1920×1200. Scratch variants used the same seed42 and real cohort transitions (one third fit → dead); totals change 24k → 16k. No static look resource changed. The war-room tool hook closes the room and opens the actual court host panel. comparison.png shows whole screens; count-crop.png enlarges the numeric region. Different window sizes mean this is not a controlled rendering comparison between equal-size states.

Independent fresh Sol critic inspected whole screens and crops: no numeric-fit defect; totals, arm counts and regiment counts fit with gaps from bars. Hierarchy, contrast, palette and book-face readability pass. Native crop resampling is not evidence of a font defect.

Inherited visual defects remain and are not accepted as good design: regiment names truncate; arm summary uses icons without written arm labels; a floating 600 map badge violates the current taste principles. These concern existing layout/map rendering, outside the personnel-reading edit. No full visual redesign or scrolling audit was performed. See full.png and casualties.png for exact evidence; this review accepts numerical fit only.

The first attempted second capture stalled at renderer startup and was terminated by its exact owned PID23817. The retry completed. Existing missing gdai descriptor, stale map-bake warning and shutdown-resource warnings are present in capture logs. No headless 3D capture was used.

## Realm reader and actual LEDGER click followup

Same1920×1200 real-window captures compare the stale equipment-based realm card(16k) with final personnel card(24k), and an actual click at the visible player's star. The click log records pickcharacter:you then selectedcharacter:you; the resulting left card is King Aldric, consistent with facts-column precedence. No special-case click priority or density thinning. The selected image hides realm facts by design, so a separate unselected final shot verifies count fit. Renderer startup stalled on two2560followups; exactownedPIDs29318/29388 terminated;1920capturescompleted. CLIvsyncdisable/fps60/position0,0 used for followup captures only, no project resource changed.

A numeric wrap left Fleet on one line and700on the next. Final dynamic text uses a nonbreaking space between each arm name and its count; chart/layout resources unchanged. Realm dashboard targeted file rerun passed; shutdownresource/RIDwarningsremain. Fresh independent Sol visual followup found no new blocking visible defect: the Fleet700 pair wraps cleanly, provinces remain inbounds, and actual-click selected node/name/card agree. Native full/crop sheets inspected. Long selected relationship lists still require scrolling; inherited graph density remains a limit.
