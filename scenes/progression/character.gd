class_name Character
extends RefCounted
## Hold the builder: a fictional character, independent of the real player's
## body (DESIGN.md, 4). Only the choices and the earned values are stored; the
## skills and the unlocks are derived by [Progression].

var name := ""
var pronouns := ""
## The palette indices of the look: "skin", "hair", "clothing".
var appearance := {"skin": 0, "hair": 0, "clothing": 0}
var background_id := "apprentice"
var attributes: Dictionary = {}
var traits: Array[String] = []
## The skill which the trait "specialist" raises.
var specialist_skill := ""
## The skill points the player invested (and the practice), by skill ID.
var invested: Dictionary = {}
var skill_points := 0
var perk_tokens := 0
var attribute_points := 0
var perks: Array[String] = []
var xp := 0
var karma := 0
## The reward IDs already claimed (as keys); every reward is granted once.
var claimed_rewards: Dictionary = {}
var completed_missions: Array[String] = []
## Whether the character took a mission; then the creation can not be reset.
var started := false


static func create_default(content: ContentDb) -> Character:
    var character := Character.new()
    character.attributes = content.default_attributes.duplicate()
    return character


func attribute(id: String) -> int:
    return int(attributes.get(id, 0))


func level() -> int:
    return Progression.level_for_xp(xp)


func has_completed(mission_id: String) -> bool:
    return mission_id in completed_missions


func to_dict() -> Dictionary:
    var rewards: Array = claimed_rewards.keys()
    rewards.sort()
    return {
        "name": name,
        "pronouns": pronouns,
        "appearance": appearance.duplicate(),
        "background_id": background_id,
        "attributes": attributes.duplicate(),
        "traits": traits.duplicate(),
        "specialist_skill": specialist_skill,
        "invested": invested.duplicate(),
        "skill_points": skill_points,
        "perk_tokens": perk_tokens,
        "attribute_points": attribute_points,
        "perks": perks.duplicate(),
        "xp": xp,
        "karma": karma,
        "claimed_rewards": rewards,
        "completed_missions": completed_missions.duplicate(),
        "started": started,
    }


## Read a character and validate every value against the content and the caps;
## return null and append to [param problems] if it is invalid.
static func from_dict(data: Variant, content: ContentDb, problems: Array[String]) -> Character:
    if not data is Dictionary:
        problems.append("the character is not an object")
        return null
    var record: Dictionary = data
    var character := Character.new()
    character.name = str(record.get("name", "")).left(40)
    character.pronouns = str(record.get("pronouns", "")).left(30)
    var look: Variant = record.get("appearance", {})
    if look is Dictionary:
        for key in ["skin", "hair", "clothing"]:
            character.appearance[key] = clampi(int(look.get(key, 0)), 0, 7)
    character.background_id = str(record.get("background_id", ""))
    if not content.backgrounds.has(character.background_id):
        problems.append("unknown background %s" % character.background_id)
        return null
    var values: Variant = record.get("attributes", {})
    if not values is Dictionary:
        problems.append("the attributes are not an object")
        return null
    for id in ContentDb.ATTRIBUTE_IDS:
        var value := int(values.get(id, 0))
        if value < content.attribute_min or value > content.attribute_max:
            problems.append("attribute %s out of range: %d" % [id, value])
            return null
        character.attributes[id] = value
    for id in record.get("traits", []):
        if not content.traits.has(str(id)) or not content.traits[str(id)].get("implemented"):
            problems.append("unknown trait %s" % id)
            return null
        character.traits.append(str(id))
    if character.traits.size() > content.max_traits:
        problems.append("too many traits")
        return null
    character.specialist_skill = str(record.get("specialist_skill", ""))
    var invested_values: Variant = record.get("invested", {})
    if invested_values is Dictionary:
        for id in invested_values:
            if content.skills.has(str(id)):
                character.invested[str(id)] = clampi(int(invested_values[id]), 0, 100)
            else:
                problems.append("unknown skill %s" % id)
    character.skill_points = maxi(0, int(record.get("skill_points", 0)))
    character.perk_tokens = maxi(0, int(record.get("perk_tokens", 0)))
    character.attribute_points = maxi(0, int(record.get("attribute_points", 0)))
    for id in record.get("perks", []):
        if content.perks.has(str(id)) and str(id) not in character.perks:
            character.perks.append(str(id))
        else:
            problems.append("unknown perk %s" % id)
    character.xp = maxi(0, int(record.get("xp", 0)))
    character.karma = maxi(0, int(record.get("karma", 0)))
    for id in record.get("claimed_rewards", []):
        character.claimed_rewards[str(id)] = true
    for id in record.get("completed_missions", []):
        if content.missions.has(str(id)) and str(id) not in character.completed_missions:
            character.completed_missions.append(str(id))
    character.started = bool(record.get("started", false))
    return character
