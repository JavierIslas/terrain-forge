class_name TestForgeArchitecture
extends GdUnitTestSuite
## Guard arquitectónico de Terrain Forge.
##
## Convierte las políticas del addon en contratos ejecutables:
## 1. El core no referencia clases del anfitrión (funciona instalado solo).
## 2. Ningún módulo consume el RNG global de Godot (determinismo real).
## 3. Ningún nombre de archivo ni class_name colisiona con el anfitrión
##    (tiers.conf de nombres planos no distingue directorios).
## 4. El plugin está registrado con la estructura esperada.


const ADDON_DIR := "res://addons/terrain_forge"
const HOST_DIR := "res://addons/hex_strategy_map"
## Único archivo autorizado a depender del anfitrión (lazy-load del adaptador hex).
const HOST_AWARE_FILES := ["hex_topology.gd"]
## Tokens prohibidos en el core: ni código ni comentarios — la alineación con
## el anfitrión se documenta en docs/, no en los fuentes.
const FORBIDDEN_HOST_TOKENS := [
	"HexGrid", "HexCell", "MapGenerator", "PathFinder", "FogOfWar",
	"HexRenderer", "res://addons/hex_strategy_map",
]
const FORBIDDEN_RNG_TOKENS := ["randi()", "randf()", "randomize()", ".shuffle("]
## Llamadas que SOLO son legítimas calificadas (rng.randi_range(...)): una
## no calificada resuelve a la función global de Godot (RNG global) — la
## clase exacta de bug corregida en el generador del anfitrión.
const UNQUALIFIED_RNG_CALLS := ["randi_range(", "randf_range("]


# === Estructura del plugin ===

func test_plugin_cfg_declara_plugin() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("%s/plugin.cfg" % ADDON_DIR)
	assert_int(err).is_equal(OK)
	assert_str(str(cfg.get_value("plugin", "name", ""))).is_not_empty()
	assert_str(str(cfg.get_value("plugin", "script", ""))).is_equal("plugin.gd")


func test_plugin_script_tiene_hooks_de_editor() -> void:
	assert_bool(_script_has_method("%s/plugin.gd" % ADDON_DIR, "_enter_tree")).is_true()
	assert_bool(_script_has_method("%s/plugin.gd" % ADDON_DIR, "_exit_tree")).is_true()


func test_project_godot_habilita_terrain_forge() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://project.godot")
	assert_int(err).is_equal(OK)
	var enabled: PackedStringArray = cfg.get_value("editor_plugins", "enabled", PackedStringArray())
	assert_bool("terrain_forge" in enabled).is_true()


# === Pureza del core respecto al anfitrión ===

func test_core_no_referencia_clases_del_anfitrion() -> void:
	for file_name in _list_gd_files(ADDON_DIR):
		if file_name in HOST_AWARE_FILES:
			continue
		var source := _read_source(ADDON_DIR + "/" + file_name)
		for token in FORBIDDEN_HOST_TOKENS:
			assert_bool(source.contains(token)).is_false()


func test_ningun_modulo_consume_rng_global() -> void:
	for file_name in _list_gd_files(ADDON_DIR):
		var source := _read_source(ADDON_DIR + "/" + file_name)
		for token in FORBIDDEN_RNG_TOKENS:
			assert_bool(source.contains(token)).is_false()


func test_ninguna_llamada_no_calificada_a_rng_nativo() -> void:
	## Regresión del gotcha @GlobalScope: randi_range/randf_range sin '.'
	## delante consumen el RNG global aunque la clase defina métodos propios.
	for file_name in _list_gd_files(ADDON_DIR):
		var source := _read_source(ADDON_DIR + "/" + file_name)
		for call_name in UNQUALIFIED_RNG_CALLS:
			assert_bool(_has_unqualified_call(source, call_name)).is_false()


# === No colisiones con el anfitrión ===

func test_ningun_nombre_de_archivo_colisiona_con_anfitrion() -> void:
	var host_files := _list_gd_files(HOST_DIR)
	for file_name in _list_gd_files(ADDON_DIR):
		## plugin.gd es estructural: todo addon necesita el suyo y pack.sh
		## lo maneja por directorio, no por tiers.conf.
		if file_name == "plugin.gd":
			continue
		assert_bool(host_files.has(file_name)).is_false()


func test_ningun_class_name_duplica_anfitrion() -> void:
	var host_classes := _collect_class_names(HOST_DIR)
	for class_name_str in _collect_class_names(ADDON_DIR):
		assert_bool(host_classes.has(class_name_str)).is_false()


# === Alineación de enums con el anfitrión (congelada por contract) ===

func test_terrain_alineado_valor_por_valor_con_anfitrion() -> void:
	for terrain_name in ["ROAD", "PLAINS", "FOREST", "MOUNTAIN", "WATER"]:
		assert_int(MapCell.Terrain[terrain_name]).is_equal(HexCell.Terrain[terrain_name])


func test_edge_types_alineados_con_anfitrion() -> void:
	for edge_name in ["NONE", "RIVER", "ROAD", "WALL", "CUSTOM"]:
		assert_int(SquareGrid.EdgeType[edge_name]).is_equal(HexGrid.EdgeType[edge_name])


# === Helpers ===

func _list_gd_files(dir_path: String) -> PackedStringArray:
	var files := PackedStringArray()
	_collect_gd_files(dir_path, "", files)
	return files


## Recursivo (incluye examples/ y subdirectorios): devuelve paths relativos
## al directorio del addon, porque pack.sh distribuye todo el árbol.
func _collect_gd_files(base_path: String, prefix: String, files: PackedStringArray) -> void:
	var full := base_path if prefix.is_empty() else "%s/%s" % [base_path, prefix]
	var dir := DirAccess.open(full)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var relative := entry if prefix.is_empty() else "%s/%s" % [prefix, entry]
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_gd_files(base_path, relative, files)
		elif entry.ends_with(".gd"):
			files.append(relative)
		entry = dir.get_next()
	dir.list_dir_end()


## true si alguna ocurrencia de call_name NO está precedida por '.' (llamada
## calificada de método) ni por 'func ' (declaración del wrapper propio) —
## la llamada no calificada resuelve a la función de @GlobalScope.
func _has_unqualified_call(source: String, call_name: String) -> bool:
	var search_from := 0
	while true:
		var index := source.find(call_name, search_from)
		if index < 0:
			return false
		var qualified := index > 0 and source[index - 1] == "."
		var declaration := index >= 5 and source.substr(index - 5, 5) == "func "
		if not qualified and not declaration:
			return true
		search_from = index + call_name.length()
	return false


func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var content := f.get_as_text()
	f.close()
	return content


func _script_has_method(path: String, method_name: String) -> bool:
	var script: GDScript = load(path)
	if not script:
		return false
	for m in script.get_script_method_list():
		if m.get("name", "") == method_name:
			return true
	return false


func _collect_class_names(dir_path: String) -> PackedStringArray:
	var names := PackedStringArray()
	for file_name in _list_gd_files(dir_path):
		var source := _read_source(dir_path + "/" + file_name)
		for line in source.split("\n"):
			var trimmed := line.strip_edges()
			if trimmed.begins_with("class_name "):
				names.append(trimmed.get_slice(" ", 1))
	return names
