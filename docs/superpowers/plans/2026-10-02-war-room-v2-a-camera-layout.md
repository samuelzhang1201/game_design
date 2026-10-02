# WAR ROOM v2 — A: camera and layout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The WAR ROOM turns all the way round like the 3D map, widens over the left column (the report rolls up and unrolls only for a regiment's card), and a Missive board on an easel can be flown to, read and clicked.

**Architecture:** `WarCamera` (pure) gains free yaw, pitch by distance, wall clearance and the north ease; `WarRoomGestures` and `WarRoomView._gui_input` take the 3D map's mouse and keys. `GameRoot` fits the room over the left column and the map; a `WarReportRoll` overlay draws the report rolling up / down from a capture of it; the screen BORROWS the column's `MapDetailPanel` into its own `%CardRoll` while a piece is picked. The board is a quad in the room whose texture is a SubViewport holding a `MissiveScreen` in board-only mode; `WarBoard` (pure) does the panel hit, the board pose and the flight; clicks are pushed into the SubViewport as real input.

**Tech Stack:** Godot 4.7, typed GDScript, GUT, `tools/snapshot_screen.gd`.

**Spec:** `docs/superpowers/specs/2026-10-02-war-room-v2-design.md` (§1; §0 rulings 1–5). Read it, and the 2026-10-01 spec's §1 and §3 for what the room is today.

This is plan A of four (A camera and layout → B graticule and scale → C Deploy → D art). B, C and D get their own plans once the one before has landed.

## Global Constraints

- Every design value lives in `data/balance.csv` (key,value,notes), never a literal in a script; notes start `WAR ROOM v2 (owner 2026-10-02, spec §…)`.
- `scripts/war_room/` never names the `Game` autoload (`tests/war_room/test_war_room_isolation.gd` scans it). Only `scripts/ui/` touches `Game`.
- Typed GDScript everywhere (vars, params, returns).
- Every UI flow is checked through REAL input (`tools/snapshot_screen.gd`'s `_real_click` / `_real_drag`), never by calling internals (memory: verify-ui-through-real-input).
- A headless run cannot render 3D: never run a 3D snapshot with `--headless` (it hangs). GUT tests run headless and must not need a render (no `get_texture().get_image()` there).
- The suite must end with the expected error count: `./run_tests.sh` prints it; in this worktree the gdai plugin binaries are absent, so expect `Errors 0`.
- Never switch branches in `/Users/samuelzhang/game_design` (shared checkout). Work only in `.claude/worktrees/war-room-v2` on `design/war-room-v2`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A right DRAG must never open the order menu** and a right CLICK on a piece must still open it — pin: Task 2 tests both.
2. **Panning must follow the pointer at every yaw** (at 180° a drag right must still move the table right on screen) — pin: Task 1 `pan_view` at 90° and 180°.
3. **The council's talk box keeps WASD**: typing "was" in the right column must not pan the room — pin: Task 2 test with a focused LineEdit.
4. **Closing the room with a card shown gives the detail panel back to the column** — the court's own card clicks must still land in the column afterwards — pin: Task 5 test.
5. **The board's clicks never leak into the room** (a click on a note must not also pick a piece or pan) and Escape in board view returns to the table rather than opening the pause menu — pin: Task 8 tests.

---

### Task 0: Worktree setup and a green baseline

**Files:** none committed.

- [ ] **Step 1: Bring the git-ignored assets over** (memory: worktree-needs-ignored-assets)

```bash
cd /Users/samuelzhang/game_design/.claude/worktrees/war-room-v2
cp -Rc /Users/samuelzhang/game_design/.godot ./.godot
mkdir -p assets/3D/terrain
for d in beria textures trees; do ln -s /Users/samuelzhang/game_design/assets/3D/terrain/$d assets/3D/terrain/$d; done
(cd /Users/samuelzhang/game_design && git ls-files --others --ignored --exclude-standard assets/3D | grep -v model_wip | grep -v '^assets/3D/terrain/') > /tmp/wr_ignored.txt
while IFS= read -r f; do mkdir -p "$(dirname "$f")"; cp -c "/Users/samuelzhang/game_design/$f" "$f"; done < /tmp/wr_ignored.txt
```

- [ ] **Step 2: Run the war room tests as a baseline**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/war_room,res://tests/ui -ginclude_subdirs -gprefix=test_war \
  -gpre_run_script=res://tests/pre_run.gd -gexit 2>&1 | tail -15
```
Expected: all pass. If any fail here, stop and report — they are not this plan's to fix.

---

### Task 1: `WarCamera` turns all the way round, pitches by distance, keeps inside the walls, eases north

**Files:**
- Modify: `scripts/war_room/war_camera.gd` (rewrite)
- Modify: `data/balance.csv` (remove `war_cam_pitch_deg`, `war_cam_yaw_max_deg`; add keys below)
- Modify: `scripts/war_room/war_room_view.gd:84-93` (`bind`)
- Modify: `tests/war_room/test_war_camera.gd` (rewrite)
- Modify: `tests/engine/test_war_room_data.gd:16-18` (key list)

**Interfaces:**
- Produces: `WarCamera` with `var target: Vector3`, `var distance: float`, `var yaw_deg: float`, `var min_distance`, `var max_distance`, `var pitch_near_deg`, `var pitch_far_deg`, `var bounds: Rect2`, `var room: Rect2`; `func pitch_deg() -> float`, `func transform() -> Transform3D`, `func clear_distance() -> float`, `func zoom_about(ground: Vector3, factor: float) -> void`, `func pan(delta_xz: Vector2) -> void`, `func pan_view(delta: Vector2) -> void`, `func turn(delta_deg: float) -> void`, `func start_north() -> void`, `func step(delta: float, seconds: float) -> bool`, `func easing() -> bool`.

- [ ] **Step 1: Write the failing tests** — replace `tests/war_room/test_war_camera.gd` with:

```gdscript
extends GutTest
## The officer's view over the table (spec 2026-10-02-war-room-v2 §1.1): it
## turns all the way round, its pitch follows the distance, it stays inside
## the room, and the compass eases it back to the sheet's foot.

func _cam() -> WarCamera:
	var c := WarCamera.new()
	c.distance = 1.6
	c.min_distance = 0.12
	c.max_distance = 2.4
	c.pitch_near_deg = 30.0
	c.pitch_far_deg = 55.0
	c.bounds = Rect2(-0.7, -0.5, 1.4, 1.0)
	return c


func test_pitch_follows_the_distance_on_a_log_scale() -> void:
	var c := _cam()
	c.distance = 0.12
	assert_almost_eq(c.pitch_deg(), 30.0, 0.0001, "closest: oblique")
	c.distance = 2.4
	assert_almost_eq(c.pitch_deg(), 55.0, 0.0001, "farthest: overhead")
	c.distance = 1.6
	# t = ln(1.6/0.12) / ln(2.4/0.12) = 2.5903 / 2.9957 = 0.86467
	assert_almost_eq(c.pitch_deg(), 51.617, 0.01)


func test_the_camera_looks_at_its_target_from_the_south_at_yaw_zero() -> void:
	var c := _cam()
	var t := c.transform()
	var p := deg_to_rad(c.pitch_deg())
	assert_almost_eq(t.origin.y, 1.6 * sin(p), 0.0001)
	assert_almost_eq(t.origin.z, 1.6 * cos(p), 0.0001)
	assert_almost_eq(t.origin.x, 0.0, 0.0001)
	assert_almost_eq((-t.basis.z).normalized().dot((c.target - t.origin).normalized()), 1.0, 0.0001)


func test_turn_wraps_through_a_full_circle() -> void:
	var c := _cam()
	c.turn(200.0)
	assert_almost_eq(c.yaw_deg, -160.0, 0.0001)
	c.turn(-40.0)
	assert_almost_eq(c.yaw_deg, 160.0, 0.0001)
	var t := c.transform()
	assert_lt(t.origin.z, 0.0, "at 160 deg the camera stands north of the table")


func test_pan_view_follows_the_pointer_at_every_yaw() -> void:
	var c := _cam()
	c.pan_view(Vector2(0.1, 0.0))
	assert_almost_eq(c.target.x, 0.1, 0.0001, "yaw 0: screen right is +x")
	c.target = Vector3.ZERO
	c.yaw_deg = 90.0
	c.pan_view(Vector2(0.1, 0.0))
	assert_almost_eq(c.target.z, -0.1, 0.0001, "yaw 90: screen right is -z")
	assert_almost_eq(c.target.x, 0.0, 0.0001)
	c.target = Vector3.ZERO
	c.yaw_deg = 180.0
	c.pan_view(Vector2(0.1, 0.2))
	assert_almost_eq(c.target.x, -0.1, 0.0001, "yaw 180: screen right is -x")
	assert_almost_eq(c.target.z, -0.2, 0.0001, "yaw 180: screen down is -z")


func test_pan_stays_on_the_table() -> void:
	var c := _cam()
	c.pan(Vector2(5.0, 5.0))
	assert_almost_eq(c.target.x, 0.7, 0.0001)
	assert_almost_eq(c.target.z, 0.5, 0.0001)


func test_zoom_about_a_ground_point_keeps_it_under_the_pointer_direction() -> void:
	var c := _cam()
	var ground := Vector3(0.4, 0.0, 0.2)
	c.zoom_about(ground, 0.5)
	assert_almost_eq(c.distance, 0.8, 0.0001)
	assert_almost_eq(c.target.x, 0.2, 0.0001, "the target walks half way to the point")
	c.zoom_about(ground, 0.01)
	assert_almost_eq(c.distance, 0.12, 0.0001, "held at the closest lean")


func test_the_camera_is_kept_inside_the_room() -> void:
	var c := _cam()
	c.room = Rect2(-1.0, -1.0, 2.0, 2.0)
	c.distance = 2.4   # horizontal reach 2.4 * cos 55 = 1.377 > 1
	var d := c.clear_distance()
	assert_lt(d, 2.4, "shortened")
	var o := c.transform().origin
	assert_almost_eq(o.z, 1.0, 0.001, "stands at the wall")
	c.room = Rect2()
	assert_almost_eq(c.clear_distance(), 2.4, 0.0001, "no room, no walls")


func test_the_compass_eases_the_yaw_back_to_zero() -> void:
	var c := _cam()
	c.yaw_deg = 120.0
	c.start_north()
	assert_true(c.easing())
	assert_true(c.step(0.2, 0.4))
	assert_almost_eq(c.yaw_deg, 60.0, 0.0001, "half way: smoothstep(0.5) = 0.5")
	assert_true(c.step(0.2, 0.4))
	assert_almost_eq(c.yaw_deg, 0.0, 0.0001)
	assert_false(c.easing())
	assert_false(c.step(0.2, 0.4), "nothing to ease")


func test_a_turn_cancels_the_ease() -> void:
	var c := _cam()
	c.yaw_deg = 90.0
	c.start_north()
	c.turn(10.0)
	assert_false(c.easing())
```

- [ ] **Step 2: Run the tests to see them fail**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/war_room/test_war_camera.gd -gpre_run_script=res://tests/pre_run.gd -gexit 2>&1 | tail -20
```
Expected: FAIL (`pitch_near_deg`, `pan_view`, `room`, `start_north` … do not exist).

- [ ] **Step 3: Rewrite `scripts/war_room/war_camera.gd`**

```gdscript
class_name WarCamera
extends RefCounted
## The officer's view over the plotting table (spec 2026-10-02-war-room-v2
## §1.1, after the 3D map): an orbit about a point on the table that turns all
## the way round, its pitch following the distance — oblique close in,
## overhead stepped back (Map3DGeometry.pitch_for's log scale) — and kept
## inside the room's walls. The compass eases it back to the sheet's foot.

var target := Vector3.ZERO
var distance := 1.6
var yaw_deg := 0.0
var min_distance := 0.12
var max_distance := 2.4
var pitch_near_deg := 30.0
var pitch_far_deg := 55.0
var bounds := Rect2(-0.7, -0.5, 1.4, 1.0)
## The floor the camera may stand over (x, z), the walls less their clearance;
## an empty rect keeps no walls.
var room := Rect2()
var _north_from := 0.0
var _north_t := -1.0


func pitch_deg() -> float:
	return _pitch_at(distance)


func _pitch_at(d: float) -> float:
	return Map3DGeometry.pitch_for(d, min_distance, max_distance, pitch_near_deg, pitch_far_deg)


func _back(d: float) -> Vector3:
	var p := deg_to_rad(_pitch_at(d))
	var y := deg_to_rad(yaw_deg)
	return Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * d


func transform() -> Transform3D:
	var origin := target + _back(clear_distance())
	return Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)


## The distance actually drawn: `distance`, shortened until the camera stands
## over `room` (a bisection: the pitch moves with the distance).
func clear_distance() -> float:
	if room.size == Vector2.ZERO or _inside(distance):
		return distance
	var lo := min_distance
	var hi := distance
	for i in 24:
		var mid := (lo + hi) * 0.5
		if _inside(mid):
			lo = mid
		else:
			hi = mid
	return lo


func _inside(d: float) -> bool:
	var o := target + _back(d)
	return o.x >= room.position.x and o.x <= room.end.x and o.z >= room.position.y and o.z <= room.end.y


## Lean toward (factor < 1) or back from `ground`: the distance scales and the
## target walks the same share toward the point, so the point holds its bearing.
func zoom_about(ground: Vector3, factor: float) -> void:
	var d := clampf(distance * factor, min_distance, max_distance)
	var share := 1.0 - d / distance
	target = target.lerp(Vector3(ground.x, target.y, ground.z), share)
	distance = d
	_clamp()


## Move the target by a table-plane delta (world x, z).
func pan(delta_xz: Vector2) -> void:
	target += Vector3(delta_xz.x, 0.0, delta_xz.y)
	_clamp()


## Move the target by a delta in SCREEN directions (x right, y down), turned
## by the yaw, so a drag follows the pointer however the room is turned.
func pan_view(delta: Vector2) -> void:
	var y := deg_to_rad(yaw_deg)
	pan(Vector2(cos(y), -sin(y)) * delta.x + Vector2(sin(y), cos(y)) * delta.y)


func turn(delta_deg: float) -> void:
	_north_t = -1.0
	yaw_deg = wrapf(yaw_deg + delta_deg, -180.0, 180.0)


func start_north() -> void:
	_north_from = yaw_deg
	_north_t = 0.0


func easing() -> bool:
	return _north_t >= 0.0


## One frame of the ease back to yaw 0 over `seconds`; true when it moved.
func step(delta: float, seconds: float) -> bool:
	if _north_t < 0.0:
		return false
	_north_t += delta / maxf(seconds, 0.01)
	yaw_deg = Map3DGeometry.ease_yaw(_north_from, _north_t)
	if _north_t >= 1.0:
		_north_t = -1.0
		yaw_deg = 0.0
	return true


func _clamp() -> void:
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
```

- [ ] **Step 4: Balance keys.** In `data/balance.csv` delete the rows `war_cam_pitch_deg` and `war_cam_yaw_max_deg` and add after `war_cam_zoom_step`:

```csv
war_cam_pitch_near_deg,30,"WAR ROOM v2 (owner 2026-10-02, spec §1.1): the look down at the closest lean, degrees — oblique, as the 3D map near"
war_cam_pitch_far_deg,55,"WAR ROOM v2 (owner 2026-10-02, spec §1.1): the look down stepped right back; log-scaled between the two by distance, ~52 at the opening 1.6 m as before"
war_cam_turn_deg_per_px,0.25,"WAR ROOM v2 (owner 2026-10-02, spec §1.1): a right drag turns the room this many degrees per design px (the 3D map's map3d_rotate_deg_per_px)"
war_cam_north_s,0.4,"WAR ROOM v2 (owner 2026-10-02, spec §1.1): seconds the key's compass takes to ease the room back to the sheet's foot"
war_cam_wall_clear_m,0.35,"WAR ROOM v2 (owner 2026-10-02, spec §1.1): the camera keeps this far inside the room's walls; nearer, its distance is shortened"
war_room_floor_x_m,3.0,"WAR ROOM v2 (spec §1.1): the room's half width (x), metres — assets/3D/war_room/room is x ±3"
war_room_floor_z_min_m,-2.0,"WAR ROOM v2 (spec §1.1): the room's north wall (z), metres"
war_room_floor_z_max_m,3.0,"WAR ROOM v2 (spec §1.1): the room's south wall (z), metres"
```

- [ ] **Step 5: Bind them** — in `scripts/war_room/war_room_view.gd` `bind()`, replace the two lines

```gdscript
	_rig.pitch_deg = repo.bal("war_cam_pitch_deg")
	...
	_rig.yaw_max = repo.bal("war_cam_yaw_max_deg")
```
with
```gdscript
	_rig.pitch_near_deg = repo.bal("war_cam_pitch_near_deg")
	_rig.pitch_far_deg = repo.bal("war_cam_pitch_far_deg")
	var clear := repo.bal("war_cam_wall_clear_m")
	var half := repo.bal("war_room_floor_x_m") - clear
	var z0 := repo.bal("war_room_floor_z_min_m") + clear
	_rig.room = Rect2(-half, z0, half * 2.0, repo.bal("war_room_floor_z_max_m") - clear - z0)
```

- [ ] **Step 6: Update the data test's key list** — in `tests/engine/test_war_room_data.gd` replace `"war_cam_pitch_deg",` and `"war_cam_yaw_max_deg",` with `"war_cam_pitch_near_deg", "war_cam_pitch_far_deg", "war_cam_turn_deg_per_px", "war_cam_north_s", "war_cam_wall_clear_m", "war_room_floor_x_m", "war_room_floor_z_min_m", "war_room_floor_z_max_m",`.

- [ ] **Step 7: Run the tests**

Run the Step 2 command, then the same with `-gtest=res://tests/engine/test_war_room_data.gd`, then `-gdir=res://tests/war_room -ginclude_subdirs`.
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/war_room/war_camera.gd scripts/war_room/war_room_view.gd data/balance.csv tests/war_room/test_war_camera.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war-room): the room turns all the way round, pitches by distance, keeps inside its walls

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The 3D map's mouse and keys in the room

