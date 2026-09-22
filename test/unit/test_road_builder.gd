class_name TestRoadBuilder
extends GdUnitTestSuite
## Caminos: MST entre locations + Dijkstra por celda con penalización de agua
## (puentes permitidos), edges ROAD y conversión de terreno opcional.
## Determinista sin rng: tie-break por orden (cost, x, y) y row-major.


func _make_topology(map_w: int, map_h: int) -> SquareTopology:
	var grid := SquareGrid.new(map_w, map_h)
	grid.generate_cells()
	return SquareTopology.new(grid)


func _fill(topo: SquareTopology, terrain: int) -> void:
	for coord in topo.get_all_coords():
		topo.set_terrain(coord, terrain)


func _count_road_edges(topo: SquareTopology) -> int:
	var total := 0
	for key in topo.grid.edges:
		if topo.grid.edges[key]["type"] == SquareGrid.EdgeType.ROAD:
			total += 1
	return total


func test_build_conecta_locations_con_edges_road() -> void:
	var topo := _make_topology(12, 10)
	_fill(topo, MapCell.Terrain.PLAINS)
	topo.set_location(Vector2i(1, 1), 1)
	topo.set_location(Vector2i(10, 8), 1)
	var result := RoadBuilder.build(topo, {})
	assert_int(result.road_paths.size()).is_equal(1)
	var path: Array = result.road_paths[0]
	assert_bool(path[0] == Vector2i(1, 1)).is_true()
	assert_bool(path[path.size() - 1] == Vector2i(10, 8)).is_true()
	for j in path.size() - 1:
		assert_int(topo.distance(path[j], path[j + 1])).is_equal(1)
		var edge: Dictionary = topo.grid.get_edge(path[j], path[j + 1])
		assert_int(edge.get("type", -1)).is_equal(SquareGrid.EdgeType.ROAD)
	assert_int(_count_road_edges(topo)).is_equal(path.size() - 1)


func test_build_es_determinista_con_iguales_entradas() -> void:
	var topo_a := _make_topology(15, 11)
	var topo_b := _make_topology(15, 11)
	for topo in [topo_a, topo_b]:
		_fill(topo, MapCell.Terrain.PLAINS)
		topo.set_terrain(Vector2i(7, 5), MapCell.Terrain.WATER)
		topo.set_location(Vector2i(1, 1), 1)
		topo.set_location(Vector2i(13, 9), 1)
		topo.set_location(Vector2i(3, 8), 1)
	var result_a := RoadBuilder.build(topo_a, {})
	var result_b := RoadBuilder.build(topo_b, {})
	assert_array(result_b.road_paths).is_equal(result_a.road_paths)
	assert_int(result_b.road_bridges).is_equal(result_a.road_bridges)
	assert_int(_count_road_edges(topo_b)).is_equal(_count_road_edges(topo_a))


func test_build_con_menos_de_dos_locations_retorna_vacio() -> void:
	var topo := _make_topology(8, 6)
	_fill(topo, MapCell.Terrain.PLAINS)
	var zero := RoadBuilder.build(topo, {})
	assert_array(zero.road_paths).is_equal([])
	assert_int(zero.road_bridges).is_equal(0)
	topo.set_location(Vector2i(2, 2), 1)
	var one := RoadBuilder.build(topo, {})
	assert_array(one.road_paths).is_equal([])
	assert_int(one.road_bridges).is_equal(0)
	assert_int(_count_road_edges(topo)).is_equal(0)
	assert_int(topo.get_terrain(Vector2i(2, 2))).is_equal(MapCell.Terrain.PLAINS)


func test_build_camino_fijo_en_tablero_empatado() -> void:
	## 3x3 todo PLAINS, locations en esquinas opuestas: todos los caminos
	## cuestan igual y el tie-break (cost, x, y) congela EL camino exacto.
	var topo := _make_topology(3, 3)
	_fill(topo, MapCell.Terrain.PLAINS)
	topo.set_location(Vector2i(0, 0), 1)
	topo.set_location(Vector2i(2, 2), 1)
	var result := RoadBuilder.build(topo, {})
	var expected: Array = [
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	]
	assert_array(result.road_paths[0]).is_equal(expected)


