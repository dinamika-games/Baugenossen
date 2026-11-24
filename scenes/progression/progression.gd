class_name Progression
extends RefCounted
## Apply the rules of the character (DESIGN.md, 4): the attribute budget, the
## skills, the levels, the karma, the perks, the unlocks and the practice.
##
## Nothing here depends on the real player's body or performance: the rules
## see only the fictional character and the completed constructions.

const SKILL_CAP := 100
const POINTS_PER_LEVEL := 10
const PRACTICE_MINIMUM_INSTANCES := 3
const PRACTICE_SKILLS := 3

const LEVEL_RANKS := [
    [1, "RANK_APPRENTICE"],
    [5, "RANK_JOURNEYMAN"],
    [10, "RANK_CRAFTSPERSON"],
    [15, "RANK_BUILDER"],
    [20, "RANK_MASTER_BUILDER"],
    [30, "RANK_CITY_BUILDER"],
    [40, "RANK_GRANDMASTER"],
    [50, "RANK_LIVING_LEGEND"],
]

const REPUTATIONS := [
    [0, "REPUTATION_NEWCOMER"],
    [100, "REPUTATION_HELPING_HAND"],
    [500, "REPUTATION_TRUSTED_NEIGHBOUR"],
    [1500, "REPUTATION_PILLAR"],
    [5000, "REPUTATION_COMMUNITY_BUILDER"],
    [15000, "REPUTATION_LIVING_LEGEND"],
]


## The cumulative XP needed for the level: 100 * (L - 1) * L / 2.
static func xp_for_level(level: int) -> int:
    return 100 * (level - 1) * level / 2


static func level_for_xp(xp: int) -> int:
    var level := 1
    while xp_for_level(level + 1) <= xp:
        level += 1
    return level


static func rank_key(level: int) -> String:
    var key := ""
    for entry in LEVEL_RANKS:
        if level >= int(entry[0]):
            key = str(entry[1])
    return key


static func reputation_key(karma: int) -> String:
    var key := ""
    for entry in REPUTATIONS:
        if karma >= int(entry[0]):
            key = str(entry[1])
    return key


static func skill_rank_key(value: int, content: ContentDb) -> String:
    var key := ""
    for rank in content.skill_ranks:
        if value >= int(rank["minimum"]):
            key = str(rank["key"])
    return key


static func crane_capacity(character: Character) -> int:
    return 4 + character.attribute("B")


## Check the creation: each attribute within its range and all of them summing
## to the budget, a known background, at most two implemented traits, and a
## skill for the specialist. Return the problems as translation keys.
static func creation_problems(character: Character, content: ContentDb) -> Array[String]:
    var problems: Array[String] = []
    var total := 0
    for id in ContentDb.ATTRIBUTE_IDS:
        var value := character.attribute(id)
        total += value
        if value < content.attribute_min or value > content.attribute_max:
            problems.append("CREATE_ERROR_ATTRIBUTE_RANGE")
    if total != content.attribute_total:
        problems.append("CREATE_ERROR_ATTRIBUTE_TOTAL")
    if not content.backgrounds.has(character.background_id):
        problems.append("CREATE_ERROR_BACKGROUND")
    if character.traits.size() > content.max_traits:
        problems.append("CREATE_ERROR_TOO_MANY_TRAITS")
    for id in character.traits:
        if not content.traits.has(id) or not content.traits[id].get("implemented", false):
            problems.append("CREATE_ERROR_TRAIT")
    if "specialist" in character.traits and not content.skills.has(character.specialist_skill):
        problems.append("CREATE_ERROR_SPECIALIST")
    if character.name.strip_edges() == "":
        problems.append("CREATE_ERROR_NAME")
    return problems


static func attribute_points_left(character: Character, content: ContentDb) -> int:
    var total := 0
    for id in ContentDb.ATTRIBUTE_IDS:
        total += character.attribute(id)
    return content.attribute_total - total


