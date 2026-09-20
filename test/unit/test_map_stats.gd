class_name TestMapStats
extends GdUnitTestSuite
## Stats del mapa y snapshot re-materializable.


func _make_topology(map_w: int, int_h: int) -> SquareTopology:
	var grid := SquareGrid.new(map_w, int_h)
	grid.generate_cells()
	return SquareTopology.new(grid)


func test_distribucion_suma_el_total_de_celdas() -> void:
	var topo := _make_topology(8, 6)
	TerrainForge.generate(topo, {"seed": 42})
	var report := MapStats.distribution_report(topo)
	assert_int(report.cell_count).is_equal(48)
	var total := 0
	for terrain in report.counts:
		total += report.counts[terrain]
	assert_int(total).is_equal(48)
	for terrain in report.ratios:
		assert_bool(report.ratios[terrain] >= 0.0 and report.ratios[terrain] <= 1.0).is_true()


func test_report_incluye_stats_y_snapshot() -> void:
	var topo := _make_topology(8, 6)
	var report := TerrainForge.generate_with_report(topo, {"seed": 1})
	assert_bool(report.has("stats")).is_true()
	assert_int(report.stats.cell_count).is_equal(48)
	assert_bool(report.has("snapshot")).is_true()
	assert_int(report.snapshot.width).is_equal(8)
	assert_int(report.snapshot.terrain_classes.size()).is_equal(48)


func test_snapshot_remateraliza_estado_completo() -> void:
	var original := _make_topology(10, 8)
	var params := {"seed": 42, "river_count": 3, "location_count": 4, "smoothing_passes": 1}
	var report := TerrainForge.generate_with_report(original, params)

	var restored := _make_topology(10, 8)
	TerrainForge.apply_snapshot(restored, report.snapshot)

	for coord in original.get_all_coords():
		assert_int(restored.get_terrain(coord)).is_equal(original.get_terrain(coord))
		assert_float(restored.get_elevation(coord)).is_equal(original.get_elevation(coord))
	assert_int(restored.edge_count()).is_equal(original.edge_count())
	var restored_locations := 0
	for coord in restored.get_all_coords():
		if restored.has_location(coord):
			restored_locations += 1
	assert_int(restored_locations).is_equal(4)


func test_snapshot_rechaza_dimensiones_distintas() -> void:
	var original := _make_topology(10, 8)
	var report := TerrainForge.generate_with_report(original, {"seed": 1})
	var otra := _make_topology(6, 6)
	TerrainForge.apply_snapshot(otra, report.snapshot)
	assert_int(otra.get_terrain(Vector2i(0, 0))).is_equal(MapCell.Terrain.PLAINS)


func test_generate_250x250_completa_bajo_presupuesto() -> void:
	## Humo de no-regresión grueso (budget holgado: en idle mide ~2.6s):
	## 62.500 celdas, pipeline completo con ríos y locations. El presupuesto
	## estricto por celda vive en benchmarks, no en la suite unitaria.
	## En CI el budget se relaja: los runners de GitHub son 2-4× más lentos
	## que una máquina idle local y el flake no diría nada del código.
	var topo := _make_topology(250, 250)
	var budget := 8000
	if OS.has_environment("CI"):
		budget = 25000
	var started := Time.get_ticks_msec()
	TerrainForge.generate(topo, {"seed": 42, "river_count": 4, "location_count": 8, "smoothing_passes": 1})
	var elapsed := Time.get_ticks_msec() - started
	assert_int(elapsed).is_less(budget)
