extends "res://tests/godot/godot_test.gd"
## Check the cooperative's progress and the parts of the levels (DESIGN.md, 2.4, 4
## and 12): the missions open in order, a completion and its wishes count once,
## every mission can be completed, every level gives enough parts for its
## sample solutions, and the yard gives and takes back the parts.

const SampleBuilds := preload("res://tests/godot/sample_builds.gd")

var content: ContentDb


func _run() -> void:
    content = ContentDb.get_default()
    _test_missions_open_in_order()
    _test_missions_solvable()
    _test_completion()
    _test_supply()
    _test_levels_give_enough()


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


func _test_supply() -> void:
    var grid := SampleBuilds.new(content).place_to_sit()
    var supply := PartSupply.for_level(content.mission("place_to_sit")["parts"], grid)
    check_equal(supply.kinds[0], "bench_basic", "the yard keeps the order of the level")
    check_equal(supply.counts["bench_basic"], 0, "the bench on the site is not in the yard")
    check_equal(supply.counts["chair_basic"], 2, "the chairs are")
    check_equal(supply.take(0), "", "an empty place gives nothing")
    check_equal(supply.take(1), "chair_basic", "a chair is taken")
    check_equal(supply.count(1), 1, "one is left")
    supply.give_back("chair_basic")
    check_equal(supply.count(1), 2, "and it comes back")
    supply.give_back("stove_basic")
    check_equal(supply.kinds.back(), "stove_basic", "another kind gets a new place")


## Every level gives the parts of its sample solutions (both designs of the
## home), so that many solutions are possible.
func _test_levels_give_enough() -> void:
    var builds := SampleBuilds.new(content)
    var home_single := builds.new_site("flat_40_24")
    builds.first_home_single(home_single)
    var home_two := builds.new_site("flat_40_24")
    builds.first_home_two_storeys(home_two)
    var garden := builds.new_site("flat_40_24")
    builds.garden(garden)
    var workshop := builds.new_site("flat_40_24")
    builds.workshop(workshop)
    var solutions := {
        "place_to_sit": [builds.place_to_sit()],
        "first_home": [home_single, home_two],
        "garden_for_everyone": [garden],
        "neighbourhood_workshop": [workshop],
    }
    for id in solutions:
        var parts: Dictionary = content.mission(id)["parts"]
        for grid in solutions[id]:
            var supply := PartSupply.for_level(parts, grid)
            var used := {}
            for instance_id in grid.instances:
                var instance: PartInstance = grid.instances[instance_id]
                if not instance.protected:
                    used[instance.definition_id] = int(used.get(instance.definition_id, 0)) + 1
            for part_id in used:
                check(
                    int(parts.get(part_id, 0)) >= int(used[part_id]),
                    "%s gives enough of %s" % [id, part_id]
                )
            check(supply.counts.values().max() >= 0, "%s: the supply is consistent" % id)
