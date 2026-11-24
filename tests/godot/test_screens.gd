extends "res://tests/godot/godot_test.gd"
## Start every screen headless and check that it builds without errors, with
## and without a game in progress, also with a long Unicode name (DESIGN.md,
## 7 and 8).

const GameFixture := preload("res://tests/godot/game_fixture.gd")


func _run() -> void:
    var fixture := GameFixture.new(self, "screens")
    var game: Node = root.get_node("Game")
    for screen in ["main_menu", "credits", "settings", "character_creation", "calibration"]:
        await _show(game, screen)
    var character := GameFixture.new_character(game.content)
    character.name = "Ŝtefánija-Āmina Łukasiewicz-Øvergård 李小龙"
    game.session.new_game(character)
    check(game.session.save(), "the game is saved into the fixture")
    for screen in ["city_map", "character_sheet"]:
        await _show(game, screen)
    for id in game.content.mission_order:
        game.mission_id = id
        await _show(game, "build_site")
    game.last_summary = {
        "xp": 20,
        "karma": 20,
        "levels": 0,
        "wishes": [],
        "practice": [],
        "first": true,
        "saved": true
    }
    game.mission_id = "place_to_sit"
    await _show(game, "mission_results")
    check(fixture.directory != "", "the fixture has its own directory")


func _show(game: Node, screen: String) -> void:
    var scene: Node = load(game.SCREENS[screen]).instantiate()
    root.add_child(scene)
    for i in range(3):
        await process_frame
    check(scene.is_inside_tree(), "the screen %s runs" % screen)
    scene.queue_free()
    await process_frame
