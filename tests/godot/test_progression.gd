extends "res://tests/godot/godot_test.gd"
## Check the rules of the character: the attribute budget, the skill formula,
## the backgrounds and traits, the caps, the levels, the perks, the unlocks, the
## practice and the idempotent rewards (DESIGN.md, 4 and 12).

const SampleBuilds := preload("res://tests/godot/sample_builds.gd")

var content: ContentDb


func _run() -> void:
    content = ContentDb.get_default()
    _test_creation()
    _test_skill_formula()
    _test_levels()
    _test_rewards_once()
    _test_invest_and_caps()
    _test_perks()
    _test_unlocks_differ_but_missions_solvable()
    _test_practice()


func _character(background := "apprentice") -> Character:
    var character := Character.create_default(content)
    character.name = "Ana"
    character.background_id = background
    return character


func _test_creation() -> void:
    var character := _character()
    check(Progression.creation_problems(character, content).is_empty(), "the defaults are valid")
    check_equal(Progression.attribute_points_left(character, content), 0, "40 points spent")
    character.attributes["B"] = 7
    check(
        "CREATE_ERROR_ATTRIBUTE_TOTAL" in Progression.creation_problems(character, content),
        "41 points are too many"
    )
    character.attributes["B"] = 11
    character.attributes["U"] = 1
    character.attributes["I"] = 5
    check(
        "CREATE_ERROR_ATTRIBUTE_RANGE" in Progression.creation_problems(character, content),
        "an attribute may not pass 10"
    )
    character = _character()
    character.traits = ["traditionalist", "modernist", "naturalist"] as Array[String]
    check(
        "CREATE_ERROR_TOO_MANY_TRAITS" in Progression.creation_problems(character, content),
        "at most two traits"
    )
    character.traits = ["perfectionist"] as Array[String]
    check(
        "CREATE_ERROR_TRAIT" in Progression.creation_problems(character, content),
        "an unimplemented trait can not be chosen"
    )
    character.traits = ["specialist"] as Array[String]
    check(
        "CREATE_ERROR_SPECIALIST" in Progression.creation_problems(character, content),
        "the specialist needs a skill"
    )
    character.name = "  "
    check(
        "CREATE_ERROR_NAME" in Progression.creation_problems(character, content),
        "the builder needs a name"
    )
    character.name = "Ŝtefan 李"
    character.specialist_skill = "ecology"
    check(Progression.creation_problems(character, content).is_empty(), "a Unicode name is fine")


func _test_skill_formula() -> void:
    var character := _character("carpenter")
    # Carpentry: D 6, U 6 -> 5 + 12 + 12 = 29, + 20 = 49.
    check_equal(Progression.skill(character, "carpentry", content), 49, "carpentry of a carpenter")
    check_equal(
        Progression.skill(character, "restoration", content), 5 + 10 + 12 + 10, "restoration"
    )
    check_equal(Progression.skill(character, "masonry", content), 29, "masonry without bonus")
    var apprentice := _character("apprentice")
    check_equal(Progression.skill(apprentice, "masonry", content), 34, "the apprentice gets +5")
    character.traits = ["traditionalist"] as Array[String]
    check_equal(Progression.skill(character, "masonry", content), 44, "traditionalist +15 masonry")
    check_equal(
        Progression.skill(character, "electrical_engineering", content), 19, "and -10 electrical"
    )
    character.traits = ["specialist"] as Array[String]
    character.specialist_skill = "ecology"
    check_equal(Progression.skill(character, "ecology", content), 49, "specialist +20")
    check_equal(Progression.skill(character, "masonry", content), 24, "and -5 elsewhere")
    var low := _character()
    for id in ContentDb.ATTRIBUTE_IDS:
        low.attributes[id] = 1
    low.background_id = "artist"
    low.traits = ["modernist"] as Array[String]
    check_equal(Progression.skill(low, "carpentry", content), 0, "a skill never drops below 0")
    var high := _character("bricklayer")
    high.attributes["B"] = 10
    high.attributes["U"] = 10
    high.traits = ["traditionalist"] as Array[String]
    high.invested["masonry"] = 30
    check_equal(Progression.skill(high, "masonry", content), 100, "nor passes 100")
    var raised := _character()
    raised.attribute_points = 1
    var before := Progression.skill(raised, "masonry", content)
    check(Progression.raise_attribute(raised, "B", content), "an attribute point raises Brawn")
    check_equal(Progression.skill(raised, "masonry", content), before + 2, "and masonry by 2")
    raised.attributes["B"] = 10
    raised.attribute_points = 1
    check(not Progression.raise_attribute(raised, "B", content), "not past 10")
    check_equal(raised.attribute_points, 1, "and the point stays")


func _test_levels() -> void:
    check_equal(Progression.xp_for_level(2), 100, "level 2 at 100 XP")
    check_equal(Progression.xp_for_level(3), 300, "level 3 at 300 XP")
    check_equal(Progression.xp_for_level(5), 1000, "level 5 at 1000 XP")
    check_equal(Progression.level_for_xp(0), 1, "start at level 1")
    check_equal(Progression.level_for_xp(99), 1, "99 XP is still level 1")
    check_equal(Progression.level_for_xp(600), 4, "600 XP is level 4")
    check_equal(Progression.rank_key(12), "RANK_CRAFTSPERSON", "rank of level 12")
    check_equal(Progression.reputation_key(520), "REPUTATION_TRUSTED_NEIGHBOUR", "reputation")