**Files:**
- Modify: `scripts/war_room/war_room_gestures.gd` (rewrite)
- Modify: `scripts/war_room/war_room_rake.gd` (add `empty_press()`)
- Modify: `scripts/war_room/war_room_view.gd` (`_gui_input`, `_process`, `key_pan`)
- Modify: `data/balance.csv` (add `war_key_pan_screens_per_s`, `war_click_slop_px`)
- Test: `tests/war_room/test_war_room_gestures.gd` (create)

**Interfaces:**
- Consumes: Task 1's `WarCamera.turn`, `pan_view`, `zoom_about`, `step`, `easing`.
- Produces: `WarRoomGestures` (RefCounted, an INSTANCE now: it holds the right button's press) with `func handle(event: InputEvent, rig: WarCamera, repo: DataRepository, ground_at: Callable, left_pans: bool) -> int` returning `WarRoomGestures.NONE`, `MOVED` or `RIGHT_CLICK`; `static func key_dir() -> Vector2`. `WarRoomRake.empty_press() -> bool`. `WarRoomView.key_pan(delta: float) -> bool`.

- [ ] **Step 1: Write the failing tests** — create `tests/war_room/test_war_room_gestures.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The room takes the 3D map's mouse (spec 2026-10-02-war-room-v2 §1.1): a
## right drag turns and never opens a menu, a right click does, a left drag on
## open table pans in screen directions, the wheel leans about the pointer.

var repo: DataRepository
var rig: WarCamera
var g: WarRoomGestures


func before_each() -> void:
	repo = SuiteData.repo()
	rig = WarCamera.new()
	rig.bounds = Rect2(-0.7, -0.5, 1.4, 1.0)
	g = WarRoomGestures.new()


func _ground(_p: Vector2) -> Vector3:
	return Vector3.ZERO


func _button(index: MouseButton, down: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = down
	e.position = at
	return e


func _motion(mask: int, at: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.button_mask = mask
	e.position = at
	e.relative = rel
	return e


func test_a_right_drag_turns_and_its_release_is_not_a_click() -> void:
	assert_eq(g.handle(_button(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100)), rig, repo, _ground, false), WarRoomGestures.NONE)
	assert_eq(g.handle(_motion(MOUSE_BUTTON_MASK_RIGHT, Vector2(140, 100), Vector2(40, 0)), rig, repo, _ground, false), WarRoomGestures.MOVED)
	assert_almost_eq(rig.yaw_deg, -40.0 * repo.bal("war_cam_turn_deg_per_px"), 0.0001, "the 3D map's sign: yaw -= dx * rate")
	assert_eq(g.handle(_button(MOUSE_BUTTON_RIGHT, false, Vector2(140, 100)), rig, repo, _ground, false), WarRoomGestures.NONE)


func test_a_right_click_is_reported() -> void:
	g.handle(_button(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100)), rig, repo, _ground, false)
	assert_eq(g.handle(_button(MOUSE_BUTTON_RIGHT, false, Vector2(101, 100)), rig, repo, _ground, false), WarRoomGestures.RIGHT_CLICK)


func test_a_left_drag_pans_only_when_allowed() -> void:
	var rel := Vector2(10, 0)
	assert_eq(g.handle(_motion(MOUSE_BUTTON_MASK_LEFT, Vector2(110, 0), rel), rig, repo, _ground, false), WarRoomGestures.NONE)
	assert_eq(rig.target, Vector3.ZERO)
	assert_eq(g.handle(_motion(MOUSE_BUTTON_MASK_LEFT, Vector2(110, 0), rel), rig, repo, _ground, true), WarRoomGestures.MOVED)
	assert_almost_eq(rig.target.x, -10.0 * rig.distance * repo.bal("war_pan_drag_speed"), 0.00001, "the table follows the pointer")


func test_the_wheel_leans_in() -> void:
	var d := rig.distance
	assert_eq(g.handle(_button(MOUSE_BUTTON_WHEEL_UP, true, Vector2.ZERO), rig, repo, _ground, false), WarRoomGestures.MOVED)
	assert_lt(rig.distance, d)
```

Add to `tests/war_room/test_war_room_view.gd` (it already lays a 1000×600 view):

```gdscript
func test_wasd_does_not_pan_while_a_text_box_has_focus() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var box := LineEdit.new()
	add_child_autofree(box)
	var before := view.camera_rig().target
	Input.parse_input_event(_key(KEY_A, true))
	assert_true(view.key_pan(0.1), "A pans the room")
	box.grab_focus()
	var moved := view.camera_rig().target
	assert_false(view.key_pan(0.1), "the talk box keeps its keys")
	Input.parse_input_event(_key(KEY_A, false))
	assert_ne(moved, before)
	assert_eq(view.camera_rig().target, moved)


func _key(code: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	return e
```

- [ ] **Step 2: Run to see them fail**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/war_room/test_war_room_gestures.gd -gpre_run_script=res://tests/pre_run.gd -gexit 2>&1 | tail -20
```
Expected: FAIL (`handle`, `NONE`, `key_pan` missing).

- [ ] **Step 3: Rewrite `scripts/war_room/war_room_gestures.gd`**

```gdscript
class_name WarRoomGestures
extends RefCounted
## The room camera's gestures (spec 2026-10-02-war-room-v2 §1.1), the 3D map's
## (Map3DInput): a right DRAG turns, a right CLICK is reported for the order
## menu, a left drag on open table pans (the view says when: a press on a piece
## is the rake's), the middle button and a two-finger drag pan, the wheel and a
## pinch lean about the pointer, WASD / arrows pan. Moves the rig; the view
## applies it to the camera.

enum { NONE, MOVED, RIGHT_CLICK }

var _rpress := Vector2.ZERO
var _rdragged := false


func handle(event: InputEvent, rig: WarCamera, repo: DataRepository, ground_at: Callable, left_pans: bool) -> int:
	var slop := repo.bal("war_click_slop_px")
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := repo.bal("war_cam_zoom_step")
			rig.zoom_about(ground_at.call(mb.position), 1.0 / step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else step)
			return MOVED
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rpress = mb.position
				_rdragged = false
				return NONE
			if not _rdragged and mb.position.distance_to(_rpress) <= slop:
				return RIGHT_CLICK
			return NONE
		return NONE
	if event is InputEventMagnifyGesture:
		var gm := event as InputEventMagnifyGesture
		rig.zoom_about(ground_at.call(gm.position), 1.0 / maxf(gm.factor, 0.01))
		return MOVED
	if event is InputEventPanGesture:
		rig.pan_view((event as InputEventPanGesture).delta * rig.distance * repo.bal("war_pan_gesture_speed"))
		return MOVED
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			if mm.position.distance_to(_rpress) > slop:
				_rdragged = true
			rig.turn(-mm.relative.x * repo.bal("war_cam_turn_deg_per_px"))
			return MOVED
		if (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE) or (left_pans and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT)):
			rig.pan_view(-mm.relative * rig.distance * repo.bal("war_pan_drag_speed"))
			return MOVED
	return NONE


