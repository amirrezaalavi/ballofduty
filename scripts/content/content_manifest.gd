class_name ContentManifest
extends Resource
## The single entry point for bundled artifacts. It lists pack paths instead of
## preloading them so maps can stay lazy; the catalog loads and validates every
## pack before the first match.

@export var game_version: String = "0.1.0"
## res:// paths to ContentPack resources. Order is the pack load order.
@export var pack_paths: Array[String] = []
