class_name TestNoiseField
extends GdUnitTestSuite
## Contrato de NoiseField: determinismo por seed y buffer packed del mapa.


func test_sampling_es_determinista_por_seed() -> void:
	var a := NoiseField.create(42)
	var b := NoiseField.create(42)
	for y in 5:
		for x in 7:
			assert_float(a.sample_at(Vector2i(x, y), 7, 5)).is_equal(b.sample_at(Vector2i(x, y), 7, 5))


func test_sampling_difiere_por_seed() -> void:
	var a := NoiseField.create(1)
	var b := NoiseField.create(999)
	var all_equal := true
	for y in 4:
		for x in 4:
			if a.sample_at(Vector2i(x, y), 4, 4) != b.sample_at(Vector2i(x, y), 4, 4):
				all_equal = false
	assert_bool(all_equal).is_false()


func test_sample_map_llena_buffer_del_tamano_del_mapa() -> void:
	var field := NoiseField.create(7)
	var heights := field.sample_map(10, 8)
	assert_int(heights.size()).is_equal(80)
	for i in heights.size():
		assert_bool(absf(heights[i]) <= 1.0).is_true()


func test_sample_map_coincide_con_sample_at() -> void:
	var field := NoiseField.create(3)
	var heights := field.sample_map(6, 4)
	for y in 4:
		for x in 6:
			assert_float(heights[y * 6 + x]).is_equal(field.sample_at(Vector2i(x, y), 6, 4))


func test_domain_warp_cambia_el_resultado_sin_romper_determinismo() -> void:
	var plain := NoiseField.create(5)
	var warped := NoiseField.create(5, {"domain_warp": 40.0})
	var warped_b := NoiseField.create(5, {"domain_warp": 40.0})
	assert_float(warped.sample_at(Vector2i(3, 3), 8, 8)).is_not_equal(plain.sample_at(Vector2i(3, 3), 8, 8))
	assert_float(warped.sample_at(Vector2i(3, 3), 8, 8)).is_equal(warped_b.sample_at(Vector2i(3, 3), 8, 8))


func test_fractal_type_fbm_explicito_es_identico_al_default() -> void:
	## Setear FRACTAL_FBM explícito debe dejar el estado del noise idéntico al
	## default implícito del anfitrión (paridad bit a bit intacta).
	var plain := NoiseField.create(42)
	var fbm := NoiseField.create(42, {"fractal_type": FastNoiseLite.FRACTAL_FBM})
	for y in 5:
		for x in 7:
			assert_float(fbm.sample_at(Vector2i(x, y), 7, 5)).is_equal(plain.sample_at(Vector2i(x, y), 7, 5))


func test_fractal_type_ridged_cambia_salida_y_es_determinista() -> void:
	var ridged := NoiseField.create(42, {"fractal_type": FastNoiseLite.FRACTAL_RIDGED})
	var ridged_b := NoiseField.create(42, {"fractal_type": FastNoiseLite.FRACTAL_RIDGED})
	var plain := NoiseField.create(42)
	assert_float(ridged.sample_at(Vector2i(3, 3), 8, 8)).is_not_equal(plain.sample_at(Vector2i(3, 3), 8, 8))
	assert_float(ridged.sample_at(Vector2i(3, 3), 8, 8)).is_equal(ridged_b.sample_at(Vector2i(3, 3), 8, 8))
