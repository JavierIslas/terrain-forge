class_name TestGridSearch
extends GdUnitTestSuite
## Búsqueda genérica sobre el puerto: reachable por presupuesto, camino óptimo
## con costos terreno+edge, inyectables y topologías no rectangulares.


func _make_grid(width: int, height: int, default_terrain: int = MapCell.Terrain.PLAINS) -> SquareGrid:
	var grid := SquareGrid.new(width, height)
	grid.generate_cells(default_terrain)
	return grid


## Costo acumulado de un camino sumando el modelo aditivo del puerto.
func _path_cost(topology: GridTopology, path: Array[Vector2i]) -> float:
	var total := 0.0
	for i in path.size() - 1:
		total += topology.get_movement_cost(path[i + 1]) + topology.get_edge_cost(path[i], path[i + 1])
	return total


func test_defaults_de_costo_del_puerto_son_neutrales() -> void:
	var topo := MinimalTriangle.new(4)
	assert_float(topo.get_movement_cost(Vector2i(0, 0))).is_equal(1.0)
	assert_bool(topo.is_passable(Vector2i(0, 0))).is_true()
	assert_float(topo.get_edge_cost(Vector2i(0, 0), Vector2i(0, 1))).is_equal(0.0)


func test_find_reachable_acumula_costos_de_terreno_en_grid_plano() -> void:
	var topo := SquareTopology.new(_make_grid(5, 5))
	var reachable := GridSearch.find_reachable(topo, Vector2i(2, 2), 3.0)
	assert_int(reachable.size()).is_equal(13)
	assert_float(reachable[Vector2i(2, 2)]).is_equal(0.0)
	assert_float(reachable[Vector2i(3, 2)]).is_equal(1.5)
	assert_float(reachable[Vector2i(4, 2)]).is_equal(3.0)
	assert_float(reachable[Vector2i(0, 2)]).is_equal(3.0)
	assert_bool(reachable.has(Vector2i(0, 1))).is_false()


func test_find_reachable_excluye_celdas_mayores_a_max_cost() -> void:
	var topo := SquareTopology.new(_make_grid(5, 5))
	var just_origin := GridSearch.find_reachable(topo, Vector2i(2, 2), 1.4)
	assert_int(just_origin.size()).is_equal(1)
	var exact := GridSearch.find_reachable(topo, Vector2i(2, 2), 1.5)
	assert_int(exact.size()).is_equal(5)


func test_find_reachable_marca_agua_como_intransitable() -> void:
	var grid := _make_grid(3, 3)
	grid.set_terrain(Vector2i(1, 1), MapCell.Terrain.WATER)
	var reachable := GridSearch.find_reachable(SquareTopology.new(grid), Vector2i(0, 0), 99.0)
	assert_bool(reachable.has(Vector2i(1, 1))).is_false()
	assert_int(reachable.size()).is_equal(8)


func test_find_reachable_origen_invalido_retorna_vacio() -> void:
	var topo := SquareTopology.new(_make_grid(5, 5))
	assert_int(GridSearch.find_reachable(topo, Vector2i(99, 99), 5.0).size()).is_equal(0)


func test_find_reachable_max_cost_negativo_retorna_vacio() -> void:
	var topo := SquareTopology.new(_make_grid(5, 5))
	assert_int(GridSearch.find_reachable(topo, Vector2i(2, 2), -1.0).size()).is_equal(0)


func test_find_path_rodea_muro_de_agua_por_el_hueco() -> void:
	var grid := _make_grid(5, 5)
	for y in 5:
		grid.set_terrain(Vector2i(2, y), MapCell.Terrain.WATER)
	grid.set_terrain(Vector2i(2, 4), MapCell.Terrain.PLAINS)
	var path := GridSearch.find_path(SquareTopology.new(grid), Vector2i(0, 2), Vector2i(4, 2))
	assert_int(path.size()).is_equal(9)
	assert_vector(path[0]).is_equal(Vector2i(0, 2))
	assert_vector(path[path.size() - 1]).is_equal(Vector2i(4, 2))
	assert_bool(path.has(Vector2i(2, 4))).is_true()
	assert_bool(path.has(Vector2i(2, 0))).is_false()
	assert_bool(path.has(Vector2i(2, 1))).is_false()


