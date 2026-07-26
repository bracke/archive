# Phase 0 Dependency Audit

## files Mapping

`archive` follows the `files` root layout: `alire.toml`, `archive.gpr`, `src/`, `share/`, `tools/`, and a nested AUnit test crate under `tests/`.

The durable implementation mapping is maintained in `docs/FILES_MAPPING.md`.

Mapped concepts:

- executable boundary: `Files.Main` -> `Archive.Main`
- startup facade: `Files.Application` -> `Archive.Application`
- root model: `Files.Model.Window_Model` -> `Archive.Model.Application_Model`
- command registry: `Files.Commands` -> `Archive.Commands`
- settings model: `Files.Settings.Settings_Model` -> `Archive.Settings.Settings_Model`
- localization facade: `Files.Localization` -> `Archive.Localization`
- development profile: root and tests set `[build-profiles] "*" = "development"`
- native linker surface: mirrors `files.gpr` for guikit/Vulkan/gdk-pixbuf linkage

## Dependency Status

`tarlib` now exposes public TAR reading and writing surfaces:

- `Tarlib.Writers`
- `Tarlib.Readers`
- `Tarlib.Files`
- `Tarlib.Entries`
- `Tarlib.Inputs`
- `Tarlib.Outputs`
- `Tarlib.Errors`

TAR work in `archive` should be implemented through those public packages. Missing `archive` work is now integration and UI workflow work: mapping `tarlib` entries into archive indexes, previewing payloads, extracting through policy, and adding create/update flows that emit TAR through `Tarlib.Writers` and `Tarlib.Files`.

`zlib` exposes public zlib/gzip/raw Deflate APIs and public streaming filter objects. `Archive.Compression.Zlib` is the only application package that talks directly to that API: its public one-shot convenience functions now delegate to bounded streaming paths with caller-controlled input/output chunks, output limits, ratio limits, compressed/uncompressed counters, cancellation checks, concatenated gzip member handling, stream-end state, unused-input reporting, and typed application error mapping.

`guikit` exposes reusable input, layout, widgets, item grid, list/tree panels, palette, segmented controls, command palette, settings panel, and drawing primitives. The GUI shell phase should map to these public packages before adding custom widgets.

`i18n` exposes locale and CLDR foundations. `files` currently wraps runtime catalog loading behind `Files.Localization`; `archive` has the same facade shape and must replace the initial minimal fallback with full i18n runtime catalog loading before GUI text is considered complete.

`project_tools` exposes Ada process, manifest, fixture, source, generated-doc, release, and AUnit check helpers. The tests subcrate owns release/check tooling.
