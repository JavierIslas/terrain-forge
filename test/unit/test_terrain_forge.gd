class_name TestTerrainForge
extends GdUnitTestSuite
## Motor: pipeline de stages, determinismo punta a punta, presets y falloff.


func _make_topology(map_w: int = 8, map_h: int = 6) -> SquareTopology:
	var grid := SquareGrid.new(map_w, map_h)
	grid.generate_cells()
	return SquareTopology.new(grid)


func test_generate_llena_terreno_y_elevacion() -> void:
	var topo := _make_topology()
	TerrainForge.generate(topo, {"seed": 42})
	var valid_terrains: Array = [
		MapCell.Terrain.ROAD, MapCell.Terrain.PLAINS, MapCell.Terrain.FOREST,
		MapCell.Terrain.MOUNTAIN, MapCell.Terrain.WATER,
	]
	var has_elevation := false
	for coord in topo.get_all_coords():
		assert_bool(topo.get_terrain(coord) in valid_terrains).is_true()
		if absf(topo.get_elevation(coord)) > 0.001:
			has_elevation = true
	assert_bool(has_elevation).is_true()


func test_generate_es_determinista_con_mismo_seed() -> void:
	var topo_a := _make_topology()
	var topo_b := _make_topology()
	TerrainForge.generate(topo_a, {"seed": 42, "smoothing_passes": 1})
	TerrainForge.generate(topo_b, {"seed": 42, "smoothing_passes": 1})
	for coord in topo_a.get_all_coords():
		assert_int(topo_b.get_terrain(coord)).is_equal(topo_a.get_terrain(coord))
		assert_float(topo_b.get_elevation(coord)).is_equal(topo_a.get_elevation(coord))


func test_generate_difiere_por_seed() -> void:
	var topo_a := _make_topology(10, 8)
	var topo_b := _make_topology(10, 8)
	TerrainForge.generate(topo_a, {"seed": 1})
	TerrainForge.generate(topo_b, {"seed": 999})
	var differs := false
	for coord in topo_a.get_all_coords():
		if topo_a.get_terrain(coord) != topo_b.get_terrain(coord):
			differs = true
			break
	assert_bool(differs).is_true()


func test_seed_negativo_es_determinista_y_difiere_de_cero() -> void:
	## Los seeds negativos son válidos (paridad con el anfitrión, que los
	## acepta): mismo seed → mismo mapa; distinto seed → mapa distinto.
	var topo_a := _make_topology()
	var topo_b := _make_topology()
	var topo_zero := _make_topology()
	TerrainForge.generate(topo_a, {"seed": -7})
	TerrainForge.generate(topo_b, {"seed": -7})
	TerrainForge.generate(topo_zero, {"seed": 0})
	var differs_from_zero := false
	for coord in topo_a.get_all_coords():
		assert_int(topo_b.get_terrain(coord)).is_equal(topo_a.get_terrain(coord))
		if topo_a.get_terrain(coord) != topo_zero.get_terrain(coord):
			differs_from_zero = true
	assert_bool(differs_from_zero).is_true()


func test_report_registra_seed_y_stages_corridos() -> void:
	var topo := _make_topology()
	var report := TerrainForge.generate_with_report(topo, {"seed": 5, "stages": [TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY]})
	assert_int(report.seed).is_equal(5)
	assert_array(report.stages_run).is_equal([TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY])


func test_stage_custom_callable_se_ejecuta() -> void:
	var topo := _make_topology(4, 4)
	var custom := func(topology: GridTopology, ctx: Dictionary) -> void:
		topology.set_terrain(Vector2i(0, 0), MapCell.Terrain.WATER)
		ctx.report.custom_marker = ctx.width
	TerrainForge.generate(topo, {"seed": 1, "stages": [TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY, custom]})
	assert_int(topo.get_terrain(Vector2i(0, 0))).is_equal(MapCell.Terrain.WATER)
	assert_int(topo.get_dimensions().x).is_equal(4)


func test_stages_default_generan_mapa_usable() -> void:
	var topo := _make_topology(12, 9)
	var report := TerrainForge.generate_with_report(topo, {"seed": 42})
	assert_array(report.stages_run).is_equal(TerrainForge.STAGES_DEFAULT)
	assert_int(topo.cell_count()).is_equal(108)


