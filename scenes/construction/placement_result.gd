class_name PlacementResult
extends RefCounted
## Tell whether a placement is valid, and if not, why: a translation key (e.g.,
## ERROR_OVERLAP), its parameters and the instances in the way, which the build
## screen highlights.

var ok := true
var reason_key := ""
var params: Dictionary = {}
var instance_ids: Array[int] = []
## A warning for a valid placement (e.g., a floor which still overhangs too far).
var warning_key := ""


static func valid() -> PlacementResult:
    return PlacementResult.new()


static func invalid(
    key: String, ids: Array[int] = [], parameters: Dictionary = {}
) -> PlacementResult:
    var result := PlacementResult.new()
    result.ok = false
    result.reason_key = key
    result.instance_ids = ids
    result.params = parameters
    return result