func _test_rewards_once() -> void:
    var character := _character("carpenter")
    var gained := Progression.award_once(character, "test:big", 1000, 50, content)
    check_equal(gained, 4, "1000 XP gives four levels at once")
    check_equal(character.level(), 5, "level 5")
    check_equal(character.skill_points, 40, "10 skill points per level")
    check_equal(character.perk_tokens, 1, "a perk token at level 3")
    check_equal(character.attribute_points, 1, "an attribute point at level 5")
    check_equal(Progression.award_once(character, "test:big", 1000, 50, content), -1, "only once")
    check_equal(character.xp, 1000, "the XP is not doubled")
    check_equal(character.karma, 50, "nor the karma")
    var apprentice := _character("apprentice")
    Progression.award_once(apprentice, "test:one", 100, 0, content)
    check_equal(apprentice.skill_points, 12, "the apprentice gets 12 points per level")


func _test_invest_and_caps() -> void:
    var character := _character("carpenter")
    character.skill_points = 60
    check(not Progression.invest(character, "carpentry", 52, content), "not beyond 100")
    check_equal(character.skill_points, 60, "no points are lost")
    check(Progression.invest(character, "carpentry", 51, content), "up to 100")
    check_equal(Progression.skill(character, "carpentry", content), 100, "carpentry 100")
    check_equal(character.skill_points, 9, "9 points left")
    check(not Progression.invest(character, "carpentry", 20, content), "not more than unspent")
    check(not Progression.invest(character, "juggling", 1, content), "not an unknown skill")


func _test_perks() -> void:
    var character := _character()
    check_equal(
        Progression.perk_problem(character, "golden_hands", content),
        "PERK_ERROR_NO_TOKEN",
        "a perk costs a token"
    )
    character.perk_tokens = 1
    check_equal(
        Progression.perk_problem(character, "golden_hands", content),
        "PERK_ERROR_REQUIREMENTS",
        "Golden Hands needs Dexterity 7"
    )
    check(not Progression.buy_perk(character, "golden_hands", content), "so it is not bought")
    check_equal(character.perk_tokens, 1, "and the token stays")
    check_equal(
        Progression.perk_problem(character, "green_thumb", content),
        "PERK_ERROR_NOT_IMPLEMENTED",
        "a future perk can not be bought"
    )
    character.attributes["D"] = 7
    character.attributes["R"] = 4
    check(Progression.buy_perk(character, "golden_hands", content), "with D 7, it is bought")
    check_equal(character.perk_tokens, 0, "for one token")
    character.perk_tokens = 1
    check_equal(
        Progression.perk_problem(character, "golden_hands", content), "PERK_ERROR_OWNED", "once"
    )
    character.xp = Progression.xp_for_level(10)
    var before := Progression.skill(character, "ecology", content)
    check(Progression.buy_perk(character, "jack_of_all_trades", content), "Jack at level 10")
    check_equal(Progression.skill(character, "ecology", content), before + 5, "+5 to every skill")


func _test_unlocks_differ_but_missions_solvable() -> void:
    var bricklayer := _character("bricklayer")
    var gardener := _character("gardener")
    var bricks := Progression.unlocked_parts(bricklayer, content)
    var plants := Progression.unlocked_parts(gardener, content)
    check(bricks.has("wall_stone") and not plants.has("wall_stone"), "the bricklayer has stone")
    check(plants.has("tree_large") and not bricks.has("tree_large"), "the gardener has big trees")
    for id in content.part_order:
        if content.part(id).requirements.is_empty():
            check(bricks.has(id) and plants.has(id), "both have the universal %s" % id)
    var weakest := _character()
    for attribute in ContentDb.ATTRIBUTE_IDS:
        weakest.attributes[attribute] = 1
    for id in content.part_order:
        if content.part(id).requirements.is_empty():
            check(
                content.part(id).mass <= Progression.crane_capacity(weakest),
                "even Brawn 1 lifts the universal %s" % id
            )
    var builds := SampleBuilds.new(content)
    for character in [bricklayer, gardener]:
        builds.context.unlocked = Progression.unlocked_parts(character, content)
        builds.context.capacity = Progression.crane_capacity(character)
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
                "a %s completes %s" % [character.background_id, mission["id"]]
            )


func _test_practice() -> void:
    var character := _character()
    var builds := SampleBuilds.new(content)
    var grid := builds.new_site("flat_40_24")
    builds.first_home_single(grid)
    var mission := content.mission("first_home")
    var report := MissionEvaluator.evaluate(mission, grid)
    var before := Progression.skill(character, "interior_design", content)
    var summary := Progression.complete_mission(character, mission, report, grid, content)
    check(summary["first"], "the first completion")
    check_equal(summary["xp"], 100, "grants the base XP")
    check_equal(
        summary["practice"],
        ["carpentry", "interior_design"] as Array[String],
        "practice for the crafts with at least three parts"
    )
    check_equal(Progression.skill(character, "interior_design", content), before + 1, "+1")
    var again := Progression.complete_mission(character, mission, report, grid, content)
    check_equal(again["xp"], 0, "resubmitting grants no XP")
    check(again["practice"].is_empty(), "nor practice")
    check(not again["first"], "and is not a first completion")