func test_find_path_suma_sobreprecio_de_edge_rio() -> void:
	var grid := _make_grid(3, 3)
	var topo := SquareTopology.new(grid)
	var directo := GridSearch.find_path(topo, Vector2i(0, 1), Vector2i(2, 1))
	assert_int(directo.size()).is_equal(3)
	assert_bool(directo.has(Vector2i(1, 1))).is_true()
	grid.set_edge(Vector2i(0, 1), Vector2i(1, 1), SquareGrid.EdgeType.RIVER)
	grid.set_edge(Vector2i(1, 1), Vector2i(2, 1), SquareGrid.EdgeType.RIVER)
	var desviado := GridSearch.find_path(topo, Vector2i(0, 1), Vector2i(2, 1))
	assert_int(desviado.size()).is_equal(5)
	assert_bool(desviado.has(Vector2i(1, 1))).is_false()


func test_find_path_prefiere_ruta_con_edges_road() -> void:
	var grid := _make_grid(3, 3)
	var topo := SquareTopology.new(grid)
	for pair in [[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(2, 0)],
			[Vector2i(2, 0), Vector2i(2, 1)], [Vector2i(2, 1), Vector2i(2, 2)]]:
		topo.set_edge(pair[0], pair[1], SquareGrid.EdgeType.ROAD)
	var path := GridSearch.find_path(topo, Vector2i(0, 0), Vector2i(2, 2))
	assert_int(path.size()).is_equal(5)
	assert_vector(path[0]).is_equal(Vector2i(0, 0))
	assert_vector(path[1]).is_equal(Vector2i(1, 0))
	assert_vector(path[2]).is_equal(Vector2i(2, 0))
	assert_vector(path[3]).is_equal(Vector2i(2, 1))
	assert_vector(path[4]).is_equal(Vector2i(2, 2))


func test_find_path_retorna_vacio_destino_rodeado_de_agua() -> void:
	var grid := _make_grid(3, 3)
	for neighbor in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
		grid.set_terrain(neighbor, MapCell.Terrain.WATER)
	var path := GridSearch.find_path(SquareTopology.new(grid), Vector2i(0, 0), Vector2i(2, 2))
	assert_int(path.size()).is_equal(0)


func test_find_path_destino_intransitable_retorna_vacio() -> void:
	var grid := _make_grid(3, 3)
	grid.set_terrain(Vector2i(2, 1), MapCell.Terrain.WATER)
	var path := GridSearch.find_path(SquareTopology.new(grid), Vector2i(0, 0), Vector2i(2, 1))
	assert_int(path.size()).is_equal(0)


func test_find_path_origen_igual_a_destino_retorna_vacio() -> void:
	var topo := SquareTopology.new(_make_grid(3, 3))
	var path := GridSearch.find_path(topo, Vector2i(1, 1), Vector2i(1, 1))
	assert_int(path.size()).is_equal(0)


func test_find_path_incluye_ambos_extremos() -> void:
	var topo := SquareTopology.new(_make_grid(3, 3))
	var path := GridSearch.find_path(topo, Vector2i(0, 0), Vector2i(1, 0))
	assert_int(path.size()).is_equal(2)
	assert_vector(path[0]).is_equal(Vector2i(0, 0))
	assert_vector(path[1]).is_equal(Vector2i(1, 0))


func test_find_path_es_determinista_bajo_empates() -> void:
	var topo := SquareTopology.new(_make_grid(6, 6))
	var first := GridSearch.find_path(topo, Vector2i(0, 0), Vector2i(5, 5))
	var second := GridSearch.find_path(topo, Vector2i(0, 0), Vector2i(5, 5))
	assert_array(first).is_equal(second)


func test_find_path_astar_iguala_costo_total_de_find_path() -> void:
	var grid := _make_grid(5, 5)
	grid.set_terrain(Vector2i(1, 1), MapCell.Terrain.MOUNTAIN)
	grid.set_terrain(Vector2i(2, 3), MapCell.Terrain.MOUNTAIN)
	grid.set_terrain(Vector2i(3, 0), MapCell.Terrain.MOUNTAIN)
	grid.set_terrain(Vector2i(0, 4), MapCell.Terrain.FOREST)
	var topo := SquareTopology.new(grid)
	var dijkstra := GridSearch.find_path(topo, Vector2i(0, 0), Vector2i(4, 4))
	var astar := GridSearch.find_path_astar(topo, Vector2i(0, 0), Vector2i(4, 4))
	assert_int(dijkstra.size()).is_greater(0)
	assert_int(astar.size()).is_greater(0)
	assert_float(_path_cost(topo, astar)).is_equal_approx(_path_cost(topo, dijkstra), 0.0001)


