class_name PartInstance
extends RefCounted
## Hold one part placed on a site: its unique ID, the ID of its definition, its
## anchor (the bottom-left cell, or the first edge), whether it is mirrored and
## its colour variant. Protected instances are part of the site and can not be
## removed. Everything else (its cells and edges) is derived from the definition.

var id := 0
var definition_id := ""
var anchor := Vector2i.ZERO
var mirrored := false
var colour_variant := 0
var protected := false


static func create(
    instance_id: int, definition: String, at: Vector2i, mirror := false, variant := 0
) -> PartInstance:
    var instance := PartInstance.new()
    instance.id = instance_id
    instance.definition_id = definition
    instance.anchor = at
    instance.mirrored = mirror
    instance.colour_variant = variant
    return instance


func duplicate_instance() -> PartInstance:
    var copy := PartInstance.create(id, definition_id, anchor, mirrored, colour_variant)
    copy.protected = protected
    return copy


func same_as(other: PartInstance) -> bool:
    return (
        other != null
        and other.id == id
        and other.definition_id == definition_id
        and other.anchor == anchor
        and other.mirrored == mirrored
    )


func to_dict() -> Dictionary:
    var result := {
        "id": id,
        "definition_id": definition_id,
        "anchor": [anchor.x, anchor.y],
        "mirrored": mirrored,
        "colour_variant": colour_variant,
    }
    if protected:
        result["protected"] = true
    return result


## Read an instance from its dictionary; null if the dictionary is malformed.
static func from_dict(record: Variant) -> PartInstance:
    if not record is Dictionary:
        return null
    var data: Dictionary = record
    if not data.has("id") or not data.has("definition_id") or not data.has("anchor"):
        return null
    var at: Variant = data["anchor"]
    if not at is Array or at.size() != 2:
        return null
    if not (at[0] is float or at[0] is int) or not (at[1] is float or at[1] is int):
        return null
    var instance := PartInstance.create(
        int(data["id"]),
        str(data["definition_id"]),
        Vector2i(int(at[0]), int(at[1])),
        bool(data.get("mirrored", false)),
        int(data.get("colour_variant", 0))
    )
    instance.protected = bool(data.get("protected", false))
    return instance
