
extends TileMapLayer
class_name GameMap

func _ready() -> void:
	generate_pbmap("res://test.pbmap")

func _atlas_coords_to_id(coords: Vector2i) -> int:
	return (coords.x << 16) | (coords.y & 0xFFFF)

func generate_pbtiles(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	
	var collision_data: Dictionary = {}
	var tile_size: Vector2 = tile_set.tile_size
	var inv_tile_size := Vector2(
		1.0 / tile_size.x,
		1.0 / tile_size.y
	)
	var half_tile := tile_size * 0.5
	
	# collect unique atlas collisions once
	for cell_position: Vector2i in get_used_cells():
		var atlas_coords: Vector2i = get_cell_atlas_coords(cell_position)
		if collision_data.has(atlas_coords):
			continue
		
		var tile_data := get_cell_tile_data(cell_position)
		if tile_data == null:
			continue

		# skip tiles with no collision
		if tile_data.get_collision_polygons_count(0) <= 0:
			continue

		if tile_data.get_collision_polygons_count(0) > 0:
			collision_data[atlas_coords] = tile_data.get_collision_polygon_points(0, 0)

	var output := PackedStringArray()
	
	for atlas_coords in collision_data.keys():
		output.append(str(_atlas_coords_to_id(atlas_coords)) + ":")
		
		var points: PackedVector2Array = collision_data[atlas_coords]

		for point in points:
			var normalized_x := (point.x + half_tile.x) * inv_tile_size.x
			var normalized_y := (point.y + half_tile.y) * inv_tile_size.y
			output.append(str(round(normalized_x * 100.0) / 100.0) + "," + str(round(normalized_y * 100.0) / 100.0) + ";")

		output.append("")
	
	file.store_string("\n".join(output))
	file.close()

func generate_pbmap(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return

	# 1) discover which atlas tiles actually have collision in the tileset
	var collision_id_set := {}
	for cell_position: Vector2i in get_used_cells():
		var tile_data := get_cell_tile_data(cell_position)
		if tile_data == null:
			continue

		# check for any collision polygons (only include atlas tile if it truly has collision)
		if tile_data.get_collision_polygons_count(0) > 0:
			var atlas_coords: Vector2i = get_cell_atlas_coords(cell_position)
			collision_id_set[_atlas_coords_to_id(atlas_coords)] = true

	# if none have collision, bail early
	if collision_id_set.is_empty():
		file.close()
		return

	# 2) group only collision tiles by atlas id
	var tiles: Dictionary = {} # id -> Array[Vector2i]
	for cell_position: Vector2i in get_used_cells():
		var atlas_coords: Vector2i = get_cell_atlas_coords(cell_position)
		var id := _atlas_coords_to_id(atlas_coords)

		# skip any atlas tile that we discovered has no collision
		if not collision_id_set.has(id):
			continue

		# now safe to append
		if not tiles.has(id):
			tiles[id] = []
		tiles[id].append(cell_position)

	# 3) export same greedy rectangles as before
	var output := PackedStringArray()
	output.append("test.pbtiles")
	output.append("")

	for id in tiles.keys():
		output.append(str(id) + ":")

		var cells: Array = tiles[id]
		var cell_set := {}
		for c in cells:
			cell_set[c] = true

		var visited := {}

		for cell in cells:
			if visited.has(cell):
				continue

			var width := 1
			while cell_set.has(cell + Vector2i(width, 0)) and not visited.has(cell + Vector2i(width, 0)):
				width += 1

			var height := 1
			var can_expand := true
			while can_expand:
				for x in range(width):
					var check: Vector2i = cell + Vector2i(x, height)
					if not cell_set.has(check) or visited.has(check):
						can_expand = false
						break
				if can_expand:
					height += 1

			for y in range(height):
				for x in range(width):
					visited[cell + Vector2i(x, y)] = true

			if width == 1 and height == 1:
				output.append(str(cell.x) + "," + str(cell.y) + ";")
			else:
				output.append(
					str(cell.x) + "," +
					str(cell.y) + "," +
					str(width ) + "," +
					str(height) + ";"
				)

		output.append("")

	file.store_string("\n".join(output))
	file.close()
