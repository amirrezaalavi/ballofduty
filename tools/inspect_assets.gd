extends SceneTree
## Dev helper: print GLB bounds/surface counts so collision shapes and scatter
## scales are based on data, not guesses.


func _init() -> void:
	var dir := DirAccess.open("res://assets/kenney_nature/models")
	if dir == null:
		push_error("models folder missing")
		quit(1)
		return
	var files := dir.get_files()
	files.sort()
	for file: String in files:
		if not file.ends_with(".glb"):
			continue
		var packed := load("res://assets/kenney_nature/models/" + file) as PackedScene
		if packed == null:
			print("%s: FAILED TO LOAD" % file)
			continue
		var instance := packed.instantiate()
		var bounds := AABB()
		var surfaces := 0
		var found := _collect(instance, bounds, surfaces)
		bounds = found[0]
		surfaces = found[1]
		print("%-26s size=(%.2f, %.2f, %.2f) y=[%.2f..%.2f] surfaces=%d" % [
			file.get_basename(), bounds.size.x, bounds.size.y, bounds.size.z,
			bounds.position.y, bounds.position.y + bounds.size.y, surfaces,
		])
		instance.free()
	quit(0)


func _collect(node: Node, bounds: AABB, surfaces: int) -> Array:
	var accumulated := bounds
	var surface_count := surfaces
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			surface_count += mesh_instance.mesh.get_surface_count()
			var box := mesh_instance.transform * mesh_instance.mesh.get_aabb()
			accumulated = box if accumulated.size == Vector3.ZERO else accumulated.merge(box)
	for child in node.get_children():
		var result := _collect(child, accumulated, surface_count)
		accumulated = result[0]
		surface_count = result[1]
	return [accumulated, surface_count]
