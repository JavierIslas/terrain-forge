class_name TestRiverCarver
extends GdUnitTestSuite
## Ríos: edges RIVER adyacentes, determinismo por seed, spacing y límites.


func _make_topology(map_w: int, map_h: int) -> SquareTopology:
	var grid := SquareGrid.new(map_w, map_h)
	grid.generate_cells()
	return SquareTopology.new(grid)


func test_carve_genera_edges_river_entre_celdas_adyacentes() -> void:
	var topo := _make_topology(15, 15)
	var paths := RiverCarver.carve(topo, SeededRng.new(42))
	assert_int(paths.size()).is_greater_equal(1)
	var grid: SquareGrid = topo.grid
	for path in paths:
		for j in path.size() - 1:
			var edge := grid.get_edge(path[j], path[j + 1])
			assert_int(edge.get("type", -1)).is_equal(SquareGrid.EdgeType.RIVER)
			assert_int(topo.distance(path[j], path[j + 1])).is_equal(1)


func test_carve_es_determinista_con_mismo_seed() -> void:
	var topo_a := _make_topology(20, 20)
	var topo_b := _make_topology(20, 20)
	var paths_a := RiverCarver.carve(topo_a, SeededRng.new(7))
	var paths_b := RiverCarver.carve(topo_b, SeededRng.new(7))
	assert_int(paths_b.size()).is_equal(paths_a.size())
	assert_int(topo_b.edge_count()).is_equal(topo_a.edge_count())
	for i in paths_a.size():
		assert_array(paths_b[i]).is_equal(paths_a[i])


func test_carve_respeta_river_count() -> void:
	var topo := _make_topology(25, 25)
	var paths := RiverCarver.carve(topo, SeededRng.new(1), {"river_count": 4})
	assert_int(paths.size()).is_equal(4)


func test_carve_spacing_separa_nacimientos() -> void:
	var topo := _make_topology(30, 30)
	var paths := RiverCarver.carve(topo, SeededRng.new(3), {"river_count": 5, "river_spacing": 6})
	assert_int(paths.size()).is_equal(5)
	for i in paths.size():
		for j in paths.size():
			if i != j:
				assert_int(topo.distance(paths[i][0], paths[j][0])).is_greater_equal(6)


func test_carve_limita_largo_del_camino() -> void:
	var topo := _make_topology(20, 20)
	var paths := RiverCarver.carve(topo, SeededRng.new(9), {"river_count": 3})
	for path in paths:
		assert_int(path.size()).is_greater_equal(2)
		assert_int(path.size()).is_less_equal(RiverCarver.RIVER_LENGTH_MAX + 1)


func test_carve_no_repite_celdas_dentro_del_camino() -> void:
	var topo := _make_topology(20, 20)
	var paths := RiverCarver.carve(topo, SeededRng.new(11))
	for path in paths:
		var seen := {}
		for coord in path:
			assert_bool(seen.has(coord)).is_false()
			seen[coord] = true


func test_carve_con_sesgos_sigue_determinista() -> void:
	var topo_a := _make_topology(20, 20)
	var topo_b := _make_topology(20, 20)
	var params := {"river_count": 3, "river_downhill_bias": 0.8, "river_straightness": 0.5}
	RiverCarver.carve(topo_a, SeededRng.new(5), params)
	RiverCarver.carve(topo_b, SeededRng.new(5), params)
	assert_int(topo_b.edge_count()).is_equal(topo_a.edge_count())


func test_carve_ignora_el_rng_global() -> void:
	seed(12345)
	var expected := randi()
	seed(12345)
	var topo := _make_topology(15, 15)
	RiverCarver.carve(topo, SeededRng.new(2), {"river_count": 3})
	assert_int(randi()).is_equal(expected)
