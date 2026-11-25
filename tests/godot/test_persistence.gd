extends "res://tests/godot/godot_test.gd"
## Check the saves: the roundtrip, an incomplete site, the backup after
## corruption, an unknown version left untouched, the migration, and that a
## resubmitted mission counts once, also after a restart (DESIGN.md,
## 10). The test writes only into its own temporary directory.

const SampleBuilds := preload("res://tests/godot/sample_builds.gd")

var content: ContentDb
var directory := ""


func _run() -> void:
    content = ContentDb.get_default()
    directory = "user://tests/persistence_%d" % Time.get_ticks_usec()
    _test_roundtrip_and_no_duplicate_rewards()
    _test_corruption_falls_back()
    _test_unknown_version()
    _test_migration()
    _test_invalid_values()


func _session(name: String) -> GameSession:
    return GameSession.new(content, SaveRepository.new(directory.path_join(name)))


func _test_roundtrip_and_no_duplicate_rewards() -> void:
    var builds := SampleBuilds.new(content)
    var session := _session("roundtrip")
    session.new_game()
    check_equal(session.mission_status("first_home"), "locked", "the home waits for the tutorial")
    var sit := builds.place_to_sit()
    var summary := session.submit("place_to_sit", sit)
    check(summary["submitted"] and summary["saved"], "the tutorial is submitted and saved")
    check_equal(session.mission_status("first_home"), "available", "which unlocks the home")
    var home := session.open_site("first_home")
    builds.place(home, "wall_wood", 4, 0)
    session.store_site("first_home", home)
    check(session.save(), "an incomplete site is saved")

    var restarted := _session("roundtrip")
    check(restarted.continue_game(), "the game continues after a restart")
    check(restarted.progress.has_completed("place_to_sit"), "with the tutorial completed")
    check_equal(restarted.mission_status("first_home"), "in_progress", "the home is in progress")
    check_equal(restarted.open_site("first_home").instances.size(), 1, "with its wall")
    var again := restarted.submit("place_to_sit", restarted.open_site("place_to_sit"))
    check(again["submitted"], "the tutorial can be resubmitted")
    check(not again["first"], "but counts once")
    check_equal(restarted.progress.completed_missions.size(), 1, "the progress stays")
    restarted.replay("place_to_sit")
    check(restarted.open_site("place_to_sit").instances.is_empty(), "a replay starts empty")
    check_equal(restarted.mission_status("place_to_sit"), "completed", "the level stays solved")
    check(restarted.progress.has_completed("place_to_sit"), "without losing the completion")


func _test_corruption_falls_back() -> void:
    var session := _session("corrupt")
    session.new_game()
    session.save()
    session.progress.completed_missions.append("place_to_sit")
    session.save()
    var file := FileAccess.open(session.repository.path(), FileAccess.WRITE)
    file.store_string("{ this is not json")
    file.close()
    var restarted := _session("corrupt")
    check(restarted.continue_game(), "a corrupt save falls back to the backup")
    check_equal(restarted.load_message, "SAVE_RECOVERED_FROM_BACKUP", "and says so")
    check(restarted.progress.completed_missions.is_empty(), "the backup is the previous save")
    var both := FileAccess.open(restarted.repository.backup_path(), FileAccess.WRITE)
    both.store_string("also broken")
    both.close()
    var broken := _session("corrupt")
    check(not broken.continue_game(), "without a good backup, nothing loads")
    check_equal(broken.load_message, "SAVE_ERROR_CORRUPT", "and the player is told")
    check(broken.repository.locked, "the damaged save is not overwritten")
    broken.new_game()
    check(broken.save(), "a new game sets the damaged save aside")
    var kept := DirAccess.get_files_at(directory.path_join("corrupt"))
    var aside := 0
    for name in kept:
        if ".kept_" in name:
            aside += 1
    check_equal(aside, 2, "and keeps both damaged files")


func _test_unknown_version() -> void:
    var path := directory.path_join("future")
    DirAccess.make_dir_recursive_absolute(path)
    var text := JSON.stringify({"schema_version": 99, "character": {}})
    var file := FileAccess.open(path.path_join(SaveRepository.FILE_NAME), FileAccess.WRITE)
    file.store_string(text)
    file.close()
    var session := _session("future")
    check(not session.continue_game(), "a save of a newer version does not load")
    check_equal(session.load_message, "SAVE_ERROR_UNKNOWN_VERSION", "with an explanation")
    session.progress = Progress.new()
    check(not session.save(), "and is never overwritten")
    var after := FileAccess.get_file_as_string(path.path_join(SaveRepository.FILE_NAME))
    check_equal(after, text, "the file is untouched")


func _test_migration() -> void:
    var old := {
        "builder": {"name": "Ana", "xp": 20, "completed_missions": ["place_to_sit"]},
        "sites": {"place_to_sit": {"instances": [], "next_id": 1}},
    }
    var migrated := SaveRepository.migrate(old)
    check_equal(
        migrated["schema_version"], SaveRepository.SCHEMA_VERSION, "migrated to the current"
    )
    check(not migrated.has("builder") and not migrated.has("character"), "the character is gone")
    check_equal(
        migrated["progress"]["completed_missions"], ["place_to_sit"], "but its completions stay"
    )
    check(migrated["missions"].has("place_to_sit"), "the sites are kept by mission")


func _test_invalid_values() -> void:
    var problems: Array[String] = []
    var progress := Progress.from_dict(
        {"completed_missions": ["juggling", "place_to_sit"]}, content, problems
    )
    check_equal(progress.completed_missions, ["place_to_sit"], "an unknown mission is dropped")
    check(not problems.is_empty(), "and reported")
    check(Progress.from_dict("nonsense", content, problems) != null, "a damaged record is empty")
