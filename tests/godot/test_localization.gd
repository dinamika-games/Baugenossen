extends "res://tests/godot/godot_test.gd"
## Check the translations (DESIGN.md, 8): every key the content and the code
## use exists in translations/translations.csv with an English text, no key is
## its own text, and switching the locale changes no ID.

const DYNAMIC_PREFIXES := {
    "STATE_":
    ["CALIBRATION", "BUILD", "CATALOGUE", "GESTURE_PENDING", "PAUSED", "REVIEW", "COMPLETE"],
    "TUTORIAL_": ["SELECT", "MOVE", "PLACE", "REMOVE", "UNDO"],
    "CALIBRATION_STEP_": ["NEUTRAL", "LEFT", "RIGHT", "UP", "DOWN"],
    "CALIBRATION_STATUS_": ["OFF", "STARTING", "RUNNING", "FAILED"],
    "CALIBRATION_MODE_": ["PLANK", "KNEES", "SEATED", "STANDING"],
    "GESTURE_MODE_": ["PLANK", "KNEES", "SEATED", "STANDING"],
    "LANGUAGE_": ["EN"],
    "CREATE_LOOK_": ["SKIN", "HAIR", "CLOTHING"],
}


func _run() -> void:
    var content := ContentDb.get_default()
    var table := _read_csv("res://translations/translations.csv")
    check(table.size() > 300, "the table has the keys (%d)" % table.size())
    var keys := content.translation_keys()
    keys.append_array(_code_keys("res://scenes"))
    for prefix in DYNAMIC_PREFIXES:
        for suffix in DYNAMIC_PREFIXES[prefix]:
            keys.append(prefix + suffix)
    keys.append_array(Progression.LEVEL_RANKS.map(func(entry: Array) -> String: return entry[1]))
    keys.append_array(Progression.REPUTATIONS.map(func(entry: Array) -> String: return entry[1]))
    var missing: Array[String] = []
    for key in keys:
        if not table.has(key) and key not in missing:
            missing.append(key)
    check(missing.is_empty(), "every key is translated; missing: %s" % [missing])
    for key in table:
        check(str(table[key]).strip_edges() != "", "%s has an English text" % key)
    TranslationServer.set_locale("en")
    check_equal(tr("ITEM_BED_SINGLE"), "Bed", "the translation is loaded")
    var line := MissionText.line("OBJ_HOME_BEDS", 1, 2)
    check(
        line.contains("1") and line.contains("2") and not line.contains("{"),
        "placeholders: " + line
    )
    var before := content.mission_order.duplicate()
    TranslationServer.set_locale("de")
    check_equal(content.mission_order, before, "the IDs do not depend on the locale")
    TranslationServer.set_locale("en")


func _read_csv(path: String) -> Dictionary:
    var table := {}
    var file := FileAccess.open(path, FileAccess.READ)
    var header := file.get_csv_line()
    check_equal(header[0], "keys", "the CSV starts with keys")
    while not file.eof_reached():
        var row := file.get_csv_line()
        if row.size() >= 2 and row[0] != "":
            check(not table.has(row[0]), "%s is defined once" % row[0])
            table[row[0]] = row[1]
    return table


## The literal keys of tr("...") in the scripts.
func _code_keys(directory: String) -> Array[String]:
    var keys: Array[String] = []
    var pattern := RegEx.create_from_string('tr\\("([A-Z0-9_]+)"\\)')
    for name in DirAccess.get_files_at(directory):
        if name.ends_with(".gd"):
            var text := FileAccess.get_file_as_string(directory.path_join(name))
            for found in pattern.search_all(text):
                keys.append(found.get_string(1))
    for sub in DirAccess.get_directories_at(directory):
        keys.append_array(_code_keys(directory.path_join(sub)))
    return keys
