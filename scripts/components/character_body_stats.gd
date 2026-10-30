class_name CharacterBodyStats
extends Resource
## Rigid body, hit-volume and camera geometry. This is the single source of
## truth shared by the local client, remote ghosts and the headless server.
##
## It deliberately contains no movement tuning (that stays in PlayerStats) and
## no node references: apply_to_actor() looks up the well-known player nodes by
## name and writes explicit metre values. The CharacterBody3D root and every
## CollisionShape3D keep scale Vector3.ONE; only Visual.scale carries the mesh
## scale.
##
## Step 1 of L2/L8 reproduces the pre-refactor 0.82 m rig exactly. Per-class
## sizing is a later data change, not a code change.

enum Role { LOCAL, REMOTE, SERVER }

@export_group("Identity")
## 0 Knight, 1 Mage, 2 Rogue, 3 Rogue_Hooded, 4 Barbarian.
@export_range(0, 4, 1) var class_id: int = 0

@export_group("Movement capsule")
@export_range(0.05, 1.0, 0.001) var capsule_radius: float = 0.19
@export_range(0.1, 3.0, 0.001) var capsule_height: float = 0.82
## Centre of the capsule above the actor origin (the feet).
@export_range(0.0, 3.0, 0.001) var capsule_offset: float = 0.41

@export_group("Hurtbox")
@export_range(0.05, 1.0, 0.001) var hurtbox_radius: float = 0.19
@export_range(0.1, 3.0, 0.001) var hurtbox_height: float = 0.80
## Centre of the hurtbox above the actor origin (the feet).
@export_range(0.0, 3.0, 0.001) var hurtbox_offset: float = 0.40

@export_group("Visual")
## Uniform scale for the Visual node only. The actor root stays at 1.0.
@export_range(0.05, 2.0, 0.00001) var visual_scale: float = 0.32244

@export_group("Camera")
## Camera pivot height above the feet. The current rig sits slightly above the
## collision capsule (0.95 m vs 0.82 m) because it frames the head; validate()
## therefore uses a sane envelope rather than a strict inside-capsule test.
@export_range(0.1, 3.0, 0.001) var camera_pivot_height: float = 0.95
@export_range(0.5, 6.0, 0.01) var camera_spring_length: float = 2.3
@export_range(0.0, 2.0, 0.001) var camera_shoulder_offset: float = 0.35
@export_range(0.0, 1.0, 0.001) var camera_spring_margin: float = 0.08
@export_range(0.005, 0.5, 0.001) var camera_probe_radius: float = 0.05

@export_group("Aim")
## Canonical server muzzle height above the feet. The client visual hand muzzle
## stays on the animated hand; the server owns this fixed body-space origin.
@export_range(0.0, 3.0, 0.001) var eye_height: float = 0.62
## Canonical server muzzle offset in body space (x right, y up, z back).
@export var muzzle_offset: Vector3 = Vector3(0.14, 0.0, -0.30)

@export_group("Death marker")
@export_range(0.0, 2.0, 0.001) var death_disc_radius: float = 0.38
@export_range(0.0, 2.0, 0.001) var death_shell_radius: float = 0.24
@export_range(0.0, 3.0, 0.001) var death_shell_height: float = 0.80
@export_range(0.0, 3.0, 0.001) var death_shell_offset: float = 0.40


