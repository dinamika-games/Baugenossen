extends "res://tests/godot/godot_test.gd"
## Check the saves: the roundtrip, an incomplete site, the backup after
## corruption, an unknown version left untouched, the migration, and that a
## resubmitted mission grants nothing twice, also after a restart (DESIGN.md,
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


func _character() -> Character:
    var character := Character.create_default(content)
    character.name = "Ana"
    return character


func _test_roundtrip_and_no_duplicate_rewards() -> void:
    var builds := SampleBuilds.new(content)
    var session := _session("roundtrip")
    session.new_game(_character())
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
    check_equal(restarted.character.xp, 20, "with the XP of the tutorial")
    check(restarted.character.has_completed("place_to_sit"), "and its completion")
    check_equal(restarted.mission_status("first_home"), "in_progress", "the home is in progress")
    check_equal(restarted.open_site("first_home").instances.size(), 1, "with its wall")
    var again := restarted.submit("place_to_sit", restarted.open_site("place_to_sit"))
    check(again["submitted"], "the tutorial can be resubmitted")
    check_equal(again["xp"], 0, "but grants no XP again")
    check_equal(restarted.character.xp, 20, "the XP stays")
    var bench: int = sit.at(WorldGrid.SLOT_CELLS, Vector2i(5, 0))
    var site := restarted.open_site("place_to_sit")
    site.remove_instance(bench)
    restarted.store_site("place_to_sit", site)
    check_equal(
        restarted.mission_status("place_to_sit"), "needs_repair", "a broken site needs repair"
    )
    check_equal(restarted.character.karma, 20, "without losing the karma")


func _test_corruption_falls_back() -> void:
    var session := _session("corrupt")
    session.new_game(_character())
    session.save()
    session.character.xp = 5
    session.save()
    var file := FileAccess.open(session.repository.path(), FileAccess.WRITE)
    file.store_string("{ this is not json")
    file.close()
    var restarted := _session("corrupt")
    check(restarted.continue_game(), "a corrupt save falls back to the backup")
    check_equal(restarted.load_message, "SAVE_RECOVERED_FROM_BACKUP", "and says so")
    check_equal(restarted.character.xp, 0, "the backup is the previous save")
    var both := FileAccess.open(restarted.repository.backup_path(), FileAccess.WRITE)
    both.store_string("also broken")
    both.close()
    var broken := _session("corrupt")
    check(not broken.continue_game(), "without a good backup, nothing loads")
    check_equal(broken.load_message, "SAVE_ERROR_CORRUPT", "and the player is told")
    check(broken.repository.locked, "the damaged save is not overwritten")
    broken.new_game(_character())
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
    session.character = _character()
    check(not session.save(), "and is never overwritten")
    var after := FileAccess.get_file_as_string(path.path_join(SaveRepository.FILE_NAME))
    check_equal(after, text, "the file is untouched")


func _test_migration() -> void:
    var old := {
        "builder": _character().to_dict(),
        "sites": {"place_to_sit": {"instances": [], "next_id": 1}},
    }
    var migrated := SaveRepository.migrate(old)
    check_equal(
        migrated["schema_version"], SaveRepository.SCHEMA_VERSION, "migrated to the current"
    )
    check(migrated.has("character") and not migrated.has("builder"), "the builder is the character")
    check(migrated["missions"].has("place_to_sit"), "the sites are kept by mission")


func _test_invalid_values() -> void:
    var problems: Array[String] = []
    var record := _character().to_dict()
    record["attributes"]["B"] = 50
    check(Character.from_dict(record, content, problems) == null, "an attribute of 50 is rejected")
    record = _character().to_dict()
    record["background_id"] = "astronaut"
    check(Character.from_dict(record, content, problems) == null, "an unknown background too")
    record = _character().to_dict()
    record["invested"] = {"carpentry": 500}
    record["xp"] = -10
    var character := Character.from_dict(record, content, problems)
    check_equal(character.invested["carpentry"], 100, "investments are capped")
    check_equal(character.xp, 0, "the XP is never negative")