## The keys held now as a screen direction (x right, y down), unit or zero.
static func key_dir() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	return dir.normalized()
```

- [ ] **Step 4: `WarRoomRake.empty_press()`** — append to `scripts/war_room/war_room_rake.gd`:

```gdscript
## A left press on open table with nothing in hand and no march armed: a drag
## from it pans the room (spec 2026-10-02-war-room-v2 §1.1), as on the 3D map.
func empty_press() -> bool:
	return _pressed and _press_code == "" and code == "" and not _view.aiming
```

- [ ] **Step 5: The view takes them** — in `scripts/war_room/war_room_view.gd`:

Add a field next to `_rake`: `var _gestures := WarRoomGestures.new()`.

Replace `_gui_input` with:

```gdscript
func _gui_input(event: InputEvent) -> void:
	if _sheet < 0:
		return
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_rake.on_left(mb)
	elif mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) and _rake.empty_press():
		pass   # an open-table drag: the gestures pan below
	elif mm != null and not (mm.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)):
		_rake.on_motion(mm)
	var did := _gestures.handle(event, _rig, _repo, _ground_under, _rake.empty_press())
	if did == WarRoomGestures.RIGHT_CLICK:
		var code := piece_under(mb.position)
		if code != "":
			army_menu_requested.emit(code, mb.position)
		accept_event()
	elif did == WarRoomGestures.MOVED:
		_apply_camera()
		accept_event()
```

(`_rake.on_left` keeps its own `accept_event()` calls for clicks; a left drag that panned is released with `moved` true and no piece, which `on_left` already ignores.)

Add after `_process`'s swap handling — replace the whole `_process` with:

```gdscript
func _process(delta: float) -> void:
	if _rig.step(delta, _repo.bal("war_cam_north_s")) or key_pan(delta):
		_apply_camera()
	if not _swap.active():
		return
	if _swap.step(delta):
		lay_sheet(_swap.to)
	_table.scale = Vector3(1.0, 1.0, _swap.z_scale())
	_pieces.visible = not _swap.active()
	_pennants.visible = _pieces.visible


## WASD / arrows pan the room (spec 2026-10-02-war-room-v2 §1.1), never while
## a text box (the council's talk box) has the focus; true when it moved.
func key_pan(delta: float) -> bool:
	if _sheet < 0 or not is_visible_in_tree():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false
	var dir := WarRoomGestures.key_dir()
	if dir == Vector2.ZERO:
		return false
	_rig.pan_view(dir * _rig.distance * _repo.bal("war_key_pan_screens_per_s") * delta)
	return true
```

Balance rows (after `war_pan_gesture_speed`):

```csv
war_key_pan_screens_per_s,0.7,"WAR ROOM v2 (owner 2026-10-02, spec §1.1): WASD / arrows pan this many camera-distances a second (the 3D map's map3d_key_pan_screens_per_s)"
war_click_slop_px,10,"WAR ROOM v2 (spec §1.1): a right press and release further apart than this, or one that turned the room, is a drag, not a click (Map3DInput.CLICK_SLOP)"
```

Add `"war_key_pan_screens_per_s", "war_click_slop_px",` to `tests/engine/test_war_room_data.gd`'s key list.

- [ ] **Step 6: Run the tests**

Run the Step 2 command, then `-gdir=res://tests/war_room -ginclude_subdirs` and `-gtest=res://tests/ui/test_war_room_screen.gd`.
Expected: all PASS.

- [ ] **Step 7: Look at it** — a right drag, through the real window (NOT headless):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- \
  --screen root --quiet --war-room --out /tmp/wr_a_open.png
```
Open the shot; the room opens as before (Task 9 adds `--war-turn`). Then run the game (`/Applications/Godot.app/Contents/MacOS/Godot --path .`), open WAR ROOM, right-drag left and right, left-drag on open table, WASD, wheel: the table must move the same way as the 3D map does for the same gesture. If a right drag turns the OPPOSITE way to the map, flip the sign in `handle` and the test's expected value together.

- [ ] **Step 8: Commit**

```bash
git add scripts/war_room/war_room_gestures.gd scripts/war_room/war_room_rake.gd scripts/war_room/war_room_view.gd data/balance.csv tests/war_room/test_war_room_gestures.gd tests/war_room/test_war_room_view.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war-room): the 3D map's mouse and keys — right drag turns, left drag pans, WASD

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The key's compass turns the room back to the sheet's foot

**Files:**
- Modify: `scripts/ui/war_margin_key.gd` (`setup`, add `_has_point`, `_gui_input`, signal)
- Modify: `scripts/ui/war_room_screen.gd` (`open`: connect)
- Modify: `scripts/war_room/war_room_view.gd` (add `start_north()`)
- Test: `tests/ui/test_war_margin_key.gd` (add a test)

**Interfaces:**
- Consumes: `WarCamera.start_north()`.
- Produces: `WarMarginKey` signal `north_pressed`; `func rose_rect() -> Rect2`. `WarRoomView.start_north() -> void`.

- [ ] **Step 1: Failing test** — append to `tests/ui/test_war_margin_key.gd`:

```gdscript
func test_a_click_on_the_rose_asks_for_north_and_nowhere_else_is_taken() -> void:
	watch_signals(key)
	var r := key.rose_rect()
	assert_true(key._has_point(r.get_center()))
	assert_false(key._has_point(Vector2(r.end.x + 20.0, r.end.y + 20.0)), "the legend lets clicks through to the room")
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = r.get_center()
	key._gui_input(e)
	assert_signal_emitted(key, "north_pressed")
```

- [ ] **Step 2: Run** `-gtest=res://tests/ui/test_war_margin_key.gd` — Expected: FAIL (`rose_rect` missing).

- [ ] **Step 3: Implement** — in `scripts/ui/war_margin_key.gd` add at the top (after `extends`): `signal north_pressed`; in `setup` change `mouse_filter = Control.MOUSE_FILTER_IGNORE` to `mouse_filter = Control.MOUSE_FILTER_STOP` and set `tooltip_text = "Turn to the sheet's foot"`; add:

```gdscript
## The compass rose's box, this Control's px (the top-left square of
## war_key_rose_px, as _draw places it).
func rose_rect() -> Rect2:
	var rose := _repo.bal("war_key_rose_px") if _repo != null else 0.0
	return Rect2(Vector2.ZERO, Vector2(rose, rose))


## Only the rose takes a click; the legend and the bar let it through.
func _has_point(point: Vector2) -> bool:
	return rose_rect().has_point(point)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and rose_rect().has_point(mb.position):
		north_pressed.emit()
		accept_event()
```

The rose already turns with the yaw (`_draw_rose`); the view's `camera_moved` redraws it.

In `scripts/war_room/war_room_view.gd` add:

```gdscript
## The key's compass: ease the room back to the sheet's foot (yaw 0).
func start_north() -> void:
	_rig.start_north()
```

In `scripts/ui/war_room_screen.gd` `open()`, inside `if not _bound:` after the `camera_moved` connection: `(%Key as WarMarginKey).north_pressed.connect(_view.start_north)`.

