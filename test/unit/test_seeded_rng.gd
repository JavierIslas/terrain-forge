class_name TestSeededRng
extends GdUnitTestSuite
## Contrato de SeededRng: determinismo, derivación splitmix64 y aislamiento
## del RNG global.


const CANONICAL_SALT := 7919


func test_derive_seed_matchea_vector_canonico_de_splitmix64() -> void:
	## splitmix64 con estado 0 → primer output 0xE220A8397B1DCDAF
	## (representado como int64 firmado).
	assert_int(SeededRng.derive_seed(0, 0)).is_equal(-2152535657050944081)


func test_derive_seed_es_determinista() -> void:
	assert_int(SeededRng.derive_seed(42, CANONICAL_SALT)).is_equal(-617814143380232287)
	assert_int(SeededRng.derive_seed(42, CANONICAL_SALT)).is_equal(SeededRng.derive_seed(42, CANONICAL_SALT))


func test_derive_seed_difiere_por_salt_y_por_master() -> void:
	assert_int(SeededRng.derive_seed(42, 7919)).is_not_equal(SeededRng.derive_seed(42, 104729))
	assert_int(SeededRng.derive_seed(1, 0)).is_not_equal(SeededRng.derive_seed(2, 0))


func test_stream_derivado_es_determinista() -> void:
	var a := SeededRng.new(42).derive_stream(CANONICAL_SALT)
	var b := SeededRng.new(42).derive_stream(CANONICAL_SALT)
	for i in 10:
		assert_int(a.randi_range(0, 1000000)).is_equal(b.randi_range(0, 1000000))


func test_shuffled_es_determinista_con_mismo_seed() -> void:
	var items: Array = range(20)
	var a := SeededRng.new(7).shuffled(items)
	var b := SeededRng.new(7).shuffled(items)
	assert_array(a).is_equal(b)


func test_shuffled_ignora_el_seed_del_rng_global() -> void:
	## Regresión del gotcha de GDScript: una llamada no calificada a
	## randi_range dentro de SeededRng resolvía a la función global de Godot,
	## haciendo que el barajado dependiera del RNG global y no del seed propio.
	var items: Array = range(20)
	seed(1)
	var a := SeededRng.new(7).shuffled(items)
	seed(2)
	var b := SeededRng.new(7).shuffled(items)
	assert_array(a).is_equal(b)


func test_shuffled_no_muta_el_original() -> void:
	var items: Array = range(10)
	var before := items.duplicate()
	SeededRng.new(7).shuffled(items)
	assert_array(items).is_equal(before)


func test_shuffled_preserva_elementos() -> void:
	var items: Array = range(30)
	var shuffled := SeededRng.new(9).shuffled(items)
	assert_int(shuffled.size()).is_equal(items.size())
	var sorted_copy := shuffled.duplicate()
	sorted_copy.sort()
	assert_array(sorted_copy).is_equal(items)


func test_shuffled_cambia_el_orden_con_otros_seeds() -> void:
	var items: Array = range(30)
	var a := SeededRng.new(1).shuffled(items)
	var b := SeededRng.new(2).shuffled(items)
	assert_array(a).is_not_equal(b)


func test_randi_range_respecta_limites() -> void:
	var rng := SeededRng.new(3)
	for i in 100:
		var value := rng.randi_range(-5, 5)
		assert_bool(value >= -5 and value <= 5).is_true()


func test_pick_devuelve_elemento_o_null() -> void:
	var rng := SeededRng.new(5)
	var items: Array = [10, 20, 30]
	for i in 20:
		assert_bool(rng.pick(items) in items).is_true()
	assert_object(rng.pick([])).is_null()


func test_no_consume_el_rng_global() -> void:
	## Regresión ejecutable de la clase de bug de scatter_locations: ninguna
	## operación del addon puede avanzar el RNG global de Godot.
	seed(987654321)
	var expected_first := randi()
	var expected_second := randi()
	seed(987654321)
	var rng := SeededRng.new(77)
	rng.randi_range(0, 100)
	rng.shuffled(range(50))
	rng.pick([1, 2, 3])
	assert_int(randi()).is_equal(expected_first)
	assert_int(randi()).is_equal(expected_second)
