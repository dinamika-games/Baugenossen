class_name Json
extends RefCounted
## Parse JSON quietly: [method JSON.parse_string] reports every malformed text as
## an engine error, but a damaged save is expected and handled by the caller.


## The parsed value, or null if the text is not valid JSON.
static func parse(text: String) -> Variant:
    var json := JSON.new()
    if json.parse(text) != OK:
        return null
    return json.data
