class_name OneEuroFilter
extends RefCounted
## Smooth a noisy signal with little lag: the faster it moves, the less it is
## smoothed (Casiez, Roussel and Vogel, "1€ Filter", CHI 2012). Still, it is
## calm; moving, it follows quickly.

## The cutoff frequency at rest, in Hz: lower is calmer, but lags more.
var min_cutoff := 1.0
## How much the cutoff rises with the speed of the signal.
var beta := 1.0
var derivative_cutoff := 1.0

var _value := 0.0
var _derivative := 0.0
var _last := -1.0


func _init(cutoff := 1.0, speed_coefficient := 1.0) -> void:
    min_cutoff = cutoff
    beta = speed_coefficient


## The filtered value of the signal at the time (in seconds).
func filter(value: float, time: float) -> float:
    if _last < 0.0:
        _value = value
        _last = time
        return value
    var dt := time - _last
    if dt <= 0.000001:
        return _value
    _last = time
    var derivative := (value - _value) / dt
    _derivative += _alpha(derivative_cutoff, dt) * (derivative - _derivative)
    var cutoff := min_cutoff + beta * absf(_derivative)
    _value += _alpha(cutoff, dt) * (value - _value)
    return _value


## Start anew: the next value passes as it is.
func reset() -> void:
    _last = -1.0
    _derivative = 0.0


static func _alpha(cutoff: float, dt: float) -> float:
    var tau := 1.0 / (TAU * cutoff)
    return 1.0 / (1.0 + tau / dt)