func test_build_penaliza_el_agua_con_road_water_cost() -> void:
	## Agua en el centro; locations arriba/abajo en línea recta que la cruza.
	## Penalización alta → rodea sin tocarla (0 puentes); baja → cruza (puente).
	var water := {Vector2i(3, 3): true}
	for cost in [{"road_water_cost": 8.0}, {"road_water_cost": 0.5}]:
		var topo := _make_topology(7, 7)
		_fill(topo, MapCell.Terrain.PLAINS)
		topo.set_terrain(Vector2i(3, 3), MapCell.Terrain.WATER)
		topo.set_location(Vector2i(3, 0), 1)
		topo.set_location(Vector2i(3, 6), 1)
		var result := RoadBuilder.build(topo, cost)
		assert_int(result.road_paths.size()).is_equal(1)
		if float(cost["road_water_cost"]) > 1.0:
			assert_int(result.road_bridges).is_equal(0)
		else:
			assert_int(result.road_bridges).is_greater_equal(1)


func test_build_cruza_agua_como_puente_sin_convertirla() -> void:
	var topo := _make_topology(5, 5)
	_fill(topo, MapCell.Terrain.PLAINS)
	topo.set_terrain(Vector2i(2, 2), MapCell.Terrain.WATER)
	topo.set_location(Vector2i(2, 0), 1)
	topo.set_location(Vector2i(2, 4), 1)
	var result := RoadBuilder.build(topo, {"road_water_cost": 0.0})
	assert_int(result.road_bridges).is_equal(1)
	assert_int(topo.get_terrain(Vector2i(2, 2))).is_equal(MapCell.Terrain.WATER)
	var path: Array = result.road_paths[0]
	for coord in path:
		if coord == Vector2i(2, 2):
			continue
		assert_int(topo.get_terrain(coord)).is_equal(MapCell.Terrain.ROAD)


func test_build_con_road_terrain_false_deja_el_terreno_intacto() -> void:
	var topo := _make_topology(9, 7)
	_fill(topo, MapCell.Terrain.FOREST)
	topo.set_location(Vector2i(1, 1), 1)
	topo.set_location(Vector2i(7, 5), 1)
	RoadBuilder.build(topo, {"road_terrain": false})
	assert_int(_count_road_edges(topo)).is_greater_equal(1)
	for coord in topo.get_all_coords():
		assert_int(topo.get_terrain(coord)).is_equal(MapCell.Terrain.FOREST)


func test_build_road_mountain_cost_evita_montanas() -> void:
	## Con penalización alta el camino rodea la montaña (que no se toca); con
	## el default 0 la cruza y la convierte en paso de montaña (ROAD).
	var topo := _make_topology(7, 7)
	_fill(topo, MapCell.Terrain.PLAINS)
	topo.set_terrain(Vector2i(3, 3), MapCell.Terrain.MOUNTAIN)
	topo.set_location(Vector2i(3, 0), 1)
	topo.set_location(Vector2i(3, 6), 1)
	var evitado := RoadBuilder.build(topo, {"road_mountain_cost": 8.0})
	for path in evitado.road_paths:
		for coord in path:
			assert_bool(coord == Vector2i(3, 3)).is_false()
	assert_int(topo.get_terrain(Vector2i(3, 3))).is_equal(MapCell.Terrain.MOUNTAIN)

	var cruzado := _make_topology(7, 7)
	_fill(cruzado, MapCell.Terrain.PLAINS)
	cruzado.set_terrain(Vector2i(3, 3), MapCell.Terrain.MOUNTAIN)
	cruzado.set_location(Vector2i(3, 0), 1)
	cruzado.set_location(Vector2i(3, 6), 1)
	RoadBuilder.build(cruzado, {})
	assert_int(cruzado.get_terrain(Vector2i(3, 3))).is_equal(MapCell.Terrain.ROAD)


func test_build_cost_fn_inyectable_cambia_la_ruta() -> void:
	## cost_fn que encarece un tramo del muro central (columna 3, filas 1-3):
	## el camino lo rodea por el borde superior o inferior sin tocarlo.
	var topo := _make_topology(7, 5)
	_fill(topo, MapCell.Terrain.PLAINS)
	topo.set_location(Vector2i(0, 2), 1)
	topo.set_location(Vector2i(6, 2), 1)
	var wall := {Vector2i(3, 1): true, Vector2i(3, 2): true, Vector2i(3, 3): true}
	var expensive_wall := func(coord: Vector2i) -> float:
		return 20.0 if wall.has(coord) else 1.0
	var result := RoadBuilder.build(topo, {}, expensive_wall)
	assert_int(result.road_paths.size()).is_equal(1)
	for coord in result.road_paths[0]:
		assert_bool(wall.has(coord)).is_false()


