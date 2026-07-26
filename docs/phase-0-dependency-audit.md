# Phase 0 Dependency Audit

## files Mapping

`archive` follows the `files` root layout: `alire.toml`, `archive.gpr`, `src/`, `share/`, `tools/`, and a nested AUnit test crate under `tests/`.

The durable implementation mapping is maintained in `docs/FILES_MAPPING.md`.

Mapped concepts:

- executable boundary: `Files.Main` -> `Archive.Main`
- startup and shutdown facade: `Files.Application` -> `Archive.Application`
- live desktop boundary: `Files.Application.Windows` -> `Archive.Application.Windows`
- root model: `Files.Model.Window_Model` -> `Archive.Model.Application_Model`
- command registry and executor: `Files.Commands` -> `Archive.Commands`
- settings model: `Files.Settings.Settings_Model` -> `Archive.Settings.Settings_Model`
- localization facade: `Files.Localization` -> `Archive.Localization`
- command palette model: `Files.Command_Palette` and `Files.Model` palette state -> `Archive.View_Snapshots.Command_Palette` and `Archive.Model`
- GUI rendering bridge: `Files.Rendering` -> `Archive.GUI_Frame`
- input/controller boundary: `Files.Controller` and `Files.Events` -> `Archive.UI`, `Archive.GUI_Runtime`, and `Archive.Tasking.Services`
- development profile: root and tests set `[build-profiles] "*" = "development"`
- native linker surface: mirrors `files.gpr` for guikit/Vulkan/gdk-pixbuf linkage

No private `files` package is imported. Any shared behavior must come through
public reusable packages or be implemented in `archive` at the archive-domain
boundary.

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

`guikit` exposes reusable input, layout, widgets, item grid, list/tree panels, palette, segmented controls, command palette, settings panel, and drawing primitives. The concrete public GUI packages used or mapped by `archive` include:

- `Guikit.Input` for keyboard shortcuts and command dispatch bindings
- `Guikit.Item_Grid` for grid, compact, and details content rows
- `Guikit.Command_Palette` for command search overlays
- `Guikit.Settings_Panel` for settings overlays
- `Guikit.List_Panel` for preview and property surfaces
- `Guikit.Draw`, `Guikit.Layout`, and Vulkan-facing packages for the live frame boundary

`i18n` and the current `messages` runtime expose locale and catalog foundations.
`files` now wraps runtime catalog loading and rendering behind
`Files.Localization`; `archive` follows the same facade shape in
`Archive.Localization`. The concrete API mapping is:

- `Messages.Runtime.Initialize` for catalog-root initialization
- `Messages.Runtime.Load` for loading packaged catalogs
- `Messages.Runtime.Render` for localized message rendering
- `Messages.Result.Render_Result` for structured render outcomes
- `Messages.Arguments.Arguments` for parameterized message data

Domain and worker packages must return stable keys and typed arguments; final
localized text is produced at the `Archive.Localization` presentation boundary.

`project_tools` exposes Ada process, manifest, fixture, source, generated-doc,
release, and AUnit check helpers. The tests subcrate owns release/check tooling
and uses public packages such as `Project_Tools.Processes` and
`Project_Tools.Text` rather than shell scripts.

## Exact Build And Test Commands

The exact build and test commands for this repository are:

- `alr build`
- `alr -C tests build`
- `tests/bin/archive_tests`
- `tests/bin/check_all`
- `tests/bin/release_report --check`
