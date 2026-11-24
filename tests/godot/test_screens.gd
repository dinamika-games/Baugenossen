extends "res://tests/godot/godot_test.gd"
## Start every screen headless and check that it builds without errors and
## fits on one screen of 1280 x 720 (nothing scrolls: no scroll bar, and no
## control reaches beyond the screen), with and without a game in progress,
## in English and in German, also with a long Unicode name (DESIGN.md, 7 and 8).

const GameFixture := preload("res://tests/godot/game_fixture.gd")


func _run() -> void:
    for locale in ["en", "de"]:
        TranslationServer.set_locale(locale)
        await _all_screens()
    TranslationServer.set_locale("en")


func _all_screens() -> void:
    var fixture := GameFixture.new(self, "screens")
    var game: Node = root.get_node("Game")
    for screen in ["main_menu", "credits"]:
        await _show(game, screen)
    game.session.new_game()
    check(game.session.save(), "the game is saved into the fixture")
    await _show(game, "city_map")
    for id in game.content.mission_order:
        game.mission_id = id
        await _show(game, "build_site")
    game.last_summary = {"wishes": [], "first": true, "saved": true}
    game.mission_id = "place_to_sit"
    await _show(game, "mission_results")
    check(fixture.directory != "", "the fixture has its own directory")


func _show(game: Node, screen: String) -> void:
    var scene: Node = load(game.SCREENS[screen]).instantiate()
    root.add_child(scene)
    for i in range(3):
        await process_frame
    check(scene.is_inside_tree(), "the screen %s runs" % screen)
    if screen != "build_site":
        _check_fits(scene, screen)
    scene.queue_free()
    await process_frame


## Check that no visible control of the screen reaches beyond it, and that
## nothing scrolls.
func _check_fits(scene: Node, screen: String) -> void:
    var bounds := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(1.0)
    var outside: Array[String] = []
    for node in scene.find_children("*", "Control", true, false):
        var control := node as Control
        if not control.is_visible_in_tree():
            continue
        check(not control is ScrollContainer, "%s does not scroll" % screen)
        if not bounds.encloses(control.get_global_rect()):
            outside.append("%s %s" % [control.get_class(), control.get_global_rect()])
    check(
        outside.is_empty(),
        (
            "%s fits on one screen (%s): %s"
            % [screen, TranslationServer.get_locale(), outside.slice(0, 3)]
        )
    )
