extends SceneTree
## Take screenshots of the screens, with sample constructions, to review the
## placeholder art and the layout without playing. It needs a display (run it
## under xvfb-run on a server); the saves and settings go to user://screenshots/.
##
## xvfb-run -a $GODOT --path . --resolution 1280x720 --script dev/screenshots/take_screenshots.gd -- <output dir>

const SampleBuilds := preload("res://tests/godot/sample_builds.gd")
const GameFixture := preload("res://tests/godot/game_fixture.gd")


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var output := args[0] if not args.is_empty() else "user://screenshots"
    DirAccess.make_dir_recursive_absolute(output)
    GameFixture.new(self, "screenshots")
    var game: Node = root.get_node("Game")
    await _shoot(game, "main_menu", output.path_join("01_main_menu.png"))
    game.session.new_game()
    var builds := SampleBuilds.new(game.content)
    game.session.store_site("place_to_sit", builds.place_to_sit())
    var home := builds.new_site("flat_40_24")
    builds.first_home_two_storeys(home)
    builds.place(home, "window_basic", 6, 8)
    builds.place(home, "bench_basic", 0, 0)
    builds.place(home, "grass_patch", 24, 0)
    builds.place(home, "tree_small", 28, 0)
    var single := builds.new_site("flat_40_24")
    builds.first_home_single(single)
    game.session.store_site("first_home", home)
    var garden := builds.new_site("flat_40_24")
    builds.garden(garden)
    game.session.store_site("garden_for_everyone", garden)
    game.session.progress.completed_missions.append("place_to_sit")
    await _shoot(game, "city_map", output.path_join("02_city_map.png"))
    game.mission_id = "first_home"
    await _shoot(game, "build_site", output.path_join("03_build_two_storeys.png"))
    game.session.store_site("first_home", single)
    await _shoot(game, "build_site", output.path_join("04_build_single.png"))
    game.mission_id = "garden_for_everyone"
    await _shoot(game, "build_site", output.path_join("05_build_garden.png"))
    quit()


func _shoot(game: Node, screen: String, path: String) -> void:
    var scene: Node = load(game.SCREENS[screen]).instantiate()
    root.add_child(scene)
    for i in range(10):
        await process_frame
    if screen == "build_site":
        # NOTE (mristin):
        # The hook carries a bed over the site, low enough to show where it
        # lands.
        scene.carried = "bed_single"
        scene._delta = 1.0
        scene._move_hook(30.0 - scene.hook.x, 14.0)
        if path.ends_with("05_build_garden.png"):
            # NOTE (mristin):
            # The garden shows the yard with the parts of the level.
            scene.carried = ""
            scene._move_hook(scene.yard_left() + 4.5 - scene.hook.x, 14.0)
            scene._fit_camera()
        scene._show_hook()
        for i in range(3):
            await process_frame
    await RenderingServer.frame_post_draw
    root.get_viewport().get_texture().get_image().save_png(path)
    print("Saved ", path)
    scene.queue_free()
    await process_frame
