# How to play

*Player-facing summary of the build as it stands (aligned with the code 2026-09-18). The owner's interface requirements that shaped it follow below, with the ones later rulings replaced marked as superseded.*

## Starting

- The title screen offers **Start Game**, **Load Game** and **Quit**. Start Game asks for your given name and family name over your house's arms; **Space** quick-starts with the founding names.
- A reign opens with a narration of the realm's situation, then your council's first words. You are the king of the realm and the lord of ONE province — the capital's.

## Time

- Time runs in **days**. The top bar's clock is the only switch: `||` pause, `>` play, `2x`, `4x`. It starts paused. There is no End Turn.
- The thirtieth day ends the **month**: taxes and goods are settled, ministers' concerns are scanned, and an event may fire. An event **stops the clock** and opens the council; answer it to go on.
- The **news bar** above the tabs reports the month's close, building progress and waiting events while the clock runs; LOG opens its history.

## The screen

- **Top bar:** the date, the clock, MENU, and your two purses — the **crown's** (treasury, strategic goods, civil goods; marked with a crown) and **your house's** own (marked with your arms). The crown takes a share of the realm's other provinces and pays the court; your purse takes your own provinces in full and pays for your manors.
- **Left column — facts:** the realm dashboard by default; the country under the cursor; the host while MILITARY is on; the card of whatever you click on the map.
- **Middle — the map.** Wheel to zoom, drag to pan, hover to name, click to open a card (a town, a province; a manor in the ECONOMY and MANORS views).
- **Right edge — the council.** ENTER THE COUNCIL opens where you stand, who is present, MOVE, and the record of everything said. On the court it also holds the order box and your ministers' lettered suggestions.

## Speaking and giving orders

- Talking to someone opens the **audience window** over the map: their portrait, opinion (hover for its reasons), traits and skills on the left; their words, BIO / SKILLS / TIES, your options and a talk box on the right. Events use the same window.
- Click a face in the council column to seek that person out; **MOVE** takes you to another place in the district at no cost in time.
- **Click a suggestion** to carry it out at once, or **type an order** in plain words. A typed order gets a reply, then the ledger lines that actually applied. Every order costs something — gold, goods, or someone's opinion.
- **Laws** are decreed and ride by courier. The economy and political laws (the tax and tariff rates, grain policy, the severity of justice, the church policy) go to every province you hold, and each province follows its law from the day its courier arrives. The military laws (plunder, the conduct of the host, quarter, ransom and the rest) go to each camp and to each unit in the field, and a unit carries what it was told into the next camp. A decree is said once in the news when it is sent and once when its last courier is home, "in force everywhere" or how many places it reached; the chancery files a letter on the MISSIVE board for each. An event may change a law at once.
- Ministers remember: opinions move for stated reasons, promises you make fall due, and a broken promise is the worst insult you can give.

## Manors and the economy

- Every land cell is a **manor** held by a house. Open **MANORS** (colours manors by house, lists them in the Manor Master table) or **ECONOMY** (shows what the land produces) and click a manor for its card.
- From the card: **BUY** / **SELL** land, **BUILD** from the dropdown (buildings take days and slots; the × on a slot pulls one down), **WORK** to change its chief good, **HURRY** a building, or **SEIZE BY FORCE**. These orders run at once, without the model. You may build only in provinces you control; you buy in your own province or a neighbouring one, and across the border only land touching the realm, paid from the treasury.

## The tabs

`3D MAP` | `HEIGHTS` | `ECONOMY` | `MANORS` | `REALM` | `MILITARY` | `WAR ROOM` | `FAMILIES` | `LAWS` | `RELIGION` | `RELATIONSHIP`

- **3D MAP** swaps the map for a 3D landscape (drag to pan, right-drag to turn, wheel to zoom, WASD / arrows); clicks open the same cards. It needs the 3D world built for the map (`tools/map3d/`).
- **HEIGHTS**, **ECONOMY**, **MANORS** are map themes, one at a time. **MILITARY** draws your regiments on the map and your host in the left column.
- **REALM**, **FAMILIES**, **RELIGION** open tables of the realm's current state; **WAR ROOM** is a placeholder; **RELATIONSHIP** opens the web of kin, friendships and feuds.
- **LAWS** opens the laws screen over the map; the clock keeps running. It has three pages (economy, politics, military), with one row per law: what is decreed, how many places the couriers have told so far, what the chosen value does, and its cost (couriers, gold, the longest ride) or why it cannot be sent. **Decree** sends the law by courier, and each place follows it only once its courier arrives. **Places** lists the places not yet told, with the days left for each courier; a place is marked "lost" if its courier was lost and "not sent" if it was gained after the decree, and **Send again** rides for both. Press LAWS again, Close or Esc to put it away.

