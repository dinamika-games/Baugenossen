extends "res://tests/godot/godot_test.gd"
## Play the tutorial with the keyboard only, as a player does (DESIGN.md, 12:
## "keyboard-only full loop"): open the catalogue, pick the bench, lower the
## hook, place, pick the tree and the grass, place them, remove and undo, review
## and hand over, and see the results. Then check the rewards and the save.

const GameFixture := preload("res://tests/godot/game_fixture.gd")

var site: Node


func _run() -> void:
    GameFixture.new(self, "keyboard")
    var game: Node = root.get_node("Game")
    game.session.new_game(GameFixture.new_character(game.content))
    game.mission_id = "place_to_sit"
    site = load(game.SCREENS["build_site"]).instantiate()
    root.add_child(site)
    await _frames(3)

    await _pick("recreation", 0)
    check_equal(site.carried, "bench_basic", "the bench is picked with the keyboard")
    await _hold(KEY_S, 1.5)
    await _hold(KEY_A, 0.4)
    await _tap(KEY_SPACE)
    check_equal(site.grid.instances.size(), 1, "the bench is placed with Space")

    await _pick("nature", 1)
    check_equal(site.carried, "tree_small", "the tree is picked")
    await _hold(KEY_D, 0.7)
    await _tap(KEY_SPACE)
    # NOTE (mristin):
    # The catalogue opens on the part carried last, the tree; the grass is next.
    await _pick("nature", 1)
    check_equal(site.carried, "grass_patch", "the grass is picked")
    await _tap(KEY_SPACE)
    check_equal(site.grid.instances.size(), 3, "the tree and the grass are placed")

    await _tap(KEY_X)
    await _tap(KEY_SPACE)
    check_equal(site.grid.instances.size(), 2, "X and Space remove a part")
    await _tap(KEY_Z, true)
    check_equal(site.grid.instances.size(), 3, "Ctrl+Z brings it back")
    await _tap(KEY_X)

    check(site.report.can_submit(), "the tutorial is solved: %s" % [_failed(site.report)])
    await _tap(KEY_ENTER)
    check_equal(site.dispatcher.state, InputDispatcher.REVIEW, "Enter opens the review")
    await _tap(KEY_SPACE)
    check_equal(site.dispatcher.state, InputDispatcher.COMPLETE, "Space hands it over")
    await _frames(240)
    check(not site.view.residents.is_empty(), "the residents come")
    var character: Character = game.session.character
    check(character.has_completed("place_to_sit"), "the mission is completed")
    check_equal(character.xp, 20, "with 20 XP")
    var saved := GameSession.new(game.content, game.session.repository)
    check(saved.continue_game() and saved.character.has_completed("place_to_sit"), "and saved")
    await _tap(KEY_SPACE)
    await _frames(3)
    check_equal(
        current_scene.scene_file_path if current_scene != null else "",
        game.SCREENS["mission_results"],
        "Space goes on to the results"
    )


func _failed(report: MissionEvaluator.Report) -> Array:
    var ids := []
    for result in report.mandatory:
        if not result["satisfied"]:
            ids.append(result["id"])
    return ids


## Open the catalogue, go to the category, move right [param rights] times from
## the focused entry, and select it.
func _pick(category: String, rights: int) -> void:
    await _tap(KEY_TAB)
    check_equal(site.dispatcher.state, InputDispatcher.CATALOGUE, "Tab opens the catalogue")
    for i in range(8):
        if site.hud.category == category:
            break
        await _tap(KEY_S)
    for i in range(rights):
        await _tap(KEY_RIGHT)
    await _tap(KEY_SPACE)


func _key(keycode: Key, pressed: bool, ctrl := false) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = pressed
    event.ctrl_pressed = ctrl
    Input.parse_input_event(event)


func _tap(keycode: Key, ctrl := false) -> void:
    _key(keycode, true, ctrl)
    await _frames(2)
    _key(keycode, false, ctrl)
    await _frames(2)


func _hold(keycode: Key, seconds: float) -> void:
    _key(keycode, true)
    await _frames(int(seconds * 60))
    _key(keycode, false)
    await _frames(2)


func _frames(count: int) -> void:
    for i in range(count):
        await process_frame
