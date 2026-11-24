class_name DwellSelector
extends RefCounted
## Select a catalogue entry by pointing at it for [member dwell_seconds] with
## the raised hand (DESIGN.md, 3.3); the hand's return completes the selection.
## The progress is shown on the entry, so the player sees it fill.

var dwell_seconds := 0.65
var target := ""
var progress := 0.0
var _since := -1.0


## Point at the entry (or "" for none) at the time; return the progress [0, 1].
func point(entry: String, now: float) -> float:
    if entry != target:
        target = entry
        _since = now
    if target == "":
        progress = 0.0
    else:
        progress = clampf((now - _since) / dwell_seconds, 0.0, 1.0)
    return progress


## The selected entry once the dwell completed, or "".
func selected() -> String:
    return target if progress >= 1.0 else ""


func reset() -> void:
    target = ""
    progress = 0.0
    _since = -1.0
