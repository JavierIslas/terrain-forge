# Terrain Forge
# Copyright (C) 2026 Javier Islas
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version. This program is distributed WITHOUT ANY WARRANTY; see the GNU
# AGPL for details: <https://www.gnu.org/licenses/>.
#
# A commercial license that exempts you from the AGPL is available: see
# LICENSE_COMMERCIAL.md or contact islasjavieralf@gmail.com.

class_name TerrainForge
extends RefCounted
## Motor de generación: pipeline de stages sobre cualquier GridTopology.
##
## Todo estático y sin estado compartido: cada generate() construye su propio
## contexto (rng maestro + buffers packed) y corre la lista de stages.
## "Inject behavior, don't subclass": la key "stages" acepta un Array mixto de
## nombres built-in (STAGE_*) y Callables custom (topology, ctx) -> void.
##
## ctx (Dictionary que reciben los stages custom):
##   master: SeededRng maestro | params: Dictionary | profile: BiomeProfile
##   width/height: int | heights: PackedFloat32Array (row-major)
##   moisture: PackedFloat32Array (row-major, vacía si no se sampleó)
##   report: Dictionary (seed, stages_run, ...)

## Salts de derivación por stage (splitmix64 sobre el seed maestro).
## El stage de elevación NO deriva: usa el seed maestro crudo para mantener
## paridad bit a bit con el generador del anfitrión (mismo seed → mismo mapa
## base). RIVERS/LOCATIONS mantienen los offsets del anfitrión por cultura.
const SALT_MOISTURE := 0x4D4F49
const SALT_RIVERS := 7919
const SALT_LOCATIONS := 104729

const STAGE_ELEVATION := "elevation"
const STAGE_MOISTURE := "moisture"
const STAGE_FALLOFF := "falloff"
const STAGE_CLASSIFY := "classify"
const STAGE_SMOOTH := "smooth"
const STAGE_RIVERS := "rivers"
const STAGE_LOCATIONS := "locations"
const STAGE_CONNECTIVITY := "connectivity"

## Pipeline por defecto (los ríos corren con river_count default; locations
## son no-op salvo location_count > 0; conectividad reporta por defecto).
const STAGES_DEFAULT: Array = [STAGE_ELEVATION, STAGE_MOISTURE, STAGE_FALLOFF, STAGE_CLASSIFY, STAGE_SMOOTH, STAGE_RIVERS, STAGE_LOCATIONS, STAGE_CONNECTIVITY]


## Genera sobre [param topology] con [param params] y retorna la topología
## (flujo cómodo). Para el reporte usar generate_with_report().
static func generate(topology: GridTopology, params: Dictionary = {}) -> GridTopology:
	generate_with_report(topology, params)
	return topology


## Igual que generate() pero retorna el report del run (seed, stages_run,
## stats, snapshot, river_paths, locations, connectivity, ...).
static func generate_with_report(topology: GridTopology, params: Dictionary = {}) -> Dictionary:
	var ctx := _build_context(topology, params)
	if topology.cell_count() == 0:
		push_error("TerrainForge: la topología no tiene celdas (¿falta generate_cells()?)")
		return ctx.report
	var stages: Array = params.get("stages", STAGES_DEFAULT)
	for stage in stages:
		_run_stage(stage, topology, ctx)
	ctx.report.stats = MapStats.distribution_report(topology)
	ctx.report.snapshot = _build_snapshot(topology, ctx)
	return ctx.report


## Re-materializa un snapshot (de report.snapshot) sobre cualquier topología
## con las MISMAS dimensiones. Estado final completo: terrenos (post
## smoothing), elevación, ríos y locations (los RIVER previos se limpian).
## Falla con push_error si las dimensiones no coinciden, sin tocar la topología.
static func apply_snapshot(topology: GridTopology, snapshot: Dictionary) -> void:
	if topology.get_dimensions() != Vector2i(snapshot.width, snapshot.height):
		push_error("TerrainForge.apply_snapshot: dimensiones %s != snapshot %s" % [
			topology.get_dimensions(), Vector2i(snapshot.width, snapshot.height)])
		return
	var classes: PackedInt32Array = snapshot.terrain_classes
	if classes.size() != topology.cell_count():
		push_error("TerrainForge.apply_snapshot: snapshot tiene %d clases para %d celdas" % [
			classes.size(), topology.cell_count()])
		return
	var heights: PackedFloat32Array = snapshot.heights
	var scale: float = snapshot.elevation_scale
	var cursor := 0
	for coord in topology.get_all_coords():
		topology.set_terrain(coord, classes[cursor])
		topology.set_elevation(coord, heights[coord.y * int(snapshot.width) + coord.x] * scale)
		cursor += 1
	topology.clear_edges(SquareGrid.EdgeType.RIVER)
	for path in snapshot.river_paths:
		for j in path.size() - 1:
			topology.set_edge(path[j], path[j + 1], SquareGrid.EdgeType.RIVER)
	for coord in topology.get_all_coords():
		topology.set_location(coord, 0)
	for coord in snapshot.locations:
		topology.set_location(coord, int(snapshot.get("location_type", 1)))


