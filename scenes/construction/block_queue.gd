class_name BlockQueue
extends RefCounted
## Offer the blocks to build with, like a conveyor (DESIGN.md, 2.4): five
## blocks wait in a row; the player takes the one they want, and a new one
## comes in at the end. Every [member shift_seconds], the oldest block leaves
## and a new one comes in (first in, first out), so that the choice changes
## even while the player builds.
##
## The new blocks are drawn at random from the offered parts, favouring the
## structure, and the parts with the tags which the mission still needs (see
## [member wanted_tags]), so that a home gets its stove before long.

const SIZE := 5
## How much more likely a part with a wanted tag comes.
const WANTED_WEIGHT := 4.0
## How likely each category comes.
const CATEGORY_WEIGHTS := {
    "structure": 4.0,
    "access": 1.0,
    "furniture": 1.5,
    "utilities": 1.0,
    "nature": 1.5,
    "recreation": 1.0,
}

## The blocks in the row, oldest first.
var slots: Array[String] = []
## The seconds between two shifts of the row.
var shift_seconds := 15.0
## How far the row is to its next shift, in [0, 1).
var progress := 0.0
## The tags which the mission still needs (as keys).
var wanted_tags: Dictionary = {}

var _content: ContentDb
var _offered: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _init(content: ContentDb, offered: Array = [], seed_value := -1) -> void:
    _content = content
    for id in content.part_order:
        if offered.is_empty() or id in offered:
            if CATEGORY_WEIGHTS.has(content.part(id).category_id):
                _offered.append(id)
    if seed_value >= 0:
        _rng.seed = seed_value
    else:
        _rng.randomize()
    while slots.size() < SIZE:
        slots.append(_draw())


## Take the block of the slot: it leaves the row, and a new one comes in at
## the end. Return its part ID, or "" if the slot is empty.
func take(index: int) -> String:
    if index < 0 or index >= slots.size():
        return ""
    var taken := slots[index]
    slots.remove_at(index)
    slots.append(_draw())
    return taken


## Let the time pass; return whether the row shifted (the oldest block left).
func advance(seconds: float) -> bool:
    progress += seconds / shift_seconds
    if progress < 1.0:
        return false
    progress = fmod(progress, 1.0)
    slots.pop_front()
    slots.append(_draw())
    return true


func _draw() -> String:
    var total := 0.0
    var weights: Array[float] = []
    for id in _offered:
        var weight := _weight(_content.part(id))
        weights.append(weight)
        total += weight
    var pick := _rng.randf() * total
    for i in range(_offered.size()):
        pick -= weights[i]
        if pick <= 0.0:
            return _offered[i]
    return _offered.back()


func _weight(definition: PartDef) -> float:
    var weight := float(CATEGORY_WEIGHTS.get(definition.category_id, 1.0))
    for tag in definition.tags:
        if wanted_tags.has(tag):
            return weight * WANTED_WEIGHT
    return weight
