# Terrain Forge

[![CI](https://github.com/JavierIslas/terrain-forge/actions/workflows/ci.yml/badge.svg)](https://github.com/JavierIslas/terrain-forge/actions/workflows/ci.yml)

Procedural terrain generation for **Godot 4.6 / GDScript** with a **pluggable
grid topology**: generate on **squares** (built-in, zero dependencies), on
**hexagons** (via the FREE tier of
[Hex Strategy Map](https://github.com/JavierIslas/hex-strategy-map)), or on
**any topology you implement** by extending the `GridTopology` port.

Deterministic for a fixed seed end-to-end: nothing consumes Godot's global RNG,
so generating in-editor, in CI or on a server yields the same map bit-for-bit.

> Not a renderer and not a game framework. It is the *generation* layer: it
> writes terrain, elevation, rivers, locations and connectivity into your grid.

## Why this exists

[Hex Strategy Map](https://github.com/JavierIslas/hex-strategy-map)'s
`MapGenerator` is hex-only and lives inside that addon's paid tier. Terrain
Forge extracts generation into its own product with the same output contract on
hex (**bit-for-bit parity** with the host generator, test-frozen — migrating a
game changes which function creates the grid, not the map), plus squares, plus
custom topologies — and an injectable stage pipeline for the improvements the
host never had.

## Features

- Pipeline of injectable stages: `elevation → moisture → falloff → classify →
  smooth → rivers → locations → connectivity` — reorder them, or pass your own
  `Callable` stages.
- **Squares** (4- or 8-connected) with zero host dependencies; **hex** via the
  host's FREE tier only; **custom topologies** by overriding ~16 virtuals on
  `GridTopology`.
- Bit-for-bit terrain parity with the host generator (frozen by test, negative
  seeds included).
- Real determinism: seeded sub-streams derived with splitmix64; the global RNG
  is never touched (guarded by tests, not convention).
- Presets (`pangaea`, `archipelago`, `highlands`), biome profiles and an
  injectable `classify_fn(value, moisture)`.
- fBm control (`octaves`, `gain`, `lacunarity`), domain warping, island falloff,
  majority-vote smoothing.
- Rivers with high-elevation starts and spacing; locations with terrain filters
  and spacing.
- Connectivity report + repair: carves `WATER→PLAINS` corridors so every land
  cell is reachable.
- Serializable snapshots: re-materialize the exact same map on any topology
  with the same dimensions.

## Install

**Godot Asset Library** — search for *Terrain Forge*; files land under
`addons/terrain_forge/`.

**itch.io** — the same code plus a commercial license (see below).

**From source** — copy `addons/terrain_forge/` into your project's `addons/`.

Hex mode additionally needs [Hex Strategy Map](https://github.com/JavierIslas/hex-strategy-map)
— the **FREE tier is enough**; Terrain Forge never touches its PRO modules.

## Quick start

Squares (standalone):

```gdscript
var grid := SquareGrid.new(40, 30)
grid.generate_cells()
var topology := SquareTopology.new(grid)          # SquareTopology.new(grid, 8) for 8-dir
TerrainForge.generate(topology, {"seed": 42, "smoothing_passes": 1,
    "river_count": 3, "location_count": 5, "location_spacing": 3})
```

Hex (requires Hex Strategy Map, FREE tier):

```gdscript
var grid = HexTopology.generate_hex(40, 30, {"seed": 42})
# grid IS a HexGrid: feed it to HexRenderer, FogOfWar, PathFinder — the whole
# host stack works unchanged.
```

Full parameter table and the port contract: [`addons/terrain_forge/docs/api_reference.md`](addons/terrain_forge/docs/api_reference.md).
Guided examples: `addons/terrain_forge/examples/` (interactive hex/square demo
and a standalone squares demo).

## Determinism & parity

- All randomness flows through `SeededRng` (local `RandomNumberGenerator` +
  splitmix64 stream derivation). A regression test runs the full pipeline and
  asserts Godot's global RNG sequence is untouched.
- With default terrain params, the same `seed` produces exactly the same
  terrain and elevation as the host's `MapGenerator.generate_noise_terrain`
  (bit-for-bit, test-frozen against an embedded reference of the host
  algorithm, pinned to hex-strategy-map v2.x).
- Regeneration is idempotent: regenerating with the same seed reproduces the
  exact same final state — no accumulated rivers or orphan edges.

## Testing

Tests run under [gdUnit4](https://github.com/MikeSchulze/gdUnit4) in `test/unit/`
(115 test cases, 12 suites):

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    -a res://test/unit --ignoreHeadlessMode -c
```

The hex suites run against a vendored FREE-tier fixture of the host (see
`addons/hex_strategy_map/VENDORED.md`); `map_generator.gd` (PRO) is
intentionally absent — parity uses an embedded reference.

### Continuous integration

Every push to `main` and every pull request runs an editor pass (parse errors
+ class cache) and the full gdUnit4 suite on Godot 4.6 headless, failing on
zero collected tests (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

A scheduled job also runs weekly to watch the vendored hex fixture for
upstream drift, opening an issue when the published host diverges from the
pinned copies (see [`.github/workflows/drift.yml`](.github/workflows/drift.yml)).

## License

Terrain Forge is **dual-licensed**:

- **GNU AGPL v3.0** (default, see [`LICENSE`](LICENSE)) — free for open-source
  use. The AGPL is copyleft over a network: if you run Terrain Forge
  server-side as part of a product (e.g. a map generation service), that
  product's source must be released under the AGPL too.
- **Commercial license** (see [`LICENSE_COMMERCIAL.md`](LICENSE_COMMERCIAL.md))
  — exempts you from the AGPL obligations for closed-source projects,
  including server-side use.

For a commercial license: **islasjavieralf@gmail.com** for terms.
