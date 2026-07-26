# Product Scope

`archive` is a graphical desktop archive manager. It is a sibling application
to `files` and should reuse the same architectural conventions wherever the
concepts apply.

## Reconciled Scope

The original project prompt defined V1 as a read-only archive browser. The
current product direction supersedes that limitation: `archive` is no longer
read-only. It must support archive management workflows, including safe
creation and update flows, while retaining the original safety, tasking,
localization, testing, and dependency boundaries.

This scope change does not relax parser ownership or safety invariants. Archive
mutation must be planned, validated, and published through controlled services.
Widgets must never rewrite archives directly.

## Product Goals

The application should let a user:

- open a local archive;
- detect and validate the archive format;
- index the archive without eagerly decompressing every payload;
- display archive contents as a virtual filesystem;
- navigate, sort, filter, select, inspect, preview, and verify entries;
- extract selected entries or the complete archive safely;
- create supported archive formats;
- add, replace, remove, and rename entries where the format adapter supports it;
- close, reload, or save archive sessions with explicit operation results.

## Dependency Ownership

- `guikit` owns GUI widgets, layout, dialogs, focus, accessibility, and
  main-thread integration.
- `i18n` owns all user-visible text and locale-sensitive formatting.
- `tarlib` owns TAR parsing, traversal, metadata interpretation, payload
  boundaries, validation, fixture generation, and TAR writing.
- `zlib` owns gzip, zlib-wrapped, and raw-DEFLATE compression/decompression.
- `project_tools` owns Ada release/check/build process helpers in the tests
  subcrate.
- AUnit owns the test framework.

Do not invoke external archive tools. Do not add script tooling. Do not parse
TAR outside `tarlib`. Do not implement DEFLATE outside `zlib`.

## Format Scope

Required V1 read workflows:

| Format | Browse | Preview | Verify | Extract | Backend |
| --- | --- | --- | --- | --- | --- |
| TAR | required | required | required | required | `tarlib` |
| TAR.GZ / TGZ | required | required | required | required | `zlib` + `tarlib` |
| ZIP stored | required | required | required | required | archive ZIP adapter |
| ZIP DEFLATE | required | required | required | required | archive ZIP adapter + `zlib` |
| ZIP BZip2 / LZMA / Zstandard | supported | supported | supported | supported | archive ZIP adapter + `zlib` |
| gzip | required | required | required | required | `zlib` |
| AR | supported | supported | supported | supported | archive AR adapter |

Required V1 write workflows:

| Format | Create | Add/Replace File | Remove Entry | Rename Entry | Backend |
| --- | --- | --- | --- | --- | --- |
| TAR | required | required | required by save-in-place/save-as publication | required by save-in-place/save-as publication | `tarlib` |
| TAR.GZ / TGZ | required | required | required by save-in-place/save-as publication | required by save-in-place/save-as publication | `zlib` + `tarlib` |
| ZIP stored | required | required | required by save-in-place/save-as publication | required by save-in-place/save-as publication | archive ZIP adapter |
| ZIP DEFLATE | required | required | required by save-in-place/save-as publication | required by save-in-place/save-as publication | archive ZIP adapter + `zlib` |
| gzip | required single-file | replace logical file | not applicable | required logical name | `zlib` |
| 7z | required for supported zlib subset | required | required by save-in-place/save-as publication | required by save-in-place/save-as publication | `zlib` |

Save-in-place targets the currently open archive path. The implementation stages
and verifies a replacement archive beside the target before publication, so the
user-facing mutation is in-place while the safety boundary still preserves the
old archive until validation succeeds. Write commands gather required payloads through
model-owned dialogs, publish typed write plans, and keep unavailable states as
stable reason codes.
Per-entry command availability is owned by `Archive.Archives.Capabilities`,
which reports preview, extract, verify, external-open, link-follow, and write
actions using stable reason codes rather than localized strings.

