extends "res://tests/godot/godot_test.gd"
## Check the rooms, the navigation and the objectives, and that the initial
## missions are solvable in different ways and fail with specific feedback
## (DESIGN.md, 5 and 11, M2).

const SampleBuilds := preload("res://tests/godot/sample_builds.gd")

var content: ContentDb
var builds: SampleBuilds


func _run() -> void:
    content = ContentDb.get_default()
    builds = SampleBuilds.new(content)
    _test_rooms_and_doors()
    _test_roof_gap_and_regions()
    _test_stairs_link()
    _test_green_area_unique()
    _test_distinct_room_matching()
    _test_unknown_objective_type()
    _test_place_to_sit()
    _test_first_home_layouts()
    _test_first_home_failures()
    _test_garden_and_workshop()


func _result(report: MissionEvaluator.Report, id: String) -> Dictionary:
    for result in report.mandatory + report.optional:
        if result["id"] == id:
            return result
    return {}


func _failed_ids(report: MissionEvaluator.Report) -> Array[String]:
    var ids: Array[String] = []
    for result in report.mandatory:
        if not result["satisfied"]:
            ids.append(str(result["id"]))
    return ids


## A closed box from x0 to x1 on the ground with a door on the left.
func _box(grid: WorldGrid, x0: int, x1: int, door := true) -> void:
    if door:
        builds.wall_with_door(grid, x0, 0)
    else:
        builds.place(grid, "wall_wood", x0, 0)
    builds.place(grid, "wall_wood", x1, 0)
    builds.place_row(grid, "roof_flat", x0, x1, 6)


func _test_rooms_and_doors() -> void:
    var grid := builds.new_site("flat_40_24")
    _box(grid, 4, 10)
    var rooms := RoomDetector.detect(grid)
    check_equal(rooms.rooms.size(), 1, "a closed box with a door is one room")
    check_equal(rooms.rooms[0].area(), 36, "of 6 x 6 cells")
    var navigation := NavigationGraph.build(grid)
    var reachable := navigation.reachable_from(grid.entry)
    check(reachable.has(Vector2i(6, 0)), "the door lets people in")
    var sealed := builds.new_site("flat_40_24")
    _box(sealed, 4, 10, false)
    check_equal(RoomDetector.detect(sealed).rooms.size(), 1, "a box without a door is a room too")
    var inside := NavigationGraph.build(sealed).reachable_from(sealed.entry)
    check(not inside.has(Vector2i(6, 0)), "but nobody gets in")
    check(inside.has(Vector2i(3, 0)), "the ground outside is walkable")


func _test_roof_gap_and_regions() -> void:
    var grid := builds.new_site("flat_40_24")
    _box(grid, 4, 10)
    var roof: int = grid.at(WorldGrid.SLOT_EDGE_H, Vector2i(6, 6))
    grid.remove_instance(roof)
    check(RoomDetector.detect(grid).rooms.is_empty(), "a gap in the roof lets the weather in")
    var two := builds.new_site("flat_40_24")
    _box(two, 4, 10)
    _box(two, 20, 26)
    var rooms := RoomDetector.detect(two)
    check_equal(rooms.rooms.size(), 2, "two separate houses are two rooms")
    check(rooms.room_at(Vector2i(5, 1)) != rooms.room_at(Vector2i(21, 1)), "with distinct IDs")
    builds.place(two, "wall_wood", 7, 0)
    check_equal(RoomDetector.detect(two).rooms.size(), 3, "an inner wall splits a room")


func _test_stairs_link() -> void:
    var grid := builds.new_site("flat_40_24")
    builds.first_home_two_storeys(grid)
    var navigation := NavigationGraph.build(grid)
    var reachable := navigation.reachable_from(grid.entry)
    check(reachable.has(Vector2i(6, 6)), "the stairs lead upstairs")
    var path := navigation.path(grid.entry, Vector2i(6, 6))
    check(path.size() > 5 and path[0] == grid.entry, "there is a path upstairs")
    var wheelchair := NavigationGraph.build(grid, "wheelchair")
    check(
        not wheelchair.reachable_from(grid.entry).has(Vector2i(6, 6)),
        "the stairs do not count for a wheelchair"
    )
    var stairs: int = grid.at(WorldGrid.SLOT_CELLS, Vector2i(9, 0))
    grid.remove_instance(grid.at(WorldGrid.SLOT_EDGE_H, Vector2i(14, 6)))
    var report := SupportEvaluator.evaluate(grid)
    check_equal(
        str(report.problems.get(stairs, "")), "ERROR_TOP_LANDING", "stairs need both landings"
    )


