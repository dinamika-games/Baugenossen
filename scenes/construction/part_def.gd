class_name PartDef
extends RefCounted
## Define a kind of construction part (see data/parts.json and DESIGN.md, 2.2).
##
## The grid coordinates: x grows to the right, y grows upwards, and the cell
## (x, y) is the square from (x, y) to (x + 1, y + 1). The ground is the
## implicit surface H(x, 0) below the row y = 0.
##
## The layers:
## * "edge_h": horizontal edges (floors and roofs); the footprint [n, 0] covers
##   the edges H(x, y) .. H(x + n - 1, y).
## * "edge_v": vertical edges (walls and doors); the footprint [0, n] covers the
##   edges V(x, y) .. V(x, y + n - 1).
## * "volume" and "decor": cells (furniture, stairs, trees); they share the
##   exclusive occupancy of the cells.
## * "surface": cells on the ground or the floor (grass), under the volumes.
## * "background": cells behind (back walls).
## * "window": cells over the background (windows), see DESIGN.md, 2.3.

var id := ""
var name := ""
var description := ""
var category_id := ""
var layer := ""
var footprint := Vector2i.ZERO
var mass := 1
var tags: Dictionary = {}
var support_rule := "base"
var craft_skill := ""
var material_id := ""
var visual_id := ""
## The cells (offsets from the anchor) which nobody can walk through.
var blocked_cells: Array[Vector2i] = []
## The cells (offsets) from where a resident uses the part; by default the
## bottom row of the footprint.
var interaction_offsets: Array[Vector2i] = []
## The bottom and the top landing of the stairs and the ladders (offsets).
var landings: Array[Vector2i] = []
var allowed_transforms: Array[String] = []
var colour_variants := 1


static func from_dict(record: Dictionary) -> PartDef:
    var definition := PartDef.new()
    definition.id = str(record["id"])
    definition.name = str(record["name"])
    definition.description = str(record["description"])
    definition.category_id = str(record["category_id"])
    definition.layer = str(record["layer"])
    definition.footprint = Vector2i(int(record["footprint"][0]), int(record["footprint"][1]))
    definition.mass = int(record["mass"])
    for tag in record["tags"]:
        var text := str(tag)
        var colon := text.find(":")
        if colon >= 0:
            definition.tags[text.substr(0, colon)] = int(text.substr(colon + 1))
        else:
            definition.tags[text] = 1
    definition.support_rule = str(record["support_rule"])
    definition.craft_skill = str(record.get("craft_skill", ""))
    definition.material_id = str(record.get("material_id", ""))
    definition.visual_id = str(record["visual_id"])
    definition.blocked_cells = _cells(record.get("blocked_cells", []))
    if record.has("interaction_offsets"):
        definition.interaction_offsets = _cells(record["interaction_offsets"])
    elif definition.is_cell_layer():
        for dx in range(definition.footprint.x):
            definition.interaction_offsets.append(Vector2i(dx, 0))
    definition.landings = _cells(record.get("landings", []))
    for transform in record.get("allowed_transforms", []):
        definition.allowed_transforms.append(str(transform))
    definition.colour_variants = maxi(1, int(record.get("colour_variants", 1)))
    return definition


static func _cells(values: Array) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for value in values:
        result.append(Vector2i(int(value[0]), int(value[1])))
    return result


func is_cell_layer() -> bool:
    return layer in ["volume", "decor", "surface", "background", "window"]


func has_valid_footprint() -> bool:
    match layer:
        "edge_h":
            return footprint.x >= 1 and footprint.y == 0
        "edge_v":
            return footprint.x == 0 and footprint.y >= 1
        _:
            return footprint.x >= 1 and footprint.y >= 1


func has_tag(tag: String) -> bool:
    return tags.has(tag)


## The value of a tag: its capacity (e.g., 2 for "seat_capacity:2"), 1 for a
## plain tag and 0 if the part does not have it.
func tag_value(tag: String) -> int:
    return int(tags.get(tag, 0))


func can_mirror() -> bool:
    return "mirror" in allowed_transforms


## Mirror an offset within the footprint, horizontally.
func mirror_offset(offset: Vector2i, mirrored: bool) -> Vector2i:
    if not mirrored:
        return offset
    return Vector2i(footprint.x - 1 - offset.x, offset.y)
