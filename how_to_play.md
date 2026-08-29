System Requriements:
1. Need a dedicated UI scene showing kingdom's basic data
2. The council only summarize the event and result, don't need to say everyone's speech
3. Conversation style should be one after one: one minister speaks, you reply, another one jumps in, then you again.
4. there should be a conversatin scene, in this scene, only shows one portrait for one minister, with the conversation box at mid bottom position
5. The council only inform events, with a round table like portait as placeholder
6. slow down the speed of day run after end turn
7. ministers don't need to report numeric result.
8. the default options for prompt should be more like nature language
9. The kingdom info scene like a info card, and shows the changes during day run
10. no need to show the ministers portraits on the top of scene
11. please advice me a good and scalable architecture of scenes strucures and implement.
12. create a input function that when I hit R then restart the game
13. create an easy main scene, hit space to start the game.
14. the conversation box is a fixed-size strip at the very bottom of the view; long content scrolls inside it, and the box never covers the minister portrait (supersedes the "mid bottom" box in 4)
15. the kingdom info card is compact and always pinned to the top-left corner of every gameplay screen (conversation, court, day run)
16. the whole UI follows the UI_example.png mock (dark ground, thin gold trim, parchment text): a top strip with date + the six metrics and their per-tick deltas + a pending-event chip replaces the kingdom card (supersedes 15)
17. the conversation scene shows a minister dossier card on the left (portrait, name, seat title, opinion bar, trait chips); every minister has full-body art — chancellor (minister_1), marshal (minister_2), steward (char_new, the taxes ledger), spymaster (char_new2, the hooded courier), chaplain duplicates char_new until own art lands; king.jpg is installed as the player's (you) art for a future player card
18. the court screen puts the lettered suggestion buttons and End Turn in a right-side advice panel; response buttons everywhere are lettered "A. / B. / C." like the mock
19. map_example.jpeg is the static 2D map placeholder shown (dimmed) behind every screen
20. frame.jpg (young king bottom-left, old king top-right, at a chess game) frames every screen; the UI is inset into its interior so the kings and rails stay visible, and the interior was keyed transparent via tools/key_frame_interior.py into assets/ui/frame.png