- [ ] **Step 4: Run** the key test and `tests/ui/test_war_room_screen.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/war_margin_key.gd scripts/ui/war_room_screen.gd scripts/war_room/war_room_view.gd tests/ui/test_war_margin_key.gd
git commit -m "feat(war-room): the key's compass eases the room back to the sheet's foot

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The room widens over the left column; the report rolls up

**Files:**
- Create: `scripts/ui/war_table/war_report_roll.gd`
- Modify: `scripts/ui/court_screen.gd`, `scripts/ui/conversation_scene.gd` (add `left_column()`)
- Modify: `scripts/ui/game_root.gd` (`toggle_war_room`, `_fit_war_room`, a capture)
- Modify: `scripts/ui/war_room_screen.gd` (`open` takes the capture; `close` plays the unroll)
- Modify: `scripts/war_room/war_room_view.gd` (`hold_size`)
- Modify: `scenes/war_room/war_room.tscn` (`Display`: `expand_mode = 1`, `stretch_mode = 0`)
- Modify: `data/balance.csv` (`war_report_roll_s`, `war_report_roller_px`)
- Test: `tests/ui/test_war_room_screen.gd` (adjust the size assert, add tests), `tests/ui/test_war_report_roll.gd` (create)

**Interfaces:**
- Produces: `WarReportRoll` (Control) with `static func play(host: Node, rect: Rect2, capture: Texture2D, up: bool, seconds: float, roller_px: float, paper: bool) -> WarReportRoll` (adds itself to `host`, frees itself at the end); `func share() -> float` (0 rolled, 1 open — the visible share of the paper now). Screens: `func left_column() -> PanelContainer`. `GameRoot.war_room_rect() -> Rect2`. `WarRoomView.hold_size(on: bool) -> void`.

- [ ] **Step 1: Failing tests** — create `tests/ui/test_war_report_roll.gd`:

```gdscript
extends GutTest
## The steward's report rolls up when the WAR ROOM opens and down when it
## closes (spec 2026-10-02-war-room-v2 §1.2): an overlay that draws the share
## of the paper left and frees itself.

func test_rolling_up_goes_from_open_to_rolled_and_frees_itself() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var roll := WarReportRoll.play(host, Rect2(0, 0, 240, 600), null, true, 0.2, 12.0, true)
	assert_almost_eq(roll.share(), 1.0, 0.0001)
	await wait_seconds(0.1)
	assert_between(roll.share(), 0.05, 0.95)
	await wait_seconds(0.2)
	assert_false(is_instance_valid(roll), "freed when done")


func test_rolling_down_starts_rolled() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var roll := WarReportRoll.play(host, Rect2(0, 0, 240, 600), null, false, 0.2, 12.0, true)
	assert_almost_eq(roll.share(), 0.0, 0.0001)
	assert_eq(roll.mouse_filter, Control.MOUSE_FILTER_IGNORE)
```

In `tests/ui/test_war_room_screen.gd`, change `test_the_tab_lays_the_home_provinces_sheet_over_the_map`'s size assert to:

```gdscript
	var column: Control = r.current_screen.left_column()
	var wide := Rect2(column.global_position, Vector2(map.global_position.x + map.size.x - column.global_position.x, map.size.y))
	assert_eq(screen.size, wide.size, "the room runs from the column's left edge to the map's right edge")
	assert_eq(screen.position, Vector2(column.global_position.x, map.global_position.y))
```

and, in the same test, replace its `await wait_process_frames(3)` after the tab press with `await wait_seconds(Game.data.bal("war_report_roll_s") + 0.1)` (the room widens over that time). Add:

```gdscript
func test_closing_the_room_hands_the_column_its_place_back() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	r.war_room_screen().close()
	await wait_process_frames(1)
	assert_false(r.war_room_screen().visible)
	assert_true(r.current_screen.left_column().is_visible_in_tree())
```

- [ ] **Step 2: Run** `-gtest=res://tests/ui/test_war_report_roll.gd` and `-gtest=res://tests/ui/test_war_room_screen.gd`. Expected: FAIL (`WarReportRoll`, `left_column` missing).

- [ ] **Step 3: `WarReportRoll`** — create `scripts/ui/war_table/war_report_roll.gd`:

```gdscript
class_name WarReportRoll
extends Control
## The steward's report rolling up as the WAR ROOM opens over its column, and
## down again as it closes (spec 2026-10-02-war-room-v2 §1.2). An overlay laid
## on the column's rect: it draws the top share of a capture of the report
## (the paper as it lay) above a roller, the share eased from 1 to 0 (up) or 0
## to 1 (down), and frees itself. Without a capture (headless, or none taken)
## it draws the paper's own colour. Under the leather chrome (`paper` false)
## the same share slides the column up and fades it instead of rolling it.

var _capture: Texture2D
var _up := true
var _seconds := 0.4
var _roller := 12.0
var _paper := true
var _t := 0.0


static func play(host: Node, rect: Rect2, capture: Texture2D, up: bool, seconds: float,
		roller_px: float, paper: bool) -> WarReportRoll:
	var r := WarReportRoll.new()
	r.name = "WarReportRoll"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.top_level = true
	r.position = rect.position
	r.size = rect.size
	r._capture = capture
	r._up = up
	r._seconds = maxf(seconds, 0.01)
	r._roller = roller_px
	r._paper = paper
	host.add_child(r)
	return r


## The share of the paper showing now: 1 open, 0 rolled to its roller.
func share() -> float:
	var k := smoothstep(0.0, 1.0, clampf(_t / _seconds, 0.0, 1.0))
	return 1.0 - k if _up else k


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= _seconds:
		queue_free()


func _draw() -> void:
	var s := share()
	var h := (size.y - _roller) * s
	if _paper:
		var body := Rect2(0.0, 0.0, size.x, h)
		if _capture != null and h > 0.5:
			var src := Rect2(Vector2.ZERO, Vector2(_capture.get_width(), _capture.get_height() * h / size.y))
			draw_texture_rect_region(_capture, body, src)
		elif h > 0.5:
			draw_rect(body, UiPalette.ink("paper") if UiPalette.war_table() else UiPalette.PANEL_BG)
		_draw_roller(Rect2(0.0, h, size.x, _roller))
	else:
		var a := s
		var drop := (1.0 - s) * size.y * 0.25
		if _capture != null:
			draw_texture_rect(_capture, Rect2(0.0, -drop, size.x, size.y), false, Color(1, 1, 1, a))
		else:
			draw_rect(Rect2(0.0, -drop, size.x, size.y), Color(UiPalette.PANEL_BG, a))


## A wooden roller: a dark core, a lit band along its top, end caps.
func _draw_roller(r: Rect2) -> void:
	var wood := Color(0.36, 0.24, 0.14)
	draw_rect(r, wood)
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), wood.lightened(0.25))
	draw_rect(Rect2(r.position + Vector2(0.0, r.size.y * 0.8), Vector2(r.size.x, r.size.y * 0.2)), wood.darkened(0.4))
	var cap := Color(0.62, 0.48, 0.22)
	draw_rect(Rect2(r.position - Vector2(r.size.y * 0.3, 0.0), Vector2(r.size.y * 0.3, r.size.y)), cap)
	draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(r.size.y * 0.3, r.size.y)), cap)
```

Before writing, check `UiPalette.ink("paper")` exists (`grep -n "static func ink" scripts/ui/ui_palette.gd` and the keys it takes); if `"paper"` is not a key, use the war-table palette's paper row the same way `PaperStyle.make("paper", …)` reads its tint (`grep -n "tint_key" scripts/ui/war_table/paper_style.gd`).

Add to `data/balance.csv`:

```csv
war_report_roll_s,0.45,"WAR ROOM v2 (owner 2026-10-02, spec §1.2): seconds the steward's report takes to roll up as the room opens over its column, and down as it closes; the room widens over the same time"
war_report_roller_px,12,"WAR ROOM v2 (spec §1.2): the report's roller's thickness, design px"
```

and add both keys to `tests/engine/test_war_room_data.gd`'s list.

- [ ] **Step 4: Screens name their left column** — in `scripts/ui/court_screen.gd` next to `map_panel()`:

```gdscript
## The left column (the FACTS column, invariant 10): the WAR ROOM widens over it.
func left_column() -> PanelContainer:
	return %LogPanel
```

and in `scripts/ui/conversation_scene.gd` next to its `map_panel()`:

```gdscript
## The left column (the FACTS column, invariant 10): the WAR ROOM widens over it.
func left_column() -> PanelContainer:
	return %MinisterPanel
```

- [ ] **Step 5: The view can hold its viewport's size** — in `scripts/war_room/war_room_view.gd`:

```gdscript
var _hold_size := false


## While the room's rect animates, keep the SubViewport's size (the Display
## stretches); on release it is fitted once (spec §1.2: no reallocation a frame).
func hold_size(on: bool) -> void:
	_hold_size = on
	if not on:
		_fit_viewport()
```