func test_find_path_astar_retorna_vacio_si_inalcanzable() -> void:
	var grid := _make_grid(3, 3)
	for neighbor in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
		grid.set_terrain(neighbor, MapCell.Terrain.WATER)
	var path := GridSearch.find_path_astar(SquareTopology.new(grid), Vector2i(0, 0), Vector2i(2, 2))
	assert_int(path.size()).is_equal(0)


func test_cost_fn_inyectable_reemplaza_modelo_aditivo() -> void:
	var grid := _make_grid(4, 4)
	grid.set_terrain(Vector2i(1, 0), MapCell.Terrain.MOUNTAIN)
	var topo := SquareTopology.new(grid)
	var por_tabla := GridSearch.find_reachable(topo, Vector2i(0, 0), 2.0)
	assert_int(por_tabla.size()).is_equal(2)
	assert_bool(por_tabla.has(Vector2i(1, 0))).is_false()
	var plano := GridSearch.find_reachable(topo, Vector2i(0, 0), 2.0, {
		"cost_fn": func(_from: Vector2i, _to: Vector2i) -> float: return 1.0,
	})
	assert_int(plano.size()).is_equal(6)
	assert_bool(plano.has(Vector2i(1, 0))).is_true()


func test_passable_fn_inyectable_filtra_vecinos() -> void:
	var topo := SquareTopology.new(_make_grid(3, 3))
	var path := GridSearch.find_path(topo, Vector2i(0, 1), Vector2i(2, 1), {
		"passable_fn": func(coord: Vector2i) -> bool: return coord != Vector2i(1, 1),
	})
	assert_bool(path.has(Vector2i(1, 1))).is_false()
	assert_int(path.size()).is_greater(2)


func test_params_reachable_restringe_la_busqueda() -> void:
	var topo := SquareTopology.new(_make_grid(5, 5))
	var island := {Vector2i(0, 0): 0.0, Vector2i(1, 0): 1.5}
	var fuera := GridSearch.find_path(topo, Vector2i(0, 0), Vector2i(4, 4), {"reachable": island})
	assert_int(fuera.size()).is_equal(0)
	var dentro := GridSearch.find_path(topo, Vector2i(0, 0), Vector2i(1, 0), {"reachable": island})
	assert_int(dentro.size()).is_equal(2)


func test_find_path_funciona_en_topologia_no_rectangular() -> void:
	var topo := MinimalTriangle.new(6)
	var path := GridSearch.find_path(topo, Vector2i(0, 0), Vector2i(3, 5))
	assert_int(path.size()).is_equal(9)
	assert_vector(path[0]).is_equal(Vector2i(0, 0))
	assert_vector(path[path.size() - 1]).is_equal(Vector2i(3, 5))
	for coord in path:
		assert_bool(coord.x <= coord.y).is_true()


## Topología mínima no rectangular SIN overrides de costo: ejercita los
## defaults neutrales del puerto (costo 1.0, pasable = válido, edge 0.0).
class MinimalTriangle extends GridTopology:
	var cells := {}

	func _init(size: int) -> void:
		for y in size:
			for x in size:
				if x <= y:
					cells[Vector2i(x, y)] = true

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
		return Vector2i(cells.size(), cells.size())

	func cell_count() -> int:
		return cells.size()

	func get_terrain(coord: Vector2i) -> int:
		return 1 if is_valid(coord) else -1

	func set_terrain(_coord: Vector2i, _terrain: int) -> void:
		pass

	func get_elevation(_coord: Vector2i) -> float:
		return 0.0

	func set_elevation(_coord: Vector2i, _elevation: float) -> void:
		pass

	func set_location(_coord: Vector2i, _location_type: int) -> void:
		pass

	func has_location(_coord: Vector2i) -> bool:
		return false

	func set_edge(_a: Vector2i, _b: Vector2i, _edge_type: int) -> void:
		pass

	func edge_count() -> int:
		return 0

	func clear_edges(_edge_type: int) -> int:
		return 0
