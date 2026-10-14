# Unit sounds

## Freesound

All Freesound files are CC0 1.0 (public domain) from freesound.org; no attribution required.

| File | Use | Author | Source |
|---|---|---|---|
| 770083__vrymaa__footsteps-knight-team-walk-run-castle-hall.wav | heavy-armour infantry marching | Vrymaa | https://freesound.org/people/Vrymaa/sounds/770083/ |
| 384890__ali_6868__knight-right-footstep-on-gravel-5-with-chainmail.wav | armoured footstep on gravel, chainmail | Ali_6868 | https://freesound.org/people/Ali_6868/sounds/384890/ |

## The game's loops (cut from the originals, which stay git-ignored in `source/`)

| Loop | Cut from | How |
|---|---|---|
| march_armour.wav | 770083 (Vrymaa), the WALK section 4–22 s (the run after 26 s is left out) | mono 44.1 kHz, 17 s, 1 s crossfade tail→head so it loops seamless, -20 LUFS |

## Ovani Sound, *Sound FX Starter Pack Vol. 1* (bought by the owner; royalty-free licence, https://ovanisound.com/policies/terms-of-service)

The pack itself stays git-ignored in `assets/audio/Sound FX Starter Pack Vol. 1/`; only the cuts below are committed.

| File | Cut from | How |
|---|---|---|
| march_gallop.wav | `Medieval/Horse Gallop Loop.wav` (owner 2026-10-14: 所有骑兵前进的音效换成Horse Gallop Loop.wav), whole — the pack's own seamless loop | mono 44.1 kHz, 12.1 s, -20 LUFS (+2.5 dB under a limiter, peak -1 dBFS) |
| garrison_equip.wav | `Medieval/Equip.wav` (owner 2026-10-14: 转驻防的时候加入Equip.wav的音效), whole — two light clinks at 0.10 / 0.14 s, the clank at 0.25 s (balance `map3d_unit_settle_hit_s`), a rattle to 0.6 s | mono 44.1 kHz, 0.76 s, -20 LUFS |

The loops play through their `.import` (`edit/loop_mode=2`, QOA); the settle sound does not loop. `unit_sounds.tres` maps each arm to its march loop: infantry, archers and artillery march to the armour, cavalry and the royal piece to the gallop. `settle_sounds.tres` maps an arm to the sound it settles into GARRISON with: the infantry's Equip. The chainmail single step (384890) is kept in `source/` unused.
