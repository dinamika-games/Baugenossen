extends SceneTree
## Run a test script headless: override [method _run], call [method check] and
## the test ends with "RESULT: OK" (exit code 0) or the list of failures (1).
##
## $GODOT --headless --path . --script tests/godot/test_<name>.gd

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
    _start.call_deferred()


func _start() -> void:
    await _run()
    if _failures.is_empty():
        print("%d check(s) passed." % _checks)
        print("RESULT: OK")
        quit(0)
    else:
        print("%d of %d check(s) failed:" % [_failures.size(), _checks])
        for failure in _failures:
            print("  - ", failure)
        print("RESULT: FAILED")
        quit(1)


## Override with the test.
func _run() -> void:
    pass


func check(condition: bool, message: String) -> void:
    _checks += 1
    if not condition:
        print("FAIL ", message)
        _failures.append(message)


func check_equal(actual: Variant, expected: Variant, message: String) -> void:
    _checks += 1
    if actual != expected:
        var text := "%s: expected %s, got %s" % [message, expected, actual]
        print("FAIL ", text)
        _failures.append(text)
