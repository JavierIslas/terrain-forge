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

class_name GridSearch
extends RefCounted
## Búsqueda de caminos y alcance sobre cualquier GridTopology.
##
## Dijkstra y A* con heap de orden total (cost, x, y): el orden de settle y
## los parents son únicos, así el resultado es exactamente determinista sin
## depender del orden de get_neighbors() (el mismo esquema del trazado de
## caminos del forge). El costo por paso espeja al anfitrión: entrar a una
## celda cuesta get_movement_cost(destino) + get_edge_cost(origen, destino);
## la pasabilidad solo la decide el terreno (un edge caro encarece el paso,
## nunca lo bloquea). Read-only sobre la topología: no muta celdas ni edges,
## así que regenerar el mapa entre llamadas es seguro.
##
## find_path/find_path_astar devuelven el camino con AMBOS extremos (misma
## convención que topology.line()); el buscador del anfitrión omite el origen.
##
## params (diccionario plano del motor, igual que los stages):
##   "cost_fn"     (from, to) -> float — reemplaza el modelo aditivo.
##   "passable_fn" (coord) -> bool — reemplaza is_passable del puerto.
##   "reachable"   Dictionary — restringe la búsqueda a un set previo (p. ej.
##                 la salida de find_reachable); si viene, reemplaza el
##                 filtro de pasabilidad, igual que en el anfitrión.


## Celdas alcanzables desde [param origin] con costo acumulado <= [param
## max_cost] (las que cuestan exactamente el presupuesto quedan incluidas).
## Retorna Dictionary[Vector2i, float] con el origen a 0.0; {} si el origen
## no existe o el presupuesto es negativo.
static func find_reachable(topology: GridTopology, origin: Vector2i, max_cost: float, params: Dictionary = {}) -> Dictionary:
	if topology == null or not topology.is_valid(origin) or max_cost < 0.0:
		return {}
	var cost_fn := _resolve_cost_fn(topology, params)
	var neighbor_ok := _resolve_neighbor_filter(topology, params)
	var dist := {origin: 0.0}
	var heap: Array = []
	_heap_push(heap, 0.0, origin)
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var coord: Vector2i = entry[1]
		var cost: float = entry[0]
		if cost > dist.get(coord, INF):
			continue
		for neighbor in topology.get_neighbors(coord):
			if not neighbor_ok.call(coord, neighbor):
				continue
			var new_cost: float = cost + cost_fn.call(coord, neighbor)
			if new_cost > max_cost:
				continue
			if not dist.has(neighbor) or new_cost < dist[neighbor]:
				dist[neighbor] = new_cost
				_heap_push(heap, new_cost, neighbor)
	return dist


## Camino óptimo de [param origin] a [param target] por Dijkstra, extremos
## incluidos; [] si es inalcanzable, el destino es intransitable o los
## argumentos son inválidos.
static func find_path(topology: GridTopology, origin: Vector2i, target: Vector2i, params: Dictionary = {}) -> Array[Vector2i]:
	return _search_path(topology, origin, target, params, Callable())


## Como find_path pero con A*: heurística topology.distance escalada por el
## costo de terreno pasable más barato del grid (admisible salvo mapas
## dominados por edges que abaratan, heredado del diseño del anfitrión).
## Más rápido que find_path en mapas grandes; ante la duda, find_path es la
## referencia óptima.
static func find_path_astar(topology: GridTopology, origin: Vector2i, target: Vector2i, params: Dictionary = {}) -> Array[Vector2i]:
	var min_cost := _min_passable_cost(topology)
	var heuristic := func(coord: Vector2i) -> float:
		return float(topology.distance(coord, target)) * min_cost
	return _search_path(topology, origin, target, params, heuristic)


## Núcleo de find_path/find_path_astar: solo difieren en la prioridad del
## heap (g puro vs g + heurística). Validación espejo del anfitrión: sin
## reachable se exige destino válido y transitable; con reachable, básica.
static func _search_path(topology: GridTopology, origin: Vector2i, target: Vector2i, params: Dictionary, heuristic: Callable) -> Array[Vector2i]:
	if topology == null or not topology.is_valid(origin) or origin == target:
		return []
	var reachable: Dictionary = params.get("reachable", {})
	if reachable.is_empty() and not _target_ok(topology, target, params):
		return []
	var cost_fn := _resolve_cost_fn(topology, params)
	var neighbor_ok := _resolve_neighbor_filter(topology, params)
	var dist := {origin: 0.0}
	var parent := {}
	var heap: Array = []
	_heap_push(heap, _priority(heuristic, origin, 0.0), origin)
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var coord: Vector2i = entry[1]
		if entry[0] > _priority(heuristic, coord, dist.get(coord, INF)):
			continue
		if coord == target:
			break
		for neighbor in topology.get_neighbors(coord):
			if not neighbor_ok.call(coord, neighbor):
				continue
			var new_cost: float = dist[coord] + cost_fn.call(coord, neighbor)
			if not dist.has(neighbor) or new_cost < dist[neighbor]:
				dist[neighbor] = new_cost
				parent[neighbor] = coord
				_heap_push(heap, _priority(heuristic, neighbor, new_cost), neighbor)
	return _reconstruct_path(parent, origin, target)


