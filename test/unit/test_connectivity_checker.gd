class_name TestConnectivityChecker
extends GdUnitTestSuite
## Conectividad: reporte BFS determinista y reparación por corredores.


func _make_topology(map_w: int, map_h: int) -> SquareTopology:
	var grid := SquareGrid.new(map_w, map_h)
	grid.generate_cells()
	return SquareTopology.new(grid)


func _fill(topo: SquareTopology, terrain: int) -> void:
	for coord in topo.get_all_coords():
		topo.set_terrain(coord, terrain)


func test_analyze_mapa_conectado_tiene_una_region() -> void:
	var topo := _make_topology(6, 5)
	_fill(topo, MapCell.Terrain.PLAINS)
	var analysis := ConnectivityChecker.analyze(topo)
	assert_bool(analysis.is_connected).is_true()
	assert_int(analysis.regions.size()).is_equal(1)
	assert_float(analysis.largest_ratio).is_equal(1.0)
	assert_int(analysis.largest_coords.size()).is_equal(30)


func test_analyze_detecta_componentes_separadas_por_agua() -> void:
	var topo := _make_topology(7, 5)
	_fill(topo, MapCell.Terrain.PLAINS)
	for y in 5:
		topo.set_terrain(Vector2i(3, y), MapCell.Terrain.WATER)
	var analysis := ConnectivityChecker.analyze(topo)
	assert_bool(analysis.is_connected).is_false()
	assert_int(analysis.regions.size()).is_equal(2)
	assert_int(analysis.region_sizes[0]).is_equal(15)
	assert_int(analysis.region_sizes[1]).is_equal(15)


func test_analyze_mapa_todos_agua_sin_regiones() -> void:
	var topo := _make_topology(4, 4)
	_fill(topo, MapCell.Terrain.WATER)
	var analysis := ConnectivityChecker.analyze(topo)
	assert_bool(analysis.is_connected).is_true()
	assert_int(analysis.regions.size()).is_equal(0)
	assert_float(analysis.largest_ratio).is_equal(0.0)


func test_analyze_passable_fn_custom() -> void:
	var topo := _make_topology(5, 3)
	_fill(topo, MapCell.Terrain.PLAINS)
	for y in 3:
		topo.set_terrain(Vector2i(2, y), MapCell.Terrain.MOUNTAIN)
	var analysis := ConnectivityChecker.analyze(topo, func(coord: Vector2i) -> bool:
		return topo.get_terrain(coord) != MapCell.Terrain.MOUNTAIN)
	assert_bool(analysis.is_connected).is_false()
	assert_int(analysis.regions.size()).is_equal(2)


func test_analyze_ordena_regiones_determinista() -> void:
	var topo_a := _make_topology(8, 4)
	var topo_b := _make_topology(8, 4)
	for topo in [topo_a, topo_b]:
		_fill(topo, MapCell.Terrain.PLAINS)
		for y in 4:
			topo.set_terrain(Vector2i(4, y), MapCell.Terrain.WATER)
		topo.set_terrain(Vector2i(0, 0), MapCell.Terrain.WATER)
	var sizes_a: Array = ConnectivityChecker.analyze(topo_a).region_sizes
	var sizes_b: Array = ConnectivityChecker.analyze(topo_b).region_sizes
	assert_array(sizes_b).is_equal(sizes_a)
	assert_int(sizes_a[0]).is_greater_equal(sizes_a[1])


func test_repair_conecta_componentes_tallando_corredor() -> void:
	var topo := _make_topology(7, 5)
	_fill(topo, MapCell.Terrain.PLAINS)
	for y in 5:
		topo.set_terrain(Vector2i(3, y), MapCell.Terrain.WATER)
	var after := ConnectivityChecker.repair(topo)
	assert_bool(after.is_connected).is_true()
	assert_int(after.repaired).is_greater(0)
	assert_int(topo.get_terrain(Vector2i(3, 0))).is_equal(MapCell.Terrain.PLAINS)
	# Corredor bien comportado: talla exactamente la celda del camino y nada más.
	assert_int(after.repaired).is_equal(1)
	for y in range(1, 5):
		assert_int(topo.get_terrain(Vector2i(3, y))).is_equal(MapCell.Terrain.WATER)


