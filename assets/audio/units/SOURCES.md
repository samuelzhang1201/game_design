# Freesound unit sounds

All files are CC0 1.0 (public domain) from freesound.org; no attribution required.

| File | Use | Author | Source |
|---|---|---|---|
| 770083__vrymaa__footsteps-knight-team-walk-run-castle-hall.wav | heavy-armour infantry marching | Vrymaa | https://freesound.org/people/Vrymaa/sounds/770083/ |
| 384890__ali_6868__knight-right-footstep-on-gravel-5-with-chainmail.wav | armoured footstep on gravel, chainmail | Ali_6868 | https://freesound.org/people/Ali_6868/sounds/384890/ |
| 437108__craigsmith__g38-13-group-of-horses-walking.wav | cavalry on the march | craigsmith | https://freesound.org/people/craigsmith/sounds/437108/ |

## The game's loops (cut from the originals, which stay git-ignored in `source/`)

| Loop | Cut from | How |
|---|---|---|
| march_armour.wav | 770083 (Vrymaa), the WALK section 4–22 s (the run after 26 s is left out) | mono 44.1 kHz, 17 s, 1 s crossfade tail→head so it loops seamless, -20 LUFS |
| march_horses.wav | 437108 (craigsmith), the steady section 28–58 s | mono 44.1 kHz, 29 s, 1 s crossfade tail→head, -20 LUFS |

Both loop through their `.import` (`edit/loop_mode=2`, QOA). `unit_sounds.tres` maps each arm to its loop: infantry, archers and artillery march to the armour, cavalry and the royal piece to the horses. The chainmail single step (384890) is kept in `source/` unused.
