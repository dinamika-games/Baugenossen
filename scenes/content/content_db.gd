class_name ContentDb
extends RefCounted
## Load and validate the game content of data/*.json: the parts, the sites,
## the residents and the missions.
##
## The content is language-neutral: every text is a translation key (see
## translations/translations.csv). Every reference between the records is checked
## at load time; an invalid record (e.g., an unknown objective type) fails the
## load with a diagnostic in [member errors], and never passes silently.

const DATA_DIR := "res://data"

const LAYERS := ["edge_h", "edge_v", "background", "window", "volume", "decor", "surface"]
const SUPPORT_RULES := ["none", "base", "span", "wall", "beam", "stairs", "ladder"]

static var _default: ContentDb = null

## The parts by their ID, in the order of the file.
var parts: Dictionary = {}
var part_order: Array[String] = []
var categories: Array = []
var sites: Dictionary = {}
var residents: Dictionary = {}
var missions: Dictionary = {}
var mission_order: Array[String] = []

## The problems found while loading; empty if the content is valid.
var errors: Array[String] = []


## Load the content of the game once and keep it; push the errors, if any.
static func get_default() -> ContentDb:
    if _default == null:
        _default = ContentDb.new()
        _default.load_from(DATA_DIR)
        for error in _default.errors:
            push_error("Content: " + error)
    return _default


func load_from(directory: String) -> bool:
    errors.clear()
    _load_parts(_read_json(directory + "/parts.json"))
    _load_sites(_read_json(directory + "/sites.json"))
    _load_residents(_read_json(directory + "/residents.json"))
    _load_missions(_read_json(directory + "/missions.json"))
    return errors.is_empty()


func part(id: String) -> PartDef:
    return parts.get(id) as PartDef


func mission(id: String) -> Dictionary:
    return missions.get(id, {})


func site(id: String) -> Dictionary:
    return sites.get(id, {})


## Collect every translation key the content refers to, for the coverage check.
func translation_keys() -> Array[String]:
    var keys: Array[String] = []
    for id in part_order:
        var definition := part(id)
        keys.append(definition.name)
        keys.append(definition.description)
    for category in categories:
        keys.append(str(category["name"]))
    for record in sites.values():
        keys.append(str(record["name"]))
    for record in residents.values():
        keys.append(str(record["name"]))
    for id in mission_order:
        var record: Dictionary = missions[id]
        for field in ["title", "brief", "thanks"]:
            keys.append(str(record[field]))
        for zone in record["zones"].values():
            keys.append(str(zone["name"]))
        for objective in _all_objectives(record):
            keys.append(str(objective["text"]))
    return keys


static func _all_objectives(record: Dictionary) -> Array:
    var result: Array = []
    var pending: Array = []
    pending.append_array(record["mandatory_objectives"])
    pending.append_array(record["optional_objectives"])
    while not pending.is_empty():
        var objective: Dictionary = pending.pop_front()
        result.append(objective)
        if objective.has("objectives"):
            pending.append_array(objective["objectives"])
    return result


func _error(message: String) -> void:
    errors.append(message)


func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        _error("missing file %s" % path)
        return {}
    var parsed: Variant = Json.parse(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        _error("%s is not a JSON object" % path)
        return {}
    return parsed


func _require(record: Dictionary, fields: Array, context: String) -> bool:
    var ok := true
    for field in fields:
        if not record.has(field):
            _error("%s lacks the field %s" % [context, field])
            ok = false
    return ok


func _load_parts(data: Dictionary) -> void:
    categories = data.get("categories", [])
    var category_ids := {}
    for category in categories:
        category_ids[str(category["id"])] = true
    for record in data.get("parts", []):
        var context := "part %s" % record.get("id", "?")
        var fields := ["id", "name", "description", "category_id", "layer", "footprint", "mass"]
        fields.append_array(["tags", "support_rule", "visual_id"])
        if not _require(record, fields, context):
            continue
        var definition := PartDef.from_dict(record)
        if definition.id in parts:
            _error("%s is defined twice" % context)
        if definition.layer not in LAYERS:
            _error("%s has the unknown layer %s" % [context, definition.layer])
        if definition.support_rule not in SUPPORT_RULES:
            _error("%s has the unknown support rule %s" % [context, definition.support_rule])
        if definition.category_id not in category_ids:
            _error("%s has the unknown category %s" % [context, definition.category_id])
        if not definition.has_valid_footprint():
            _error("%s has an invalid footprint %s" % [context, record["footprint"]])
        if definition.support_rule in ["stairs", "ladder"] and definition.landings.size() != 2:
            _error("%s needs exactly two landings" % context)
        parts[definition.id] = definition
        part_order.append(definition.id)


func _load_sites(data: Dictionary) -> void:
    for record in data.get("sites", []):
        if not _require(record, ["id", "name", "width", "height", "entry"], "site"):
            continue
        if int(record["width"]) < 4 or int(record["height"]) < 4:
            _error("site %s is too small" % record["id"])
        for instance in record.get("initial_instances", []):
            if str(instance.get("definition_id", "")) not in parts:
                _error("site %s places an unknown part %s" % [record["id"], instance])
        sites[str(record["id"])] = record


func _load_residents(data: Dictionary) -> void:
    for record in data.get("residents", []):
        if _require(record, ["id", "name"], "resident"):
            residents[str(record["id"])] = record


func _load_missions(data: Dictionary) -> void:
    var fields := ["id", "title", "brief", "site_id", "requester_ids", "prerequisite_ids"]
    fields.append("thanks")
    fields.append_array(["mandatory_objectives", "optional_objectives", "npc_spawn_defs"])
    for record in data.get("missions", []):
        var context := "mission %s" % record.get("id", "?")
        if not _require(record, fields, context):
            continue
        if not record.has("zones"):
            record["zones"] = {}
        if not record.has("available_catalogue_ids"):
            record["available_catalogue_ids"] = []
        if str(record["site_id"]) not in sites:
            _error("%s uses the unknown site %s" % [context, record["site_id"]])
        for resident in record["requester_ids"]:
            if resident not in residents:
                _error("%s refers to the unknown resident %s" % [context, resident])
        for spawn in record["npc_spawn_defs"]:
            if str(spawn.get("resident_id", "")) not in residents:
                _error("%s spawns the unknown resident %s" % [context, spawn])
        for part_id in record["available_catalogue_ids"]:
            if part_id not in parts:
                _error("%s offers the unknown part %s" % [context, part_id])
        var ids := {}
        for objective in record["mandatory_objectives"] + record["optional_objectives"]:
            var id := str(objective.get("id", ""))
            if id in ids:
                _error("%s has the objective %s twice" % [context, id])
            ids[id] = true
        for objective in _all_objectives(record):
            for problem in Objectives.validate(objective, record, self):
                _error("%s, objective %s: %s" % [context, objective.get("id", "?"), problem])
        missions[str(record["id"])] = record
        mission_order.append(str(record["id"]))
    for id in mission_order:
        for prerequisite in missions[id]["prerequisite_ids"]:
            if prerequisite not in missions:
                _error("mission %s requires the unknown mission %s" % [id, prerequisite])
