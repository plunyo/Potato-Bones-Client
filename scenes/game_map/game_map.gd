extends TileMapLayer
class_name GameMap

func _ready() -> void:
	generate_pbtiles("res://test.pbtiles")

func generate_pbtiles(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	var collision_data: Dictionary[Vector2i, PackedVector2Array] = {}

	for cell_position: Vector2i in get_used_cells():
		var atlas_coords := get_cell_atlas_coords(cell_position)

		if collision_data.has(atlas_coords):
			continue

		var tile_data := get_cell_tile_data(cell_position)
		if tile_data and tile_data.get_collision_polygons_count(0) > 0:
			collision_data[atlas_coords] = tile_data.get_collision_polygon_points(0, 0)

	file.store_string(str(collision_data))
	file.close()
