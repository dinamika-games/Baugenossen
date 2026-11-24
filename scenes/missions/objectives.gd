class_name Objectives
extends RefCounted
## Validate and evaluate the objectives of the missions: deterministic
## predicates over a [SiteAnalysis] (DESIGN.md, 5.2).
##
## Every result is a dictionary with: "id", "satisfied", "current", "required",
## "text_key" (with the placeholders {current} and {required}), "hint_key" (why
## it is not satisfied, or ""), "cells" and "instances" to highlight.
##
## An unknown or not yet implemented type fails the content load (see
## [method validate]); it never passes silently.

## The parameters of each implemented type: name -> kind.
const TYPES := {
    "usable_tag_count":
    {
        "tag": "string",
        "minimum": "int",
        "?indoors": "bool",
        "?outdoors": "bool",
        "?zone": "zone",
        "?reachable": "bool",
        "?count_instances": "bool",
    },
    "enclosed_room_count": {"minimum": "int", "minimum_area": "int", "?accessible": "bool"},
    "room_with_tags": {"tags": "array", "minimum_count": "int", "?minimum_area": "int"},
    "distinct_rooms_with_tags": {"requirements": "array"},
    "reachable_zone": {"zone_id": "zone"},
    "connected_zones": {"a": "zone", "b": "zone", "?mode": "string"},
    "green_area": {"minimum_cells": "int"},
    "preserve_instances": {"ids": "array"},
    "max_height": {"cells": "int"},
    "forbidden_occupancy": {"zone_id": "zone"},
    "no_unsupported_parts": {},
    "all_of": {"objectives": "array"},
}

## Named in DESIGN.md, 5.2, but not implemented yet: no mission may use them.
const FUTURE_TYPES := [
    "daylight",
    "wheelchair_access",
    "material_budget",
    "water_clearance",
    "habitat",
    "heritage_preservation",
]

const COMMON_FIELDS := ["id", "type", "text_key", "xp", "karma"]


## Check an objective of the mission; return the problems (empty if valid).
static func validate(
    objective: Dictionary, mission: Dictionary, _content: ContentDb
) -> Array[String]:
    var problems: Array[String] = []
    var type := str(objective.get("type", ""))
    if type in FUTURE_TYPES:
        problems.append("the objective type %s is not implemented yet" % type)
        return problems
    if not TYPES.has(type):
        problems.append("unknown objective type '%s'" % type)
        return problems
    for field in ["id", "text_key"]:
        if not objective.has(field):
            problems.append("lacks the field %s" % field)
    var spec: Dictionary = TYPES[type]
    for key in spec:
        var name := str(key).trim_prefix("?")
        var optional := str(key).begins_with("?")
        if not objective.has(name):
            if not optional:
                problems.append("lacks the parameter %s" % name)
            continue
        var problem := _check_kind(objective[name], str(spec[key]), mission)
        if problem != "":
            problems.append("parameter %s %s" % [name, problem])
    for name in objective:
        if name not in COMMON_FIELDS and not spec.has(name) and not spec.has("?" + name):
            problems.append("unknown parameter %s" % name)
    if type == "connected_zones" and str(objective.get("mode", "walk")) not in ["walk"]:
        problems.append("mode %s is not implemented" % objective.get("mode"))
    return problems


static func _check_kind(value: Variant, kind: String, mission: Dictionary) -> String:
    match kind:
        "int":
            if not (value is int or value is float) or int(value) < 0:
                return "must be a non-negative number"
        "bool":
            if not value is bool:
                return "must be true or false"
        "string":
            if not value is String or str(value) == "":
                return "must be a text"
        "array":
            if not value is Array:
                return "must be a list"
        "zone":
            if not mission.get("zones", {}).has(str(value)):
                return "refers to the unknown zone %s" % value
    return ""


static func _result(
    objective: Dictionary, satisfied: bool, current: int, required: int
) -> Dictionary:
    return {
        "id": str(objective["id"]),
        "satisfied": satisfied,
        "current": current,
        "required": required,
        "text_key": str(objective["text_key"]),
        "hint_key": "",
        "cells": [],
        "instances": [],
        "xp": int(objective.get("xp", 0)),
        "karma": int(objective.get("karma", 0)),
    }