## The base of the skill: 5 + 2 A + 2 B + the background + the traits (+ the
## perk "Jack of All Trades"), clamped to [0, 100].
static func base_skill(character: Character, skill_id: String, content: ContentDb) -> int:
    var skill: Dictionary = content.skills[skill_id]
    var value := 5
    for attribute in skill["attributes"]:
        value += 2 * character.attribute(str(attribute))
    var bonuses: Dictionary = content.backgrounds[character.background_id]["skill_bonuses"]
    value += int(bonuses.get(skill_id, bonuses.get("*", 0)))
    for trait_id in character.traits:
        var record: Dictionary = content.traits[trait_id]
        var modifiers: Dictionary = record["skill_modifiers"]
        if trait_id == "specialist" and skill_id == character.specialist_skill:
            value += int(record.get("selected_skill_bonus", 0))
        else:
            value += int(modifiers.get(skill_id, modifiers.get("*", 0)))
    if "jack_of_all_trades" in character.perks:
        value += 5
    return clampi(value, 0, SKILL_CAP)


static func skill(character: Character, skill_id: String, content: ContentDb) -> int:
    var value := base_skill(character, skill_id, content)
    return mini(SKILL_CAP, value + int(character.invested.get(skill_id, 0)))


static func points_per_level(character: Character, content: ContentDb) -> int:
    var background: Dictionary = content.backgrounds[character.background_id]
    return POINTS_PER_LEVEL + int(background.get("extra_points_per_level", 0))


## Grant a reward once: the XP and the karma, and every level gained on the way
## with its skill points, perk tokens (every third level) and attribute points
## (every fifth). Return the levels gained, or -1 if it was claimed already.
static func award_once(
    character: Character, reward_id: String, xp: int, karma: int, content: ContentDb
) -> int:
    if character.claimed_rewards.has(reward_id):
        return -1
    character.claimed_rewards[reward_id] = true
    var before := character.level()
    character.xp += maxi(0, xp)
    character.karma += maxi(0, karma)
    var after := character.level()
    for level in range(before + 1, after + 1):
        character.skill_points += points_per_level(character, content)
        if level % 3 == 0:
            character.perk_tokens += 1
        if level % 5 == 0:
            character.attribute_points += 1
    return after - before


## Invest unspent skill points; return false (and change nothing) if the points
## are not there or the skill would pass its cap.
static func invest(character: Character, skill_id: String, points: int, content: ContentDb) -> bool:
    if not content.skills.has(skill_id) or points <= 0 or points > character.skill_points:
        return false
    if skill(character, skill_id, content) + points > SKILL_CAP:
        return false
    character.invested[skill_id] = int(character.invested.get(skill_id, 0)) + points
    character.skill_points -= points
    return true


static func raise_attribute(character: Character, id: String, content: ContentDb) -> bool:
    if id not in ContentDb.ATTRIBUTE_IDS or character.attribute_points <= 0:
        return false
    if character.attribute(id) >= content.attribute_max:
        return false
    character.attributes[id] = character.attribute(id) + 1
    character.attribute_points -= 1
    return true


## Whether the character meets every requirement (skills, attributes, level).
static func meets(requirements: Array, character: Character, content: ContentDb) -> bool:
    return missing_requirements(requirements, character, content).is_empty()


## The requirements the character does not meet yet, for the explanations.
static func missing_requirements(
    requirements: Array, character: Character, content: ContentDb
) -> Array[Dictionary]:
    var missing: Array[Dictionary] = []
    for requirement in requirements:
        var minimum := int(requirement.get("minimum", 0))
        var current := 0
        match str(requirement.get("type", "")):
            "skill":
                current = skill(character, str(requirement["id"]), content)
            "attribute":
                current = character.attribute(str(requirement["id"]))
            "level":
                current = character.level()
            "any_skill":
                for id in content.skill_order:
                    current = maxi(current, skill(character, id, content))
            "perk":
                current = 1 if str(requirement["id"]) in character.perks else 0
                minimum = 1
        if current < minimum:
            var entry: Dictionary = requirement.duplicate()
            entry["current"] = current
            missing.append(entry)
    return missing


## The part IDs which the character can use (as keys).
static func unlocked_parts(character: Character, content: ContentDb) -> Dictionary:
    var unlocked := {}
    for id in content.part_order:
        if meets(content.part(id).requirements, character, content):
            unlocked[id] = true
    return unlocked