## Returns a list of human-readable problems; empty means valid.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if class_id < 0 or class_id >= NetProtocol.CLASS_COUNT:
		errors.append("class_id %d outside 0..%d" % [class_id, NetProtocol.CLASS_COUNT - 1])
	if not _positive(capsule_radius):
		errors.append("capsule_radius must be > 0")
	if not _positive(capsule_height):
		errors.append("capsule_height must be > 0")
	if not _positive(hurtbox_radius):
		errors.append("hurtbox_radius must be > 0")
	if not _positive(hurtbox_height):
		errors.append("hurtbox_height must be > 0")
	if not _positive(visual_scale):
		errors.append("visual_scale must be > 0")
	if not _positive(camera_pivot_height):
		errors.append("camera_pivot_height must be > 0")
	if not _positive(camera_spring_length):
		errors.append("camera_spring_length must be > 0")
	if camera_shoulder_offset < 0.0:
		errors.append("camera_shoulder_offset must be >= 0")
	if not _positive(camera_spring_margin):
		errors.append("camera_spring_margin must be > 0")
	if not _positive(camera_probe_radius):
		errors.append("camera_probe_radius must be > 0")
	if camera_probe_radius >= camera_spring_margin:
		errors.append("camera_probe_radius must be smaller than camera_spring_margin")
	if not _positive(eye_height):
		errors.append("eye_height must be > 0")
	if not _positive(death_disc_radius) or not _positive(death_shell_radius):
		errors.append("death marker radii must be > 0")
	if not _positive(death_shell_height):
		errors.append("death_shell_height must be > 0")

	if capsule_height < capsule_radius * 2.0:
		errors.append("capsule_height must be >= 2 * capsule_radius")
	if hurtbox_height < hurtbox_radius * 2.0:
		errors.append("hurtbox_height must be >= 2 * hurtbox_radius")

	var capsule_bottom := capsule_offset - capsule_height * 0.5
	var capsule_top := capsule_offset + capsule_height * 0.5
	var hurtbox_bottom := hurtbox_offset - hurtbox_height * 0.5
	var hurtbox_top := hurtbox_offset + hurtbox_height * 0.5
	if capsule_bottom < -0.001:
		errors.append("capsule extends below the feet")
	if hurtbox_bottom < capsule_bottom - 0.001:
		errors.append("hurtbox extends below the capsule")
	if hurtbox_top > capsule_top + 0.001:
		errors.append("hurtbox extends above the capsule")
	if hurtbox_radius > capsule_radius + 0.001:
		errors.append("hurtbox_radius must be <= capsule_radius")

	# The camera pivot is allowed to sit above the collision capsule (today it is
	# 0.13 m above it), but not arbitrarily far away from the body.
	if camera_pivot_height > capsule_top + 0.25:
		errors.append("camera_pivot_height is too far above the body")
	if eye_height > capsule_top + 0.25:
		errors.append("eye_height is too far above the body")
	if muzzle_offset.length() > 2.0:
		errors.append("muzzle_offset is unreasonably long")
	return errors


## Applies the profile to a player actor. Safe for LOCAL, REMOTE and SERVER:
## the server path never reads Visual or the camera; it only needs the collision
## capsule, the hurtbox and the exposed body_stats property on the actor.
func apply_to_actor(actor: Node, role: int = Role.LOCAL) -> bool:
	if actor == null:
		push_error("CharacterBodyStats.apply_to_actor: actor is null")
		return false
	var errors := validate()
	if not errors.is_empty():
		push_error("CharacterBodyStats[%d] invalid: %s" % [class_id, ", ".join(errors)])
		return false
	if actor is Node3D and not (actor as Node3D).scale.is_equal_approx(Vector3.ONE):
		push_error("CharacterBodyStats.apply_to_actor: actor root scale must be Vector3.ONE")
		return false

	var capsule_node := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if capsule_node == null:
		push_error("CharacterBodyStats.apply_to_actor: missing CollisionShape3D")
		return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = capsule_radius
	capsule.height = capsule_height
	capsule_node.shape = capsule
	capsule_node.position = Vector3(0.0, capsule_offset, 0.0)
	capsule_node.scale = Vector3.ONE

	var hurtbox_shape_node := actor.get_node_or_null("BodyHurtbox/CollisionShape3D") as CollisionShape3D
	if hurtbox_shape_node == null:
		push_error("CharacterBodyStats.apply_to_actor: missing BodyHurtbox/CollisionShape3D")
		return false
	var hurtbox := CapsuleShape3D.new()
	hurtbox.radius = hurtbox_radius
	hurtbox.height = hurtbox_height
	hurtbox_shape_node.shape = hurtbox
	hurtbox_shape_node.position = Vector3(0.0, hurtbox_offset, 0.0)
	hurtbox_shape_node.scale = Vector3.ONE

	if role == Role.SERVER:
		return true

	var visual := actor.get_node_or_null("Visual") as Node3D
	if visual:
		visual.scale = Vector3.ONE * visual_scale
	var rig := actor.get_node_or_null("CameraPivot")
	if rig and rig.has_method("apply_body_stats"):
		rig.apply_body_stats(self)
	return true


## Canonical authoritative muzzle: fixed body-space eye + shoulder offset. The
## client's visible hand muzzle is intentionally different and stays visual-only.
func canonical_muzzle(actor_position: Vector3, yaw: float, pitch: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return actor_position + Vector3(0.0, eye_height, 0.0) + basis * muzzle_offset


## Camera position used for the server's aim ray. It mirrors the client camera
## at rest; spring-arm compression against walls remains a documented gap.
func camera_origin(actor_position: Vector3, yaw: float, pitch: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return (
		actor_position
		+ Vector3(0.0, camera_pivot_height, 0.0)
		+ basis * Vector3(camera_shoulder_offset, 0.0, camera_spring_length)
	)


func _positive(value: float) -> bool:
	# NaN compares false; inf fails the upper bound.
	return value > 0.0 and value < 100.0
