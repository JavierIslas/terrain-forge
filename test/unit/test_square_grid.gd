class_name TestSquareGrid
extends GdUnitTestSuite
## Modelo espejo SquareGrid/MapCell: storage, edges simétricos y roundtrip.


func test_generate_cells_crea_rectangulo_completo() -> void:
	var grid := SquareGrid.new(10, 8)
	grid.generate_cells()
	assert_int(grid.width).is_equal(10)
	assert_int(grid.height).is_equal(8)
	assert_int(grid.cells.size()).is_equal(80)


func test_dimensiones_invalidas_caen_a_fallback() -> void:
	var grid := SquareGrid.new(0, -5)
	assert_int(grid.width).is_equal(15)
	assert_int(grid.height).is_equal(15)


func test_get_cell_inexistente_es_null() -> void:
	var grid := SquareGrid.new(3, 3)
	grid.generate_cells()
	assert_object(grid.get_cell(Vector2i(9, 9))).is_null()


func test_edge_key_es_simetrico() -> void:
	var a := Vector2i(2, 3)
	var b := Vector2i(1, 5)
	assert_str(SquareGrid.edge_key(a, b)).is_equal(SquareGrid.edge_key(b, a))


func test_set_edge_asigna_costo_default_y_reemplaza() -> void:
	var grid := SquareGrid.new(4, 4)
	grid.set_edge(Vector2i(0, 0), Vector2i(1, 0), SquareGrid.EdgeType.RIVER)
	assert_float(grid.get_edge(Vector2i(0, 0), Vector2i(1, 0))["cost"]).is_equal(2.0)
	grid.set_edge(Vector2i(0, 0), Vector2i(1, 0), SquareGrid.EdgeType.WALL)
	assert_int(grid.edges.size()).is_equal(1)
	assert_float(grid.get_edge(Vector2i(0, 0), Vector2i(1, 0))["cost"]).is_equal(-1.0)


func test_set_edge_no_aliasea_el_properties_del_caller() -> void:
	var grid := SquareGrid.new(4, 4)
	var props := {"name": "ford"}
	grid.set_edge(Vector2i(0, 0), Vector2i(1, 0), SquareGrid.EdgeType.RIVER, props)
	grid.set_edge(Vector2i(2, 2), Vector2i(3, 2), SquareGrid.EdgeType.WALL, props)
	assert_int(grid.get_edge(Vector2i(0, 0), Vector2i(1, 0))["type"]).is_equal(SquareGrid.EdgeType.RIVER)
	assert_int(grid.get_edge(Vector2i(2, 2), Vector2i(3, 2))["type"]).is_equal(SquareGrid.EdgeType.WALL)


func test_clear_edges_elimina_solo_el_tipo_pedido() -> void:
	var grid := SquareGrid.new(4, 4)
	grid.set_edge(Vector2i(0, 0), Vector2i(1, 0), SquareGrid.EdgeType.RIVER)
	grid.set_edge(Vector2i(1, 0), Vector2i(2, 0), SquareGrid.EdgeType.RIVER)
	grid.set_edge(Vector2i(2, 0), Vector2i(3, 0), SquareGrid.EdgeType.WALL)
	var topology := SquareTopology.new(grid)
	var removed := topology.clear_edges(SquareGrid.EdgeType.RIVER)
	assert_int(removed).is_equal(2)
	assert_int(grid.edges.size()).is_equal(1)
	assert_bool(grid.has_edge(Vector2i(2, 0), Vector2i(3, 0))).is_true()


func test_serialize_deserialize_roundtrip() -> void:
	var grid := SquareGrid.new(4, 3)
	grid.generate_cells()
	grid.set_terrain(Vector2i(0, 0), MapCell.Terrain.WATER)
	grid.get_cell(Vector2i(0, 0)).elevation = 3.25
	grid.set_edge(Vector2i(0, 0), Vector2i(1, 0), SquareGrid.EdgeType.RIVER)
	var restored := SquareGrid.deserialize(grid.serialize())
	assert_int(restored.cells.size()).is_equal(12)
	assert_int(restored.get_cell(Vector2i(0, 0)).terrain).is_equal(MapCell.Terrain.WATER)
	assert_float(restored.get_cell(Vector2i(0, 0)).elevation).is_equal(3.25)
	assert_bool(restored.has_edge(Vector2i(0, 0), Vector2i(1, 0))).is_true()


func test_map_cell_serialize_roundtrip() -> void:
	var cell := MapCell.new(Vector2i(3, 4), MapCell.Terrain.FOREST)
	cell.elevation = 2.5
	cell.location_type = 1
	var restored := MapCell.deserialize(cell.serialize())
	assert_bool(restored.coord == Vector2i(3, 4)).is_true()
	assert_int(restored.terrain).is_equal(MapCell.Terrain.FOREST)
	assert_float(restored.elevation).is_equal(2.5)
	assert_bool(restored.has_location()).is_true()


func test_terrain_cost_default_tiene_cinco_terrenos() -> void:
	assert_int(SquareGrid.TERRAIN_COST.size()).is_equal(5)
	assert_float(SquareGrid.TERRAIN_COST[MapCell.Terrain.WATER]).is_equal(-1.0)