func test_repair_no_cambia_mapa_ya_conectado() -> void:
	var topo := _make_topology(5, 5)
	_fill(topo, MapCell.Terrain.PLAINS)
	var after := ConnectivityChecker.repair(topo)
	assert_bool(after.is_connected).is_true()
	assert_int(after.repaired).is_equal(0)


func test_repair_es_determinista() -> void:
	var results: Array = []
	for run in 2:
		var topo := _make_topology(9, 5)
		_fill(topo, MapCell.Terrain.PLAINS)
		for y in 5:
			topo.set_terrain(Vector2i(4, y), MapCell.Terrain.WATER)
		var after := ConnectivityChecker.repair(topo)
		var terrains := {}
		for coord in topo.get_all_coords():
			terrains[coord] = topo.get_terrain(coord)
		results.append([after.repaired, after.is_connected, terrains])
	assert_int(results[1][0]).is_equal(results[0][0])
	assert_bool(results[1][1]).is_true()
	var terrains_a: Dictionary = results[0][2]
	var terrains_b: Dictionary = results[1][2]
	for coord in terrains_a:
		assert_int(terrains_b[coord]).is_equal(terrains_a[coord])


func test_repair_puentea_waypoints_fuera_del_grid() -> void:
	## Regresión del corredor agujereado: line() con un waypoint fuera del
	## grid entre extremos válidos a distancia 2 (el artefacto odd-r del
	## lerp+round hex). Sin puente, el waypoint se salta y las componentes
	## quedan a distancia 2 → desconectadas.
	var grid := SquareGrid.new(5, 10)
	grid.generate_cells()
	var topo := DetourLineTopology.new(
		grid, Vector2i(0, 6), Vector2i(0, 8), [Vector2i(-1, 7)])
	_fill(topo, MapCell.Terrain.WATER)
	topo.set_terrain(Vector2i(0, 6), MapCell.Terrain.PLAINS)
	topo.set_terrain(Vector2i(0, 8), MapCell.Terrain.PLAINS)
	var after := ConnectivityChecker.repair(topo)
	assert_bool(after.is_connected).is_true()
	assert_int(topo.get_terrain(Vector2i(0, 7))).is_equal(MapCell.Terrain.PLAINS)
	assert_int(after.repaired).is_equal(1)


func test_repair_puentea_salto_de_varios_pasos() -> void:
	## Variante con DOS waypoints fugados consecutivos (gap de distancia 3):
	## el puente debe recorrer las celdas intermedias dentro del grid.
	var grid := SquareGrid.new(5, 10)
	grid.generate_cells()
	var topo := DetourLineTopology.new(
		grid, Vector2i(0, 5), Vector2i(0, 8), [Vector2i(-2, 7), Vector2i(-1, 8)])
	_fill(topo, MapCell.Terrain.WATER)
	topo.set_terrain(Vector2i(0, 5), MapCell.Terrain.PLAINS)
	topo.set_terrain(Vector2i(0, 8), MapCell.Terrain.PLAINS)
	var after := ConnectivityChecker.repair(topo)
	assert_bool(after.is_connected).is_true()
	assert_int(topo.get_terrain(Vector2i(0, 6))).is_equal(MapCell.Terrain.PLAINS)
	assert_int(topo.get_terrain(Vector2i(0, 7))).is_equal(MapCell.Terrain.PLAINS)


## Doble de topología: line() que emula el artefacto del lerp+round hex
## (waypoints fuera del grid entre extremos válidos). Solo muta el par
## inyectado; el resto delega en la línea squares real (misma familia que
## TriangleTopology en test_terrain_forge.gd: topología real con el
## contrato del puerto ejercitado en un edge case).
class DetourLineTopology extends SquareTopology:
	var detour_from: Vector2i
	var detour_to: Vector2i
	var detour_cells: Array[Vector2i] = []


	func _init(square_grid: SquareGrid, from_coord: Vector2i, to_coord: Vector2i, cells: Array[Vector2i]) -> void:
		super(square_grid)
		detour_from = from_coord
		detour_to = to_coord
		detour_cells = cells


	func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
		if a == detour_from and b == detour_to:
			var detoured: Array[Vector2i] = [a]
			detoured.append_array(detour_cells)
			detoured.append(b)
			return detoured
		return super(a, b)
