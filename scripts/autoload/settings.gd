extends Node
## Minimal persistent settings: sensitivity, invert-Y, scope scale, master
## volume and render quality. Gameplay reads these values at runtime; the CP5
## settings panel (scripts/ui/settings_panel.gd) writes them back.

signal changed

const SETTINGS_PATH := "user://settings.cfg"

const DEFAULT_SENSITIVITY := 0.0022
const DEFAULT_INVERT_Y := false
const DEFAULT_SCOPE_SENSITIVITY_SCALE := 0.7
const DEFAULT_MASTER_VOLUME := 1.0

## Quality is an index into these tables so the UI never hardcodes the mapping.
const QUALITY_LOW := 0
const QUALITY_MEDIUM := 1
const QUALITY_HIGH := 2
const QUALITY_NAMES: Array[String] = ["LOW", "MEDIUM", "HIGH"]
## Compatibility-safe knobs only: 3D resolution scale + directional shadow
## atlas size. Both are real render settings and safe to change at runtime.
const QUALITY_SCALES: Array[float] = [0.7, 0.85, 1.0]
const QUALITY_SHADOW_ATLAS: Array[int] = [1024, 2048, 4096]
const DEFAULT_QUALITY := QUALITY_HIGH

const SENSITIVITY_MIN := 0.0005
const SENSITIVITY_MAX := 0.01
const SCOPE_SCALE_MIN := 0.2
const SCOPE_SCALE_MAX := 1.0

var settings_path: String = SETTINGS_PATH
var sensitivity: float = DEFAULT_SENSITIVITY
var invert_y: bool = DEFAULT_INVERT_Y
var scope_sensitivity_scale: float = DEFAULT_SCOPE_SENSITIVITY_SCALE
var master_volume: float = DEFAULT_MASTER_VOLUME
var quality: int = DEFAULT_QUALITY


func _ready() -> void:
	load_settings()
	_apply_audio()
	_apply_quality()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	sensitivity = clampf(
		float(config.get_value("input", "sensitivity", sensitivity)),
		SENSITIVITY_MIN,
		SENSITIVITY_MAX
	)
	invert_y = bool(config.get_value("input", "invert_y", invert_y))
	scope_sensitivity_scale = clampf(
		float(config.get_value("input", "scope_sensitivity_scale", scope_sensitivity_scale)),
		SCOPE_SCALE_MIN,
		SCOPE_SCALE_MAX
	)
	master_volume = clampf(float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	quality = clampi(int(config.get_value("video", "quality", quality)), QUALITY_LOW, QUALITY_HIGH)
	changed.emit()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "sensitivity", sensitivity)
	config.set_value("input", "invert_y", invert_y)
	config.set_value("input", "scope_sensitivity_scale", scope_sensitivity_scale)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("video", "quality", quality)
	config.save(settings_path)
	_apply_audio()
	_apply_quality()
	changed.emit()


func set_sensitivity(value: float) -> void:
	sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	save_settings()


func set_invert_y(value: bool) -> void:
	invert_y = value
	save_settings()


func set_scope_sensitivity_scale(value: float) -> void:
	scope_sensitivity_scale = clampf(value, SCOPE_SCALE_MIN, SCOPE_SCALE_MAX)
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	save_settings()


func set_quality(value: int) -> void:
	quality = clampi(value, QUALITY_LOW, QUALITY_HIGH)
	save_settings()


func quality_name() -> String:
	return QUALITY_NAMES[clampi(quality, QUALITY_LOW, QUALITY_HIGH)]


func reset_defaults() -> void:
	sensitivity = DEFAULT_SENSITIVITY
	invert_y = DEFAULT_INVERT_Y
	scope_sensitivity_scale = DEFAULT_SCOPE_SENSITIVITY_SCALE
	master_volume = DEFAULT_MASTER_VOLUME
	quality = DEFAULT_QUALITY
	save_settings()


func _apply_audio() -> void:
	if master_volume <= 0.001:
		AudioServer.set_bus_mute(0, true)
		return
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))


## Render quality is applied to the root viewport so it survives menu → match
## transitions without touching gameplay, maps or the network layer.
func _apply_quality() -> void:
	# Settings is also instantiated in unit tests that are not inside the tree.
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var viewport := tree.root
	if viewport == null:
		return
	quality = clampi(quality, QUALITY_LOW, QUALITY_HIGH)
	viewport.scaling_3d_scale = QUALITY_SCALES[quality]
	RenderingServer.directional_shadow_atlas_set_size(QUALITY_SHADOW_ATLAS[quality], false)