func test_falloff_puro_centro_intacto_y_esquina_resta_strength() -> void:
	var heights := PackedFloat32Array()
	heights.resize(9)
	heights.fill(0.5)
	var result := TerrainForge.apply_falloff(heights, 3, 3, 1.0, 2.0)
	assert_float(result[4]).is_equal(0.5)
	assert_float(result[0]).is_equal(-0.5)
	assert_float(result[8]).is_equal(-0.5)


func test_falloff_como_stage_empuja_bordes_a_agua() -> void:
	var topo_plain := _make_topology(10, 10)
	var topo_falloff := _make_topology(10, 10)
	TerrainForge.generate(topo_plain, {"seed": 42})
	TerrainForge.generate(topo_falloff, {"seed": 42, "island_falloff": 1.0})
	var corners := [Vector2i(0, 0), Vector2i(9, 0), Vector2i(0, 9), Vector2i(9, 9)]
	var gained_water := 0
	for corner in corners:
		if topo_falloff.get_terrain(corner) == MapCell.Terrain.WATER and topo_plain.get_terrain(corner) != MapCell.Terrain.WATER:
			gained_water += 1
	assert_int(gained_water).is_greater_equal(2)


func test_moisture_habilita_clasificacion_por_biomas() -> void:
	var profile_fn := func(_value: float, moisture: float) -> int:
		return MapCell.Terrain.FOREST if moisture > 0.1 else MapCell.Terrain.PLAINS
	## Sin stage de moisture: classify_fn recibe moisture 0.0 → todo PLAINS.
	var topo_dry := _make_topology(12, 9)
	TerrainForge.generate(topo_dry, {"seed": 42, "classify_fn": profile_fn, "stages": [TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY]})
	var forest_without := _count_terrain(topo_dry, MapCell.Terrain.FOREST)

	## Con stage de moisture (default stages lo incluyen al ver classify_fn).
	var topo_wet := _make_topology(12, 9)
	TerrainForge.generate(topo_wet, {"seed": 42, "classify_fn": profile_fn, "moisture_frequency": 0.05})
	var forest_with := _count_terrain(topo_wet, MapCell.Terrain.FOREST)

	assert_int(forest_without).is_equal(0)
	assert_int(forest_with).is_greater(0)


func test_presets_retornan_params_validos() -> void:
	for preset_name in ["pangaea", "archipelago", "highlands"]:
		var preset_params: Dictionary = TerrainForge.preset(preset_name)
		assert_bool(preset_params.is_empty()).is_false()
		var topo := _make_topology(8, 8)
		var merged: Dictionary = preset_params.duplicate()
		merged.seed = 7
		TerrainForge.generate(topo, merged)


func test_pipeline_completo_genera_rios_y_locations() -> void:
	var topo := _make_topology(20, 15)
	var report := TerrainForge.generate_with_report(topo, {
		"seed": 42,
		"river_count": 3,
		"location_count": 4,
		"location_spacing": 2,
	})
	assert_bool(report.stages_run.has(TerrainForge.STAGE_RIVERS)).is_true()
	assert_bool(report.stages_run.has(TerrainForge.STAGE_LOCATIONS)).is_true()
	assert_int(report.river_paths.size()).is_equal(3)
	assert_int(report.locations.size()).is_equal(4)
	assert_int(topo.edge_count()).is_greater_equal(3)
	for coord in report.locations:
		assert_bool(topo.has_location(coord)).is_true()


func test_pipeline_completo_ignora_el_rng_global() -> void:
	## Regresión de punta a punta: el pipeline entero (ríos + locations
	## incluidos) no puede avanzar el RNG global de Godot.
	seed(111222333)
	var expected_first := randi()
	var expected_second := randi()
	seed(111222333)
	var topo := _make_topology(20, 15)
	TerrainForge.generate(topo, {"seed": 42, "river_count": 3, "location_count": 5, "smoothing_passes": 1})
	assert_int(randi()).is_equal(expected_first)
	assert_int(randi()).is_equal(expected_second)


func test_stage_conectividad_reporta_por_defecto_y_repara_bajo_pedido() -> void:
	var topo_report := _make_topology(20, 15)
	var report := TerrainForge.generate_with_report(topo_report, {"seed": 3})
	assert_bool(report.connectivity.has("is_connected")).is_true()
	assert_bool(report.connectivity.has("repaired")).is_false()

	var topo_repair := _make_topology(20, 15)
	var repair_report := TerrainForge.generate_with_report(topo_repair, {"seed": 3, "connectivity_mode": "repair"})
	assert_bool(repair_report.connectivity.has("repaired")).is_true()
	assert_int(repair_report.connectivity.repaired).is_greater_equal(0)
	assert_bool(repair_report.connectivity.is_connected).is_true()