## Why a perk can not be bought now: "" if it can, or a translation key.
static func perk_problem(character: Character, perk_id: String, content: ContentDb) -> String:
    var perk: Dictionary = content.perks.get(perk_id, {})
    if perk.is_empty():
        return "PERK_ERROR_UNKNOWN"
    if not perk.get("implemented", false):
        return "PERK_ERROR_NOT_IMPLEMENTED"
    if perk_id in character.perks:
        return "PERK_ERROR_OWNED"
    if character.perk_tokens <= 0:
        return "PERK_ERROR_NO_TOKEN"
    if not meets(perk["requirements"], character, content):
        return "PERK_ERROR_REQUIREMENTS"
    return ""


static func buy_perk(character: Character, perk_id: String, content: ContentDb) -> bool:
    if perk_problem(character, perk_id, content) != "":
        return false
    character.perks.append(perk_id)
    character.perk_tokens -= 1
    return true


## Award the practice of a first completion: +1 to each of up to three craft
## skills with the most distinct final parts (at least three), ties broken by
## the skill ID. Return the skills which got the point.
static func award_practice(
    character: Character, mission_id: String, grid: WorldGrid, content: ContentDb
) -> Array[String]:
    var practised: Array[String] = []
    var reward_id := "practice:" + mission_id
    if character.claimed_rewards.has(reward_id):
        return practised
    character.claimed_rewards[reward_id] = true
    var counts := {}
    for id in grid.sorted_ids():
        var instance: PartInstance = grid.instances[id]
        if instance.protected:
            continue
        var craft := grid.definition_of(instance).craft_skill
        if content.skills.has(craft):
            counts[craft] = int(counts.get(craft, 0)) + 1
    var candidates: Array = []
    for craft in counts:
        if int(counts[craft]) >= PRACTICE_MINIMUM_INSTANCES:
            candidates.append([-int(counts[craft]), str(craft)])
    candidates.sort()
    for candidate in candidates.slice(0, PRACTICE_SKILLS):
        var skill_id: String = candidate[1]
        if skill(character, skill_id, content) < SKILL_CAP:
            character.invested[skill_id] = int(character.invested.get(skill_id, 0)) + 1
            practised.append(skill_id)
    return practised


## Whether the mission is open: its prerequisites completed and the karma met.
static func mission_available(character: Character, mission: Dictionary) -> bool:
    for prerequisite in mission["prerequisite_ids"]:
        if not character.has_completed(str(prerequisite)):
            return false
    return character.karma >= int(mission.get("min_karma", 0))


## Complete a mission: the base reward once, every satisfied optional wish once,
## the practice on the first completion. Return a summary for the results.
static func complete_mission(
    character: Character,
    mission: Dictionary,
    report: MissionEvaluator.Report,
    grid: WorldGrid,
    content: ContentDb
) -> Dictionary:
    var summary := {"xp": 0, "karma": 0, "levels": 0, "wishes": [], "practice": [], "first": false}
    if not report.can_submit():
        return summary
    var level_before := character.level()
    var mission_id := str(mission["id"])
    var first := not character.has_completed(mission_id)
    var base_xp := int(mission["base_xp"])
    var base_karma := int(mission["base_karma"])
    if award_once(character, "mission:" + mission_id, base_xp, base_karma, content) >= 0:
        summary["xp"] += base_xp
        summary["karma"] += base_karma
    for result in report.optional:
        if not result["satisfied"]:
            continue
        var reward_id := "wish:%s:%s" % [mission_id, result["id"]]
        if award_once(character, reward_id, int(result["xp"]), int(result["karma"]), content) >= 0:
            summary["xp"] += int(result["xp"])
            summary["karma"] += int(result["karma"])
            summary["wishes"].append(str(result["id"]))
    if first:
        character.completed_missions.append(mission_id)
        summary["practice"] = award_practice(character, mission_id, grid, content)
    summary["first"] = first
    summary["levels"] = character.level() - level_before
    return summary
