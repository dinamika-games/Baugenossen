extends "res://tests/godot/godot_test.gd"
## Play the tutorial with the body, as a player does (DESIGN.md, 12): the
## crane calibrates itself while the body holds still, then a synthetic body
## picks blocks from the row with short dips, leans to move the hook and places
## with push-ups. Check that neither the keys nor the mouse move the hook, that
## the mission is completed and saved, and that the results follow.

const GameFixture := preload("res://tests/godot/game_fixture.gd")
const STEP := 1.0 / 60.0

var site: Node
var body := SyntheticPoseProvider.new()


func _run() -> void:
    GameFixture.new(self, "body_loop")
    var game: Node = root.get_node("Game")
    game.pose_provider = body
    game.session.new_game()
    game.mission_id = "place_to_sit"
    site = load(game.SCREENS["build_site"]).instantiate()
    root.add_child(site)
    await _frames(180)
    check_equal(site.dispatcher.state, InputDispatcher.BUILD, "the site is ready to build")
    check(site.pose.calibration.has("h"), "the crane learned the posture by itself")

    var start: Vector2 = site.hook
    await _key(KEY_RIGHT, 0.5)
    await _key(KEY_D, 0.5)
    check(site.hook.distance_to(start) < 0.01, "the keys do not move the hook")
    var motion := InputEventMouseMotion.new()
    motion.position = Vector2(50, 50)
    Input.parse_input_event(motion)
    await _frames(5)
    check(site.hook.distance_to(start) < 0.01, "nor does the mouse")

    # NOTE (mristin):
    # The row is random; the test lays it out, and stops it from moving on.
    site.queue.shift_seconds = 1.0e9
    site.queue.slots.assign(
        ["grass_patch", "bench_basic", "tree_small", "grass_patch", "bench_basic"]
    )
    site._choose_slot(0)
    check_equal(site.carried, "grass_patch", "the hook carries the first block")
    await _short_dip()
    check_equal(site.carried, "bench_basic", "a short dip takes the next block")
    check_equal(site.grid.instances.size(), 0, "without placing")
    await _move_hook_to(6.5)
    await _dip()
    check_equal(site.grid.instances.size(), 1, "a push-up places the bench where it lands")
    check_equal(site.carried, "tree_small", "and the next block of the row comes up")
    await _move_hook_to(12.5)
    await _dip()
    check_equal(site.carried, "grass_patch", "the grass comes next")
    await _dip()
    check_equal(site.grid.instances.size(), 3, "the tree and the grass are placed")
    check(site.report.can_submit(), "the tutorial is solved")

    await _tap(KEY_ENTER)
    check_equal(site.dispatcher.state, InputDispatcher.REVIEW, "Enter opens the review")
    await _tap(KEY_SPACE)
    check_equal(site.dispatcher.state, InputDispatcher.COMPLETE, "Space hands it over")
    await _frames(240)
    check(game.session.progress.has_completed("place_to_sit"), "completed")
    var saved := GameSession.new(game.content, game.session.repository)
    check(saved.continue_game() and saved.progress.has_completed("place_to_sit"), "and saved")
    await _tap(KEY_SPACE)
    await _frames(3)
    check_equal(
        current_scene.scene_file_path if current_scene != null else "",
        game.SCREENS["mission_results"],
        "Space goes on to the results"
    )


## Lean until the hook is over the column, then hold neutral.
func _move_hook_to(x: float) -> void:
    for i in range(1200):
        var delta: float = x - site.hook.x
        if absf(delta) < 0.3:
            break
        # NOTE (mristin):
        # The shoulders moving right in the camera's picture are a lean to the
        # player's left: the hook goes left.
        body.shift = clampf(-delta * 0.03, -0.06, 0.06)
        await _frames(1)
    body.shift = 0.0
    await _frames(60)


## A short dip: down a little and up again.
func _short_dip() -> void:
    body.rise = -0.12
    await _frames(30)
    body.rise = 0.0
    await _frames(40)


## A push-up: down and up again.
func _dip() -> void:
    body.rise = -0.2
    await _frames(30)
    body.rise = 0.0
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
