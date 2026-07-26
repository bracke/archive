# Mapping To `files`

`archive` is developed as a sibling application of `files`. Shared concepts must
follow the public shape of `files` and reusable dependency APIs; private `files`
implementation packages must not be imported.

## Repository And Build

- root crate: `archive`
- executable: `archive`
- root GPR: `archive.gpr`
- tests subcrate: `tests/archive_tests`
- tests executable: `archive_tests`
- repository checks: Ada executable `tests/bin/check_all`
- development builds: full dependency graph through Alire development profiles

## Application Model

- Startup and shutdown mapping: `Files.Application` maps to
  `Archive.Application`, while the live desktop entry point maps from
  `Files.Application.Windows` to `Archive.Application.Windows`.
- startup facade: `Archive.Application`
- authoritative state: `Archive.Model.Application_Model`
- lifecycle: no archive, opening, ready, warnings, failed, shutdown
- immutable published archive indexes: `Archive.Archives.Index`
- snapshots: `Archive.View_Snapshots`
- `Files.Model` maps to `Archive.Model`

Widgets must consume snapshots and commands. Widgets must not own archive
reader handles, mutation plans, extraction plans, settings state, or worker
state.

## Commands

`Archive.Commands` is the central registry and executor. Menus, toolbar rows,
command palette rows, dialogs, keyboard shortcuts, context menus, and
accessibility actions must use stable command IDs from this registry.

The command surface includes read workflows, extraction workflows, verification,
and the expanded write scope:

- new archive
- save archive
- save archive as
- add files
- add directory
- remove selected
- rename selected

Availability checks must remain side-effect-free and return stable unavailable
reason keys.

## Settings

`Files.Settings` maps to `Archive.Settings`.

`Archive.Settings` follows the `files` settings pattern:

- compiled defaults
- persisted settings
- validated effective settings
- explicit schema version
- explicit migration path
- smallest-domain recovery
- atomic persistence
- recent archives persist stable source paths

Localized display strings must not be persisted as identifiers.

## Localization

`Files.Localization` maps to `Archive.Localization`.

`Archive.Localization` is the presentation boundary for user-visible text. Domain
and worker packages return stable keys, typed data, and structured errors; they
must not produce final localized sentences.

## GUI

The GUI shell must map to `files` concepts where applicable:

- menu bar
- toolbar
- breadcrumb
- virtualized main content views
- preview panel
- status surface
- command palette
- dialogs
- focus and accessibility metadata

Concrete `guikit` mappings are:

- content rows and details layout: `Guikit.Item_Grid`
- command palette overlay: `Guikit.Command_Palette`
- settings overlay: `Guikit.Settings_Panel`
- preview and property panels: `Guikit.List_Panel`

Custom widgets require a concrete gap in `guikit` or reusable public `files`
surface.

No private `files` package may be imported. Shared behavior must be consumed
through public reusable APIs, or the archive-specific equivalent must remain in
`Archive.*`.

## Archive-Specific Extensions

Archive-specific code remains outside `files`:

- format detection
- TAR adapter through `tarlib`
- ZIP adapter
- gzip/zlib adapter
- immutable archive index construction
- safe extraction planning
- safe archive write planning
- temporary backing resources
- archive-source monitoring