static func evaluate(
    objective: Dictionary, analysis: SiteAnalysis, mission: Dictionary
) -> Dictionary:
    var type := str(objective["type"])
    var result: Dictionary
    match type:
        "usable_tag_count":
            result = _usable_tag_count(objective, analysis, mission)
        "enclosed_room_count":
            result = _enclosed_room_count(objective, analysis)
        "room_with_tags":
            result = _room_with_tags(objective, analysis)
        "distinct_rooms_with_tags":
            result = _distinct_rooms_with_tags(objective, analysis)
        "reachable_zone":
            result = _reachable_zone(objective, analysis, mission)
        "connected_zones":
            result = _connected_zones(objective, analysis, mission)
        "green_area":
            var cells := analysis.green_cells()
            var required := int(objective["minimum_cells"])
            result = _result(objective, cells.size() >= required, cells.size(), required)
        "preserve_instances":
            result = _preserve_instances(objective, analysis)
        "max_height":
            result = _max_height(objective, analysis)
        "forbidden_occupancy":
            result = _forbidden_occupancy(objective, analysis, mission)
        "no_unsupported_parts":
            var problems := analysis.support_problems()
            result = _result(objective, problems.is_empty(), problems.size(), 0)
            for id in analysis.support.problem_ids():
                result["instances"].append(id)
            if not problems.is_empty():
                result["hint_key"] = str(problems[analysis.support.problem_ids()[0]])
        "all_of":
            result = _all_of(objective, analysis, mission)
        _:
            push_error("Unknown objective type %s" % type)
            result = _result(objective, false, 0, 1)
    return result


static func zone_rect(mission: Dictionary, zone_id: String) -> Rect2i:
    var rect: Array = mission["zones"][zone_id]["rect"]
    return Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))


static func _usable_tag_count(
    objective: Dictionary, analysis: SiteAnalysis, mission: Dictionary
) -> Dictionary:
    var grid := analysis.grid
    var tag := str(objective["tag"])
    var must_reach := bool(objective.get("reachable", true))
    var by_instance := bool(objective.get("count_instances", false))
    var zone := Rect2i()
    if objective.has("zone"):
        zone = zone_rect(mission, str(objective["zone"]))
    var count := 0
    var missed: Array[int] = []
    var hint := ""
    for id in grid.sorted_ids():
        var instance: PartInstance = grid.instances[id]
        var definition := grid.definition_of(instance)
        if not definition.has_tag(tag):
            continue
        if objective.has("zone") and not zone.has_point(instance.anchor):
            continue
        if bool(objective.get("indoors", false)) and not analysis.is_indoors(id):
            missed.append(id)
            hint = "HINT_NOT_INDOORS"
            continue
        if bool(objective.get("outdoors", false)) and analysis.is_indoors(id):
            continue
        if must_reach and not analysis.is_usable(id):
            missed.append(id)
            hint = "HINT_UNREACHABLE"
            continue
        count += 1 if by_instance else definition.tag_value(tag)
    var required := int(objective["minimum"])
    var result := _result(objective, count >= required, count, required)
    if count < required:
        result["instances"] = missed
        result["hint_key"] = hint
    return result


static func _room_qualifies(
    room: RoomDetector.Room, analysis: SiteAnalysis, minimum_area: int
) -> bool:
    return room.area() >= minimum_area and analysis.room_accessible(room)


static func _enclosed_room_count(objective: Dictionary, analysis: SiteAnalysis) -> Dictionary:
    var minimum_area := int(objective["minimum_area"])
    var accessible := bool(objective.get("accessible", true))
    var count := 0
    var largest := 0
    var hint := "HINT_NO_ROOM"
    for room in analysis.rooms.rooms:
        largest = maxi(largest, room.area())
        if room.area() < minimum_area:
            hint = "HINT_ROOM_TOO_SMALL"
            continue
        if accessible and not analysis.room_accessible(room):
            hint = "HINT_ROOM_NO_ENTRANCE"
            continue
        count += 1
    var required := int(objective["minimum"])
    var result := _result(objective, count >= required, count, required)
    if count < required:
        result["hint_key"] = hint
    return result


## The tags which have a usable instance in each room: room ID -> {tag: true}.
static func _tags_by_room(analysis: SiteAnalysis) -> Dictionary:
    var result := {}
    var grid := analysis.grid
    for id in grid.sorted_ids():
        if not analysis.is_usable(id) or not analysis.is_indoors(id):
            continue
        var room := analysis.room_of(id)
        if not result.has(room):
            result[room] = {}
        for tag in grid.definition_of(grid.instances[id]).tags:
            result[room][tag] = true
    return result


static func _room_has(tags_by_room: Dictionary, room: int, tags: Array) -> bool:
    for tag in tags:
        if not tags_by_room.get(room, {}).has(str(tag)):
            return false
    return true


static func _room_with_tags(objective: Dictionary, analysis: SiteAnalysis) -> Dictionary:
    var tags_by_room := _tags_by_room(analysis)
    var minimum_area := int(objective.get("minimum_area", 0))
    var count := 0
    for room in analysis.rooms.rooms:
        if (
            _room_qualifies(room, analysis, minimum_area)
            and _room_has(tags_by_room, room.id, objective["tags"])
        ):
            count += 1
    var required := int(objective["minimum_count"])
    var result := _result(objective, count >= required, count, required)
    if count < required:
        result["hint_key"] = "HINT_ROOM_MISSING_THINGS"
    return result


