class_name PartSupply
extends RefCounted
## Hold the parts of a puzzle level (DESIGN.md, 2.4): the level gives a fixed
## set of parts, enough for many solutions; the yard shows each kind once,
## with how many are left. Taking a part leaves one less; a part given back
## (lowered onto the yard) is one more. Nothing comes at random and nothing
## leaves: no part is ever lost.

## The kinds of parts, in the order of the level (the places of the yard).
var kinds: Array[String] = []
## part ID -> how many are left in the yard.
var counts: Dictionary = {}


## The supply of the level's parts, less those already standing on the site
## (not the protected ones; never below zero).
static func for_level(parts: Dictionary, grid: WorldGrid) -> PartSupply:
    var supply := PartSupply.new()
    for id in parts:
        supply.kinds.append(str(id))
        supply.counts[str(id)] = int(parts[id])
    if grid != null:
        for id in grid.instances:
            var instance: PartInstance = grid.instances[id]
            if not instance.protected and supply.counts.has(instance.definition_id):
                supply.counts[instance.definition_id] = maxi(
                    0, int(supply.counts[instance.definition_id]) - 1
                )
    return supply


func count(index: int) -> int:
    if index < 0 or index >= kinds.size():
        return 0
    return int(counts[kinds[index]])


## Take one part of the kind at the place; return its ID, or "" if none is
## left.
func take(index: int) -> String:
    if count(index) <= 0:
        return ""
    counts[kinds[index]] = count(index) - 1
    return kinds[index]


## Give a part back to the yard (a kind which the level did not give, e.g.,
## from an older game, gets a new place at the end).
func give_back(part_id: String) -> void:
    if not counts.has(part_id):
        kinds.append(part_id)
        counts[part_id] = 0
    counts[part_id] = int(counts[part_id]) + 1