func test_build_en_topologia_desconectada_salta_lo_inalcanzable() -> void:
	## Dos componentes sin conexión: la pareja es inalcanzable y se salta sin
	## crash (degrade documentado). No asertamos edges acá: esta topología de
	## prueba implementa clear_edges fielmente, pero el contrato del salto es
	## sobre los paths.
	var topo := TwoIslandsTopology.new()
	topo.set_location(Vector2i(0, 0), 1)
	topo.set_location(Vector2i(6, 0), 1)
	var result := RoadBuilder.build(topo, {})
	assert_array(result.road_paths).is_equal([])
	assert_int(result.road_bridges).is_equal(0)


func test_build_ignora_el_rng_global() -> void:
	seed(4242)
	var expected := randi()
	seed(4242)
	var topo := _make_topology(12, 10)
	_fill(topo, MapCell.Terrain.PLAINS)
	topo.set_location(Vector2i(1, 1), 1)
	topo.set_location(Vector2i(10, 8), 1)
	RoadBuilder.build(topo, {})
	assert_int(randi()).is_equal(expected)


func test_build_perf_smoke_100x100_bajo_presupuesto() -> void:
	## Humo de no-regresión: pipeline completo con roads activado sobre 10.000
	## celdas y MST de 6 locations (5 caminos con Dijkstra early-exit). El
	## presupuesto es holgado; en CI se relaja (runners 2-4× más lentos).
	var topo := _make_topology(100, 100)
	var budget := 5000
	if OS.has_environment("CI"):
		budget = 15000
	var started := Time.get_ticks_msec()
	var report := TerrainForge.generate_with_report(topo, {
		"seed": 42, "smoothing_passes": 1, "location_count": 6,
		"location_spacing": 8, "roads": true})
	var elapsed := Time.get_ticks_msec() - started
	assert_int(report.road_paths.size()).is_equal(5)
	assert_int(elapsed).is_less(budget)


class TwoIslandsTopology extends GridTopology:
	## Dos componentes 4-dir desconectadas (2 celdas cada una) para el caso
	## inalcanzable del trazado. Solo implementa lo que RoadBuilder consume.
	var cells := {}
	var edges := {}

	func _init() -> void:
		for coord in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 0), Vector2i(6, 0)]:
			cells[coord] = MapCell.new(coord)

	func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		var deltas: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0)]
		for delta in deltas:
			var candidate := coord + delta
			if cells.has(candidate):
				result.append(candidate)
		return result

	func is_valid(coord: Vector2i) -> bool:
		return cells.has(coord)

	func distance(a: Vector2i, b: Vector2i) -> int:
		return absi(a.x - b.x) + absi(a.y - b.y)

	func get_all_coords() -> Array[Vector2i]:
		var coords: Array[Vector2i] = []
		coords.assign(cells.keys())
		return coords

	func get_terrain(_coord: Vector2i) -> int:
		return MapCell.Terrain.PLAINS

	func set_terrain(_coord: Vector2i, _terrain: int) -> void:
		pass

	func set_location(coord: Vector2i, location_type: int) -> void:
		cells[coord].location_type = location_type

	func has_location(coord: Vector2i) -> bool:
		return cells.has(coord) and cells[coord].location_type > 0

	func set_edge(a: Vector2i, b: Vector2i, edge_type: int) -> void:
		edges[_edge_key(a, b)] = {"type": edge_type}

	func edge_count() -> int:
		return edges.size()

	func clear_edges(edge_type: int) -> int:
		var removed := 0
		for key in edges.keys():
			if edges[key]["type"] == edge_type:
				edges.erase(key)
				removed += 1
		return removed

	func _edge_key(a: Vector2i, b: Vector2i) -> String:
		var lo := a if a.x < b.x or (a.x == b.x and a.y < b.y) else b
		var hi := b if lo == a else a
		return "%d,%d;%d,%d" % [lo.x, lo.y, hi.x, hi.y]