## Other keys

- **Esc** or MENU: pause menu — Resume, Save Game, Load Game, Restart, Quit to Desktop. A loaded game resumes at court, or at the council if an event is waiting.
- **R** restarts to the title screen.

---

# Interface requirements (owner's list, kept as history)

1. Need a dedicated UI scene showing kingdom's basic data
2. The council only summarize the event and result, don't need to say everyone's speech
3. Conversation style should be one after one: one minister speaks, you reply, another one jumps in, then you again.
4. there should be a conversatin scene, in this scene, only shows one portrait for one minister, with the conversation box at mid bottom position
5. The council only inform events, with a round table like portait as placeholder
6. ~~slow down the speed of day run after end turn~~ — superseded: there is no End Turn; time runs on the play/pause clock (owner 2026-09-14)
7. ministers don't need to report numeric result.
8. the default options for prompt should be more like nature language
9. The kingdom info scene like a info card, and shows the changes during day run *(the day run screen was removed 2026-09-18)*
10. no need to show the ministers portraits on the top of scene
11. please advice me a good and scalable architecture of scenes strucures and implement.
12. create a input function that when I hit R then restart the game
13. create an easy main scene, hit space to start the game.
14. the conversation box is a fixed-size strip at the very bottom of the view; long content scrolls inside it, and the box never covers the minister portrait (supersedes the "mid bottom" box in 4)
15. the kingdom info card is compact and always pinned to the top-left corner of every gameplay screen (conversation, court; the day run was removed 2026-09-18)
16. *(top strip superseded 2026-09-14: the top bar holds the date, the clock, MENU and the two purses only; the temper moved to the country card and dashboard. The whole UI is now a dark theme after Crusader Kings III, owner 2026-09-15.)* the whole UI follows the UI_example.png mock (dark ground, thin gold trim, parchment text): a top strip with date + the six metrics and their per-tick deltas + a pending-event chip replaces the kingdom card (supersedes 15)
17. *(dossier superseded 2026-09-15 by the audience window centred over the map; every character now has their own portrait from the image-generation pipeline, the Chaplain included.)* the conversation scene shows a minister dossier card on the left (portrait, name, seat title, opinion bar, trait chips); every minister has full-body art — chancellor (minister_1), marshal (minister_2), steward (char_new, the taxes ledger), spymaster (char_new2, the hooded courier), chaplain duplicates char_new until own art lands; king.jpg is installed as the player's (you) art for a future player card
18. *(End Turn removed 2026-09-14.)* the court screen puts the lettered suggestion buttons and End Turn in a right-side advice panel; response buttons everywhere are lettered "A. / B. / C." like the mock
19. *(superseded: the live world map drawn from the Azgaar pack stands in the middle of every gameplay screen.)* a static 2D map placeholder was shown (dimmed) behind every screen; its image is deleted
20. frame.jpg (young king bottom-left, old king top-right, at a chess game) frames the play area; the interior was keyed transparent via tools/key_frame_interior.py into assets/2D/ui/panels/frame.png
21. per game_ui.png: gameplay screens are two mock-proportioned UI columns (left dossier/log, right responses/advice) with the framed map view between them at the mock map region's EXACT landscape ratio — cover-cropped, never distorted, always bright, covered by nothing; the kings frame lives on the menu only (its corner figures would swallow a ratio-locked map window)
22. *(day run superseded 2026-09-14: no End Turn; the news bar above the tab bar carries dated headlines while the clock runs; the skill bars now sit in the audience window.)* the day run is the ROYAL CHRONICLE (game_ui.png): a transparent LIVE ticker window at the map's lower left that rolls the fortnight day by day with dated news entries after End Turn; UI and conversation fonts share the same scale, and the dossier shows one colored bar per council skill (diplomacy green, martial red, steward gold, intrigue purple, admin blue) plus the opinion bar
23. *(tabs now: 3D MAP | HEIGHTS | ECONOMY | MANORS | REALM | MILITARY | WAR ROOM | FAMILIES | LAWS | RELIGION | RELATIONSHIP; MAP and PROVINCES were removed 2026-09-13.)* a bottom tab bar on every gameplay screen — MAP | REALM | MILITARY | LAWS | RELIGION | RELATIONSHIP: MAP returns to the plain view, RELATIONSHIP opens the live graph (king at center, kin gold, friendships green, feuds red, thickness = strength), the rest open live tables of engine truth
23b. *(the family flag was replaced by the house's generated arms, owner 2026-09-15.)* the main menu offers Start Game / Load Game / Quit; Start Game opens character creation — given name, family name, and a family flag (the family name is inherited by the whole royal house, the flag flies beside the date); Space still quick-starts with the founding names
23d. the upper right panel names where you stand (Council Chamber, War Room, Falconspire Keep, the High Street...) and shows everyone present — click a face to seek them out and speak with them; MOVE lists the Crown District's locations and moving within the region costs no time
23c. *(events and the dossier pages now live in the audience window, owner 2026-09-15.)* a new reign opens with a nameless narration of the realm's situation (game_story/chapter_0/game_start.md); events pop up centered with an art placeholder and their choices inside; the left dossier column is tabbed BIO | SKILLS | TIES; transcript names are color-coded per speaker and replies surface one by one
24. a MENU button at the top bar's right (or Esc) opens the pause menu — Resume, Save Game, Load Game, Restart, Quit to Desktop; a loaded save resumes at court, or on the conversation stage when an event is still pending
25. *(partly superseded 2026-09-10: a clicked map element's card goes in the LEFT column, never the right; 2026-09-15: the talk is the audience window over the map; End Turn is gone.)* (2026-09-09) gameplay screens share one frame: the LEFT column is always on and shows the realm dashboard by default (resources as icons with floating tooltips, the temper of the realm as bars, the people as a pie, the host by arm, the largest provinces); on the stage the minister dossier takes it only while a person speaks or is singled out. The RIGHT slot is empty by default and the map runs to the edge: an ENTER THE COUNCIL handle stands on the right edge, and opening it brings the council column (stage: where you stand, occupants, MOVE, the transcript, replies, the talk box; court: the record, the order box, the lettered suggestions, End Turn) with LEAVE THE COUNCIL at its top; clicking a map element puts the detail column in the same slot (its details, ASK THE COUNCIL, CLOSE) and closing it gives the council back if it was open. Ask brings the council up to send from. Columns start under the top bar, never over it.
26. *(the top bar now shows only the two purses.)* (2026-09-09) titles and section headers are two sizes smaller everywhere; the top bar shows each metric as a glyph with a tooltip instead of a word.
27. *(superseded 2026-09-10/13: MILITARY is a map layer of regiment counters with the host in the left column.)* (2026-09-09) the MILITARY tab shows the host by arm with an icon per type and a bar for its size, every regiment with its main arm, and the neighbours' strength as reported — charts, not a table.
28. *(superseded 2026-09-13: the PROVINCES tab is gone — the seams and province clicks are always on — and cards open in the LEFT column.)* (2026-09-09) the PROVINCES tab toggles the province seams on the map (no names drawn); clicking a province opens its account in the right detail column — full for the player's own land, only name, kingdom, house, and seat abroad.
29. *(the card now opens in the LEFT column; manors have their own card with a painting, icon stats and orders.)* (2026-09-09) clicking a town, or one of the player's own provinces in the province view, shows an info CARD in the right detail column after Azgaar's burg editor: heraldry in the kingdom's colour, a field grid (group, type, culture, population; for a province its house, seat, population, area, terrain, towns, regiments, hazards), feature and goods glyphs with tooltips, wealth and treasury, and a window onto the map around the place. Foreign provinces show only house and seat.
30. *(superseded 2026-09-17: settlements are aerial photographs in `assets/settlements/painted/`, drawn in proportion to the zoom.)* (2026-09-09) towns draw on the map as the owner's settlement art (assets/settlements/, cut from the supplied sheet by tools/split_settlements.py): hamlet, village, town, walled town, city, and capital, matched to each burg's group and walls by data/settlement_art.csv, standing on the town's point, scaled with the zoom between map_sprite_min_px and map_sprite_max_px, and clickable anywhere on the picture; zoomed out they fall back to pins.
