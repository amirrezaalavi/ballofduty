extends Node
## Tiny synthesized SFX layer. No external audio assets needed for CP3; keeps
## the Web payload small and avoids licensing work.

const MIX_RATE := 22050
const VOICES := 6

var _players: Array[AudioStreamPlayer] = []
var _sounds: Dictionary = {}


func _ready() -> void:
	for _i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

	_sounds["shoot"] = _synth(0.09, 300.0, 140.0, 0.55, 0.35)
	_sounds["hit"] = _synth(0.055, 880.0, 700.0, 0.25, 0.05)
	_sounds["reload"] = _synth(0.11, 220.0, 160.0, 0.35, 0.3)
	_sounds["empty"] = _synth(0.05, 160.0, 120.0, 0.2, 0.6)
	_sounds["death"] = _synth(0.45, 300.0, 80.0, 0.25, 0.0)


func play_shoot() -> void:
	_play("shoot", -9.0)


func play_hit() -> void:
	_play("hit", -12.0)


func play_reload() -> void:
	_play("reload", -13.0)


func play_empty() -> void:
	_play("empty", -14.0)


func play_death() -> void:
	_play("death", -8.0)


func _play(key: String, volume_db: float) -> void:
	var stream: AudioStream = _sounds.get(key)
	if stream == null:
		return
	for player in _players:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume_db
			player.play()
			return


func _synth(
	duration: float,
	freq_from: float,
	freq_to: float,
	volume: float,
	noise_mix: float
) -> AudioStreamWAV:
	var sample_count := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var phase := 0.0

	for i in sample_count:
		var t := float(i) / float(MIX_RATE)
		var progress := float(i) / float(sample_count)
		var frequency := lerpf(freq_from, freq_to, progress)
		phase += TAU * frequency / float(MIX_RATE)
		var envelope := pow(1.0 - progress, 2.0)
		var tone := sin(phase)
		var noise := rng.randf_range(-1.0, 1.0)
		var sample := lerpf(tone, noise, noise_mix) * envelope * volume
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
