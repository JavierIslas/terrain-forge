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

class_name GridTopology
extends RefCounted
## Puerto de topología: el contrato que consume el motor de generación.
##
## Toda topología (cuadrados, hex del anfitrión, o una propia del usuario)
## extiende esta clase y sobrescribe los métodos. Los defaults fallan con
## push_error y retornan valores neutros, de modo que una topología incompleta
## se detecta en el primer uso en vez de corromper la generación.
##
## Contrato de vecinos: get_neighbors() retorna candidatos SIN filtrar por
## validez; el consumidor filtra con is_valid(). Es el mismo contrato implícito
## del anfitrión y evita esconder el costo del filtrado en el hot path.


## Retorna los vecinos de [param coord] como coordenadas candidatas (pueden
## caer fuera del grid; filtrar con is_valid).
func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	_require_override("get_neighbors")
	return []


## Retorna true si [param coord] existe en el grid.
func is_valid(coord: Vector2i) -> bool:
	_require_override("is_valid")
	return false


## Distancia topológica entre [param a] y [param b] (métrica de la topología:
## hex del anfitrión, Manhattan, Chebyshev, ...). Debe ser consistente con
## get_neighbors() para que spacing y conectividad sean correctos.
func distance(a: Vector2i, b: Vector2i) -> int:
	_require_override("distance")
	return 0


## Camino de celdas de [param a] a [param b], extremos incluidos. Usado por
## rectitud de ríos y corredores de reparación de conectividad.
## El camino puede incluir celdas FUERA del grid (el redondeo de la
## interpolación puede salirse del rectángulo aunque los extremos sean
## válidos): el consumidor filtra con is_valid() y puentea los huecos —
## mismo contrato de candidatos sin filtrar que get_neighbors().
func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	_require_override("line")
	return []


## Todas las coordenadas del grid en orden row-major determinista
## (y ascendente, x ascendente dentro de cada fila).
func get_all_coords() -> Array[Vector2i]:
	_require_override("get_all_coords")
	return []


## Dimensiones del grid en celdas (rectángulo envolvente).
func get_dimensions() -> Vector2i:
	_require_override("get_dimensions")
	return Vector2i.ZERO


## Cantidad total de celdas válidas.
func cell_count() -> int:
	_require_override("cell_count")
	return 0


## Terreno de [param coord]; -1 si no es consultable.
func get_terrain(coord: Vector2i) -> int:
	_require_override("get_terrain")
	return -1


## Asigna el terreno de [param coord]. Sin efecto si la coordenada no existe.
## Las topologías que materializan sobre un grid con caches de costos deben
## invalidarlos aquí (nunca escribir el campo de la celda por fuera).
func set_terrain(coord: Vector2i, terrain: int) -> void:
	_require_override("set_terrain")


## Elevación de [param coord]; 0.0 si no es consultable.
func get_elevation(coord: Vector2i) -> float:
	_require_override("get_elevation")
	return 0.0


## Asigna la elevación de [param coord].
func set_elevation(coord: Vector2i, elevation: float) -> void:
	_require_override("set_elevation")


## Marca [param coord] como location del tipo [param location_type] (> 0).
func set_location(coord: Vector2i, location_type: int) -> void:
	_require_override("set_location")


## Retorna true si [param coord] tiene una location asignada.
func has_location(coord: Vector2i) -> bool:
	_require_override("has_location")
	return false


## Define un edge del tipo [param edge_type] entre [param a] y [param b].
func set_edge(a: Vector2i, b: Vector2i, edge_type: int) -> void:
	_require_override("set_edge")


## Cantidad de edges definidos (ancla determinista de derivación de seeds).
func edge_count() -> int:
	_require_override("edge_count")
	return 0


## Elimina todos los edges del tipo [param edge_type] y retorna cuántos eran.
## Semántica de regeneración: los stages que materializan edges limpian los
## previos del mismo tipo antes de escribir los nuevos.
func clear_edges(edge_type: int) -> int:
	_require_override("clear_edges")
	return 0


func _require_override(method_name: String) -> void:
	push_error("GridTopology: '%s' debe ser sobrescrito por la topología concreta" % method_name)
