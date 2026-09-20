class_name TestHexTopology
extends GdUnitTestSuite
## Adaptador hex: salida es un HexGrid REAL del fixture del anfitrión, paridad
## bit a bit con la referencia congelada de su generador (terreno + elevación)
## y compatibilidad con el stack (PathFinder smoke). Requiere el fixture
## vendorizado en addons/hex_strategy_map/.


func test_host_disponible_en_repo_de_desarrollo() -> void:
	assert_bool(HexTopology.is_host_available()).is_true()


func test_generate_hex_retorna_hexgrid_real() -> void:
	var result = HexTopology.generate_hex(12, 9, {"seed": 42, "stages": [TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY]})
	assert_object(result).is_not_null()
	assert_bool(result is HexGrid).is_true()
	assert_int(result.get_all_cells().size()).is_equal(108)


func test_generate_hex_paridad_bit_a_bit_con_map_generator() -> void:
	## Contrato de adopción end-to-end: el pipeline terrain del forge sobre el
	## adaptador produce EXACTAMENTE el terreno y la elevación del generador
	## del anfitrión para el mismo seed (escritura vía set_terrain incluida).
	## Seeds negativos incluidos: el anfitrión los acepta y el forge también.
	## La referencia es la transcripción congelada del algoritmo PRO (ver
	## test/helpers/host_terrain_reference.gd) — MapGenerator no viaja en repo.
	var terrain_stages: Array = [TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY]
	for seed_value in [0, 42, 999, -7]:
		var forged: HexGrid = HexTopology.generate_hex(14, 10, {"seed": seed_value, "stages": terrain_stages})
		var reference: HexGrid = HostTerrainReference.generate(14, 10, seed_value)
		for coord in reference.get_all_cells():
			assert_int(forged.get_cell(coord).terrain).is_equal(reference.get_cell(coord).terrain)
			assert_float(forged.get_cell(coord).elevation).is_equal(reference.get_cell(coord).elevation)


func test_regeneracion_con_mismo_seed_es_idempotente() -> void:
	## Semántica de regeneración: apply() con los mismos params sobre el grid
	## ya generado produce EXACTAMENTE el mismo estado final que un generate
	## fresco (locations y ríos previos se limpian, no se acumulan).
	var params := {"seed": 42, "river_count": 3, "location_count": 5, "smoothing_passes": 1}
	var grid: HexGrid = HexTopology.generate_hex(15, 12, params)
	HexTopology.apply(grid, params)
	var fresh: HexGrid = HexTopology.generate_hex(15, 12, params)
	for coord in fresh.get_all_cells():
		assert_int(grid.get_cell(coord).terrain).is_equal(fresh.get_cell(coord).terrain)
		assert_bool(grid.get_cell(coord).has_location()).is_equal(fresh.get_cell(coord).has_location())
	assert_int(grid.edges.size()).is_equal(fresh.edges.size())
	for key in fresh.edges:
		assert_bool(grid.edges.has(key)).is_true()


func test_regeneracion_con_otro_seed_no_deja_rios_huerfanos() -> void:
	var grid: HexGrid = HexTopology.generate_hex(15, 12, {"seed": 1, "river_count": 3})
	HexTopology.apply(grid, {"seed": 99, "river_count": 3})
	var fresh_seed_99: HexGrid = HexTopology.generate_hex(15, 12, {"seed": 99, "river_count": 3})
	assert_int(grid.edges.size()).is_equal(fresh_seed_99.edges.size())
	for key in fresh_seed_99.edges:
		assert_bool(grid.edges.has(key)).is_true()


func test_generate_hex_determinista_pipeline_completo() -> void:
	var params := {"seed": 42, "river_count": 3, "location_count": 4, "smoothing_passes": 1}
	var a: HexGrid = HexTopology.generate_hex(15, 12, params)
	var b: HexGrid = HexTopology.generate_hex(15, 12, params)
	for coord in a.get_all_cells():
		assert_int(b.get_cell(coord).terrain).is_equal(a.get_cell(coord).terrain)
	assert_int(b.edges.size()).is_equal(a.edges.size())
	for key in a.edges:
		assert_bool(b.edges.has(key)).is_true()


func test_generate_hex_rios_y_locations_sobre_hexgrid() -> void:
	var grid: HexGrid = HexTopology.generate_hex(18, 14, {"seed": 7, "river_count": 3, "location_count": 5})
	assert_int(grid.edges.size()).is_greater(0)
	var locations := 0
	for coord in grid.get_all_cells():
		if grid.get_cell(coord).has_location():
			locations += 1
	assert_int(locations).is_equal(5)


func test_pathfinder_encuentra_camino_sobre_salida_del_forge() -> void:
	## La salida alimenta el stack del anfitrión sin adaptación: PathFinder
	## (que hardcodea topología hex) opera sobre el grid generado. El destino
	## se toma de la región alcanzable del origen (mapas con islas pueden no
	## tener camino entre celdas arbitrarias).
	var grid: HexGrid = HexTopology.generate_hex(20, 16, {"seed": 21})
	var origin: Vector2i
	for coord in grid.get_all_cells():
		if grid.is_passable(coord):
			origin = coord
			break
	var reachable := PathFinder.find_reachable(origin, 12.0, grid)
	assert_bool(reachable.size() > 2).is_true()
	var destination: Vector2i
	for coord in reachable:
		destination = coord
	var path := PathFinder.find_path(origin, destination, grid)
	assert_bool(path.size() >= 2).is_true()


func test_line_hex_es_continua_y_termina_en_destino() -> void:
	var topology := HexTopology.new(HexGrid.new(10, 10))
	topology.grid.generate_cells()
	var path := topology.line(Vector2i(0, 0), Vector2i(6, 5))
	assert_bool(path[0] == Vector2i(0, 0)).is_true()
	for i in path.size() - 1:
		assert_int(topology.distance(path[i], path[i + 1])).is_equal(1)
	assert_bool(path[path.size() - 1] == Vector2i(6, 5)).is_true()


func test_distance_y_vecinos_coinciden_con_el_anfitrion() -> void:
	var topology := HexTopology.new(HexGrid.new(8, 8))
	topology.grid.generate_cells()
	var coord := Vector2i(3, 3)
	assert_int(topology.distance(coord, Vector2i(0, 0))).is_equal(HexGrid.distance(coord, Vector2i(0, 0)))
	var neighbors := topology.get_neighbors(coord)
	assert_int(neighbors.size()).is_equal(6)
	for neighbor in neighbors:
		assert_int(HexGrid.distance(coord, neighbor)).is_equal(1)


func test_apply_regenera_terreno_sobre_grid_existente() -> void:
	var grid: HexGrid = HexTopology.generate_hex(10, 8, {"seed": 1, "stages": [TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY]})
	var expected: HexGrid = HexTopology.generate_hex(10, 8, {"seed": 99, "stages": [TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY]})
	HexTopology.apply(grid, {"seed": 99, "stages": [TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY]})
	for coord in grid.get_all_cells():
		assert_int(grid.get_cell(coord).terrain).is_equal(expected.get_cell(coord).terrain)
