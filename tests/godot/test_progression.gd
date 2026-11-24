extends "res://tests/godot/godot_test.gd"
## Check the cooperative's progress and the row of blocks (DESIGN.md, 2.4, 4
## and 12): the missions open in order, a completion and its wishes count once,
## every mission can be completed, and the row offers five blocks, gives a new
## one for each taken, lets the oldest go after a while, and brings the parts
## which the mission still needs.

const SampleBuilds := preload("res://tests/godot/sample_builds.gd")

var content: ContentDb


func _run() -> void:
    content = ContentDb.get_default()
    _test_missions_open_in_order()
    _test_missions_solvable()
    _test_completion()
    _test_queue()
    _test_wanted_parts()


func _test_missions_open_in_order() -> void:
    var progress := Progress.new()
    var first := content.mission(content.mission_order[0])
    var second := content.mission("garden_for_everyone")
    check(Progression.mission_available(progress, first), "the first mission is open")
    check(not Progression.mission_available(progress, second), "the garden waits")
    for prerequisite in second["prerequisite_ids"]:
        progress.completed_missions.append(str(prerequisite))
    check(Progression.mission_available(progress, second), "and opens after its prerequisites")


func _test_missions_solvable() -> void:
    var builds := SampleBuilds.new(content)
    var sit := builds.place_to_sit()
    var home := builds.new_site("flat_40_24")
    builds.first_home_single(home)
    var garden := builds.new_site("flat_40_24")
    builds.garden(garden)
    var workshop := builds.new_site("flat_40_24")
    builds.workshop(workshop)
    var grids := [sit, home, garden, workshop]
    for i in range(4):
        var mission := content.mission(content.mission_order[i])
        check(
            MissionEvaluator.evaluate(mission, grids[i]).can_submit(),
            "%s can be completed" % mission["id"]
        )


func _test_completion() -> void:
    var progress := Progress.new()
    var builds := SampleBuilds.new(content)
    var grid := builds.new_site("flat_40_24")
    builds.first_home_single(grid)
    var mission := content.mission("first_home")
    var report := MissionEvaluator.evaluate(mission, grid)
    var summary := Progression.complete_mission(progress, mission, report)
    check(summary["first"], "the first completion")
    check(progress.has_completed("first_home"), "is recorded")
    var again := Progression.complete_mission(progress, mission, report)
    check(not again["first"], "resubmitting is not a first completion")
    check(again["wishes"].is_empty(), "and fulfils no wish twice")
    check_equal(progress.completed_missions.size(), 1, "recorded once")
    var problems: Array[String] = []
    var restored := Progress.from_dict(progress.to_dict(), content, problems)
    check(restored.has_completed("first_home") and problems.is_empty(), "the progress is saved")


func _test_queue() -> void:
    var queue := BlockQueue.new(content, [], 7)
    check_equal(queue.slots.size(), BlockQueue.SIZE, "five blocks wait")
    var second := queue.slots[2]
    var last := queue.slots[4]
    var taken := queue.take(1)
    check(taken != "", "a block is taken")
    check_equal(queue.slots.size(), BlockQueue.SIZE, "a new one comes in")
    check_equal(queue.slots[1], second, "the others move up")
    check_equal(queue.slots[3], last, "in their order")
    var oldest := queue.slots[1]
    queue.shift_seconds = 10.0
    check(not queue.advance(9.0), "the row waits")
    check(queue.advance(1.5), "then the oldest leaves")
    check_equal(queue.slots[0], oldest, "first in, first out")
    check_equal(queue.slots.size(), BlockQueue.SIZE, "and still five wait")
    check(queue.take(9) == "", "no block beyond the row")
    var offered := ["bench_basic", "tree_small", "grass_patch"]
    var tutorial := BlockQueue.new(content, offered, 3)
    for i in range(30):
        check(tutorial.take(0) in offered, "only the offered parts come")


func _test_wanted_parts() -> void:
    var mission := content.mission("first_home")
    var report := MissionEvaluator.evaluate(
        mission, SampleBuilds.new(content).new_site("flat_40_24")
    )
    var wanted := preload("res://scenes/build_site/build_site.gd").wanted_tags(mission, report)
    check(not wanted.is_empty(), "an empty site wants the parts of the objectives")
    var queue := BlockQueue.new(content, [], 11)
    queue.wanted_tags = wanted
    var hits := 0
    for i in range(200):
        var definition := content.part(queue.take(0))
        for tag in definition.tags:
            if wanted.has(tag):
                hits += 1
                break
    check(hits > 60, "the wanted parts come often: %d of 200" % hits)
