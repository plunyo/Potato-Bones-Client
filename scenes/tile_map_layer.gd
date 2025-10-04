extends TileMapLayer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func export() -> void:
	tile_set.get_ph

	var data_string: String
	var json_file: FileAccess = FileAccess.open("res://please.json", FileAccess.ModeFlags.WRITE)
	if json_file:
		json_file.store_string(data_string)