## Preset de params listo para mergear/override:
## "pangaea" | "archipelago" | "highlands". Desconocido → push_error + {}.
static func preset(name: String) -> Dictionary:
	match name:
		"pangaea":
			return {"biome": "continent", "island_falloff": 0.45}
		"archipelago":
			return {"biome": "archipelago", "island_falloff": 0.2}
		"highlands":
			return {"biome": "highlands"}
	push_error("TerrainForge: preset desconocido '%s'" % name)
	return {}


static func _build_context(topology: GridTopology, params: Dictionary) -> Dictionary:
	var requested_seed: int = int(params.get("seed", 0))
	var dims := topology.get_dimensions()
	return {
		"master": SeededRng.new(requested_seed),
		"params": params,
		"profile": BiomeProfile.from_params(params),
		"width": dims.x,
		"height": dims.y,
		"heights": PackedFloat32Array(),
		"moisture": PackedFloat32Array(),
		"report": {"seed": requested_seed, "stages_run": []},
	}


static func _run_stage(stage: Variant, topology: GridTopology, ctx: Dictionary) -> void:
	if stage is Callable:
		stage.call(topology, ctx)
		ctx.report["stages_run"].append("custom")
		return
	match str(stage):
		STAGE_ELEVATION:
			_stage_elevation(topology, ctx)
		STAGE_MOISTURE:
			_stage_moisture(topology, ctx)
		STAGE_FALLOFF:
			_stage_falloff(topology, ctx)
		STAGE_CLASSIFY:
			_stage_classify(topology, ctx)
		STAGE_SMOOTH:
			_stage_smooth(topology, ctx)
		STAGE_RIVERS:
			_stage_rivers(topology, ctx)
		STAGE_LOCATIONS:
			_stage_locations(topology, ctx)
		STAGE_CONNECTIVITY:
			_stage_connectivity(topology, ctx)
		_:
			push_error("TerrainForge: stage desconocido '%s' (posible forwarding a etapas futuras)" % str(stage))
			return
	ctx.report["stages_run"].append(stage)


## Muestrea alturas UNA vez a buffer packed; el resto de los stages lee el
## buffer. El seed del noise ES el seed maestro (paridad con el anfitrión).
static func _stage_elevation(topology: GridTopology, ctx: Dictionary) -> void:
	var master: SeededRng = ctx.master
	var field := NoiseField.create(master.current_seed, ctx.params)
	ctx.heights = field.sample_map(ctx.width, ctx.height)


## Muestrea humedad solo si hay classify_fn (biomas) o la key "moisture" se
## pidió explícitamente — el camino por defecto no paga la pasada extra.
static func _stage_moisture(topology: GridTopology, ctx: Dictionary) -> void:
	var profile: BiomeProfile = ctx.profile
	if not profile.classify_fn.is_valid() and not ctx.params.has("moisture"):
		return
	var master: SeededRng = ctx.master
	var field := NoiseField.create(SeededRng.derive_seed(master.current_seed, SALT_MOISTURE), {"frequency": ctx.params.get("moisture_frequency", 0.05)})
	ctx.moisture = field.sample_map(ctx.width, ctx.height)


## Falloff radial de isla: resta hasta "island_falloff" según la distancia
## normalizada al centro (0 en el centro, 1 en las esquinas). 0.0 = no-op.
static func _stage_falloff(topology: GridTopology, ctx: Dictionary) -> void:
	var strength: float = float(ctx.params.get("island_falloff", 0.0))
	if strength <= 0.0:
		return
	if not _has_heights(ctx):
		push_error("TerrainForge: el stage falloff requiere STAGE_ELEVATION antes (buffer de alturas vacío)")
		return
	ctx.heights = apply_falloff(ctx.heights, ctx.width, ctx.height, strength, float(ctx.params.get("island_falloff_power", 2.0)))


## Clasifica el buffer de alturas (+ humedad si existe) a terrenos y escribe
## terreno y elevación a través del puerto (respetando caches de la topología).
static func _stage_classify(topology: GridTopology, ctx: Dictionary) -> void:
	if not _has_heights(ctx):
		push_error("TerrainForge: el stage classify requiere STAGE_ELEVATION antes (buffer de alturas vacío)")
		return
	var profile: BiomeProfile = ctx.profile
	var classes := TerrainClassifier.classify_buffer(ctx.heights, profile, ctx.moisture)
	for y in ctx.height:
		for x in ctx.width:
			var coord := Vector2i(x, y)
			var index: int = y * ctx.width + x
			topology.set_terrain(coord, classes[index])
			topology.set_elevation(coord, ctx.heights[index] * profile.elevation_scale)


