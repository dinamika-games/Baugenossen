extends "res://tests/godot/godot_test.gd"
## Play the tutorial with the body, as a player does (DESIGN.md, 12): the
## crane calibrates itself while the body holds still, then a synthetic body
## leans to move the hook and goes down and up to lower and raise it: it grabs
## parts in the yard, puts them down, lifts one up again, gives parts back to
## the yard, and solves the puzzle, which completes by itself. Check that
## neither the keys nor the mouse move the hook, that
## the level is completed and saved, and that a push-up goes on to the next
## level.

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
    # The tutorial gives a bench, two chairs, a tree, two patches of grass and
    # two flower beds, in this order.
    check_equal(site.supply.kinds[0], "bench_basic", "the yard starts with the bench")
    check(site.hook.y > 10.0, "with straight arms, the hook is at the top")
    await _move_hook_to(_yard_x(0))
    await _down_and_up()
    check_equal(site.carried, "bench_basic", "going down over the bench grabs it")
    check_equal(site.supply.count(0), 0, "and none is left in the yard")
    await _move_hook_to(6.5)
    await _down_and_up()
    check_equal(site.grid.instances.size(), 1, "going down with the bench puts it there")
    check_equal(site.carried, "", "and the hook is empty again")
    await _move_hook_to(_yard_x(0))
    await _down_and_up()
    check_equal(site.carried, "", "an empty place of the yard gives nothing")

    await _move_hook_to(_yard_x(1))
    await _down_and_up()
    check_equal(site.carried, "chair_basic", "a chair is grabbed")
    await _move_hook_to(_yard_x(4))
    await _down_and_up()
    check_equal(site.carried, "", "going down over the yard gives it back")
    check_equal(site.supply.count(1), 2, "both chairs are in the yard again")

    await _move_hook_to(6.5)
    await _down_and_up()
    check_equal(site.carried, "bench_basic", "going down onto a placed bench lifts it up again")
    check_equal(site.grid.instances.size(), 0, "off the site")
    await _move_hook_to(4.5)
    await _down_and_up()
    check_equal(site.grid.instances.size(), 1, "and it can be put down elsewhere")

    # NOTE (mristin):
    # A part which the level does not give (from an older game) can be lifted
    # and put down again, or given back to the yard.
    var stove := Placement.place_command(
        site.grid,
        site.content.part("stove_basic"),
        Vector2i(17, 0),
        false,
        0,
        Placement.Context.new()
    )
    site.history.execute(stove, site.grid)
    await _move_hook_to(18.0)
    await _down_and_up()
    check_equal(site.carried, "stove_basic", "the stove is lifted")
    await _move_hook_to(15.5)
    await _down_and_up()
    check_equal(site.carried, "", "and put down again, though not given")
    await _move_hook_to(15.5)
    await _down_and_up()
    await _move_hook_to(_yard_x(0))
    await _down_and_up()
    check_equal(site.grid.instances.size(), 1, "it goes back to the yard")
    check_equal(site.supply.kinds.back(), "stove_basic", "which gets a place for it")

    for step in [[2, 12.5], [3, 12.5]]:
        await _move_hook_to(_yard_x(step[0]))
        await _down_and_up()
        check_equal(site.dispatcher.state, InputDispatcher.BUILD, "not solved yet")
        await _move_hook_to(step[1])
        await _down_and_up()
    check(site.report.can_submit(), "the puzzle is solved")
    check_equal(site.dispatcher.state, InputDispatcher.COMPLETE, "and the residents come at once")
    await _frames(240)
    check(game.session.progress.has_completed("place_to_sit"), "completed")
    var saved := GameSession.new(game.content, game.session.repository)
    check(saved.continue_game() and saved.progress.has_completed("place_to_sit"), "and saved")
    await _down_and_up()
    check_equal(game.mission_id, "first_home", "a push-up goes on to the next level")
    await _frames(3)
    check_equal(
        current_scene.scene_file_path if current_scene != null else "",
        game.SCREENS["build_site"],
        "which opens at once"
    )
    check(current_scene.pose.calibration.has("h"), "without learning the posture again")
    check_equal(game.session.next_mission("first_home"), "", "no other level is open yet")
    game.session.replay("place_to_sit")
    check(game.session.open_site("place_to_sit").instances.is_empty(), "a replay starts empty")
    check_equal(game.session.mission_status("place_to_sit"), "completed", "and stays solved")


## Lean until the hook is over the column, then hold neutral.
func _move_hook_to(x: float) -> void:
    for i in range(1200):
        var delta: float = x - site.hook.x
        if absf(delta) < 0.3:
            break
        # NOTE (mristin):
        # The shoulders moving right in the camera's picture are a lean to the
        # player's left: the hook goes left.
        # A clear lean (as players lean to travel), never a slight one, which
        # the crane takes for a drift of the resting posture.
        body.shift = -signf(delta) * clampf(absf(delta) * 0.03, 0.035, 0.06)
        await _frames(1)
    body.shift = 0.0
    await _frames(60)


## The middle of the yard's place of the kind with the index.
func _yard_x(index: int) -> float:
    return site.yard_cards()[index].get_center().x


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