and make `_fit_viewport` start with `if _hold_size: return`. In `scenes/war_room/war_room.tscn`, on the `Display` node add `expand_mode = 1` and `stretch_mode = 0` (ignore the texture's size; scale to the rect).

- [ ] **Step 6: GameRoot fits the wide rect and captures the report** — in `scripts/ui/game_root.gd`:

Replace `_fit_war_room` with:

```gdscript
func _fit_war_room() -> void:
	if current_screen == null or not current_screen.has_method("map_panel"):
		return
	var r := war_room_rect()
	if _war_room_tween != null and _war_room_tween.is_running():
		return   # the widening animation owns the rect until it ends
	_war_room_screen.position = r.position
	_war_room_screen.size = r.size

## The WAR ROOM's rect (spec 2026-10-02-war-room-v2 §1.2): from the left
## column's left edge to the map's right edge, the map's height; the map's own
## rect on a screen without a left column.
func war_room_rect() -> Rect2:
	var map: Control = current_screen.map_panel()
	var r := Rect2(map.global_position, map.size)
	if current_screen.has_method("left_column"):
		var col: Control = current_screen.left_column()
		r = Rect2(Vector2(col.global_position.x, map.global_position.y),
			Vector2(map.global_position.x + map.size.x - col.global_position.x, map.size.y))
	return r

## The left column as it is drawn now, for the report's roll (null headless,
## where nothing renders, or off the war table's paper).
func _capture_column() -> Texture2D:
	if DisplayServer.get_name() == "headless" or not current_screen.has_method("left_column"):
		return null
	var col: Control = current_screen.left_column()
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return null
	var k := get_viewport().get_final_transform().get_scale().x
	var px := Rect2i(Vector2i(col.global_position * k), Vector2i(col.size * k)).intersection(
		Rect2i(Vector2i.ZERO, img.get_size()))
	if px.size.x <= 0 or px.size.y <= 0:
		return null
	return ImageTexture.create_from_image(img.get_region(px))
```

Add the field `var _war_room_tween: Tween` beside `_war_room_screen`.

In `toggle_war_room`, replace the tail (from `_fit_war_room()` to the end) with:

```gdscript
	var capture := _capture_column()
	var wide := war_room_rect()
	var map_rect := Rect2(map.global_position, map.size)
	var map_view: Map3DView = current_screen.map3d_view() if current_screen.has_method("map3d_view") else null
	if map_view != null:
		map_view.deactivate()
	var map_orders := current_screen.find_child("ArmyOrders", true, false) as ArmyOrderMenu
	if map_orders != null:
		map_orders.withdraw_aim()
	var secs := Game.data.bal("war_report_roll_s")
	_war_room_screen.position = map_rect.position
	_war_room_screen.size = map_rect.size
	_war_room_screen.open(current_screen.detail_panel())
	if current_screen.has_method("left_column"):
		var col: Control = current_screen.left_column()
		WarReportRoll.play(self, Rect2(col.global_position, col.size), capture, true, secs,
			Game.data.bal("war_report_roller_px"), UiPalette.war_table())
		_war_room_screen.set_report_capture(capture, Rect2(col.global_position, col.size))
	_war_room_screen.view().hold_size(true)
	_war_room_tween = create_tween()
	_war_room_tween.tween_property(_war_room_screen, "position", wide.position, secs)
	_war_room_tween.parallel().tween_property(_war_room_screen, "size", wide.size, secs)
	_war_room_tween.finished.connect(func() -> void:
		_war_room_screen.view().hold_size(false)
		_fit_war_room())
```

(Keep the existing `map.item_rect_changed` connection lines above it. The `WarReportRoll` is GameRoot's child added AFTER the screen exists, so it draws over the room's left edge while the room slides under it.)

- [ ] **Step 7: The screen keeps the capture and unrolls it on close** — in `scripts/ui/war_room_screen.gd`:

```gdscript
var _capture: Texture2D
var _column_rect := Rect2()


## The report as it lay when the room opened, and where (GameRoot): closing
## unrolls it over the column again (spec §1.2).
func set_report_capture(capture: Texture2D, rect: Rect2) -> void:
	_capture = capture
	_column_rect = rect
```

and at the end of `close()` (after `closed.emit()`):

```gdscript
	if _column_rect.size.x > 0.0 and get_parent() != null:
		WarReportRoll.play(get_parent(), _column_rect, _capture, false,
			Game.data.bal("war_report_roll_s"), Game.data.bal("war_report_roller_px"), UiPalette.war_table())
	_capture = null
	_column_rect = Rect2()
```

- [ ] **Step 8: Run** `-gtest=res://tests/ui/test_war_report_roll.gd`, `-gtest=res://tests/ui/test_war_room_screen.gd`, then `-gdir=res://tests/ui -ginclude_subdirs`. Expected: PASS.

- [ ] **Step 9: Look at it** (real window):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- \
  --screen root --quiet --war-room --shot-frame 34 --out /tmp/wr_a_rolling.png
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- \
  --screen root --quiet --war-room --out /tmp/wr_a_wide.png
```
The first catches the roll mid-way (the report half rolled, a roller at its foot, the room sliding left under it); the second the room wide, no report. Check `--shot-frame`'s actual name in `tools/snapshot_screen.gd`'s argument list (`grep -n '"--shot' tools/snapshot_screen.gd`) and use what it is.

- [ ] **Step 10: Commit**

```bash
git add scripts/ui/war_table/war_report_roll.gd scripts/ui/court_screen.gd scripts/ui/conversation_scene.gd scripts/ui/game_root.gd scripts/ui/war_room_screen.gd scripts/war_room/war_room_view.gd scenes/war_room/war_room.tscn data/balance.csv tests/ui/test_war_report_roll.gd tests/ui/test_war_room_screen.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war-room): the room widens over the left column as the report rolls up

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: A picked piece unrolls its card over the room's left

**Files:**
- Modify: `scenes/war_room_screen.tscn` (add `%CardRoll` PanelContainer)
- Modify: `scripts/ui/war_room_screen.gd` (`_on_piece`, `_clear_card`, borrow / give back, margin step)
- Modify: `scripts/ui/map_detail_panel.gd` (add `content_height()`)
- Test: `tests/ui/test_war_room_screen.gd` (update the card test, add the give-back test)

**Interfaces:**
- Consumes: `war_report_roll_s`, `war_report_roller_px` (Task 4); `%CardRoll` draws its own roller (`_draw_card_roller`, below) in the report roller's colours.
- Produces: `WarRoomScreen.card_roll() -> PanelContainer`; `MapDetailPanel.content_height() -> float`.

- [ ] **Step 1: Failing tests** — in `tests/ui/test_war_room_screen.gd` replace `test_a_selected_piece_puts_its_card_in_the_left_column_and_closing_takes_it_away` with:

```gdscript
func test_a_picked_piece_unrolls_its_card_over_the_room_and_closing_gives_it_back() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	var home := detail.get_parent()
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	screen.view().piece_selected.emit(code)
	await wait_process_frames(1)
	var card := MapObjects.army_card(Game.data, code, Game.state)
	assert_eq(detail.get_parent(), screen.card_roll(), "the card is borrowed into the room's roll")
	assert_true(screen.card_roll().visible)
	assert_eq(detail.title_label().text, String(card["title"]))
	assert_gt(detail.stats_grid().get_child_count(), 0, "the stat rows are there")
	screen.close()
	assert_eq(detail.get_parent(), home, "given back to the column")
	assert_false(detail.has_content())


func test_clearing_the_pick_rolls_the_card_away_and_gives_it_back() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	var home := detail.get_parent()
	var code := String(WarRoom.pieces(Game.data, Game.state)[0]["code"])
	screen.view().piece_selected.emit(code)
	await wait_process_frames(1)
	screen.view().clear_selection()
	await wait_seconds(Game.data.bal("war_report_roll_s") + 0.1)
	assert_eq(detail.get_parent(), home)
	assert_false(screen.card_roll().visible)
```

- [ ] **Step 2: Run** `-gtest=res://tests/ui/test_war_room_screen.gd`. Expected: FAIL (`card_roll` missing).

- [ ] **Step 3: The scene** — in `scenes/war_room_screen.tscn` add, after the `Slip` node and before `KeySlip`:

```
[node name="CardRoll" type="PanelContainer" parent="."]
unique_name_in_owner = true
visible = false
clip_contents = true
layout_mode = 0
offset_left = 0.0
offset_top = 0.0
offset_right = 240.0
offset_bottom = 0.0
```

- [ ] **Step 4: `MapDetailPanel.content_height()`** — add to `scripts/ui/map_detail_panel.gd` near `has_content()`:

```gdscript
## The card's whole height with its body unscrolled: the pinned parts plus the
## scroll's content (the WAR ROOM's roll unrolls exactly this far).
func content_height() -> float:
	var h := get_combined_minimum_size().y
	if _scroll != null and _scroll.get_child_count() > 0:
		h += (_scroll.get_child(0) as Control).get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	return h
```

- [ ] **Step 5: Borrow, unroll, give back** — in `scripts/ui/war_room_screen.gd`:

Add fields:

```gdscript
var _home: Node                # the column the card was borrowed from
var _home_index := -1
var _roll_tween: Tween
```

In `_ready()` add:

```gdscript
	var roll: PanelContainer = %CardRoll
	if UiPalette.war_table():
		roll.add_theme_stylebox_override("panel", WarTable.report_style())
		WarTable.ink_column(roll)
	else:
		roll.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 24, "column"))
	roll.draw.connect(_draw_card_roller)
```

Add:

```gdscript
func card_roll() -> PanelContainer:
	return %CardRoll


## Unroll the card over the room's left, where the column was (spec §1.2): the
## column's MapDetailPanel is BORROWED into %CardRoll (same node, so its
## signals and the screen's references hold) and the roll grows to the card's
## height; the margin slip steps right of it.
func _unroll_card() -> void:
	var roll: PanelContainer = %CardRoll
	if _detail.get_parent() != roll:
		_home = _detail.get_parent()
		_home_index = _detail.get_index()
		_detail.reparent(roll, false)
		_detail.visible = true
		if not _detail.closed.is_connected(_view.clear_selection):
			_detail.closed.connect(_view.clear_selection)
	var top: float = %Slip.offset_top
	var full := minf(_detail.content_height() + 48.0, size.y - top - 16.0)
	roll.position = Vector2(16.0, top)
	roll.size = Vector2(ScreenLayout.LEFT_WIDTH, roll.size.y if roll.visible else 0.0)
	roll.visible = true
	%Slip.offset_left = 16.0 + ScreenLayout.LEFT_WIDTH + 12.0
	%Slip.offset_right = %Slip.offset_left + 236.0
	_tween_roll(full, func() -> void: pass)


func _roll_card_away() -> void:
	var roll: PanelContainer = %CardRoll
	if not roll.visible:
		_give_back()
		return
	_tween_roll(0.0, func() -> void:
		roll.visible = false
		_give_back())


func _tween_roll(to_h: float, done: Callable) -> void:
	if _roll_tween != null:
		_roll_tween.kill()
	_roll_tween = create_tween()
	_roll_tween.tween_property(%CardRoll, "size:y", to_h, Game.data.bal("war_report_roll_s") * 0.6)
	_roll_tween.finished.connect(done)


## The card back where it came from (the court's column), at its old place.
func _give_back() -> void:
	%Slip.offset_left = 16.0
	%Slip.offset_right = 252.0
	if _home == null or not is_instance_valid(_detail) or _detail.get_parent() == _home:
		_home = null
		return
	if _detail.closed.is_connected(_view.clear_selection):
		_detail.closed.disconnect(_view.clear_selection)
	_detail.reparent(_home, false)
	_home.move_child(_detail, _home_index)
	_home = null


## The roller at the roll's foot, like the report's (WarReportRoll).
func _draw_card_roller() -> void:
	var roll: PanelContainer = %CardRoll
	var px := Game.data.bal("war_report_roller_px")
	var r := Rect2(0.0, roll.size.y - px, roll.size.x, px)
	var wood := Color(0.36, 0.24, 0.14)
	roll.draw_rect(r, wood)
	roll.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), wood.lightened(0.25))
```

Replace `_on_piece` and `_clear_card`:

```gdscript
func _on_piece(code: String) -> void:
	if _detail == null or not is_instance_valid(_detail):
		return
	_detail.show_card(MapObjects.army_card(Game.data, code, Game.state))
	_card_mine = true
	_unroll_card()
	_folio.open_for(code)


func _clear_card() -> void:
	if _card_mine and _detail != null and is_instance_valid(_detail):
		_detail.show_entry({})
	_card_mine = false
	_roll_card_away()
```

In `close()`, the room is gone at once: after `_clear_card()` add `if _roll_tween != null: _roll_tween.kill()`, `%CardRoll.visible = false`, `_give_back()` (so the close test sees the panel home immediately).

- [ ] **Step 6: Run** `-gtest=res://tests/ui/test_war_room_screen.gd` and `-gdir=res://tests/ui -ginclude_subdirs`. Expected: PASS. Then run the court's own card tests to prove the given-back panel still works: `grep -ln "detail_panel()" tests/ui/*.gd` and run those files.

- [ ] **Step 7: Look at it** (real window):

