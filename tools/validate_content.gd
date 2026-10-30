extends SceneTree
## CI gate for external artifacts. Fails on any manifest, pack, id, path, type,
## dependency, class-coverage or budget error. Run after --import:
##   ./tools/godot --headless --path . --script tools/validate_content.gd

func _init() -> void:
	var catalog := ContentCatalog.new()
	var ok := catalog.load_manifest(ContentCatalog.DEFAULT_MANIFEST)
	print("CONTENT packs=%d entries=%d errors=%d warnings=%d" % [
		catalog.packs.size(), catalog.all_ids().size(),
		catalog.error_count(), catalog.warning_count(),
	])
	for kind: StringName in ContentCatalog.KINDS:
		for entry in catalog.entries(kind, true):
			print("CONTENT_ENTRY kind=%s id=%s wire=%d path=%s" % [
				entry.kind, entry.id, entry.wire_id, entry.path,
			])
	for message in catalog.errors:
		print("CONTENT_ERROR: %s" % message)
	for message in catalog.warnings:
		print("CONTENT_WARN: %s" % message)
	if not ok or not catalog.is_ok():
		print("CONTENT_FAIL")
		quit(1)
		return
	print("CONTENT_OK")
	quit(0)
