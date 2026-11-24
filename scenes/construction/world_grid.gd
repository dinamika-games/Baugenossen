class_name WorldGrid
extends RefCounted
## Hold the authoritative construction state of one site: the parts placed on
## it and which slots they occupy (DESIGN.md, 2.1 and 2.2).
##
## The grid knows nothing about the rendering, the input or the missions. It
## only checks the geometry of a placement (bounds, overlaps and crossings);
## [Placement] adds the support, the mass and the unlocks. The edits go through
## [EditCommand]s so that they can be undone.

signal changed

## The slot maps: each maps a cell or an edge (Vector2i) to the instance ID.
const SLOT_CELLS := "cells"
const SLOT_SURFACE := "surface"
const SLOT_BACKGROUND := "background"
const SLOT_WINDOW := "window"
const SLOT_EDGE_H := "edge_h"
const SLOT_EDGE_V := "edge_v"

var width := 40
var height := 24
var entry := Vector2i.ZERO
var content: ContentDb
var instances: Dictionary = {}
var next_id := 1

var _slots: Dictionary = {
    SLOT_CELLS: {},
    SLOT_SURFACE: {},
    SLOT_BACKGROUND: {},
    SLOT_WINDOW: {},
    SLOT_EDGE_H: {},
    SLOT_EDGE_V: {},
}


func _init(db: ContentDb = null, site_width := 40, site_height := 24) -> void:
    content = db
    width = site_width
    height = site_height


## Make the grid of a site of the content, with its protected initial parts.
static func from_site(db: ContentDb, site: Dictionary) -> WorldGrid:
    var grid := WorldGrid.new(db, int(site["width"]), int(site["height"]))
    grid.entry = Vector2i(int(site["entry"][0]), int(site["entry"][1]))
    for record in site.get("initial_instances", []):
        var instance := PartInstance.from_dict(record)
        instance.id = grid.allocate_id()
        instance.protected = true
        grid.add_instance(instance)
    return grid


func allocate_id() -> int:
    var result := next_id
    next_id += 1
    return result


func definition_of(instance: PartInstance) -> PartDef:
    return content.part(instance.definition_id)


static func slot_map_name(definition: PartDef) -> String:
    match definition.layer:
        "edge_h":
            return SLOT_EDGE_H
        "edge_v":
            return SLOT_EDGE_V
        "surface":
            return SLOT_SURFACE
        "background":
            return SLOT_BACKGROUND
        "window":
            return SLOT_WINDOW
        _:
            return SLOT_CELLS


## The slots (cells or edges) which a part covers at the anchor.
static func slot_keys(definition: PartDef, anchor: Vector2i) -> Array[Vector2i]:
    var keys: Array[Vector2i] = []
    match definition.layer:
        "edge_h":
            for dx in range(definition.footprint.x):
                keys.append(anchor + Vector2i(dx, 0))
        "edge_v":
            for dy in range(definition.footprint.y):
                keys.append(anchor + Vector2i(0, dy))
        _:
            for dy in range(definition.footprint.y):
                for dx in range(definition.footprint.x):
                    keys.append(anchor + Vector2i(dx, dy))
    return keys


func slots_of(instance: PartInstance) -> Array[Vector2i]:
    return slot_keys(definition_of(instance), instance.anchor)


## The cells of a cell-layer part, or [] for an edge part.
func cells_of(instance: PartInstance) -> Array[Vector2i]:
    var definition := definition_of(instance)
    if not definition.is_cell_layer():
        return []
    return slot_keys(definition, instance.anchor)


## The instance ID in the slot of the map, or 0 if the slot is free.
func at(map_name: String, key: Vector2i) -> int:
    return int(_slots[map_name].get(key, 0))


func instance_in(map_name: String, key: Vector2i) -> PartInstance:
    var id := at(map_name, key)
    return instances.get(id) as PartInstance if id != 0 else null


