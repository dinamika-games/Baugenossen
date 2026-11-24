extends "res://tests/godot/godot_test.gd"
## Play the tutorial with the body, as a player does (DESIGN.md, 12): a
## synthetic body leans and rises to move the hook and lifts its hands to open
## the catalogue and to place; a helper picks the parts with the mouse. Check
## that neither the keys nor the mouse move the hook, that the mission is
## completed, rewarded and saved, and that the results follow.

const GameFixture := preload("res://tests/godot/game_fixture.gd")
const STEP := 1.0 / 60.0

var site: Node
var body := SyntheticPoseProvider.new()


func _run() -> void:
    GameFixture.new(self, "body_loop")
    var game: Node = root.get_node("Game")
    var settings: Node = root.get_node("Settings")
    settings.set_value("calibration", _calibrate())
    game.pose_provider = body
    game.session.new_game(GameFixture.new_character(game.content))
    game.mission_id = "place_to_sit"
    site = load(game.SCREENS["build_site"]).instantiate()
    root.add_child(site)
    await _frames(40)
    check_equal(site.dispatcher.state, InputDispatcher.BUILD, "the site is ready to build")

    var start: Vector2 = site.hook
    await _key(KEY_RIGHT, 0.5)
    await _key(KEY_D, 0.5)
    check(site.hook.distance_to(start) < 0.01, "the keys do not move the hook")
    var motion := InputEventMouseMotion.new()
    motion.position = Vector2(50, 50)
    Input.parse_input_event(motion)
    await _frames(5)
    check(site.hook.distance_to(start) < 0.01, "nor does the mouse")

    await _lift("left")
    check_equal(
        site.dispatcher.state, InputDispatcher.CATALOGUE, "the left hand opens the catalogue"
    )
    site.hud.part_clicked.emit("bench_basic")
    # NOTE (mristin):
    # After a choice, the hook waits for the neutral posture (half a second).
    await _frames(45)
    check_equal(site.carried, "bench_basic", "a helper picks the bench with the mouse")
    await _move_hook_to(Vector2(6.5, 0.0))
    await _lift("right")
    check_equal(site.grid.instances.size(), 1, "the right hand places the bench")

    site.hud.part_clicked.emit("tree_small")
    await _frames(45)
    await _move_hook_to(Vector2(12.5, 0.0))
    await _lift("right")
    site.hud.part_clicked.emit("grass_patch")
    await _frames(45)
    await _lift("right")
    check_equal(site.grid.instances.size(), 3, "the tree and the grass are placed")
    check(site.report.can_submit(), "the tutorial is solved")

    await _tap(KEY_ENTER)
    check_equal(site.dispatcher.state, InputDispatcher.REVIEW, "Enter opens the review")
    await _tap(KEY_SPACE)
    check_equal(site.dispatcher.state, InputDispatcher.COMPLETE, "Space hands it over")
    await _frames(240)
    var character: Character = game.session.character
    check(character.has_completed("place_to_sit") and character.xp == 20, "completed, 20 XP")
    var saved := GameSession.new(game.content, game.session.repository)
    check(saved.continue_game() and saved.character.has_completed("place_to_sit"), "and saved")
    await _tap(KEY_SPACE)
    await _frames(3)
    check_equal(
        current_scene.scene_file_path if current_scene != null else "",
        game.SCREENS["mission_results"],
        "Space goes on to the results"
    )


## Calibrate with the synthetic body: leaning is a shift, rising a rise.
func _calibrate() -> Dictionary:
    var calibration := PoseCalibration.new()
    var postures := {
        "neutral": [0.0, 0.0],
        "left": [-0.06, 0.0],
        "right": [0.06, 0.0],
        "up": [0.0, 0.12],
        "down": [0.0, -0.12]
    }
    var probe := SyntheticPoseProvider.new()
    for attempt in range(20):
        if calibration.done():
            break
        var posture: Array = postures[calibration.current_step()]
        probe.shift = posture[0]
        probe.rise = posture[1]
        for i in range(90):
            probe.advance(1.0 / 30.0)
            if calibration.feed(PoseMeasure.measure(probe.latest_frame()), probe.time):
                break
    return calibration.values


## Lean and rise until the hook is near the target, then hold neutral.
func _move_hook_to(target: Vector2) -> void:
    for i in range(1200):
        var delta: Vector2 = target - site.hook
        if absf(delta.x) < 0.3 and absf(delta.y) < 0.3:
            break
        body.shift = clampf(delta.x * 0.03, -0.06, 0.06) if absf(delta.x) >= 0.3 else 0.0
        body.rise = clampf(delta.y * 0.04, -0.12, 0.12) if absf(delta.y) >= 0.3 else 0.0
        await _frames(1)
    body.shift = 0.0
    body.rise = 0.0
    await _frames(60)


## Lift a hand and lower it again: one gesture.
func _lift(side: String) -> void:
    if side == "right":
        body.lift_right = 0.25
    else:
        body.lift_left = 0.25
    await _frames(24)
    body.lift_right = 0.0
    body.lift_left = 0.0
    await _frames(40)


func _key(keycode: Key, seconds: float) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = true
    Input.parse_input_event(event)
    await _frames(int(seconds * 60))
    var release := event.duplicate()
    release.pressed = false
    Input.parse_input_event(release)
    await _frames(2)


func _tap(keycode: Key) -> void:
    await _key(keycode, 2.0 / 60.0)


func _frames(count: int) -> void:
    for i in range(count):
        body.advance(STEP)
        await process_frame
