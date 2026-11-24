extends "res://tests/godot/godot_test.gd"
## Check the construction model: the edges, the footprints, the layers, the
## atomic placement, the support, undo and redo, the protected parts and the
## windows (DESIGN.md, 2 and 12).

var content: ContentDb
var context := Placement.Context.new()


func _run() -> void:
    content = ContentDb.get_default()
    check(content.errors.is_empty(), "the content loads without errors: %s" % [content.errors])
    _test_edges_and_footprints()
    _test_layers()
    _test_invalid_placement_is_atomic()
    _test_support_chain()
    _test_floating_cycle()
    _test_remove_support_warns()
    _test_overhang()
    _test_undo_redo()
    _test_protected()
    _test_window_over_back_wall()
    _test_move()
    _test_mass_and_locks()
    _test_serialization()


func _grid() -> WorldGrid:
    return WorldGrid.new(content, 40, 24)


func _place(grid: WorldGrid, part_id: String, x: int, y: int, mirrored := false) -> int:
    var command := Placement.place_command(
        grid, content.part(part_id), Vector2i(x, y), mirrored, 0, context
    )
    if command == null or not command.apply(grid):
        return 0
    return command.additions[0].id


func _test_edges_and_footprints() -> void:
    var floor_def := content.part("floor_wood")
    check_equal(
        WorldGrid.slot_keys(floor_def, Vector2i(3, 6)),
        [Vector2i(3, 6), Vector2i(4, 6)] as Array[Vector2i],
        "a floor of 2 covers H(3,6) and H(4,6)"
    )
    var wall_def := content.part("wall_wood")
    check_equal(WorldGrid.slot_keys(wall_def, Vector2i(2, 0)).size(), 6, "a wall covers 6 edges")
    check_equal(WorldGrid.slot_keys(wall_def, Vector2i(2, 0))[5], Vector2i(2, 5), "up to V(2,5)")
    var bed_def := content.part("bed_single")
    check_equal(WorldGrid.slot_keys(bed_def, Vector2i(1, 0)).size(), 6, "a bed covers 3x2 cells")
    var grid := _grid()
    check(
        not Placement.validate(grid, floor_def, Vector2i(39, 6), false, context).ok,
        "a floor may not stick out of the site"
    )
    check(
        not Placement.validate(grid, floor_def, Vector2i(3, 0), false, context).ok,
        "the ground H(x, 0) is not ours to build"
    )
    check(
        Placement.validate(grid, wall_def, Vector2i(40, 0), false, context).ok,
        "a wall may stand on the right border V(40, y)"
    )
    check(
        not Placement.validate(grid, wall_def, Vector2i(41, 0), false, context).ok,
        "but not beyond it"
    )


func _test_layers() -> void:
    var grid := _grid()
    check(_place(grid, "grass_patch", 2, 0) != 0, "grass on the ground")
    check(_place(grid, "flower_bed", 2, 0) != 0, "a flower bed on the grass (other layer)")
    check(_place(grid, "back_wall", 2, 0) != 0, "a back wall behind")
    check(_place(grid, "flower_bed", 3, 0) == 0, "two flower beds can not overlap")
    check(_place(grid, "bed_single", 2, 0) == 0, "a bed can not stand in a flower bed")
    check(_place(grid, "bed_single", 10, 0) != 0, "a bed")
    var result := Placement.validate(
        grid, content.part("wall_wood"), Vector2i(11, 0), false, context
    )
    check_equal(result.reason_key, "ERROR_CROSSES_PART", "a wall can not cut through a bed")
    check(_place(grid, "wall_wood", 10, 0) != 0, "a wall right next to the bed is fine")


func _test_invalid_placement_is_atomic() -> void:
    var grid := _grid()
    _place(grid, "bed_single", 5, 0)
    var before := JSON.stringify(grid.to_dict())
    var command := Placement.place_command(
        grid, content.part("bed_single"), Vector2i(6, 0), false, 0, context
    )
    check(command == null, "an overlapping placement makes no command")
    var forged := EditCommand.new(
        "place", [], [PartInstance.create(grid.next_id, "bed_single", Vector2i(6, 0))]
    )
    check(not forged.apply(grid), "a forged overlapping command does not apply")
    check_equal(JSON.stringify(grid.to_dict()), before, "the grid is unchanged")
    var both := (
        EditCommand
        . new(
            "place",
            [],
            [
                PartInstance.create(50, "table_basic", Vector2i(20, 0)),
                PartInstance.create(51, "table_basic", Vector2i(21, 0)),
            ]
        )
    )
    check(not both.apply(grid), "a command whose second part overlaps does not apply")
    check_equal(JSON.stringify(grid.to_dict()), before, "and leaves nothing behind")


