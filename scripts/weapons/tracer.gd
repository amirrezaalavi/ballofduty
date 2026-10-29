class_name Tracer
extends Node3D
## Cosmetic projectile tracer. No collision, no damage; predicted locally on
## fire and spawned from server SHOT events for other players.

var _life := 0.08


static func spawn(parent: Node, origin: Vector3, direction: Vector3, color: Color = Color(1.0, 0.82, 0.35)) -> void:
	if parent == null or direction.length_squared() < 0.0001:
		return
	if DisplayServer.get_name() == "headless":
		return
	var tracer := Tracer.new()
	parent.add_child(tracer)
	tracer.global_position = origin
	tracer.look_at(origin + direction.normalized(), Vector3.UP)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.022, 0.022, 0.9)
	mesh.mesh = box
	mesh.position = Vector3(0.0, 0.0, -0.45)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	mesh.material_override = material
	tracer.add_child(mesh)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
