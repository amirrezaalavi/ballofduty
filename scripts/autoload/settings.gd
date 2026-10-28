extends Node
## Minimal persistent settings for CP1: sensitivity, invert-Y and master volume.
## The full settings UI lands in CP5; gameplay reads these values at runtime.

signal changed

const SETTINGS_PATH := "user://settings.cfg"

var settings_path: String = SETTINGS_PATH
var sensitivity: float = 0.0022
var invert_y: bool = false
var scope_sensitivity_scale: float = 0.7
var master_volume: float = 1.0


func _ready() -> void:
	load_settings()
	_apply_audio()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	sensitivity = clampf(float(config.get_value("input", "sensitivity", sensitivity)), 0.0005, 0.01)
	invert_y = bool(config.get_value("input", "invert_y", invert_y))
	scope_sensitivity_scale = clampf(
		float(config.get_value("input", "scope_sensitivity_scale", scope_sensitivity_scale)),
		0.2,
		1.0
	)
	master_volume = clampf(float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	changed.emit()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "sensitivity", sensitivity)
	config.set_value("input", "invert_y", invert_y)
	config.set_value("input", "scope_sensitivity_scale", scope_sensitivity_scale)
	config.set_value("audio", "master_volume", master_volume)
	config.save(settings_path)
	_apply_audio()
	changed.emit()


func set_sensitivity(value: float) -> void:
	sensitivity = clampf(value, 0.0005, 0.01)
	save_settings()


func set_invert_y(value: bool) -> void:
	invert_y = value
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	save_settings()


func _apply_audio() -> void:
	if master_volume <= 0.001:
		AudioServer.set_bus_mute(0, true)
		return
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))