func _test_support_chain() -> void:
    var grid := _grid()
    check(_place(grid, "bed_single", 5, 3) == 0, "a bed can not float")
    check(_place(grid, "floor_wood", 5, 6) == 0, "a floor can not float")
    check(_place(grid, "wall_wood", 4, 0) != 0, "a wall on the ground")
    check(_place(grid, "wall_wood", 10, 0) != 0, "another wall")
    var floors := []
    for x in [4, 6, 8]:
        floors.append(_place(grid, "floor_wood", x, 6))
    check(not floors.has(0), "a floor from wall to wall")
    var report := SupportEvaluator.evaluate(grid)
    check(report.problems.is_empty(), "everything is supported: %s" % [report.problems])
    check(_place(grid, "bed_single", 5, 6) != 0, "a bed on the upper floor")
    check(_place(grid, "wall_wood", 4, 6) != 0, "a wall on the wall below")
    check(_place(grid, "wall_wood", 8, 6) != 0, "a wall standing on the floor")
    check(_place(grid, "beam_wood", 12, 2) == 0, "a beam can not float")
    check(_place(grid, "beam_wood", 10, 2) != 0, "a beam fixed to a wall")
    check(_place(grid, "lamp_basic", 11, 3) != 0, "a lamp on the beam")


func _test_floating_cycle() -> void:
    var grid := _grid()
    # NOTE (mristin):
    # We force the parts in without validation: a wall and a floor which only
    # carry each other.
    grid.add_instance(PartInstance.create(1, "wall_wood", Vector2i(10, 8)))
    grid.add_instance(PartInstance.create(2, "floor_wood", Vector2i(10, 8)))
    grid.add_instance(PartInstance.create(3, "wall_wood", Vector2i(10, 2)))
    var report := SupportEvaluator.evaluate(grid)
    check(not report.is_supported(1), "the floating wall is not supported")
    check(not report.is_supported(2), "the floor on the floating wall is not supported")
    check(not report.is_supported(3), "a wall resting on nothing is not supported")
    check_equal(report.problem_ids(), [1, 2, 3] as Array[int], "all three are reported")


func _test_remove_support_warns() -> void:
    var grid := _grid()
    var wall := _place(grid, "wall_wood", 4, 0)
    var floor_id := _place(grid, "floor_wood", 2, 6)
    _place(grid, "floor_wood", 4, 6)
    var bed := _place(grid, "bed_single", 3, 6)
    check(bed != 0, "a bed on a floor which overhangs 2 cells")
    var history := CommandHistory.new()
    check(history.execute(Placement.remove_command(grid, wall), grid), "removing the wall works")
    var report := SupportEvaluator.evaluate(grid)
    check(report.problems.has(floor_id), "the floor is reported as unsupported")
    check(report.problems.has(bed), "and the bed on it, too")
    check(grid.instances.has(bed), "but nothing collapses")


func _test_overhang() -> void:
    var grid := _grid()
    _place(grid, "wall_wood", 4, 0)
    _place(grid, "wall_wood", 14, 0)
    var first := _place(grid, "roof_flat", 4, 6)
    var result := Placement.validate(
        grid, content.part("roof_flat"), Vector2i(6, 6), false, context
    )
    check(result.ok, "a roof may grow from one side")
    check_equal(result.warning_key, "ERROR_OVERHANG", "with a warning that it overhangs")
    var ids := [first]
    for x in [6, 8, 10]:
        ids.append(_place(grid, "roof_flat", x, 6))
    var report := SupportEvaluator.evaluate(grid)
    check(report.problems.has(ids[3]), "the open span blocks the submission")
    check(_place(grid, "bed_single", 9, 6) == 0, "nothing stands on an overhang")
    _place(grid, "roof_flat", 12, 6)
    report = SupportEvaluator.evaluate(grid)
    check(report.problems.is_empty(), "the closed span is supported: %s" % [report.problems])
    check(_place(grid, "roof_flat", 16, 6) == 0, "a roof segment needs a connection")
    var short := _grid()
    _place(short, "wall_wood", 4, 0)
    _place(short, "floor_wood", 2, 6)
    _place(short, "floor_wood", 4, 6)
    check(SupportEvaluator.evaluate(short).problems.is_empty(), "an overhang of 2 is fine")


func _parts(grid: WorldGrid) -> String:
    return JSON.stringify(grid.to_dict()["instances"])


