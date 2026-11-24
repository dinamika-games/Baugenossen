class_name ContentDb
extends RefCounted
## Load and validate the game content of data/*.json: the parts, the skills, the
## backgrounds, the traits, the perks, the sites, the residents and the missions.
##
## The content is language-neutral: every text is a translation key (see
## translations/translations.csv). Every reference between the records is checked
## at load time; an invalid record (e.g., an unknown objective type) fails the
## load with a diagnostic in [member errors], and never passes silently.

const DATA_DIR := "res://data"

const LAYERS := ["edge_h", "edge_v", "background", "window", "volume", "decor", "surface"]
const SUPPORT_RULES := ["none", "base", "span", "wall", "beam", "stairs", "ladder"]
const ATTRIBUTE_IDS := ["B", "U", "I", "L", "D", "E", "R"]

static var _default: ContentDb = null

## The parts by their ID, in the order of the file.
var parts: Dictionary = {}
var part_order: Array[String] = []
var categories: Array = []
var skills: Dictionary = {}
var skill_order: Array[String] = []
var skill_ranks: Array = []
var attributes: Array = []
var default_attributes: Dictionary = {}
var attribute_total := 40
var attribute_min := 1
var attribute_max := 10
var backgrounds: Dictionary = {}
var background_order: Array[String] = []
var traits: Dictionary = {}
var trait_order: Array[String] = []
var max_traits := 2
var perks: Dictionary = {}
var perk_order: Array[String] = []
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
    _load_skills(_read_json(directory + "/skills.json"))
    _load_backgrounds(_read_json(directory + "/backgrounds.json"))
    _load_traits(_read_json(directory + "/traits.json"))
    _load_perks(_read_json(directory + "/perks.json"))
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
        keys.append(definition.name_key)
        keys.append(definition.description_key)
    for category in categories:
        keys.append(str(category["name_key"]))
    for attribute in attributes:
        keys.append(str(attribute["name_key"]))
        keys.append(str(attribute["description_key"]))
    for id in skill_order:
        keys.append(str(skills[id]["name_key"]))
    for rank in skill_ranks:
        keys.append(str(rank["key"]))
    for records in [backgrounds, traits, perks]:
        for record in records.values():
            keys.append(str(record["name_key"]))
            keys.append(str(record["description_key"]))
    for record in sites.values():
        keys.append(str(record["name_key"]))
    for record in residents.values():
        keys.append(str(record["name_key"]))
    for id in mission_order:
        var record: Dictionary = missions[id]
        for field in ["title_key", "brief_key", "completion_dialogue_key"]:
            keys.append(str(record[field]))
        for zone in record["zones"].values():
            keys.append(str(zone["name_key"]))
        for objective in _all_objectives(record):
            keys.append(str(objective["text_key"]))
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
        var fields := [
            "id", "name_key", "description_key", "category_id", "layer", "footprint", "mass"
        ]
        fields.append_array(["tags", "support_rule", "visual_id", "requirements"])
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


func _load_skills(data: Dictionary) -> void:
    attributes = data.get("attributes", [])
    default_attributes = data.get("default_attributes", {})
    attribute_total = int(data.get("attribute_total", 40))
    attribute_min = int(data.get("attribute_min", 1))
    attribute_max = int(data.get("attribute_max", 10))
    skill_ranks = data.get("ranks", [])
    for record in data.get("skills", []):
        if not _require(record, ["id", "name_key", "attributes"], "skill"):
            continue
        for attribute in record["attributes"]:
            if attribute not in ATTRIBUTE_IDS:
                _error("skill %s refers to the unknown attribute %s" % [record["id"], attribute])
        skills[str(record["id"])] = record
        skill_order.append(str(record["id"]))
    var total := 0
    for attribute in ATTRIBUTE_IDS:
        total += int(default_attributes.get(attribute, 0))
    if total != attribute_total:
        _error("the default attributes sum to %d, not %d" % [total, attribute_total])


func _check_skill_map(map: Dictionary, context: String) -> void:
    for key in map:
        if key != "*" and key not in skills:
            _error("%s refers to the unknown skill %s" % [context, key])


func _load_backgrounds(data: Dictionary) -> void:
    for record in data.get("backgrounds", []):
        if not _require(record, ["id", "name_key", "description_key", "skill_bonuses"], "bg"):
            continue
        _check_skill_map(record["skill_bonuses"], "background %s" % record["id"])
        backgrounds[str(record["id"])] = record
        background_order.append(str(record["id"]))


func _load_traits(data: Dictionary) -> void:
    max_traits = int(data.get("max_traits", 2))
    for record in data.get("traits", []):
        if not _require(record, ["id", "name_key", "description_key", "skill_modifiers"], "trait"):
            continue
        _check_skill_map(record["skill_modifiers"], "trait %s" % record["id"])
        traits[str(record["id"])] = record
        trait_order.append(str(record["id"]))


func _check_requirements(requirements: Array, context: String) -> void:
    for requirement in requirements:
        var kind := str(requirement.get("type", ""))
        match kind:
            "skill":
                if str(requirement.get("id", "")) not in skills:
                    _error("%s requires the unknown skill %s" % [context, requirement.get("id")])
            "attribute":
                if str(requirement.get("id", "")) not in ATTRIBUTE_IDS:
                    _error("%s requires the unknown attribute %s" % [context, requirement])
            "level", "any_skill", "perk":
                pass
            _:
                _error("%s has the unknown requirement type %s" % [context, kind])


func _load_perks(data: Dictionary) -> void:
    for record in data.get("perks", []):
        if not _require(record, ["id", "name_key", "description_key", "requirements"], "perk"):
            continue
        _check_requirements(record["requirements"], "perk %s" % record["id"])
        perks[str(record["id"])] = record
        perk_order.append(str(record["id"]))
    for id in part_order:
        _check_requirements(part(id).requirements, "part %s" % id)


func _load_sites(data: Dictionary) -> void:
    for record in data.get("sites", []):
        if not _require(record, ["id", "name_key", "width", "height", "entry"], "site"):
            continue
        if int(record["width"]) < 4 or int(record["height"]) < 4:
            _error("site %s is too small" % record["id"])
        for instance in record.get("initial_instances", []):
            if str(instance.get("definition_id", "")) not in parts:
                _error("site %s places an unknown part %s" % [record["id"], instance])
        sites[str(record["id"])] = record


func _load_residents(data: Dictionary) -> void:
    for record in data.get("residents", []):
        if _require(record, ["id", "name_key"], "resident"):
            residents[str(record["id"])] = record


func _load_missions(data: Dictionary) -> void:
    var fields := ["id", "title_key", "brief_key", "site_id", "requester_ids", "prerequisite_ids"]
    fields.append_array(["base_xp", "base_karma", "completion_dialogue_key"])
    fields.append_array(["mandatory_objectives", "optional_objectives", "npc_spawn_defs"])
    for record in data.get("missions", []):
        var context := "mission %s" % record.get("id", "?")
        if not _require(record, fields, context):
            continue
        record["min_karma"] = int(record.get("min_karma", 0))
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