## Match the requirements to distinct rooms, so that no room counts twice;
## return how many requirements the best matching fulfils.
static func _distinct_rooms_with_tags(objective: Dictionary, analysis: SiteAnalysis) -> Dictionary:
    var tags_by_room := _tags_by_room(analysis)
    var requirements: Array = objective["requirements"]
    var candidates: Array = []
    for requirement in requirements:
        var rooms: Array[int] = []
        for room in analysis.rooms.rooms:
            if (
                _room_qualifies(room, analysis, int(requirement.get("minimum_area", 0)))
                and _room_has(tags_by_room, room.id, requirement["tags"])
            ):
                rooms.append(room.id)
        candidates.append(rooms)
    var matched := _max_matching(candidates)
    var result := _result(objective, matched >= requirements.size(), matched, requirements.size())
    if matched < requirements.size():
        result["hint_key"] = "HINT_DISTINCT_ROOMS"
    return result


## The size of the maximum matching of the requirements (each with its candidate
## rooms) to distinct rooms (augmenting paths).
static func _max_matching(candidates: Array) -> int:
    var owner := {}
    var matched := 0
    for requirement in range(candidates.size()):
        if _augment(requirement, candidates, owner, {}):
            matched += 1
    return matched


static func _augment(
    requirement: int, candidates: Array, owner: Dictionary, visited: Dictionary
) -> bool:
    for room in candidates[requirement]:
        if visited.has(room):
            continue
        visited[room] = true
        if not owner.has(room) or _augment(int(owner[room]), candidates, owner, visited):
            owner[room] = requirement
            return true
    return false


static func _reachable_zone(
    objective: Dictionary, analysis: SiteAnalysis, mission: Dictionary
) -> Dictionary:
    var rect := zone_rect(mission, str(objective["zone_id"]))
    for cell in analysis.reachable:
        if rect.has_point(cell):
            return _result(objective, true, 1, 1)
    var result := _result(objective, false, 0, 1)
    result["hint_key"] = "HINT_ZONE_UNREACHABLE"
    return result


static func _connected_zones(
    objective: Dictionary, analysis: SiteAnalysis, mission: Dictionary
) -> Dictionary:
    var a := zone_rect(mission, str(objective["a"]))
    var b := zone_rect(mission, str(objective["b"]))
    var graph := NavigationGraph.build(analysis.grid, str(objective.get("mode", "walk")))
    var starts: Array[Vector2i] = []
    for y in range(a.position.y, a.end.y):
        for x in range(a.position.x, a.end.x):
            starts.append(Vector2i(x, y))
    for cell in graph.reachable_from_many(starts):
        if b.has_point(cell):
            return _result(objective, true, 1, 1)
    var result := _result(objective, false, 0, 1)
    result["hint_key"] = "HINT_ZONES_NOT_CONNECTED"
    return result


static func _preserve_instances(objective: Dictionary, analysis: SiteAnalysis) -> Dictionary:
    var kept := 0
    var missing: Array[int] = []
    for value in objective["ids"]:
        var instance: PartInstance = analysis.grid.instances.get(int(value))
        if instance != null and instance.protected:
            kept += 1
        else:
            missing.append(int(value))
    var required: int = objective["ids"].size()
    var result := _result(objective, kept == required, kept, required)
    result["instances"] = missing
    return result


static func _max_height(objective: Dictionary, analysis: SiteAnalysis) -> Dictionary:
    var limit := int(objective["cells"])
    var highest := 0
    var over: Array[int] = []
    for id in analysis.grid.sorted_ids():
        var top := analysis.grid.top_of(analysis.grid.instances[id])
        highest = maxi(highest, top)
        if top > limit:
            over.append(id)
    var result := _result(objective, highest <= limit, highest, limit)
    result["instances"] = over
    if highest > limit:
        result["hint_key"] = "HINT_TOO_HIGH"
    return result


static func _forbidden_occupancy(
    objective: Dictionary, analysis: SiteAnalysis, mission: Dictionary
) -> Dictionary:
    var rect := zone_rect(mission, str(objective["zone_id"]))
    var inside: Array[int] = []
    for id in analysis.grid.sorted_ids():
        for key in analysis.grid.slots_of(analysis.grid.instances[id]):
            if rect.has_point(key):
                inside.append(id)
                break
    var result := _result(objective, inside.is_empty(), inside.size(), 0)
    result["instances"] = inside
    if not inside.is_empty():
        result["hint_key"] = "HINT_ZONE_MUST_STAY_FREE"
    return result


static func _all_of(
    objective: Dictionary, analysis: SiteAnalysis, mission: Dictionary
) -> Dictionary:
    var parts: Array = objective["objectives"]
    var done := 0
    var hint := ""
    var instances: Array = []
    for part in parts:
        var sub := evaluate(part, analysis, mission)
        if sub["satisfied"]:
            done += 1
        elif hint == "":
            hint = str(sub["hint_key"])
            instances = sub["instances"]
    var result := _result(objective, done == parts.size(), done, parts.size())
    result["hint_key"] = hint
    result["instances"] = instances
    return result