func _test_undo_redo() -> void:
    var grid := _grid()
    var history := CommandHistory.new()
    var empty := _parts(grid)
    var definition := content.part("table_basic")
    history.execute(
        Placement.place_command(grid, definition, Vector2i(1, 0), false, 0, context), grid
    )
    var one := _parts(grid)
    history.execute(
        Placement.place_command(grid, definition, Vector2i(5, 0), false, 0, context), grid
    )
    var two := _parts(grid)
    check(history.undo(grid), "undo")
    check_equal(_parts(grid), one, "undo restores the first state")
    check(history.redo(grid), "redo")
    check_equal(_parts(grid), two, "redo restores the second state")
    history.undo(grid)
    history.undo(grid)
    check_equal(_parts(grid), empty, "undo twice empties the site")
    check(not history.undo(grid), "nothing more to undo")
    history.redo(grid)
    var id: int = grid.sorted_ids()[0]
    history.execute(Placement.move_command(grid, id, Vector2i(9, 0), false, context), grid)
    check(not history.can_redo(), "a new edit after undo clears the redo")
    history.undo(grid)
    check_equal(grid.instances[id].anchor, Vector2i(1, 0), "undo of a move moves back")
    history.execute(Placement.remove_command(grid, id), grid)
    history.undo(grid)
    check(grid.instances.has(id), "undo of a removal restores the part")
    for i in range(CommandHistory.LIMIT + 20):
        var x := i % 38
        var y := 0 if i < 38 else 3
        if y > 0:
            continue
        history.execute(
            Placement.place_command(grid, definition, Vector2i(x, 20), false, 0, context), grid
        )
    check(history.size() <= CommandHistory.LIMIT, "the history keeps at most 100 edits")


func _test_protected() -> void:
    var grid := _grid()
    var protected := PartInstance.create(grid.allocate_id(), "tree_small", Vector2i(3, 0))
    protected.protected = true
    grid.add_instance(protected)
    check(
        Placement.remove_command(grid, protected.id) == null, "a protected part can not be removed"
    )
    var forged := EditCommand.new("remove", [protected.duplicate_instance()], [])
    check(not forged.apply(grid), "not even with a forged command")
    check(
        Placement.move_command(grid, protected.id, Vector2i(10, 0), false, context) == null,
        "nor moved"
    )


func _test_window_over_back_wall() -> void:
    var grid := _grid()
    var back := _place(grid, "back_wall", 4, 0)
    var window := _place(grid, "window_basic", 4, 2)
    check(back != 0 and window != 0, "a window goes over a back wall")
    check(_place(grid, "window_basic", 5, 2) == 0, "but not over another window")
    var history := CommandHistory.new()
    history.execute(Placement.remove_command(grid, window), grid)
    check(grid.instances.has(back), "removing the window leaves the back wall")
    check_equal(grid.pick_at(Vector2i(4, 2)), back, "the back wall shows there again")


func _test_move() -> void:
    var grid := _grid()
    var bed := _place(grid, "bed_single", 1, 0)
    check(
        Placement.move_command(grid, bed, Vector2i(2, 0), false, context) != null,
        "a bed moves onto itself"
    )
    _place(grid, "table_basic", 10, 0)
    check(
        Placement.move_command(grid, bed, Vector2i(9, 0), false, context) == null,
        "not onto a table"
    )
    var command := Placement.move_command(grid, bed, Vector2i(20, 0), true, context)
    check(command != null and command.apply(grid), "a move with mirroring")
    check_equal(grid.instances[bed].anchor, Vector2i(20, 0), "the bed moved")
    check(grid.instances[bed].mirrored, "and is mirrored")
    check_equal(grid.at(WorldGrid.SLOT_CELLS, Vector2i(1, 0)), 0, "its old cells are free")


func _test_mass_and_locks() -> void:
    var grid := _grid()
    var weak := Placement.Context.new()
    weak.capacity = 2
    var result := Placement.validate(grid, content.part("wall_wood"), Vector2i(1, 0), false, weak)
    check_equal(result.reason_key, "ERROR_OVERWEIGHT", "a weak crane can not lift a wall")
    var offered := Placement.Context.new()
    offered.offered = ["bench_basic"]
    result = Placement.validate(grid, content.part("wall_wood"), Vector2i(1, 0), false, offered)
    check_equal(result.reason_key, "ERROR_NOT_OFFERED", "the mission may restrict the catalogue")


func _test_serialization() -> void:
    var grid := _grid()
    _place(grid, "wall_wood", 4, 0)
    _place(grid, "bed_single", 5, 0, true)
    var saved := grid.to_dict()
    var other := _grid()
    var problems := other.load_dict(JSON.parse_string(JSON.stringify(saved)))
    check(problems.is_empty(), "a saved site loads: %s" % [problems])
    check_equal(JSON.stringify(other.to_dict()), JSON.stringify(saved), "and is the same")
    saved["instances"].append({"id": 99, "definition_id": "nonsense", "anchor": [1, 1]})
    saved["instances"].append({"id": 98, "definition_id": "bed_single", "anchor": [5, 0]})
    saved["instances"].append({"id": 97})
    problems = other.load_dict(saved)
    check_equal(problems.size(), 3, "unknown, overlapping and malformed parts are reported")
    check_equal(other.instances.size(), 2, "and skipped")