Resource limits are centralized in `Archive.Resource_Limits`. Configured values
may be clamped or rejected, but hard ceilings are non-configurable safety
boundaries for archive indexing, preview, extraction, event queues, and
temporary backing files.
Extraction and archive rewrite planning use `Archive.Extraction.Paths`
platform path models to derive deterministic destination keys for POSIX,
Windows-style case folding, and bounded macOS-style normalization collision
checks before any output is published.

The first GUI-facing shell is `Archive.UI`: it builds localized menu, toolbar,
breadcrumb, content, preview, command-palette, status, and guikit layout
snapshots from the authoritative model without mutating widgets directly. Its
content view snapshot explicitly models grid, compact, and details modes with
localized labels, accessibility names, stable geometry, virtualization, and
entry-ID selection. The same shell carries focus and overlay snapshots so
command palette and settings overlays have explicit priority, Escape handling,
and focus restoration. Dialog and notification snapshots are also model-owned:
open, extract, save-as, close-confirmation, unavailable-command, and save-result
surfaces are generated from authoritative state instead of widget-local state.
Keyboard handling is also centralized through `Archive.UI`: content navigation,
Tab focus traversal, Escape priority, and command shortcuts update the model
through dispatch results rather than widget-owned state. `Archive.GUI_Runtime` owns the initialized application model, shell configuration, and open operation coordinator for the desktop
runtime boundary; it validates menu, toolbar, layout, virtualization,
accessibility, resize, command dispatch, shortcut dispatch, background open
start/drain, and shutdown request behavior before a platform event loop is attached. `Archive.GUI_Frame` renders shell snapshots into concrete `guikit` draw
commands, accessibility nodes, and Vulkan-ready submission batches so the GUI
path is validated structurally in headless CI before live window presentation.
Projected content rows are rendered through `Guikit.Item_Grid` for grid,
compact, and details geometry, and command palette overlays are rendered through `Guikit.Command_Palette` rather than private overlay drawing.
The settings overlays are rendered through `Guikit.Settings_Panel`, and preview panels are rendered through `Guikit.List_Panel` using localized shell snapshot text.
`Archive.Application.Windows` owns the live desktop boundary: it initializes
GLFW, creates a Vulkan window, polls and waits for events through `guikit`,
resizes the authoritative runtime model from framebuffer dimensions, presents
`Archive.GUI_Frame` submission batches, and releases Vulkan, window, and GLFW
resources on shutdown. The default desktop run uses this live event loop; the
bounded `--live-smoke` mode validates the same boundary when a display and
Vulkan runtime are available. Desktop startup archive paths are forwarded into `Archive.GUI_Runtime.Start_Open_Archive`, and each rendered frame drains
`Archive.GUI_Runtime.Drain_Operations` before building shell snapshots so
background open completions are published on the runtime boundary. The shell includes the
model-owned breadcrumb snapshot for the current published archive index and a
content projection snapshot containing stable entry IDs for the current
directory using model-owned filter and sorting state. It also carries a command palette snapshot with localized command rows,
shortcut metadata, and unavailable reasons. Archive and focused-entry property snapshots
are published through the shell from the current model-owned index. A preview panel snapshot carries preview
phase, generation, target entry, bounded result, and accessibility metadata. Navigation commands use model-owned history
and publish current directory, focus, and back/forward availability through the shell. Entry activation is model-owned:
directory activation navigates, while regular-file activation starts preview. Entry commands require an actionable focused selection
from the current index. Copy-entry commands publish model-owned copy results for host clipboard integration. The status bar snapshot carries localized lifecycle text
plus entry-ID selection, pending-write, and verification counters.
Effective settings are owned by the application model and surfaced through the shell settings snapshot.
Settings schema 2 persists stable tokens for view mode, extraction conflict
policy, write conflict policy, link handling, startup recent behavior, window
maximized state, details columns, bounded recent archives, preview limits, and
extraction output limits. Older schema 0/1 settings migrate by filling the new
policy fields with conservative defaults.
The content view snapshot also carries the configured details-column IDs so renderers consume stable registry values, not localized column headings.
Verification phase, operation generation, and retained entry-result count are surfaced through the shell verification snapshot.
Extraction commands publish immutable extraction planning state through the shell extraction snapshot before prompting for destination handling.
Writable archive commands publish model-owned write planning state through the shell write snapshot; remove-selected planning is keyed by stable entry IDs from the current session.
The application model distinguishes ready, dirty, saving, and save-failed archive states. Add-file, add-directory, remove-selected, and rename-selected dialog completion paths publish typed write plans with a write operation generation; only ready write plans are saveable.
Write conflict handling is explicit in the write plan: duplicate-target and
file-directory conflicts retain stable reason codes, unresolved conflicts open
the write-conflict dialog, and configured or user-selected skip, overwrite, or
deterministic-rename decisions may be recorded with an apply-to-all flag before
the plan becomes saveable.
`Archive.Writes.Service` owns app-level save-as publication: it builds the archive payload through the format dispatcher, publishes through the staged write executor, reports payload and publish status, preserves pending plans on failure, and returns the model to ready only after successful publication.
`Archive.Archives.Opening` owns the source-to-model archive open workflow: it starts a model open generation, fingerprints and bounds the source file, enters the file-backed reader dispatch boundary, lets format adapters read only bounded probes, central-directory metadata, headers, trailers, and payload streams, rejects source changes detected during the attempt, and publishes the immutable index only through the matching model open generation. Failed replacement opens retain the previous active archive session.
`Archive.Archives.Opening.Tasks.Open_Worker` is the native Ada task boundary for background open attempts: it calls the worker-safe `Prepare_Path`, stores the prepared result in a protected result box, and publishes only an `Open_Completed` event through `Archive.Tasking.Services.Event_Bridge`. The main thread applies prepared results through `Publish_Prepared`.
`Archive.Operations.Opening` coordinates the open operation lifecycle: it starts
the model open generation, configures the event bridge, launches the native Ada
open worker, drains `Open_Completed` on the main-thread side, publishes the
prepared result, acknowledges the bridge wakeup, and records operation status.
Property commands open model-owned archive and entry property dialogs, and extraction cancellation clears planned extraction state.
Source path and fingerprint state are retained by the application model and exposed through the shell source snapshot.
Lifecycle commands mutate model-owned session/request state: new archive creates an empty writable archive, reload republishes the session, open-recent records a request, and quit enters shutdown.
Publishing a non-empty source path records it in settings-backed recent archive state with duplicate promotion and bounded retention.
Open Recent availability is derived from the settings-backed recent archive list.
Recent archive paths are persisted as stable data, not localized display labels,
and shell snapshots expose the recent count and ordered path list through the
settings snapshot for menu construction.

