# datad

Shared, renderer-agnostic data layer for **Immersive Data Analytics**: mesh vertices (`GeometryVertex`), paths, FITS/CSV readers, and a **canonical plotting model** used by the server and client.

## Canonical plot model (`ida.data.plot`)

- **`PlottableEntity`**: `x,y,z`; `scaleX/Y/Z`; optional `meshPath` (empty ⇒ app uses a default primitive such as a cube); **`PlotColor`** (RGBA); **`PlotRotation`** quaternion **`w, x, y, z`** (identity `1,0,0,0`); velocity `vx,vy,vz`; optional `name` and `attributes` (`KEY=VAL` strings for metadata / network).
- **`PlotIngestResult`**: `entities[]` + **`PlotVariableDisplayState`** (column names, axis indices, etc.) for client axis remapping.

Quaternion layout matches JSON / `EntityData.rotation` in `ida-network-protocol`: four floats in **w, x, y, z** order.

## Generic ingest (`ida.data.ingest`, `ida.data.ingest_horizons`)

Prefer adding **strategies here**, not new per-dataset modules in the server:

| Function | Role |
|----------|------|
| `ingestGenericTabular` | CSV/TSV via `CSVReader`, X/Y/Z columns by name or random numeric columns |
| `ingestOnlineRetail`, `ingestStarCatalogueCsv`, `ingestTycho2Dat`, `ingestCovtype` | Presets kept for backward-compatible paths |
| `ingestFitsMiddleSlice` | One 2D slice of a FITS cube as point markers |
| `ingestHorizonsEphemerisText` | JPL Horizons vector dump → plottables |

Apps map **`PlotIngestResult.entities`** to ECS/rendering (see server `plot_spawn.d`: quaternion → euler for `RotationComponent` at the boundary).

## Extending

1. **New file format**: add a loader under `source/ida/data/`, return `GeometryVertex[]`/indices or push **`PlottableEntity`** builders; export from `ida/data/package.d`.
2. **New tabular preset**: add a function in `ingest.d` (or a small submodule) that constructs `PlottableEntity[]`; avoid duplicating `CSVReader` logic.
3. **Math**: `ida.data.quat_math` provides **euler ↔ quaternion** helpers for apps that still store euler in ECS.

## Build

```bash
dub build
```

Ddoc: see module comments in `source/ida/data/package.d` and public symbols in each submodule.
