class_name Placement
extends RefCounted
## Validate placements and moves on a [WorldGrid] (DESIGN.md, 2.4 and 2.5), and
## make the [EditCommand]s which carry them out.
##
## A placement is valid if the part is offered (by the mission and the unlocks),
## the crane can lift it, it fits the geometry, and it is supported. Floors and
## roofs may overhang too far while building, and stairs may lack their top
## landing; both stay as warnings that block the submission until fixed.


class Context:
    extends RefCounted
    ## How much mass the crane lifts (4 + Brawn).
    var capacity := 99
    ## The part IDs which the mission offers; empty offers everything.
    var offered: Array = []
    ## The part IDs which the character has unlocked (as keys); null if all are.
    var unlocked: Variant = null


static func check_offer(definition: PartDef, context: Context) -> PlacementResult:
    if not context.offered.is_empty() and definition.id not in context.offered:
        return PlacementResult.invalid("ERROR_NOT_OFFERED")
    if context.unlocked != null and not (context.unlocked as Dictionary).has(definition.id):
        return PlacementResult.invalid("ERROR_LOCKED")
    if definition.mass > context.capacity:
        return PlacementResult.invalid(
            "ERROR_OVERWEIGHT", [], {"mass": definition.mass, "capacity": context.capacity}
        )
    return PlacementResult.valid()


## Check whether the part can be placed at the anchor; [param moving] is the
## instance which a move takes away first (0 for none).
static func validate(
    grid: WorldGrid,
    definition: PartDef,
    anchor: Vector2i,
    mirrored: bool,
    context: Context,
    moving := 0
) -> PlacementResult:
    if definition == null:
        return PlacementResult.invalid("ERROR_UNKNOWN_PART")
    var offer := check_offer(definition, context)
    if not offer.ok:
        return offer
    if mirrored and not definition.can_mirror():
        return PlacementResult.invalid("ERROR_CANNOT_MIRROR")
    if moving != 0:
        var moved: PartInstance = grid.instances.get(moving)
        if moved == null:
            return PlacementResult.invalid("ERROR_NOTHING_THERE")
        if moved.protected:
            return PlacementResult.invalid("ERROR_PROTECTED", [moving])

    var ignore: Array[int] = []
    if moving != 0:
        ignore.append(moving)
    var geometry := grid.check_geometry(definition, anchor, ignore)
    if not geometry.ok:
        return geometry
    return _check_support(grid, definition, anchor, mirrored, moving)


static func _check_support(
    grid: WorldGrid, definition: PartDef, anchor: Vector2i, mirrored: bool, moving: int
) -> PlacementResult:
    # NOTE (mristin):
    # We try the placement on the grid itself and restore it right away, so
    # that the support sees exactly the world after the edit.
    var taken: PartInstance = null
    if moving != 0:
        taken = grid.remove_instance(moving)
    var probe := PartInstance.create(grid.next_id, definition.id, anchor, mirrored)
    grid.add_instance(probe)
    var report := SupportEvaluator.evaluate(grid)
    grid.remove_instance(probe.id)
    grid.next_id = probe.id
    if taken != null:
        grid.add_instance(taken)

    if report.is_supported(probe.id):
        var result := PlacementResult.valid()
        if report.problems.has(probe.id):
            result.warning_key = str(report.problems[probe.id])
        return result
    if report.overhang.has(probe.id):
        var result := PlacementResult.valid()
        result.warning_key = "ERROR_OVERHANG"
        return result
    return PlacementResult.invalid("ERROR_UNSUPPORTED")


## Make the command which places a new part; null if the placement is invalid.
static func place_command(
    grid: WorldGrid,
    definition: PartDef,
    anchor: Vector2i,
    mirrored: bool,
    variant: int,
    context: Context
) -> EditCommand:
    if not validate(grid, definition, anchor, mirrored, context).ok:
        return null
    var instance := PartInstance.create(grid.next_id, definition.id, anchor, mirrored, variant)
    return EditCommand.new("place", [], [instance])


## Make the command which removes a part; null if it is protected or missing.
static func remove_command(grid: WorldGrid, id: int) -> EditCommand:
    var instance: PartInstance = grid.instances.get(id)
    if instance == null or instance.protected:
        return null
    return EditCommand.new("remove", [instance.duplicate_instance()], [])


## Make the command which moves a part (one atomic remove and place); null if
## the move is invalid.
static func move_command(
    grid: WorldGrid, id: int, anchor: Vector2i, mirrored: bool, context: Context
) -> EditCommand:
    var instance: PartInstance = grid.instances.get(id)
    if instance == null:
        return null
    var definition := grid.definition_of(instance)
    if not validate(grid, definition, anchor, mirrored, context, id).ok:
        return null
    var moved := instance.duplicate_instance()
    moved.anchor = anchor
    moved.mirrored = mirrored
    return EditCommand.new("move", [instance.duplicate_instance()], [moved])