func _test_green_area_unique() -> void:
    var grid := builds.new_site("meadow_20_12")
    builds.place(grid, "grass_patch", 2, 0)
    builds.place(grid, "flower_bed", 2, 0)
    builds.place(grid, "flower_bed", 4, 0)
    var cells := SiteAnalysis.analyse(grid).green_cells()
    check_equal(cells.size(), 4, "stacked grass and flowers count once per cell")


func _test_distinct_room_matching() -> void:
    var mission := content.mission("first_home")
    var grid := builds.new_site("flat_40_24")
    builds.first_home_single(grid)
    var report := MissionEvaluator.evaluate(mission, grid)
    var bedrooms := _result(report, "two_bedrooms")
    check(not bedrooms["satisfied"], "two beds in one room are not two bedrooms")
    check_equal(bedrooms["current"], 1, "one room can only count once")
    builds.place(grid, "wall_wood", 8, 0)
    report = MissionEvaluator.evaluate(mission, grid)
    check_equal(_failed_ids(report).size(), 6, "a closed inner wall cuts off the rest of the home")
    grid.remove_instance(grid.at(WorldGrid.SLOT_EDGE_V, Vector2i(8, 0)))
    builds.place(grid, "door_wood", 8, 0)
    builds.place(grid, "wall_short", 8, 4)
    report = MissionEvaluator.evaluate(mission, grid)
    check(_result(report, "two_bedrooms")["satisfied"], "a door between the beds: two bedrooms")
    check(report.can_submit(), "and still a valid home: %s" % [_failed_ids(report)])


func _test_unknown_objective_type() -> void:
    var mission := {"zones": {}}
    var problems := Objectives.validate(
        {"id": "x", "type": "teleport", "text_key": "X"}, mission, content
    )
    check(problems.size() == 1 and "unknown" in problems[0], "an unknown type is rejected")
    problems = Objectives.validate(
        {"id": "x", "type": "daylight", "text_key": "X"}, mission, content
    )
    check(problems.size() == 1 and "not implemented" in problems[0], "a future type is rejected")
    problems = Objectives.validate(
        {"id": "x", "type": "green_area", "text_key": "X"}, mission, content
    )
    check(
        problems.size() == 1 and "minimum_cells" in problems[0], "a missing parameter is rejected"
    )
    problems = Objectives.validate(
        {"id": "x", "type": "reachable_zone", "zone_id": "nowhere", "text_key": "X"},
        mission,
        content
    )
    check(problems.size() == 1 and "zone" in problems[0], "an unknown zone is rejected")
    var broken := ContentDb.new()
    var directory := "user://test_content_%d" % Time.get_ticks_usec()
    DirAccess.make_dir_recursive_absolute(directory)
    for file in DirAccess.get_files_at("res://data"):
        var text := FileAccess.get_file_as_string("res://data/" + file)
        if file == "missions.json":
            text = text.replace('"type": "green_area"', '"type": "greenish_area"')
        var out := FileAccess.open(directory + "/" + file, FileAccess.WRITE)
        out.store_string(text)
        out.close()
    check(not broken.load_from(directory), "the content with an unknown objective type fails")
    check(str(broken.errors).contains("greenish_area"), "with a diagnostic: %s" % [broken.errors])


func _test_place_to_sit() -> void:
    var mission := content.mission("place_to_sit")
    var grid := builds.place_to_sit()
    var report := MissionEvaluator.evaluate(mission, grid)
    check(report.can_submit(), "the tutorial is solved: %s" % [_failed_ids(report)])
    check(not _result(report, "flower_beds")["satisfied"], "without the optional flower beds")
    builds.place(grid, "flower_bed", 14, 0)
    builds.place(grid, "flower_bed", 16, 0)
    report = MissionEvaluator.evaluate(mission, grid)
    check(_result(report, "flower_beds")["satisfied"], "with two flower beds the wish is fulfilled")
    var chairs := builds.new_site("meadow_20_12")
    builds.place(chairs, "chair_basic", 3, 0)
    builds.place(chairs, "chair_basic", 6, 0, true)
    builds.place(chairs, "tree_small", 10, 0)
    builds.place(chairs, "grass_patch", 2, 0)
    check(
        MissionEvaluator.evaluate(mission, chairs).can_submit(),
        "two chairs under a tree are another valid design"
    )
    var empty := MissionEvaluator.evaluate(mission, builds.new_site("meadow_20_12"))
    check_equal(
        _failed_ids(empty), ["seats", "tree", "green"] as Array[String], "an empty site fails"
    )


