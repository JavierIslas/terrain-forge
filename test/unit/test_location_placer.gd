class_name TestLocationPlacer
extends GdUnitTestSuite
## Locations: cantidad, filtro, spacing, no-overlap y determinismo.


func _make_topology(map_w: int, map_h: int) -> SquareTopology:
	var grid := SquareGrid.new(map_w, map_h)
	grid.generate_cells()
	return SquareTopology.new(grid)


func test_place_cantidad_exacta_y_sin_overlap() -> void:
	var topo := _make_topology(6, 6)
	var placed := LocationPlacer.place(topo, SeededRng.new(1), {"location_count": 5})
	assert_int(placed.size()).is_equal(5)
	for coord in placed:
		assert_bool(topo.has_location(coord)).is_true()


func test_place_respeta_filtro_de_terreno() -> void:
	var topo := _make_topology(8, 8)
	for coord in topo.get_all_coords():
		topo.set_terrain(coord, MapCell.Terrain.WATER if coord.x < 4 else MapCell.Terrain.PLAINS)
	var placed := LocationPlacer.place(topo, SeededRng.new(2), {
		"location_count": 4,
		"location_terrain_filter": [MapCell.Terrain.PLAINS],
	})
	assert_int(placed.size()).is_equal(4)
	for coord in placed:
		assert_bool(coord.x >= 4).is_true()


func test_place_no_pisa_locations_previas() -> void:
	var topo := _make_topology(6, 6)
	topo.set_location(Vector2i(0, 0), 1)
	var placed := LocationPlacer.place(topo, SeededRng.new(3), {"location_count": 3})
	assert_int(placed.size()).is_equal(3)
	assert_bool(Vector2i(0, 0) in placed).is_false()
	var total := 0
	for coord in topo.get_all_coords():
		if topo.has_location(coord):
			total += 1
	assert_int(total).is_equal(4)


func test_place_es_determinista_con_seed_explicito() -> void:
	var topo_a := _make_topology(10, 10)
	var topo_b := _make_topology(10, 10)
	var params := {"location_count": 6}
	var placed_a := LocationPlacer.place(topo_a, SeededRng.new(77), params)
	var placed_b := LocationPlacer.place(topo_b, SeededRng.new(77), params)
	assert_array(placed_b).is_equal(placed_a)


func test_place_spacing_respeta_distancia_minima() -> void:
	var topo := _make_topology(10, 10)
	var placed := LocationPlacer.place(topo, SeededRng.new(4), {
		"location_count": 5,
		"location_spacing": 3,
	})
	for i in placed.size():
		for j in placed.size():
			if i != j:
				assert_int(topo.distance(placed[i], placed[j])).is_greater_equal(3)


func test_place_coloca_menos_si_faltan_candidatos() -> void:
	var topo := _make_topology(5, 5)
	for coord in topo.get_all_coords():
		topo.set_terrain(coord, MapCell.Terrain.WATER)
	topo.set_terrain(Vector2i(0, 0), MapCell.Terrain.PLAINS)
	topo.set_terrain(Vector2i(4, 4), MapCell.Terrain.PLAINS)
	var placed := LocationPlacer.place(topo, SeededRng.new(5), {
		"location_count": 5,
		"location_terrain_filter": [MapCell.Terrain.PLAINS],
	})
	assert_int(placed.size()).is_equal(2)


func test_place_con_type_custom_asigna_el_type() -> void:
	var topo := _make_topology(5, 5)
	LocationPlacer.place(topo, SeededRng.new(6), {"location_count": 2, "location_type": 7})
	var grid: SquareGrid = topo.grid
	for coord in topo.get_all_coords():
		if topo.has_location(coord):
			assert_int(grid.get_cell(coord).location_type).is_equal(7)


func test_place_ignora_el_rng_global() -> void:
	seed(54321)
	var expected := randi()
	seed(54321)
	var topo := _make_topology(6, 6)
	LocationPlacer.place(topo, SeededRng.new(8), {"location_count": 3})
	assert_int(randi()).is_equal(expected)
