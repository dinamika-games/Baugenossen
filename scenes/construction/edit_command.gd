class_name EditCommand
extends RefCounted
## Hold one atomic edit of a site: the instances it removes and those it adds
## (a placement adds one, a removal removes one, a move does both with the same
## ID). [method apply] either carries out the whole edit or nothing.

var kind := ""
var removals: Array[PartInstance] = []
var additions: Array[PartInstance] = []


func _init(
    edit_kind := "", removed: Array[PartInstance] = [], added: Array[PartInstance] = []
) -> void:
    kind = edit_kind
    removals = removed
    additions = added


## Carry out the edit; return false and leave the grid unchanged if it does not
## apply (e.g., a removed part is gone, protected, or the slots are taken).
func apply(grid: WorldGrid) -> bool:
    for instance in removals:
        var current: PartInstance = grid.instances.get(instance.id)
        if current == null or current.protected or not current.same_as(instance):
            return false
    var next_id := grid.next_id
    var taken: Array[PartInstance] = []
    for instance in removals:
        taken.append(grid.remove_instance(instance.id))
    var added: Array[PartInstance] = []
    for instance in additions:
        var definition := grid.content.part(instance.definition_id)
        var fits := (
            definition != null
            and not grid.instances.has(instance.id)
            and grid.check_geometry(definition, instance.anchor).ok
        )
        if not fits:
            for done in added:
                grid.remove_instance(done.id)
            for back in taken:
                grid.add_instance(back)
            grid.next_id = next_id
            return false
        var copy := instance.duplicate_instance()
        grid.add_instance(copy)
        added.append(copy)
    grid.notify_changed()
    return true


## Undo the edit, which must be the last one applied.
func revert(grid: WorldGrid) -> bool:
    return inverse().apply(grid)


func inverse() -> EditCommand:
    return EditCommand.new(kind, additions, removals)
