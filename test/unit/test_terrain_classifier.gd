class_name TestTerrainClassifier
extends GdUnitTestSuite
## Clasificación: escalera de 5 bandas, paridad bit a bit con la referencia
## congelada del generador del anfitrión, classify_fn inyectable y smoothing.


func _make_topology(map_w: int = 5, map_h: int = 5) -> SquareTopology:
	var grid := SquareGrid.new(map_w, map_h)
	grid.generate_cells()
	return SquareTopology.new(grid)


func test_escalera_de_cinco_bandas() -> void:
	var profile := BiomeProfile.create_ladder()
	assert_int(TerrainClassifier.classify_value(-0.5, profile)).is_equal(MapCell.Terrain.WATER)
	assert_int(TerrainClassifier.classify_value(-0.25, profile)).is_equal(MapCell.Terrain.WATER)
	assert_int(TerrainClassifier.classify_value(-0.1, profile)).is_equal(MapCell.Terrain.PLAINS)
	assert_int(TerrainClassifier.classify_value(0.05, profile)).is_equal(MapCell.Terrain.ROAD)
	assert_int(TerrainClassifier.classify_value(0.2, profile)).is_equal(MapCell.Terrain.FOREST)
	assert_int(TerrainClassifier.classify_value(0.5, profile)).is_equal(MapCell.Terrain.MOUNTAIN)


func test_paridad_bit_a_bit_con_el_generador_del_anfitrion() -> void:
	## El contrato de adopción: mismo seed → mismo terreno Y misma elevación,
	## celda por celda, en N seeds distintos. Incluye la banda ROAD (> 0.0).
	## Compara contra HostTerrainReference (transcripción congelada del
	## algoritmo PRO del anfitrión, que no puede vendorizarse acá).
	for seed_value in [0, 42, 999]:
		var grid = HostTerrainReference.generate(12, 9, seed_value)
		var heights := NoiseField.create(seed_value).sample_map(12, 9)
		var classes := TerrainClassifier.classify_buffer(heights, BiomeProfile.create_ladder())
		for coord in grid.cells:
			var cell = grid.cells[coord]
			var index: int = coord.y * 12 + coord.x
			assert_int(classes[index]).is_equal(cell.terrain)
			assert_float(heights[index] * 10.0).is_equal(cell.elevation)


func test_classify_fn_inyectable_reemplaza_la_escalera() -> void:
	var profile := BiomeProfile.create_ladder()
	profile.classify_fn = func(value: float, moisture: float) -> int:
		return MapCell.Terrain.MOUNTAIN if value > 0.0 else MapCell.Terrain.WATER
	assert_int(TerrainClassifier.classify_value(0.5, profile)).is_equal(MapCell.Terrain.MOUNTAIN)
	assert_int(TerrainClassifier.classify_value(-0.5, profile)).is_equal(MapCell.Terrain.WATER)
	assert_int(TerrainClassifier.classify_value(0.05, profile)).is_equal(MapCell.Terrain.MOUNTAIN)


func test_classify_fn_recibe_moisture_del_buffer() -> void:
	var profile := BiomeProfile.create_ladder()
	profile.classify_fn = func(_value: float, moisture: float) -> int:
		return MapCell.Terrain.FOREST if moisture > 0.2 else MapCell.Terrain.PLAINS
	var heights := PackedFloat32Array([0.05, 0.05, 0.05])
	var moisture := PackedFloat32Array([0.5, 0.0, 0.3])
	var classes := TerrainClassifier.classify_buffer(heights, profile, moisture)
	assert_int(classes[0]).is_equal(MapCell.Terrain.FOREST)
	assert_int(classes[1]).is_equal(MapCell.Terrain.PLAINS)
	assert_int(classes[2]).is_equal(MapCell.Terrain.FOREST)


func test_from_params_respeta_biome_y_overrides() -> void:
	var profile := BiomeProfile.from_params({"biome": "archipelago", "water_level": -0.05})
	assert_float(profile.water_level).is_equal(-0.05)
	assert_float(profile.mountain_level).is_equal(BiomeProfile.create_archipelago().mountain_level)
	var ladder := BiomeProfile.from_params({})
	assert_float(ladder.water_level).is_equal(-0.2)


