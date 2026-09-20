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

class_name NoiseField
extends RefCounted
## Muestreo de noise con paridad exacta con el generador del anfitrión.
##
## Los defaults replican la configuración implícita que el anfitrión deja en
## FastNoiseLite (SIMPLEX_SMOOTH, frequency 0.08, FBM de 5 octavas): con esos
## defaults y el mismo seed el muestreo es bit a bit idéntico, congelado por
## test. Las mejoras (octaves, gain, lacunarity, domain warp) entran como
## params opcionales y no alteran el camino por defecto.

## Escala del sampling: coordenadas normalizadas al tamaño del mapa × escala.
const NOISE_SCALE := 100.0

var _noise := FastNoiseLite.new()


## Fábrica con configuración desde params:
## "noise_type" (int), "frequency" (0.08), "octaves" (5), "fractal_gain" (0.5),
## "lacunarity" (2.0), "domain_warp" (0.0 = desactivado; > 0 lo activa con esa
## amplitud), "domain_warp_frequency" (0.05).
static func create(seed_value: int, params: Dictionary = {}) -> NoiseField:
	var field := NoiseField.new()
	field._configure(seed_value, params)
	return field


## Valor de noise en [param coord], normalizado por las dimensiones del mapa
## (mismo mapeo que el anfitrión: x/map_width × NOISE_SCALE).
func sample_at(coord: Vector2i, map_width: int, map_height: int) -> float:
	var nx := float(coord.x) / float(map_width)
	var ny := float(coord.y) / float(map_height)
	return _noise.get_noise_2d(nx * NOISE_SCALE, ny * NOISE_SCALE)


## Buffer packed de todo el mapa en orden row-major (una sola pasada; el resto
## de los stages lee el buffer, no re-muestrea).
func sample_map(map_width: int, map_height: int) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(map_width * map_height)
	for y in map_height:
		for x in map_width:
			heights[y * map_width + x] = sample_at(Vector2i(x, y), map_width, map_height)
	return heights


func _configure(seed_value: int, params: Dictionary) -> void:
	_noise.seed = seed_value
	_noise.noise_type = params.get("noise_type", FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_noise.frequency = params.get("frequency", 0.08)
	_noise.fractal_octaves = params.get("octaves", 5)
	_noise.fractal_gain = params.get("fractal_gain", 0.5)
	_noise.fractal_lacunarity = params.get("lacunarity", 2.0)
	var warp_strength: float = params.get("domain_warp", 0.0)
	if warp_strength > 0.0:
		_noise.domain_warp_enabled = true
		_noise.domain_warp_amplitude = warp_strength
		_noise.domain_warp_frequency = params.get("domain_warp_frequency", 0.05)
