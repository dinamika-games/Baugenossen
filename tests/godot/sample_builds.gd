extends RefCounted
## Build sample layouts for the tests: a solution of the tutorial, a
## single-storey and a two-storey home for "The First Home", a garden and a
## workshop. They show that the missions are solvable with the universal parts
## in more than one way (DESIGN.md, 5.4 and 12).

var content: ContentDb
var context := Placement.Context.new()


func _init(db: ContentDb) -> void:
    content = db


func new_site(site_id: String) -> WorldGrid:
    return WorldGrid.from_site(content, content.site(site_id))


## Place a part through the same validation as the player; return its ID, or 0
## (with the reason printed) if the placement is invalid.
func place(grid: WorldGrid, part_id: String, x: int, y: int, mirrored := false) -> int:
    var definition := content.part(part_id)
    var result := Placement.validate(grid, definition, Vector2i(x, y), mirrored, context)
    if not result.ok:
        print("Can not place %s at (%d, %d): %s" % [part_id, x, y, result.reason_key])
        return 0
    var command := Placement.place_command(grid, definition, Vector2i(x, y), mirrored, 0, context)
    var id: int = command.additions[0].id
    command.apply(grid)
    return id


## Place a run of horizontal parts from x0 to x1 (exclusive), left to right.
func place_row(grid: WorldGrid, part_id: String, x0: int, x1: int, y: int) -> Array[int]:
    var ids: Array[int] = []
    var step := content.part(part_id).footprint.x
    var x := x0
    while x < x1:
        ids.append(place(grid, part_id, x, y))
        x += step
    return ids


func place_to_sit() -> WorldGrid:
    var grid := new_site("meadow_20_12")
    place(grid, "bench_basic", 5, 0)
    place(grid, "tree_small", 10, 0)
    place(grid, "grass_patch", 14, 0)
    return grid


## The left wall with a door (a door of 4 and a short wall of 2 above it).
func wall_with_door(grid: WorldGrid, x: int, y: int) -> void:
    place(grid, "door_wood", x, y)
    place(grid, "wall_short", x, y + 4)


## A single-storey home from x = 4 to 20, everything on the ground floor.
func first_home_single(grid: WorldGrid) -> Dictionary:
    var ids := {}
    wall_with_door(grid, 4, 0)
    ids["right_wall"] = place(grid, "wall_wood", 20, 0)
    ids["roof"] = place_row(grid, "roof_flat", 4, 20, 6)
    ids["bed_1"] = place(grid, "bed_single", 5, 0)
    ids["bed_2"] = place(grid, "bed_single", 8, 0)
    ids["table"] = place(grid, "table_basic", 11, 0)
    place(grid, "chair_basic", 13, 0)
    place(grid, "chair_basic", 14, 0, true)
    place(grid, "stove_basic", 15, 0)
    place(grid, "sink_basic", 17, 0)
    place(grid, "toilet_basic", 19, 0)
    return ids


## A two-storey home from x = 4 to 16 with stairs; the beds are upstairs.
func first_home_two_storeys(grid: WorldGrid) -> Dictionary:
    var ids := {}
    wall_with_door(grid, 4, 0)
    place(grid, "wall_wood", 16, 0)
    ids["floor"] = place_row(grid, "floor_wood", 4, 16, 6)
    place(grid, "wall_wood", 4, 6)
    place(grid, "wall_wood", 16, 6)
    ids["roof"] = place_row(grid, "roof_flat", 4, 16, 12)
    ids["stairs"] = place(grid, "stairs_basic", 9, 0)
    place(grid, "table_basic", 5, 0)
    place(grid, "chair_basic", 7, 0)
    place(grid, "chair_basic", 8, 0)
    place(grid, "toilet_basic", 15, 0)
    ids["bed_1"] = place(grid, "bed_single", 5, 6)
    ids["bed_2"] = place(grid, "bed_single", 8, 6)
    place(grid, "stove_basic", 11, 6)
    place(grid, "sink_basic", 13, 6)
    return ids


## A garden with seats in the west and the east, trees, grass and flowers.
func garden(grid: WorldGrid) -> void:
    place(grid, "bench_basic", 6, 0)
    place(grid, "bench_basic", 26, 0)
    place(grid, "tree_small", 10, 0)
    place(grid, "tree_small", 30, 0)
    for x in [14, 16, 18, 20, 22, 24]:
        place(grid, "grass_patch", x, 0)
    for x in [14, 16, 18, 20]:
        place(grid, "flower_bed", x, 0)


## Two rooms side by side, each with a table, a chair and a lamp.
func workshop(grid: WorldGrid) -> void:
    wall_with_door(grid, 4, 0)
    wall_with_door(grid, 12, 0)
    place(grid, "wall_wood", 20, 0)
    place_row(grid, "roof_flat", 4, 20, 6)
    for x in [5, 13]:
        place(grid, "table_basic", x, 0)
        place(grid, "chair_basic", x + 2, 0)
        place(grid, "lamp_basic", x + 3, 0)