Recognized unsupported formats include RAR, XZ, CAB, CPIO,
ISO, split ZIP, multi-volume ZIP, encrypted entries outside the supported
7z subset, ZIP PPMd, and unsupported ZIP or 7z compression methods.

## Non-Negotiable Invariants

- Published archive indexes are immutable.
- Archive opening publishes an index only through `Archive.Archives.Opening`
  and a matching model open generation, with reader adapters using file-backed
  probes, metadata slices, and payload streams rather than whole-archive reads.
- Archive entries use stable IDs independent of paths.
- Duplicate archive paths remain distinct entries.
- Every filesystem write comes from a validated plan.
- No raw archive path is joined directly to an extraction or archive staging
  destination.
- Checksum failure cannot publish extracted or rewritten content.
- User settings cannot disable hard safety checks.
- Temporary resources have explicit ownership and cleanup.
- All background work uses native Ada tasking and bounded queues.
- `Archive.Tasking.Services.Event_Bridge` is the main-thread event boundary:
  it rejects stale session and operation generations before queueing,
  coalesces extraction progress through a latest-value slot, preserves terminal
  events in the bounded queue, gives terminal/control events priority over
  progress and ordinary state-change traffic, records operation ownership for
  open, preview, verification, extraction, save, and source-watch events,
  exposes a supervision snapshot for diagnostics, coalesces GUI wakeups, and
  blocks ordinary worker events after shutdown begins.
- GUI mutation occurs only on the `guikit` main thread.
- Every user-visible string resolves through `i18n`.
- Tests and release tooling are Ada-only and live in the tests subcrate.