func test_presets_de_perfil_difieren() -> void:
	var presets := [
		BiomeProfile.create_ladder(),
		BiomeProfile.create_continent(),
		BiomeProfile.create_archipelago(),
		BiomeProfile.create_highlands(),
	]
	for i in presets.size() - 1:
		assert_float(presets[i].water_level).is_not_equal(presets[i + 1].water_level)


func test_smoothing_elimina_specks_de_una_celda() -> void:
	var topo := _make_topology(5, 5)
	for coord in topo.get_all_coords():
		topo.set_terrain(coord, MapCell.Terrain.PLAINS)
	topo.set_terrain(Vector2i(2, 2), MapCell.Terrain.WATER)
	TerrainClassifier.apply_smoothing(topo, 1)
	assert_int(topo.get_terrain(Vector2i(2, 2))).is_equal(MapCell.Terrain.PLAINS)


func test_smoothing_conserva_region_grande() -> void:
	var topo := _make_topology(7, 7)
	for coord in topo.get_all_coords():
		topo.set_terrain(coord, MapCell.Terrain.PLAINS)
	for y in 7:
		topo.set_terrain(Vector2i(3, y), MapCell.Terrain.WATER)
	TerrainClassifier.apply_smoothing(topo, 1)
	for y in 7:
		assert_int(topo.get_terrain(Vector2i(3, y))).is_equal(MapCell.Terrain.WATER)


func test_smoothing_cero_pasadas_no_cambia_nada() -> void:
	var topo := _make_topology(4, 4)
	topo.set_terrain(Vector2i(0, 0), MapCell.Terrain.MOUNTAIN)
	TerrainClassifier.apply_smoothing(topo, 0)
	assert_int(topo.get_terrain(Vector2i(0, 0))).is_equal(MapCell.Terrain.MOUNTAIN)


func test_road_level_default_cero_mantiene_la_escalera() -> void:
	## El umbral de la banda ROAD era el literal 0.0; con road_level default 0.0
	## la comparación debe quedar idéntica (paridad bit a bit intacta).
	var profile := BiomeProfile.from_params({})
	assert_float(profile.road_level).is_equal(0.0)
	assert_int(TerrainClassifier.classify_value(0.05, profile)).is_equal(MapCell.Terrain.ROAD)
	assert_int(TerrainClassifier.classify_value(-0.05, profile)).is_equal(MapCell.Terrain.PLAINS)


func test_road_level_sube_el_umbral_de_banda_road() -> void:
	var profile := BiomeProfile.from_params({"road_level": 0.05})
	assert_int(TerrainClassifier.classify_value(0.03, profile)).is_equal(MapCell.Terrain.PLAINS)
	assert_int(TerrainClassifier.classify_value(0.07, profile)).is_equal(MapCell.Terrain.ROAD)


func test_from_params_lee_road_level() -> void:
	var profile := BiomeProfile.from_params({"road_level": 0.02})
	assert_float(profile.road_level).is_equal(0.02)
	var ladder := BiomeProfile.from_params({})
	assert_float(ladder.road_level).is_equal(0.0)


func test_smoothing_empate_conserva_terreno_actual() -> void:
	## Esquina con vecindario de 3 celdas y tres terrenos distintos (1-1-1):
	## empate triple → conserva el terreno actual.
	var topo := _make_topology(3, 3)
	for coord in topo.get_all_coords():
		topo.set_terrain(coord, MapCell.Terrain.PLAINS)
	topo.set_terrain(Vector2i(0, 0), MapCell.Terrain.FOREST)
	topo.set_terrain(Vector2i(1, 0), MapCell.Terrain.WATER)
	topo.set_terrain(Vector2i(0, 1), MapCell.Terrain.MOUNTAIN)
	TerrainClassifier.apply_smoothing(topo, 1)
	assert_int(topo.get_terrain(Vector2i(0, 0))).is_equal(MapCell.Terrain.FOREST)
