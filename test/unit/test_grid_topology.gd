class_name TestGridTopology
extends GdUnitTestSuite
## Contrato del puerto GridTopology verificado vía SquareTopology.


func _make_topology(map_w: int = 6, map_h: int = 4, connectivity: int = SquareTopology.CONNECTIVITY_VON_NEUMANN) -> SquareTopology:
	var grid := SquareGrid.new(map_w, map_h)
	grid.generate_cells()
	return SquareTopology.new(grid, connectivity)


func test_vecinos_von_neumann_son_cuatro_cardinales() -> void:
	var topo := _make_topology()
	var neighbors := topo.get_neighbors(Vector2i(2, 2))
	assert_int(neighbors.size()).is_equal(4)
	assert_bool(neighbors.has(Vector2i(1, 2))).is_true()
	assert_bool(neighbors.has(Vector2i(3, 2))).is_true()
	assert_bool(neighbors.has(Vector2i(2, 1))).is_true()
	assert_bool(neighbors.has(Vector2i(2, 3))).is_true()


func test_vecinos_moore_son_ocho() -> void:
	var topo := _make_topology(6, 4, SquareTopology.CONNECTIVITY_MOORE)
	assert_int(topo.get_neighbors(Vector2i(2, 2)).size()).is_equal(8)


func test_vecinos_incluyen_candidatos_fuera_de_limites() -> void:
	## Contrato: el puerto NO filtra; el consumidor filtra con is_valid.
	var topo := _make_topology(3, 3)
	assert_bool(topo.get_neighbors(Vector2i(0, 0)).has(Vector2i(-1, 0))).is_true()


func test_distance_es_manhattan_en_von_neumann() -> void:
	var topo := _make_topology()
	assert_int(topo.distance(Vector2i(0, 0), Vector2i(2, 3))).is_equal(5)


func test_distance_es_chebyshev_en_moore() -> void:
	var topo := _make_topology(6, 4, SquareTopology.CONNECTIVITY_MOORE)
	assert_int(topo.distance(Vector2i(0, 0), Vector2i(2, 3))).is_equal(3)


func test_line_escalonada_termina_en_destino_y_es_continua() -> void:
	var topo := _make_topology()
	var path := topo.line(Vector2i(0, 0), Vector2i(3, 2))
	assert_bool(path[0] == Vector2i(0, 0)).is_true()
	for i in path.size() - 1:
		var step: Vector2i = path[i + 1] - path[i]
		assert_int(absi(step.x) + absi(step.y)).is_equal(1)
	assert_bool(path[path.size() - 1] == Vector2i(3, 2)).is_true()


func test_line_bresenham_termina_en_destino_con_pasos_unitarios() -> void:
	var topo := _make_topology(6, 4, SquareTopology.CONNECTIVITY_MOORE)
	var path := topo.line(Vector2i(0, 0), Vector2i(4, 2))
	assert_bool(path[0] == Vector2i(0, 0)).is_true()
	for i in path.size() - 1:
		var step: Vector2i = path[i + 1] - path[i]
		assert_bool(absi(step.x) <= 1 and absi(step.y) <= 1).is_true()
	assert_bool(path[path.size() - 1] == Vector2i(4, 2)).is_true()


func test_get_all_coords_es_row_major() -> void:
	var topo := _make_topology(3, 2)
	var coords := topo.get_all_coords()
	assert_int(coords.size()).is_equal(6)
	assert_bool(coords[0] == Vector2i(0, 0)).is_true()
	assert_bool(coords[1] == Vector2i(1, 0)).is_true()
	assert_bool(coords[2] == Vector2i(2, 0)).is_true()
	assert_bool(coords[3] == Vector2i(0, 1)).is_true()
	assert_int(topo.cell_count()).is_equal(6)
	assert_bool(topo.get_dimensions() == Vector2i(3, 2)).is_true()


func test_storage_redondea_terrain_elevacion_location() -> void:
	var topo := _make_topology()
	topo.set_terrain(Vector2i(1, 1), MapCell.Terrain.MOUNTAIN)
	topo.set_elevation(Vector2i(1, 1), 7.5)
	topo.set_location(Vector2i(1, 1), 3)
	assert_int(topo.get_terrain(Vector2i(1, 1))).is_equal(MapCell.Terrain.MOUNTAIN)
	assert_float(topo.get_elevation(Vector2i(1, 1))).is_equal(7.5)
	assert_bool(topo.has_location(Vector2i(1, 1))).is_true()


func test_coordenada_inexistente_es_neutra_sin_crash() -> void:
	var topo := _make_topology()
	assert_int(topo.get_terrain(Vector2i(99, 99))).is_equal(-1)
	assert_float(topo.get_elevation(Vector2i(99, 99))).is_equal(0.0)
	assert_bool(topo.has_location(Vector2i(99, 99))).is_false()
	topo.set_terrain(Vector2i(99, 99), MapCell.Terrain.WATER)
	topo.set_location(Vector2i(99, 99), 1)
	assert_bool(topo.has_location(Vector2i(99, 99))).is_false()


func test_set_edge_y_edge_count_sobre_el_puerto() -> void:
	var topo := _make_topology()
	topo.set_edge(Vector2i(0, 0), Vector2i(1, 0), SquareGrid.EdgeType.RIVER)
	topo.set_edge(Vector2i(1, 0), Vector2i(2, 0), SquareGrid.EdgeType.RIVER)
	assert_int(topo.edge_count()).is_equal(2)
