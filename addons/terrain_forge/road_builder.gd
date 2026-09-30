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

class_name RoadBuilder
extends RefCounted
## Caminos entre locations: árbol de costo mínimo (MST) + trazado por celda
## con Dijkstra que penaliza el agua sin bloquearla (puentes permitidos).
##
## Determinista SIN rng: MST y Dijkstra son función pura de (terreno,
## locations, params); los empates se resuelven por orden (cost, x, y) y orden
## row-major, el mismo sesgo de coordenadas menores que topology.line(). Una
## extensión futura de "road_jitter" opt-in recién ahí derivaría su propio
## stream del seed maestro.

## Penalización extra por ENTRAR a una celda WATER (puente posible).
const ROAD_WATER_COST_DEFAULT := 8.0
## Penalización extra por MOUNTAIN; 0.0 = feature apagada (el camino puede
## cruzar montañas y convertirlas en pasos).
const ROAD_MOUNTAIN_COST_DEFAULT := 0.0


## Conecta TODAS las coords con has_location (las del run y las pre-existentes)
## con caminos de edges ROAD, y retorna:
##   { "road_paths": Array de Array[Vector2i], "road_bridges": int }
## road_bridges cuenta las celdas WATER únicas cruzadas (celdas de puente).
## params: "road_terrain" (true: convertir el terreno del camino a ROAD, salvo
## puentes), "road_water_cost" (8.0), "road_mountain_cost" (0.0).
## [param cost_fn] (coord) -> float reemplaza ambas penalizaciones (costo de
## ENTRAR a la celda; debe ser >= 0 para no romper Dijkstra).
## Parejas inalcanzables (topología desconectada) se saltan sin error.
static func build(topology: GridTopology, params: Dictionary = {}, cost_fn: Callable = Callable()) -> Dictionary:
	var locations := _collect_locations(topology)
	if locations.size() < 2:
		return {"road_paths": [], "road_bridges": 0}
	var cost_of := _resolve_cost_of(topology, params, cost_fn)
	var paths: Array = []
	for pair in _mst_pairs(topology, locations):
		# Trazar TODO sobre el terreno pre-camino (costos estables e
		# independientes del orden); materializar recién al final.
		var path := _trace(topology, pair[0], pair[1], cost_of)
		if path.size() >= 2:
			paths.append(path)
	var road_terrain := bool(params.get("road_terrain", true))
	var bridges := 0
	var bridged := {}
	for path in paths:
		for j in path.size() - 1:
			topology.set_edge(path[j], path[j + 1], SquareGrid.EdgeType.ROAD)
		for coord in path:
			if topology.get_terrain(coord) == MapCell.Terrain.WATER:
				if not bridged.has(coord):
					bridged[coord] = true
					bridges += 1
			elif road_terrain:
				topology.set_terrain(coord, MapCell.Terrain.ROAD)
	return {"road_paths": paths, "road_bridges": bridges}


## Locations en orden row-major de get_all_coords() — determinista y estable
## para los empates del MST. Lee el estado, no el report del run: las
## locations puestas fuera del pipeline también se conectan.
static func _collect_locations(topology: GridTopology) -> Array[Vector2i]:
	var locations: Array[Vector2i] = []
	for coord in topology.get_all_coords():
		if topology.has_location(coord):
			locations.append(coord)
	return locations


## Costo de ENTRAR a una celda: cost_fn inyectable si es válida; si no, 1.0 +
## penalizaciones por terreno. maxf(0.0, ...) en cada penalización: pesos
## negativos romperían Dijkstra.
static func _resolve_cost_of(topology: GridTopology, params: Dictionary, cost_fn: Callable) -> Callable:
	if cost_fn.is_valid():
		return cost_fn
	var water_cost := maxf(0.0, float(params.get("road_water_cost", ROAD_WATER_COST_DEFAULT)))
	var mountain_cost := maxf(0.0, float(params.get("road_mountain_cost", ROAD_MOUNTAIN_COST_DEFAULT)))
	return func(coord: Vector2i) -> float:
		var extra := 0.0
		var terrain := topology.get_terrain(coord)
		if terrain == MapCell.Terrain.WATER:
			extra += water_cost
		elif terrain == MapCell.Terrain.MOUNTAIN:
			extra += mountain_cost
		return 1.0 + extra


## MST por Prim O(L²) (L = locations, típicamente <= decenas): peso =
## topology.distance. Escaneo en orden row-major → en empates gana la primera
## pareja encontrada, sin rng.
static func _mst_pairs(topology: GridTopology, locations: Array[Vector2i]) -> Array:
	var pairs: Array = []
	var connected := {locations[0]: true}
	while connected.size() < locations.size():
		var best_weight := -1
		var best_pair: Array = []
		for a in locations:
			if not connected.has(a):
				continue
			for b in locations:
				if connected.has(b):
					continue
				var weight := topology.distance(a, b)
				if best_weight < 0 or weight < best_weight:
					best_weight = weight
					best_pair = [a, b]
		if best_pair.is_empty():
			break
		connected[best_pair[1]] = true
		pairs.append(best_pair)
	return pairs


## Dijkstra delegado a GridSearch (heap con orden total (cost, x, y):
## determinismo exacto sin depender del orden de get_neighbors). Sin filtro
## de pasabilidad y con destino siempre permitido: los puentes sobre agua son
## parte del diseño de caminos.
## Retorna el camino de a a b (extremos incluidos) o [] si es inalcanzable.
static func _trace(topology: GridTopology, origin: Vector2i, target: Vector2i, cost_of: Callable) -> Array[Vector2i]:
	return GridSearch.find_path(topology, origin, target, {
		"cost_fn": func(_from: Vector2i, to: Vector2i) -> float: return cost_of.call(to),
		"passable_fn": func(_coord: Vector2i) -> bool: return true,
	})
