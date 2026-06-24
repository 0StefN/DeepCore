extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  DayTimer.gd
#  Countdown timer for the mining phase.
#  Started by World.gd after scene setup.
# ─────────────────────────────────────────────────────────────────────────────

const DEFAULT_DURATION: float = 180.0  # 3 minutes

var time_remaining: float = DEFAULT_DURATION
var is_running:     bool  = false

signal time_updated(seconds_left: float)
signal time_expired()

func start(duration: float = DEFAULT_DURATION) -> void:
	time_remaining = duration
	is_running     = true

func pause()  -> void: is_running = false
func resume() -> void: is_running = true

func _process(delta: float) -> void:
	if not is_running:
		return
	time_remaining = maxf(0.0, time_remaining - delta)
	time_updated.emit(time_remaining)
	if time_remaining <= 0.0:
		is_running = false
		time_expired.emit()

func get_formatted() -> String:
	var s: int = ceili(time_remaining)
	return "%d:%02d" % [s / 60, s % 60]

func get_fraction() -> float:
	return time_remaining / DEFAULT_DURATION