func test_stages_con_buffer_sin_elevation_reportan_error() -> void:
	var topo := _make_topology(5, 5)
	TerrainForge.generate(topo, {"seed": 1, "stages": [TerrainForge.STAGE_CLASSIFY]})
	for coord in topo.get_all_coords():
		assert_int(topo.get_terrain(coord)).is_equal(MapCell.Terrain.PLAINS)


func test_topologia_sin_celdas_reporta_error_sin_snapshot() -> void:
	var grid := SquareGrid.new(20, 15)
	var report := TerrainForge.generate_with_report(SquareTopology.new(grid), {"seed": 42})
	assert_bool(report.has("snapshot")).is_false()


func test_topologia_no_rectangular_completa_el_pipeline() -> void:
	## El puerto promete "cualquier topología": una triangular (x <= y) debe
	## pasar el pipeline completo y producir snapshot sin index out of range.
	var topo := TriangleTopology.new(10, 10)
	var report := TerrainForge.generate_with_report(topo, {"seed": 42})
	assert_int(topo.cell_count()).is_equal(55)
	assert_int(report.snapshot.terrain_classes.size()).is_equal(55)
	assert_int(report.stats.cell_count).is_equal(55)


## Topología de prueba: triángulo superior (celdas donde x <= y), 4 vecinos
## cardinales, para ejercitar el contrato no-rectangular del puerto.
class TriangleTopology extends GridTopology:
	var cells := {}
	var width := 0
	var height := 0

	func _init(map_w: int, map_h: int) -> void:
		width = map_w
		height = map_h
		for y in map_h:
			for x in map_w:
				if x <= y:
					cells[Vector2i(x, y)] = {"terrain": 1, "elevation": 0.0, "location": 0}

	func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
		return [
			Vector2i(coord.x - 1, coord.y), Vector2i(coord.x + 1, coord.y),
			Vector2i(coord.x, coord.y - 1), Vector2i(coord.x, coord.y + 1),
		]

	func is_valid(coord: Vector2i) -> bool:
		return cells.has(coord)

	func distance(a: Vector2i, b: Vector2i) -> int:
		return absi(b.x - a.x) + absi(b.y - a.y)

	func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
		var path: Array[Vector2i] = [a]
		var current := a
		while current != b:
			var dx := b.x - current.x
			var dy := b.y - current.y
			if absi(dx) >= absi(dy):
				current = Vector2i(current.x + signi(dx), current.y)
			else:
				current = Vector2i(current.x, current.y + signi(dy))
			path.append(current)
		return path

	func get_all_coords() -> Array[Vector2i]:
		var coords: Array[Vector2i] = []
		coords.assign(cells.keys())
		coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y or (a.y == b.y and a.x < b.x))
		return coords

	func get_dimensions() -> Vector2i:
		return Vector2i(width, height)

	func cell_count() -> int:
		return cells.size()

	func get_terrain(coord: Vector2i) -> int:
		return cells[coord].terrain if is_valid(coord) else -1

	func set_terrain(coord: Vector2i, terrain: int) -> void:
		if is_valid(coord):
			cells[coord].terrain = terrain

	func get_elevation(coord: Vector2i) -> float:
		return cells[coord].elevation if is_valid(coord) else 0.0

	func set_elevation(coord: Vector2i, elevation: float) -> void:
		if is_valid(coord):
			cells[coord].elevation = elevation

	func set_location(coord: Vector2i, location_type: int) -> void:
		if is_valid(coord):
			cells[coord].location = location_type

	func has_location(coord: Vector2i) -> bool:
		return cells[coord].location > 0 if is_valid(coord) else false

	func set_edge(a: Vector2i, b: Vector2i, edge_type: int) -> void:
		if is_valid(a) and is_valid(b):
			_edges["%d,%d" % [a.x, a.y]] = edge_type

	func edge_count() -> int:
		return _edges.size()

	func clear_edges(_edge_type: int) -> int:
		var removed := _edges.size()
		_edges.clear()
		return removed

	var _edges := {}


func _count_terrain(topo: GridTopology, terrain: int) -> int:
	var count := 0
	for coord in topo.get_all_coords():
		if topo.get_terrain(coord) == terrain:
			count += 1
	return count