```bash
CODE=$(grep -m1 -o '^[a-z_0-9]*' data/maps/beria/military/regiments.csv | sed -n 2p)
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- \
  --screen root --quiet --war-room --war-piece "$CODE" --out /tmp/wr_a_card.png
```
(Use the code `snapshot_screen` prints on its `war: pieces=` line if the CSV's first column is not the code.) The card hangs from a roller over the room's left; the slip of other-sheet regiments stands to its right; the folio is open in the middle.

- [ ] **Step 8: Commit**

```bash
git add scenes/war_room_screen.tscn scripts/ui/war_room_screen.gd scripts/ui/map_detail_panel.gd tests/ui/test_war_room_screen.gd
git commit -m "feat(war-room): a picked piece unrolls its card over the room's left

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `MissiveScreen` gains a board-only mode

**Files:**
- Modify: `scripts/ui/missive_screen.gd` (`board_only`, `note_chosen`)
- Test: `tests/ui/test_missive_board_only.gd` (create)

**Interfaces:**
- Produces: `MissiveScreen` `signal note_chosen(id: int)`; `func set_board_only(on: bool) -> void`; `func board_only() -> bool`. In board-only mode the desk, the close button and the dim are hidden, the frame fills the control, and a note's press emits `note_chosen(id)` instead of selecting.

- [ ] **Step 1: Failing test** — create `tests/ui/test_missive_board_only.gd`:

```gdscript
extends GutTest
## The Missive board as the WAR ROOM hangs it on its easel (spec
## 2026-10-02-war-room-v2 §1.3): the board alone, and a note's press is
## reported, not read.

func test_board_only_hides_the_desk_and_reports_a_note() -> void:
	Game.start_campaign(44)
	var m := MissiveLog.make("receipt", "credible", "A receipt", Game.state.absolute_day(), {}, [])
	MissiveLog.add(Game.state, m)
	var s: MissiveScreen = load("res://scenes/missive_screen.tscn").instantiate()
	add_child_autofree(s)
	s.set_board_only(true)
	s.visible = true
	await wait_process_frames(1)
	assert_false(s.get_node("%Desk").visible)
	assert_false(s.get_node("%Close").visible)
	watch_signals(s)
	var note := s.find_child("Note%d" % int(Game.state.missives.back()["id"]), true, false) as Button
	assert_not_null(note)
	note.pressed.emit()
	assert_signal_emitted_with_parameters(s, "note_chosen", [int(Game.state.missives.back()["id"])])
	assert_eq(s.selected(), -1, "the easel's board does not read the letter itself")
```

Before writing it, check `MissiveLog.make`'s and `MissiveLog.add`'s real signatures (`grep -n "static func make\|static func add" scripts/engine/missive_log.gd`) and call them exactly as they are.

- [ ] **Step 2: Run** `-gtest=res://tests/ui/test_missive_board_only.gd`. Expected: FAIL.

- [ ] **Step 3: Implement** — in `scripts/ui/missive_screen.gd`:

```gdscript
## A note's press on the WAR ROOM's easel (board-only mode): the room opens
## the letter on the full board; the easel's own board never reads it.
signal note_chosen(id: int)

var _board_only := false


## The board alone, filling this control, for the WAR ROOM's easel (spec
## 2026-10-02-war-room-v2 §1.3): no desk, no close, no dim.
func set_board_only(on: bool) -> void:
	_board_only = on
	%Desk.visible = not on
	%Close.visible = not on
	$Dim.visible = not on
	if on:
		%Frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()


func board_only() -> bool:
	return _board_only
```

In `_note`, change `b.pressed.connect(func() -> void: select(id))` to:

```gdscript
	b.pressed.connect(func() -> void:
		if _board_only:
			note_chosen.emit(id)
		else:
			select(id))
```

(If `Dim` is not reachable as `$Dim`, use `get_node("Dim")` — it is a direct child per `scenes/missive_screen.tscn`.)

- [ ] **Step 4: Run** the test and `-gtest=res://tests/ui/test_missive_screen.gd` (or whichever existing missive screen tests `ls tests/ui | grep -i missive` lists). Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/missive_screen.gd tests/ui/test_missive_board_only.gd
git commit -m "feat(missive): a board-only mode that reports a note, for the WAR ROOM's easel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `WarBoard` — the panel's hit, its pose, the flight (pure)

**Files:**
- Create: `scripts/war_room/war_board.gd`
- Test: `tests/war_room/test_war_board.gd`

**Interfaces:**
- Produces (all static): `WarBoard.uv_of(panel: Transform3D, size_m: Vector2, origin: Vector3, dir: Vector3) -> Vector2` — the hit in 0..1 (u right, v down) on the quad whose centre and facing (+Z) are `panel`, `Vector2(-1, -1)` on a miss; `WarBoard.pose(panel: Transform3D, distance: float, offset: Vector2) -> Transform3D` — the camera square in front of it, `offset` metres in the panel's plane (x right, y up); `WarBoard.fly(from: Transform3D, to: Transform3D, t: float) -> Transform3D` — smoothstep, origins lerped, bases slerped; `WarBoard.clamp_offset(offset: Vector2, size_m: Vector2) -> Vector2` — within half the panel.

- [ ] **Step 1: Failing tests** — create `tests/war_room/test_war_board.gd`:

```gdscript
extends GutTest
## The easel's panel (spec 2026-10-02-war-room-v2 §1.3): a ray's hit as a UV,
## the pose square in front of it, the flight there and back.

var panel := Transform3D(Basis.IDENTITY, Vector3(-2.0, 1.0, 0.0))   # facing +Z
var size := Vector2(1.2, 0.8)


func test_a_ray_through_the_centre_hits_uv_half() -> void:
	var uv := WarBoard.uv_of(panel, size, Vector3(-2.0, 1.0, 2.0), Vector3(0, 0, -1))
	assert_almost_eq(uv.x, 0.5, 0.0001)
	assert_almost_eq(uv.y, 0.5, 0.0001)


func test_the_top_left_corner_is_uv_zero_and_v_runs_down() -> void:
	var uv := WarBoard.uv_of(panel, size, Vector3(-2.6, 1.4, 2.0), Vector3(0, 0, -1))
	assert_almost_eq(uv.x, 0.0, 0.0001)
	assert_almost_eq(uv.y, 0.0, 0.0001)
	var low := WarBoard.uv_of(panel, size, Vector3(-2.0, 0.8, 2.0), Vector3(0, 0, -1))
	assert_almost_eq(low.y, 0.75, 0.0001, "0.2 m below the centre of a 0.8 m panel")


func test_a_miss_and_a_ray_from_behind() -> void:
	assert_eq(WarBoard.uv_of(panel, size, Vector3(0.0, 1.0, 2.0), Vector3(0, 0, -1)), Vector2(-1, -1), "beside it")
	assert_eq(WarBoard.uv_of(panel, size, Vector3(-2.0, 1.0, 2.0), Vector3(0, 0, 1)), Vector2(-1, -1), "looking away")


func test_the_pose_stands_square_in_front() -> void:
	var t := WarBoard.pose(panel, 1.1, Vector2.ZERO)
	assert_almost_eq(t.origin.distance_to(Vector3(-2.0, 1.0, 1.1)), 0.0, 0.0001)
	assert_almost_eq((-t.basis.z).dot(Vector3(0, 0, -1)), 1.0, 0.0001, "looking straight at it")
	var shifted := WarBoard.pose(panel, 1.1, Vector2(0.2, 0.1))
	assert_almost_eq(shifted.origin.x, -1.8, 0.0001)
	assert_almost_eq(shifted.origin.y, 1.1, 0.0001)


func test_the_flight_eases_from_one_pose_to_the_other() -> void:
	var a := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var b := WarBoard.pose(panel, 1.1, Vector2.ZERO)
	assert_eq(WarBoard.fly(a, b, 0.0).origin, a.origin)
	assert_almost_eq(WarBoard.fly(a, b, 1.0).origin.distance_to(b.origin), 0.0, 0.0001)
	var mid := WarBoard.fly(a, b, 0.5).origin
	assert_almost_eq(mid.distance_to(a.origin.lerp(b.origin, 0.5)), 0.0, 0.0001, "smoothstep(0.5) = 0.5")


func test_the_offset_is_held_on_the_panel() -> void:
	assert_eq(WarBoard.clamp_offset(Vector2(5.0, -5.0), size), Vector2(0.6, -0.4))
```

- [ ] **Step 2: Run** `-gtest=res://tests/war_room/test_war_board.gd`. Expected: FAIL.

- [ ] **Step 3: Implement** — create `scripts/war_room/war_board.gd`:

```gdscript
class_name WarBoard
extends RefCounted
## The Missive board on its easel in the WAR ROOM (spec 2026-10-02-war-room-v2
## §1.3), pure: a ray's hit on the panel as a UV of the board's SubViewport
## (u right, v down), the camera's pose square in front of the panel, and the
## flight between two poses. The panel is a quad centred on `panel.origin`,
## facing its basis' +Z, `size_m` across and high.


static func uv_of(panel: Transform3D, size_m: Vector2, origin: Vector3, dir: Vector3) -> Vector2:
	var n := panel.basis.z.normalized()
	var denom := dir.dot(n)
	if denom >= -0.000001:
		return Vector2(-1, -1)   # parallel, or seen from behind
	var t := (panel.origin - origin).dot(n) / denom
	if t < 0.0:
		return Vector2(-1, -1)
	var local := panel.affine_inverse() * (origin + dir * t)
	var uv := Vector2(local.x / size_m.x + 0.5, 0.5 - local.y / size_m.y)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv


static func pose(panel: Transform3D, distance: float, offset: Vector2) -> Transform3D:
	var right := panel.basis.x.normalized()
	var up := panel.basis.y.normalized()
	var at := panel.origin + right * offset.x + up * offset.y
	var eye := at + panel.basis.z.normalized() * distance
	return Transform3D(Basis.looking_at(at - eye, up), eye)


static func fly(from: Transform3D, to: Transform3D, t: float) -> Transform3D:
	var k := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var q := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), k)
	return Transform3D(Basis(q), from.origin.lerp(to.origin, k))


static func clamp_offset(offset: Vector2, size_m: Vector2) -> Vector2:
	return Vector2(clampf(offset.x, -size_m.x * 0.5, size_m.x * 0.5), clampf(offset.y, -size_m.y * 0.5, size_m.y * 0.5))
```

- [ ] **Step 4: Run** the test. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/war_room/war_board.gd tests/war_room/test_war_board.gd
git commit -m "feat(war-room): WarBoard — the easel panel's hit, its pose and the flight

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The easel in the room — fly to it, read it, click a note

**Files:**
- Modify: `scenes/war_room/war_room.tscn` (add `Room/Easel` stand-in with `%BoardPanel`)
- Modify: `scripts/war_room/war_room_view.gd` (board mode)
- Modify: `scripts/ui/war_room_screen.gd` (the board's SubViewport and MissiveScreen; Escape; a note opens the board)
- Modify: `scripts/ui/game_root.gd` (`open_missive_over_war_room`, refresh on a new missive)
- Modify: `data/balance.csv` (`war_board_*`)
- Test: `tests/war_room/test_war_room_view.gd`, `tests/ui/test_war_room_screen.gd`

**Interfaces:**
- Consumes: `WarBoard.*` (Task 7), `MissiveScreen.set_board_only`, `note_chosen` (Task 6).
- Produces: `WarRoomRake.forget_press() -> void`, `empty_press_moved(at: Vector2) -> bool`; `WarRoomView` signals `board_entered`, `board_left`, `board_clicked(uv: Vector2, event: InputEventMouseButton)`, `board_hovered(uv: Vector2)`; `func set_board_texture(tex: Texture2D) -> void`, `func board_mode() -> String` (`"table"`, `"to_board"`, `"board"`, `"to_table"`), `func enter_board() -> void`, `func leave_board() -> void`, `func board_visible() -> bool`. `WarRoomScreen.board_screen() -> MissiveScreen`. `GameRoot.open_missive_over_war_room(id: int) -> void`.

- [ ] **Step 1: The stand-in easel in the scene** — in `scenes/war_room/war_room.tscn` add sub-resources and nodes (the easel west of the table, facing it; D replaces the frame with the modelled one):

```
[sub_resource type="QuadMesh" id="Quad_board"]
size = Vector2(1.2, 0.8)

[sub_resource type="StandardMaterial3D" id="Mat_board"]
albedo_color = Color(1, 1, 1, 1)
roughness = 0.85

[sub_resource type="BoxMesh" id="Box_easel_leg"]
size = Vector3(0.05, 1.7, 0.05)

[sub_resource type="StandardMaterial3D" id="Mat_easel"]
albedo_color = Color(0.36, 0.24, 0.14, 1)
roughness = 0.8
```

```
[node name="Easel" type="Node3D" parent="Viewport/Room"]
unique_name_in_owner = true
transform = Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, -2.1, -0.8, -0.2)

[node name="LegL" type="MeshInstance3D" parent="Viewport/Room/Easel"]
transform = Transform3D(0.996, 0.087, 0, -0.087, 0.996, 0, 0, 0, 1, -0.5, 0.85, -0.05)
mesh = SubResource("Box_easel_leg")
material_override = SubResource("Mat_easel")

[node name="LegR" type="MeshInstance3D" parent="Viewport/Room/Easel"]
transform = Transform3D(0.996, -0.087, 0, 0.087, 0.996, 0, 0, 0, 1, 0.5, 0.85, -0.05)
mesh = SubResource("Box_easel_leg")
material_override = SubResource("Mat_easel")

[node name="BoardPanel" type="MeshInstance3D" parent="Viewport/Room/Easel"]
unique_name_in_owner = true
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.45, 0.02)
mesh = SubResource("Quad_board")
material_override = SubResource("Mat_board")
```

(Bump the scene's `load_steps` by 4. The easel's local +Z faces east, toward the table; its feet stand on the floor at y −0.8. If the room's west wall or a candlestick is in the way in the shot of Step 9, move `Easel` along z only.)

- [ ] **Step 2: Failing view tests** — append to `tests/war_room/test_war_room_view.gd`:

```gdscript
func test_entering_the_board_flies_the_camera_square_in_front_of_it_and_back() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var before := (view.get_node("%Camera") as Camera3D).transform
	view.enter_board()
	assert_eq(view.board_mode(), "to_board")
	await wait_seconds(repo.bal("war_board_fly_s") + 0.15)
	assert_eq(view.board_mode(), "board")
	var cam := view.get_node("%Camera") as Camera3D
	var panel := (view.get_node("%BoardPanel") as Node3D).global_transform
	assert_almost_eq((-cam.global_transform.basis.z).dot(-panel.basis.z.normalized()), 1.0, 0.001, "square to the panel")
	view.leave_board()
	await wait_seconds(repo.bal("war_board_fly_s") + 0.15)
	assert_eq(view.board_mode(), "table")
	assert_almost_eq(cam.transform.origin.distance_to(before.origin), 0.0, 0.001, "back where it left")


func test_in_board_view_a_left_click_on_the_panel_is_the_boards_not_the_rooms() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	view.enter_board()
	await wait_seconds(repo.bal("war_board_fly_s") + 0.15)
	watch_signals(view)
	var at := view.size * 0.5   # the panel's centre is under the view's centre
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		view._gui_input(e)
	assert_signal_emitted(view, "board_clicked")
	assert_signal_not_emitted(view, "piece_selected")
	assert_signal_not_emitted(view, "selection_cleared")
```

- [ ] **Step 3: Run** `-gtest=res://tests/war_room/test_war_room_view.gd`. Expected: FAIL (`enter_board` missing).

- [ ] **Step 4: Balance keys** (add, and add each to `tests/engine/test_war_room_data.gd`'s list):

```csv
war_board_fly_s,0.7,"WAR ROOM v2 (owner 2026-10-02, spec §1.3): seconds the camera takes to fly from the table to the easel's board, and back"
war_board_distance_m,1.0,"WAR ROOM v2 (spec §1.3): the camera's opening distance square in front of the board, metres"
war_board_min_m,0.35,"WAR ROOM v2 (spec §1.3): closest lean to the board — a note's date reads"
war_board_max_m,1.4,"WAR ROOM v2 (spec §1.3): farthest step back from the board"
war_board_px,1600,"WAR ROOM v2 (spec §1.3): the board's SubViewport width, px; its height at the panel's 1.2 : 0.8"
```

- [ ] **Step 5: The view's board mode** — in `scripts/war_room/war_room_view.gd`:

```gdscript
signal board_entered
signal board_left
signal board_clicked(uv: Vector2, event: InputEventMouseButton)
signal board_hovered(uv: Vector2)

@onready var _board: MeshInstance3D = %BoardPanel

var _board_mode := "table"
var _fly_t := 0.0
var _fly_from := Transform3D()
var _table_pose := Transform3D()
var _board_dist := 1.0
var _board_offset := Vector2.ZERO


func board_mode() -> String:
	return _board_mode


## The easel's panel shows `tex` (the board-only MissiveScreen's viewport).
func set_board_texture(tex: Texture2D) -> void:
	var mat := (_board.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_texture = tex
	_board.material_override = mat


func _board_size() -> Vector2:
	return (_board.mesh as QuadMesh).size


## True when any of the panel is in the camera's view (the screen renders the
## board's viewport only then).
func board_visible() -> bool:
	if _board_mode != "table":
		return true
	return not _camera.is_position_behind(_board.global_position) \
		and Rect2(Vector2.ZERO, size).has_point(_camera.unproject_position(_board.global_position) / window_scale())


func _board_pose() -> Transform3D:
	return WarBoard.pose(_board.global_transform, _board_dist, _board_offset)


func enter_board() -> void:
	if _board_mode != "table":
		return
	_rake.drop()
	_table_pose = _camera.transform
	_fly_from = _table_pose
	_board_dist = _repo.bal("war_board_distance_m")
	_board_offset = Vector2.ZERO
	_fly_t = 0.0
	_board_mode = "to_board"
	board_entered.emit()


func leave_board() -> void:
	if _board_mode != "board" and _board_mode != "to_board":
		return
	_fly_from = _camera.transform
	_fly_t = 0.0
	_board_mode = "to_table"


## One frame of a flight; true while the camera is the flight's.
func _step_board(delta: float) -> bool:
	if _board_mode == "to_board" or _board_mode == "to_table":
		_fly_t += delta / maxf(_repo.bal("war_board_fly_s"), 0.01)
		var to := _board_pose() if _board_mode == "to_board" else _table_pose
		_camera.transform = WarBoard.fly(_fly_from, to, _fly_t)
		if _fly_t >= 1.0:
			if _board_mode == "to_table":
				_board_mode = "table"
				_apply_camera()
				board_left.emit()
			else:
				_board_mode = "board"
		return true
	return _board_mode == "board"


func _board_uv(screen_px: Vector2) -> Vector2:
	var s := screen_px * window_scale()
	return WarBoard.uv_of(_board.global_transform, _board_size(), _camera.project_ray_origin(s), _camera.project_ray_normal(s))


## Input while the board holds the camera: a left click (not a drag) on the
## panel is the board's, the wheel leans, a left drag pans in its plane.
func _board_input(event: InputEvent) -> void:
	accept_event()
	if _board_mode != "board":
		return
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if mb != null and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
		var step := _repo.bal("war_cam_zoom_step")
		_board_dist = clampf(_board_dist * (1.0 / step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else step),
			_repo.bal("war_board_min_m"), _repo.bal("war_board_max_m"))
		_camera.transform = _board_pose()
	elif mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_board_offset = WarBoard.clamp_offset(_board_offset + Vector2(-mm.relative.x, mm.relative.y)
			* _board_dist * _repo.bal("war_pan_drag_speed"), _board_size())
		_camera.transform = _board_pose()
		_board_dragged = true
	elif mm != null:
		var uv := _board_uv(mm.position)
		if uv.x >= 0.0:
			board_hovered.emit(uv)
	elif mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_board_dragged = false
		var uv := _board_uv(mb.position)
		if uv.x >= 0.0 and not _board_dragged:
			board_clicked.emit(uv, mb)


var _board_dragged := false
```

Wire it:
- In `_process`, first line: `if _step_board(delta): return` — but keep the swap stepping: put it as `var flying := _step_board(delta)` at the top and wrap the camera-moving line as `if not flying and (_rig.step(...) or key_pan(delta)): _apply_camera()`.
- In `_gui_input`, first lines after the `_sheet < 0` guard:

```gdscript
	if _board_mode != "table":
		_board_input(event)
		return
	var mbb := event as InputEventMouseButton
	if mbb != null and mbb.button_index == MOUSE_BUTTON_LEFT and not mbb.pressed \
			and piece_under(mbb.position) == "" and _board_uv(mbb.position).x >= 0.0 \
			and not _rake.empty_press_moved(mbb.position):
		_rake.forget_press()
		enter_board()
		accept_event()
		return
	tooltip_text = "Study the board" if event is InputEventMouseMotion \
		and _board_uv((event as InputEventMouseMotion).position).x >= 0.0 else ""
```

and in `scripts/war_room/war_room_rake.gd` add:

```gdscript
## A left release that ends a press which moved (a pan), so it is no click.
func empty_press_moved(at: Vector2) -> bool:
	return _pressed and at.distance_to(_press_at) >= _repo.bal("war_rake_min_px")


## The press was taken by something else (the easel): the rake forgets it.
func forget_press() -> void:
	_pressed = false
	_press_code = ""
```

(The board check comes BEFORE `_rake.on_left`, so a click on the panel neither picks a piece behind it nor clears the selection.)

- [ ] **Step 6: Run** `-gtest=res://tests/war_room/test_war_room_view.gd`. Expected: PASS.

- [ ] **Step 7: Failing screen tests** — append to `tests/ui/test_war_room_screen.gd`:

```gdscript
func test_the_easel_shows_the_missive_board_and_a_note_opens_the_full_board_over_the_room() -> void:
	var r: GameRoot = await _court()
	var m := MissiveLog.make("receipt", "credible", "A receipt", Game.state.absolute_day(), {}, [])
	MissiveLog.add(Game.state, m)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var screen := r.war_room_screen()
	var board := screen.board_screen()
	assert_true(board.board_only())
	var id := int(Game.state.missives.back()["id"])
	board.note_chosen.emit(id)
	await wait_process_frames(1)
	assert_true(r.missive_screen().visible, "the full board opens")
	assert_eq(r.missive_screen().selected(), id, "on that letter")
	assert_true(screen.visible, "over the room, which stays open")


func test_escape_in_board_view_returns_to_the_table_not_the_pause_menu() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	var view := r.war_room_screen().view()
	view.enter_board()
	await wait_seconds(Game.data.bal("war_board_fly_s") + 0.15)
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	r.get_viewport().push_input(e)
	await wait_process_frames(2)
	assert_eq(view.board_mode(), "to_table")
	assert_false(r.pause_menu_visible() if r.has_method("pause_menu_visible") else false)
```

(If GameRoot has no `pause_menu_visible()`, read `r._pause_menu.visible` — the test seams already reach privates elsewhere, e.g. `r._switch_to`.)

- [ ] **Step 8: The screen hosts the board** — in `scripts/ui/war_room_screen.gd`:

```gdscript
var _board_vp: SubViewport
var _board_screen: MissiveScreen


func board_screen() -> MissiveScreen:
	return _board_screen


## The easel's board (spec §1.3): the Missive screen, board-only, in its own
## SubViewport whose texture the panel wears; rendered only while seen.
func _build_board() -> void:
	_board_vp = SubViewport.new()
	_board_vp.name = "BoardViewport"
	var w := int(Game.data.bal("war_board_px"))
	_board_vp.size = Vector2i(w, int(round(float(w) * 0.8 / 1.2)))
	_board_vp.transparent_bg = false
	_board_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_board_vp.gui_embed_subwindows = true
	add_child(_board_vp)
	_board_screen = load("res://scenes/missive_screen.tscn").instantiate()
	_board_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_screen.theme = UiPalette.build_theme()
	_board_vp.add_child(_board_screen)
	_board_screen.set_board_only(true)
	_board_screen.visible = true
	_board_screen.note_chosen.connect(_on_note)
	_view.set_board_texture(_board_vp.get_texture())
	_view.board_clicked.connect(_push_board_click)
	_view.board_hovered.connect(_push_board_hover)


## A ray's hit on the panel, pushed into the board's viewport as real input.
func _push_board_click(uv: Vector2, mb: InputEventMouseButton) -> void:
	var e := mb.duplicate() as InputEventMouseButton
	e.position = uv * Vector2(_board_vp.size)
	e.global_position = e.position
	_board_vp.push_input(e, true)


func _push_board_hover(uv: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = uv * Vector2(_board_vp.size)
	e.global_position = e.position
	_board_vp.push_input(e, true)


func _on_note(id: int) -> void:
	var root := get_parent() as GameRoot
	if root != null:
		root.open_missive_over_war_room(id)


func refresh_board() -> void:
	if _board_screen != null:
		_board_screen.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not (event as InputEventKey).pressed \
			or (event as InputEventKey).keycode != KEY_ESCAPE:
		return
	if _view.board_mode() == "board" or _view.board_mode() == "to_board":
		_view.leave_board()
		get_viewport().set_input_as_handled()
```

Call `_build_board()` in `open()` inside `if not _bound:` after `_view.bind(...)`. In `_process`, after the `_dirty` block, add:

```gdscript
	if _board_vp != null:
		var want := SubViewport.UPDATE_ALWAYS if visible and _view.board_visible() else SubViewport.UPDATE_DISABLED
		if _board_vp.render_target_update_mode != want:
			_board_vp.render_target_update_mode = want
```

In `refresh()` also call `refresh_board()` (a state change can bring a missive).

Check the `MissiveScreen`'s Escape: it closes itself on `ui_cancel`? (`grep -n "ui_cancel\|KEY_ESCAPE" scripts/ui/missive_screen.gd`). If the board-only instance reacts to Escape, guard that handler with `if _board_only: return`.

Also add a "Back to the table" button: in `scenes/war_room_screen.tscn` add under `Top` (before `Close`):

```
[node name="BackToTable" type="Button" parent="Top"]
unique_name_in_owner = true
visible = false
layout_mode = 2
text = "Back to the table"
```

and in `_ready()`: `%BackToTable.pressed.connect(func() -> void: _view.leave_board())`, `UiPalette.command_button(%BackToTable)`, `_view.board_entered.connect(func() -> void: %BackToTable.visible = true)`, `_view.board_left.connect(func() -> void: %BackToTable.visible = false)`.

- [ ] **Step 9: GameRoot opens the board over the room** — in `scripts/ui/game_root.gd`:

```gdscript
## A note on the WAR ROOM's easel (spec 2026-10-02-war-room-v2 §1.3): the
## Missive board opens on that letter OVER the room, which stays open, so
## closing the board returns to the easel.
func open_missive_over_war_room(id: int) -> void:
	_info_screen.hide()
	_missive_screen.visible = true
	_missive_screen.set_top_inset(_active_top_bar_height())
	_missive_screen.select(id)
```

Find where GameRoot refreshes the board on a new missive (`refresh_missive_badge` around line 605: `if and_board and _missive_screen != null and _missive_screen.visible …`) and add after it:

```gdscript
	if _war_room_screen != null and _war_room_screen.visible:
		_war_room_screen.refresh_board()
```

- [ ] **Step 10: Run** `-gtest=res://tests/ui/test_war_room_screen.gd`, `-gdir=res://tests/war_room -ginclude_subdirs`, `-gdir=res://tests/ui -ginclude_subdirs`. Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add scenes/war_room/war_room.tscn scenes/war_room_screen.tscn scripts/war_room/war_room_view.gd scripts/war_room/war_room_rake.gd scripts/ui/war_room_screen.gd scripts/ui/game_root.gd data/balance.csv tests/war_room/test_war_room_view.gd tests/ui/test_war_room_screen.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war-room): the Missive board on an easel — fly to it, read it, open a note

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Shots through real input, the visual review, the documents, the full suite

**Files:**
- Modify: `tools/snapshot_screen.gd` (`--war-turn DEG`, `--war-board`, `--war-board-click fx,fy`)
- Modify: `CLAUDE.md` (the WAR ROOM paragraph)
- Modify: `docs/superpowers/specs/2026-10-02-war-room-v2-design.md` (§12 "Changed while building", only if something changed)

- [ ] **Step 1: The flags** — in `tools/snapshot_screen.gd`: add fields `var _war_turn := 0.0`, `var _war_board := false`, `var _war_board_click := Vector2(-1, -1)`; parse `--war-turn` (float), `--war-board` (flag), `--war-board-click` (`fx,fy`, shares of the view, implies `--war-board`) beside the other `--war-*` arguments; document them in the `--war-room` comment block (lines ~170–184). In `_war_room_step`, in phase 2 after the zoom: if `_war_turn != 0.0`, push a REAL right drag on the view — a press, eight motions with `MOUSE_BUTTON_MASK_RIGHT` totalling `-_war_turn / Game.data.bal("war_cam_turn_deg_per_px")` px in x, a release — written like `_real_drag` but with the right button (add `_real_right_drag(c, from, to)` beside `_real_drag`), and print `war: yaw=%.1f`. In phase 3, if `_war_board`: `_real_click` the view at the easel panel's projected centre (`view.get_node("%BoardPanel")`'s global position through the view's camera, divided by `view.window_scale()`), print `war: board mode=%s`; in phase 4, after `war_board_fly_s` seconds of frames, if `_war_board_click.x >= 0`, `_real_click(view, Vector2(view.size) * _war_board_click)` and print `war: missive open=%s selected=%d`.

- [ ] **Step 2: Shoot the set** (real window, NOT headless):

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
S="--path . res://tools/snapshot_screen.tscn -- --screen root --quiet --war-room"
$G $S --out /tmp/wr_a_1_open.png
$G $S --war-turn 90 --out /tmp/wr_a_2_turn90.png
$G $S --war-turn 180 --out /tmp/wr_a_3_turn180.png
$G $S --war-board --out /tmp/wr_a_4_board.png
$G $S --war-board --war-board-click 0.2,0.4 --out /tmp/wr_a_5_note.png
```

- [ ] **Step 3: The visual review** — invoke the `visual-review` skill (`.claude/skills/visual-review/`) on the five shots: crop the table edge at 180° (no furniture or wall clipping the camera), the easel stand-in (square, readable notes at the opening board distance), the wide room's left edge after the roll. Fix what it finds, re-shoot.

- [ ] **Step 4: The documents** — in `CLAUDE.md`'s WAR ROOM paragraph (`**The WAR ROOM — the plotting room**`), add after its first sentence a v2 sentence: "Since v2 (owner 2026-10-02, spec `docs/superpowers/specs/2026-10-02-war-room-v2-design.md`) the room TURNS like the 3D map (`WarCamera`: free yaw, pitch by distance `war_cam_pitch_near_deg` / `_far_deg`, kept inside the walls `war_room_floor_*`, the key's rose easing it back; `WarRoomGestures`: right drag turns, right click the order menu, left drag on open table pans, WASD), it WIDENS over the left column as the steward's report rolls up (`WarReportRoll`, `war_report_roll_s`; GameRoot's `war_room_rect`), a picked piece's card is the column's own `MapDetailPanel` borrowed into `%CardRoll` and unrolled over the room's left, and the Missive board hangs on an easel (`%BoardPanel`, a board-only `MissiveScreen` in a SubViewport; `WarBoard`): a click flies the camera to it, a note opens the full board on that letter over the room, Escape or Back to the table flies back." Remove the sentence about the turn being held within ±30° if present (`grep -n "yaw_max\|±30" CLAUDE.md`).

- [ ] **Step 5: The full suite**

Run: `./run_tests.sh 2>&1 | tail -25`
Expected: all pass, `Errors 0` in this worktree. Any failure outside the war room / missive / court tests: check it against main's baseline (`git stash` is shared — instead run the failing file in the main checkout) before touching it.

- [ ] **Step 6: Commit**

```bash
git add tools/snapshot_screen.gd CLAUDE.md docs/superpowers/specs/2026-10-02-war-room-v2-design.md
git commit -m "tools(war-room): --war-turn, --war-board shots; CLAUDE.md: the room turns, widens and hangs the board

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Show the owner** — send the five shots (SendUserFile) and wait for the look's approval before plan B starts.
