extends "res://tests/godot/godot_test.gd"
## Play the tutorial with the body, as a player does (DESIGN.md, 12): the
## crane calibrates itself while the body holds still, then a synthetic body
## leans to move the hook and goes down and up to lower and raise it: it grabs
## blocks in the yard, puts them down, lifts one up again, throws one into the
## skip and rings the bell. Check that neither the keys nor the mouse move the hook, that
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
    # The yard is random; the test lays it out, and stops it from moving on.
    site.queue.shift_seconds = 1.0e9
    site.queue.slots.assign(
        ["bench_basic", "tree_small", "grass_patch", "lamp_basic", "bench_basic"]
    )
    check(site.hook.y > 10.0, "with straight arms, the hook is at the top")
    await _move_hook_to(_yard_x(0))
    await _down_and_up()
    check_equal(site.carried, "bench_basic", "going down over the bench grabs it")
    check_equal(site.queue.slots[0], "tree_small", "and the yard moves up")
    await _move_hook_to(6.5)
    await _down_and_up()
    check_equal(site.grid.instances.size(), 1, "going down with the bench puts it there")
    check_equal(site.carried, "", "and the hook is empty again")

    for x in [12.5, 12.5]:
        await _move_hook_to(_yard_x(0))
        await _down_and_up()
        await _move_hook_to(x)
        await _down_and_up()
    check_equal(site.grid.instances.size(), 3, "the tree and the grass are placed")
    check(site.report.can_submit(), "the tutorial is solved")

    await _move_hook_to(_yard_x(0))
    await _down_and_up()
    check_equal(site.carried, "lamp_basic", "the lamp is not needed")
    await _move_hook_to(site.yard_left() + 1.5)
    await _down_and_up()
    check_equal(site.carried, "", "going down over the skip throws it away")
    check_equal(site.grid.instances.size(), 3, "without placing it")

    await _move_hook_to(6.5)
    await _down_and_up()
    check_equal(site.carried, "bench_basic", "going down onto a placed bench lifts it up again")
    check_equal(site.grid.instances.size(), 2, "off the site")
    await _move_hook_to(4.5)
    await _down_and_up()
    check_equal(site.grid.instances.size(), 3, "and it can be put down elsewhere")

    await _move_hook_to(site.bell_left() + 1.0)
    await _down_and_up()
    check_equal(site.dispatcher.state, InputDispatcher.COMPLETE, "the bell hands it over")
    await _frames(240)
    check(game.session.progress.has_completed("place_to_sit"), "completed")
    var saved := GameSession.new(game.content, game.session.repository)
    check(saved.continue_game() and saved.progress.has_completed("place_to_sit"), "and saved")
    site.overlays.action_requested.emit("results")
    await _frames(3)
    check_equal(
        current_scene.scene_file_path if current_scene != null else "",
        game.SCREENS["mission_results"],
        "the results follow"
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


## The middle of the yard's place of the block with the index.
func _yard_x(index: int) -> float:
    return site.yard_left() + site.SLOT_WIDTH * (index + 1.5)


## Go down to the bottom of a push-up, and up again: the hook goes down as far
## as it can, and up.
func _down_and_up() -> void:
    body.rise = -0.22
    await _frames(45)
    body.rise = 0.0
    await _frames(45)


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


func _frames(count: int) -> void:
    for i in range(count):
        body.advance(STEP)
        await process_frame