func cell_in_bounds(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


## Check that every slot of the part is within the site.
func slots_in_bounds(definition: PartDef, anchor: Vector2i) -> bool:
    for key in slot_keys(definition, anchor):
        match definition.layer:
            "edge_h":
                # NOTE (mristin):
                # H(x, 0) is the ground, which is not ours to build.
                if key.x < 0 or key.x >= width or key.y < 1 or key.y > height:
                    return false
            "edge_v":
                if key.x < 0 or key.x > width or key.y < 0 or key.y >= height:
                    return false
            _:
                if not cell_in_bounds(key):
                    return false
    return true


## Check the geometry of a placement: within the site, no overlap with the
## parts of the same slots (except those in [param ignore]), and no edge through
## the middle of a volume. Return a [PlacementResult].
func check_geometry(
    definition: PartDef, anchor: Vector2i, ignore: Array[int] = []
) -> PlacementResult:
    if not slots_in_bounds(definition, anchor):
        return PlacementResult.invalid("ERROR_OUT_OF_BOUNDS")
    var map_name := slot_map_name(definition)
    for key in slot_keys(definition, anchor):
        var other := at(map_name, key)
        if other != 0 and other not in ignore:
            return PlacementResult.invalid("ERROR_OVERLAP", [other])
    var crossed := _crossed_instances(definition, anchor, ignore)
    if not crossed.is_empty():
        return PlacementResult.invalid("ERROR_CROSSES_PART", crossed)
    return PlacementResult.valid()


## The instances which an edge part would cut through, or whose cells a volume
## would put around an existing edge.
func _crossed_instances(definition: PartDef, anchor: Vector2i, ignore: Array[int]) -> Array[int]:
    var crossed: Array[int] = []
    var cells: Dictionary = _slots[SLOT_CELLS]
    match definition.layer:
        "edge_v":
            for key in slot_keys(definition, anchor):
                var left := int(cells.get(key + Vector2i(-1, 0), 0))
                var right := int(cells.get(key, 0))
                if left != 0 and left == right and left not in ignore and left not in crossed:
                    crossed.append(left)
        "edge_h":
            for key in slot_keys(definition, anchor):
                var below := int(cells.get(key + Vector2i(0, -1), 0))
                var above := int(cells.get(key, 0))
                if below != 0 and below == above and below not in ignore and below not in crossed:
                    crossed.append(below)
        "volume", "decor":
            var size := definition.footprint
            for dy in range(size.y):
                for dx in range(1, size.x):
                    var id := at(SLOT_EDGE_V, anchor + Vector2i(dx, dy))
                    if id != 0 and id not in ignore and id not in crossed:
                        crossed.append(id)
            for dy in range(1, size.y):
                for dx in range(size.x):
                    var id := at(SLOT_EDGE_H, anchor + Vector2i(dx, dy))
                    if id != 0 and id not in ignore and id not in crossed:
                        crossed.append(id)
    return crossed


## Put the instance into the grid without any checks; see [EditCommand].
func add_instance(instance: PartInstance) -> void:
    assert(not instances.has(instance.id), "instance %d already exists" % instance.id)
    instances[instance.id] = instance
    var map: Dictionary = _slots[slot_map_name(definition_of(instance))]
    for key in slots_of(instance):
        map[key] = instance.id
    next_id = maxi(next_id, instance.id + 1)


## Take the instance out of the grid without any checks; see [EditCommand].
func remove_instance(id: int) -> PartInstance:
    var instance: PartInstance = instances.get(id)
    if instance == null:
        return null
    var map: Dictionary = _slots[slot_map_name(definition_of(instance))]
    for key in slots_of(instance):
        if int(map.get(key, 0)) == id:
            map.erase(key)
    instances.erase(id)
    return instance


func notify_changed() -> void:
    changed.emit()


## The instance IDs, sorted, so that every iteration is deterministic.
func sorted_ids() -> Array[int]:
    var ids: Array[int] = []
    for id in instances:
        ids.append(int(id))
    ids.sort()
    return ids


## Pick the part at the cell for the remove tool: the furniture first, then the
## windows, the walls and floors around the cell, the surface and the
## background; 0 if there is nothing.
func pick_at(cell: Vector2i) -> int:
    for map_name in [SLOT_CELLS, SLOT_WINDOW]:
        var id := at(map_name, cell)
        if id != 0:
            return id
    var edges := [
        [SLOT_EDGE_V, cell],
        [SLOT_EDGE_H, cell],
        [SLOT_EDGE_V, cell + Vector2i(1, 0)],
        [SLOT_EDGE_H, cell + Vector2i(0, 1)],
    ]
    for edge in edges:
        var id := at(edge[0], edge[1])
        if id != 0:
            return id
    for map_name in [SLOT_SURFACE, SLOT_BACKGROUND]:
        var id := at(map_name, cell)
        if id != 0:
            return id
    return 0


## The highest cell row (exclusive) which any part reaches.
func top_of(instance: PartInstance) -> int:
    var definition := definition_of(instance)
    match definition.layer:
        "edge_h":
            return instance.anchor.y
        "edge_v":
            return instance.anchor.y + definition.footprint.y
        _:
            return instance.anchor.y + definition.footprint.y


func to_dict() -> Dictionary:
    var records: Array = []
    for id in sorted_ids():
        records.append(instances[id].to_dict())
    return {"next_id": next_id, "instances": records}


## Restore the instances of a saved site; return the problems (empty if fine).
## Invalid instances are skipped, so that a damaged save loads what it can.
func load_dict(data: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    for id in sorted_ids():
        if not instances[id].protected:
            remove_instance(id)
    for record in data.get("instances", []):
        var instance := PartInstance.from_dict(record)
        if instance == null:
            problems.append("malformed instance %s" % [record])
            continue
        if instance.protected or instances.has(instance.id):
            # NOTE (mristin):
            # The protected parts come from the site definition, not the save.
            continue
        var definition := content.part(instance.definition_id)
        if definition == null:
            problems.append("unknown part %s" % instance.definition_id)
            continue
        if instance.mirrored and not definition.can_mirror():
            instance.mirrored = false
        instance.colour_variant = clampi(instance.colour_variant, 0, definition.colour_variants - 1)
        if instance.id <= 0:
            problems.append("invalid instance ID %d" % instance.id)
            continue
        var geometry := check_geometry(definition, instance.anchor)
        if not geometry.ok:
            problems.append("instance %d: %s" % [instance.id, geometry.reason_key])
            continue
        add_instance(instance)
    next_id = maxi(next_id, int(data.get("next_id", 1)))
    return problems