## Prioridad de heap: g puro (Dijkstra) o g + heurística (A*).
static func _priority(heuristic: Callable, coord: Vector2i, cost: float) -> float:
	if heuristic.is_valid():
		return cost + heuristic.call(coord)
	return cost


## El destino debe existir y ser transitable bajo el filtro vigente: un set
## reachable ya codifica la pasabilidad; con passable_fn inyectada manda ella
## (permite destinos que el puerto declara intransitables, p. ej. puentes).
static func _target_ok(topology: GridTopology, target: Vector2i, params: Dictionary) -> bool:
	if not topology.is_valid(target):
		return false
	var injected: Callable = params.get("passable_fn", Callable())
	if injected.is_valid():
		return injected.call(target)
	return topology.is_passable(target)


## Modelo aditivo del puerto con clamp >= 0 (pesos negativos romperían el
## heap mínimo); con las tablas congeladas el clamp nunca dispara.
static func _resolve_cost_fn(topology: GridTopology, params: Dictionary) -> Callable:
	var injected: Callable = params.get("cost_fn", Callable())
	if injected.is_valid():
		return injected
	return func(from: Vector2i, to: Vector2i) -> float:
		return maxf(0.0, topology.get_movement_cost(to) + topology.get_edge_cost(from, to))


## Precedencia espejo del anfitrión: un set reachable reemplaza el filtro de
## pasabilidad (ya la codifica); sin él, passable_fn inyectada o el puerto.
## El is_valid se aplica siempre: get_neighbors devuelve candidatos crudos.
static func _resolve_neighbor_filter(topology: GridTopology, params: Dictionary) -> Callable:
	var reachable: Dictionary = params.get("reachable", {})
	if not reachable.is_empty():
		return func(_from: Vector2i, to: Vector2i) -> bool:
			return topology.is_valid(to) and reachable.has(to)
	var injected: Callable = params.get("passable_fn", Callable())
	if injected.is_valid():
		return func(_from: Vector2i, to: Vector2i) -> bool:
			return topology.is_valid(to) and injected.call(to)
	return func(_from: Vector2i, to: Vector2i) -> bool:
		return topology.is_valid(to) and topology.is_passable(to)


## Mínimo costo de terreno pasable presente en el grid (escala de la
## heurística de A*); 1.0 si no hay celdas pasables. Sin cache: la topología
## puede cambiar entre llamadas.
static func _min_passable_cost(topology: GridTopology) -> float:
	var min_cost := INF
	for coord in topology.get_all_coords():
		var cost: float = topology.get_movement_cost(coord)
		if cost > 0.0 and cost < min_cost:
			min_cost = cost
	return 1.0 if min_cost == INF else min_cost


## Reconstruye el camino [origin..target] desde los parents; [] si el target
## nunca fue alcanzado.
static func _reconstruct_path(parent: Dictionary, origin: Vector2i, target: Vector2i) -> Array[Vector2i]:
	if not parent.has(target):
		return []
	var path: Array[Vector2i] = [target]
	var cursor := target
	while cursor != origin:
		cursor = parent[cursor]
		path.append(cursor)
	path.reverse()
	return path


# --- Heap binario mínimo con orden total (cost, x, y) ---
# El desempate por coordenadas hace el resultado independiente del orden de
# get_neighbors(): mismo esquema que el trazado de caminos del forge.

static func _heap_push(heap: Array, cost: float, coord: Vector2i) -> void:
	heap.append([cost, coord])
	var index := heap.size() - 1
	while index > 0:
		var parent_index := (index - 1) / 2
		if not _heap_entry_less(heap[index], heap[parent_index]):
			break
		var swapped = heap[index]
		heap[index] = heap[parent_index]
		heap[parent_index] = swapped
		index = parent_index


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	heap[0] = heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	var index := 0
	while true:
		var smallest := index
		var left := 2 * index + 1
		var right := 2 * index + 2
		if left < heap.size() and _heap_entry_less(heap[left], heap[smallest]):
			smallest = left
		if right < heap.size() and _heap_entry_less(heap[right], heap[smallest]):
			smallest = right
		if smallest == index:
			break
		var swapped = heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = swapped
		index = smallest
	return top


static func _heap_entry_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	var ca: Vector2i = a[1]
	var cb: Vector2i = b[1]
	if ca.x != cb.x:
		return ca.x < cb.x
	return ca.y < cb.y
