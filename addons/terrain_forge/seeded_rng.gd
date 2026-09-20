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

class_name SeededRng
extends RefCounted
## RNG determinista con derivación de sub-streams por stage vía splitmix64.
##
## Motivación: los helpers globales de aleatoriedad de Godot (shuffle, randi,
## randf, randomize) consumen el RNG GLOBAL, compartido con el juego anfitrión
## y sin reproducibilidad. Todo el addon usa exclusivamente esta clase, de modo
## que la aleatoriedad queda aislada por construcción y el guard arquitectónico
## puede prohibir esos tokens en el fuente.
##
## GOTCHA verificado: una llamada NO calificada a randi_range/randf_range
## dentro de esta clase resuelve a la función de @GlobalScope (RNG global),
## NO al método propio con el mismo nombre. Por eso todo uso interno llama
## `_rng.` directamente.

## Constantes de splitmix64 (referencia canónica de Melissa O'Neill), escritas
## como int64 firmado porque GDScript no acepta literales hex > INT64_MAX.
const _MIX_GAMMA := -7046029254386353131
const _MIX_MUL_1 := -4658895280553007687
const _MIX_MUL_2 := -7723592293110705685

## Seed efectivo de este stream (útil para reportes y snapshots).
var current_seed: int

var _rng := RandomNumberGenerator.new()


func _init(master_seed: int = 0) -> void:
	current_seed = master_seed
	_rng.seed = master_seed


## Deriva un seed de stage: splitmix64(master + salt). La avalancha completa
## de splitmix64 garantiza streams decorrelacionados entre salts contiguos.
## Determinista entre plataformas: solo aritmética entera, nunca hash().
static func derive_seed(master: int, salt: int) -> int:
	var z: int = master + salt + _MIX_GAMMA
	z = (z ^ _ushr(z, 30)) * _MIX_MUL_1
	z = (z ^ _ushr(z, 27)) * _MIX_MUL_2
	return z ^ _ushr(z, 31)


## Nuevo SeededRng independiente derivado de este (uno por stage del pipeline).
func derive_stream(salt: int) -> SeededRng:
	return SeededRng.new(derive_seed(current_seed, salt))


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## Elemento aleatorio de [param items]; null si está vacío.
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]


## Copia barajada (Fisher-Yates) de [param items] — no muta el original.
func shuffled(items: Array) -> Array:
	var copy := items.duplicate()
	for i in range(copy.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swapped: Variant = copy[i]
		copy[i] = copy[j]
		copy[j] = swapped
	return copy


## Shift lógico (sin extensión de signo): el operador >> de GDScript es
## aritmético y splitmix64 opera sobre bits sin signo.
static func _ushr(value: int, bits: int) -> int:
	return (value >> bits) & ((1 << (64 - bits)) - 1)