func _test_first_home_layouts() -> void:
    var mission := content.mission("first_home")
    var single := builds.new_site("flat_40_24")
    builds.first_home_single(single)
    var report := MissionEvaluator.evaluate(mission, single)
    check(report.can_submit(), "the single-storey home is valid: %s" % [_failed_ids(report)])
    var double := builds.new_site("flat_40_24")
    builds.first_home_two_storeys(double)
    report = MissionEvaluator.evaluate(mission, double)
    check(report.can_submit(), "the two-storey home is valid: %s" % [_failed_ids(report)])
    check(_result(report, "two_bedrooms")["satisfied"] == false, "both beds share a bedroom")
    builds.place(double, "window_basic", 6, 8)
    builds.place(double, "window_basic", 10, 2)
    builds.place(double, "bench_basic", 0, 0)
    builds.place(double, "grass_patch", 0, 0)
    builds.place(double, "grass_patch", 2, 0)
    report = MissionEvaluator.evaluate(mission, double)
    check(_result(report, "windows")["satisfied"], "two windows of the rooms")
    check(_result(report, "garden")["satisfied"], "a bench and grass outside")


func _test_first_home_failures() -> void:
    var mission := content.mission("first_home")

    var open_roof := builds.new_site("flat_40_24")
    var ids := builds.first_home_single(open_roof)
    open_roof.remove_instance(ids["roof"][3])
    var report := MissionEvaluator.evaluate(mission, open_roof)
    check(not report.can_submit(), "an open roof fails")
    check_equal(_result(report, "room")["hint_key"], "HINT_NO_ROOM", "because there is no room")
    check_equal(_result(report, "beds")["hint_key"], "HINT_NOT_INDOORS", "the beds are outdoors")

    var hidden := builds.new_site("flat_40_24")
    ids = builds.first_home_single(hidden)
    hidden.remove_instance(ids["bed_2"])
    builds.place(hidden, "wall_wood", 24, 0)
    builds.place_row(hidden, "roof_flat", 20, 24, 6)
    var bed := builds.place(hidden, "bed_single", 21, 0)
    report = MissionEvaluator.evaluate(mission, hidden)
    var beds := _result(report, "beds")
    check(not report.can_submit(), "a bed in a room without a door fails")
    check_equal(_failed_ids(report), ["beds"] as Array[String], "only the beds fail")
    check_equal(beds["hint_key"], "HINT_UNREACHABLE", "because the bed can not be reached")
    check_equal(beds["instances"], [bed], "and the bed is highlighted")

    var unsupported := builds.new_site("flat_40_24")
    ids = builds.first_home_single(unsupported)
    unsupported.remove_instance(ids["right_wall"])
    report = MissionEvaluator.evaluate(mission, unsupported)
    var support := _result(report, "supported")
    check(not support["satisfied"], "a roof without its wall fails")
    check_equal(support["hint_key"], "ERROR_OVERHANG", "because the roof overhangs")
    check(support["instances"].has(ids["roof"][7]), "and the far roof is highlighted")


func _test_garden_and_workshop() -> void:
    var garden := content.mission("garden_for_everyone")
    var grid := builds.new_site("flat_40_24")
    builds.garden(grid)
    var report := MissionEvaluator.evaluate(garden, grid)
    check(report.can_submit(), "the garden is valid: %s" % [_failed_ids(report)])
    check(_result(report, "flower_beds")["satisfied"], "with four flower beds")
    check(_result(report, "two_seating_areas")["satisfied"], "and seats in the west and east")

    var workshop := content.mission("neighbourhood_workshop")
    var rooms := builds.new_site("flat_40_24")
    builds.workshop(rooms)
    report = MissionEvaluator.evaluate(workshop, rooms)
    check(report.can_submit(), "the workshop is valid: %s" % [_failed_ids(report)])
    var one_room := builds.new_site("flat_40_24")
    builds.first_home_single(one_room)
    report = MissionEvaluator.evaluate(workshop, one_room)
    check_equal(_result(report, "rooms")["current"], 0, "a home without lamps is no workshop")
    var lamp_room := builds.new_site("flat_40_24")
    builds.workshop(lamp_room)
    lamp_room.remove_instance(lamp_room.at(WorldGrid.SLOT_EDGE_V, Vector2i(12, 0)))
    lamp_room.remove_instance(lamp_room.at(WorldGrid.SLOT_EDGE_V, Vector2i(12, 4)))
    report = MissionEvaluator.evaluate(workshop, lamp_room)
    check_equal(_result(report, "rooms")["current"], 1, "one big room can not count twice")