## Los stages con buffer requieren que elevation haya corrido en este run.
static func _has_heights(ctx: Dictionary) -> bool:
	return ctx.heights.size() >= int(ctx.width) * int(ctx.height)


## Suavizado por mayoría; "smoothing_passes" (default 0 = no-op).
static func _stage_smooth(topology: GridTopology, ctx: Dictionary) -> void:
	TerrainClassifier.apply_smoothing(topology, int(ctx.params.get("smoothing_passes", 0)))


## Ríos con stream derivado SALT_RIVERS; los caminos van al report.
## Semántica de regeneración: los edges RIVER previos se limpian antes de
## tallar, así apply() sobre un grid usado no deja ríos huérfanos del seed
## anterior (y los costos de pathfinding quedan consistentes con el mapa).
static func _stage_rivers(topology: GridTopology, ctx: Dictionary) -> void:
	topology.clear_edges(SquareGrid.EdgeType.RIVER)
	var rng: SeededRng = (ctx.master as SeededRng).derive_stream(SALT_RIVERS)
	ctx.report.river_paths = RiverCarver.carve(topology, rng, ctx.params)


## Locations con stream derivado SALT_LOCATIONS; las coords van al report.
## Semántica de regeneración: las locations previas se resetean antes de
## colocar, para que mismo seed + mismos params → mismo estado final aunque
## la topología ya tuviera locations (LocationPlacer.place es incremental).
static func _stage_locations(topology: GridTopology, ctx: Dictionary) -> void:
	for coord in topology.get_all_coords():
		if topology.has_location(coord):
			topology.set_location(coord, 0)
	var rng: SeededRng = (ctx.master as SeededRng).derive_stream(SALT_LOCATIONS)
	ctx.report.locations = LocationPlacer.place(topology, rng, ctx.params)
	ctx.report.location_type = int(ctx.params.get("location_type", 1))


## Estado final serializable: clases de terreno POST-smoothing + alturas +
## ríos + locations. Re-materializable con apply_snapshot() en cualquier
## topología de las mismas dimensiones (hex o cuadrados). Las clases se
## indexan SECUENCIALMENTE sobre get_all_coords() (soporta topologías no
## rectangulares); las alturas mantienen el índice row-major del rectángulo.
static func _build_snapshot(topology: GridTopology, ctx: Dictionary) -> Dictionary:
	var classes := PackedInt32Array()
	classes.resize(topology.cell_count())
	var cursor := 0
	for coord in topology.get_all_coords():
		classes[cursor] = topology.get_terrain(coord)
		cursor += 1
	return {
		"seed": ctx.report.seed,
		"width": ctx.width,
		"height": ctx.height,
		"heights": ctx.heights,
		"terrain_classes": classes,
		"elevation_scale": (ctx.profile as BiomeProfile).elevation_scale,
		"river_paths": ctx.report.get("river_paths", []),
		"locations": ctx.report.get("locations", []),
		"location_type": ctx.report.get("location_type", 1),
	}


## Conectividad: "connectivity_mode" "report" (default) | "repair".
static func _stage_connectivity(topology: GridTopology, ctx: Dictionary) -> void:
	var mode := str(ctx.params.get("connectivity_mode", ConnectivityChecker.MODE_REPORT))
	if mode == ConnectivityChecker.MODE_REPAIR:
		ctx.report.connectivity = ConnectivityChecker.repair(topology)
	elif mode == ConnectivityChecker.MODE_REPORT:
		ctx.report.connectivity = ConnectivityChecker.analyze(topology)
	else:
		push_error("TerrainForge: connectivity_mode desconocido '%s'" % mode)


## Falloff radial puro sobre un buffer (row-major): d = distancia normalizada
## al centro [0..1]; heights[i] -= strength * d^power. Función pura testeable.
static func apply_falloff(heights: PackedFloat32Array, map_width: int, map_height: int, strength: float, falloff_power: float = 2.0) -> PackedFloat32Array:
	var result := heights.duplicate()
	var center_x := (float(map_width) - 1.0) / 2.0
	var center_y := (float(map_height) - 1.0) / 2.0
	# Distancia máxima (del centro a una esquina) para normalizar a [0..1].
	var max_distance := sqrt(center_x * center_x + center_y * center_y)
	if max_distance <= 0.0:
		return result
	for y in map_height:
		for x in map_width:
			var dx := float(x) - center_x
			var dy := float(y) - center_y
			var normalized := sqrt(dx * dx + dy * dy) / max_distance
			result[y * map_width + x] = heights[y * map_width + x] - strength * pow(normalized, falloff_power)
	return result
