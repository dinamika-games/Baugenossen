class_name CommandHistory
extends RefCounted
## Keep the edits of a site for undo and redo, at most [constant LIMIT] of them
## (DESIGN.md, 2.4). A new edit after an undo clears the redo. The history is
## not saved: it starts empty when a site is opened (see docs/DECISIONS.md).

const LIMIT := 100

var _done: Array[EditCommand] = []
var _undone: Array[EditCommand] = []


## Apply the command and remember it; return whether it applied.
func execute(command: EditCommand, grid: WorldGrid) -> bool:
    if command == null or not command.apply(grid):
        return false
    _done.append(command)
    if _done.size() > LIMIT:
        _done.pop_front()
    _undone.clear()
    return true


func can_undo() -> bool:
    return not _done.is_empty()


func can_redo() -> bool:
    return not _undone.is_empty()


func undo(grid: WorldGrid) -> bool:
    if _done.is_empty():
        return false
    var command: EditCommand = _done.back()
    if not command.revert(grid):
        return false
    _done.pop_back()
    _undone.append(command)
    return true


func redo(grid: WorldGrid) -> bool:
    if _undone.is_empty():
        return false
    var command: EditCommand = _undone.back()
    if not command.apply(grid):
        return false
    _undone.pop_back()
    _done.append(command)
    return true


func size() -> int:
    return _done.size()


func clear() -> void:
    _done.clear()
    _undone.clear()
