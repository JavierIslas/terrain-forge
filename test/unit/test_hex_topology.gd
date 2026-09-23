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


func test_repair_hex_conecta_seed_del_repro() -> void:
	## Repro congelado del corredor agujereado: pre-fix, el sweep 1..150 en
	## 15x15 con defaults dejaba 8 seeds desconectadas tras repair (12, 24,
	## 26, 42, 45, 64, 139, 140 — regiones huérfanas tipo [162, 1]) porque
	## los waypoints de line() fuera del rectángulo odd-r se saltaban sin
	## puente.
	var params := {"seed": 12, "connectivity_mode": "repair"}
	var grid: HexGrid = HexTopology.generate_hex(15, 15, params)
	var analysis := ConnectivityChecker.analyze(HexTopology.new(grid))
	assert_bool(analysis.is_connected).is_true()


func test_repair_hex_es_determinista() -> void:
	## El puente greedy (desempates por distance, x, y) debe ser función pura
	## del terreno: mismo seed + mismos params → mismos terrenos post-repair.
	var params := {"seed": 12, "connectivity_mode": "repair"}
	var a: HexGrid = HexTopology.generate_hex(15, 15, params)
	var b: HexGrid = HexTopology.generate_hex(15, 15, params)
	for coord in a.get_all_cells():
		assert_int(b.get_cell(coord).terrain).is_equal(a.get_cell(coord).terrain)


func test_repair_hex_no_cambia_mapa_ya_conectado() -> void:
	var grid := HexGrid.new(10, 8)
	grid.generate_cells()
	for coord in grid.get_all_cells():
		grid.set_terrain(coord, HexCell.Terrain.PLAINS)
	var after := ConnectivityChecker.repair(HexTopology.new(grid))
	assert_bool(after.is_connected).is_true()
	assert_int(after.repaired).is_equal(0)


func test_line_hex_puede_salirse_del_rectangulo() -> void:
	## Contrato del que depende repair: la interpolación + redondeo puede
	## producir offsets fuera del grid entre extremos válidos (verificado
	## contra las fórmulas del anfitrión). Congelado para que un cambio en
	## las fórmulas del anfitrión o un clamp futuro dispare revisión del fix.
	var topology := HexTopology.new(HexGrid.new(15, 15))
	topology.grid.generate_cells()
	var path := topology.line(Vector2i(0, 6), Vector2i(0, 8))
	assert_bool(path.has(Vector2i(-1, 7))).is_true()
	assert_bool(topology.is_valid(Vector2i(-1, 7))).is_false()
	for i in path.size() - 1:
		assert_int(topology.distance(path[i], path[i + 1])).is_equal(1)


func test_vecinos_validos_siempre_acercan_al_objetivo() -> void:
	## Invariante de terminación del puente greedy de repair: en un
	## rectángulo odd-r completo, desde cualquier celda (≠ objetivo) existe
	## al menos un vecino VÁLIDO estrictamente más cercano al objetivo.
	var topology := HexTopology.new(HexGrid.new(12, 12))
	topology.grid.generate_cells()
	for goal in topology.get_all_coords():
		for current in topology.get_all_coords():
			if current == goal:
				continue
			if not _tiene_vecino_valido_mas_cercano(topology, current, goal):
				fail("sin vecino válido más cercano desde %s hacia %s" % [current, goal])
				return


func _tiene_vecino_valido_mas_cercano(topology: HexTopology, current: Vector2i, goal: Vector2i) -> bool:
	var current_distance := topology.distance(current, goal)
	for neighbor in topology.get_neighbors(current):
		if topology.is_valid(neighbor) and topology.distance(neighbor, goal) < current_distance:
			return true
	return false


const SWEEP_HEX_SEEDS := 300
const SWEEP_HEX_GRANDE_SEEDS := 80


func test_repair_hex_conecta_todos_los_seeds_del_sweep() -> void:
	## Propiedad del fix: con connectivity_mode "repair" el mapa queda
	## conexo para cualquier seed (pre-fix: 8/150 seeds fallaban en 15x15
	## con defaults — corredores agujereados por waypoints fuera del grid).
	for seed_value in range(1, SWEEP_HEX_SEEDS + 1):
		var params := {"seed": seed_value, "connectivity_mode": "repair"}
		var grid: HexGrid = HexTopology.generate_hex(15, 15, params)
		var analysis := ConnectivityChecker.analyze(HexTopology.new(grid))
		if not analysis.is_connected:
			fail("seed %d quedó con %d componentes tras repair" % [
				seed_value, analysis.regions.size()])
			return


func test_repair_hex_conecta_mapa_grande_del_sweep() -> void:
	## Ídem sweep chico en 24x16: ejercita corredores más largos y más
	## variedad de bordes jagged.
	for seed_value in range(1, SWEEP_HEX_GRANDE_SEEDS + 1):
		var params := {"seed": seed_value, "connectivity_mode": "repair"}
		var grid: HexGrid = HexTopology.generate_hex(24, 16, params)
		var analysis := ConnectivityChecker.analyze(HexTopology.new(grid))
		if not analysis.is_connected:
			fail("seed %d quedó con %d componentes tras repair (24x16)" % [
				seed_value, analysis.regions.size()])
			return


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
