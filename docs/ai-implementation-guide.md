# AI Implementation Guide

## Required Boundaries

- Do not hard-code user-visible GUI text; return message IDs from domain code and resolve text at the presentation boundary.
- Do not parse TAR outside `tarlib`.
- Do not write TAR outside `tarlib`.
- Do not implement DEFLATE outside `zlib`.
- Do not invoke external archive tools.
- Do not mutate guikit widgets from workers.
- Do not use unbounded inter-task queues.
- Do not identify entries by paths.
- Do not join raw archive paths to extraction destinations.
- Do not bypass `Archive.Commands`.
- Do not add scripts or a plugin system.
- Do not add a second settings subsystem.
- Do not persist transient data, preview data, worker state, temporary paths, or passwords.
- Do not scatter hard-coded resource ceilings; use `Archive.Resource_Limits`.

## Package Map

- `Archive.Application`: executable entry point and runtime modes.
- `Archive.Application.Windows`: live GLFW/Vulkan desktop runtime, bounded live
  smoke probe, resize-aware presentation loop, and resource cleanup boundary.
- `Archive.Commands`: stable command IDs, metadata, shortcuts, enablement, and pure model execution.
- `Archive.Model`: authoritative application state.
- `Archive.UI`: GUI shell snapshots, view-mode surface metadata, focus/overlay/dialog/notification state, dispatch, and guikit layout integration.
- `Archive.GUI_Frame`: converts shell snapshots into `Guikit.Draw` command vectors, accessibility nodes, and `Guikit.Vulkan` submission batches.
- `Archive.GUI_Runtime`: initialized model/config owner and open-operation owner
  for the desktop runtime boundary; use it for resize, command dispatch,
  shortcut dispatch, command-palette execution, dialog completion, background
  open start/drain, extraction/save completion, validation, and close requests.
- `Archive.Tasking.Services`: protected worker-to-main-thread event bridge;
  configure current session and operation generations for open, preview,
  verification, extraction, save, and source-watch owners; publish worker events
  through it; take latest progress separately from terminal events; inspect the
  supervision snapshot for diagnostics; and acknowledge coalesced GUI wakeups
  only on the main-thread side.
- `Archive.Settings`: validated settings model and defaults.
- `Archive.Localization`: localization facade.
- `Archive.Archives.Formats`: format registry and bounded detection.
- `Archive.Archives.Opening`: source validation, source fingerprinting,
  file-backed reader dispatch, source-change rejection, and generation-aware
  model publication for archive open attempts.
- `Archive.Archives.Streams`: bounded source-stream boundary for narrowly scoped
  prefix probes, fixture inputs, and guarded small-buffer conversions.
  Production readers should prefer file-backed metadata slices and entry
  payload streams rather than whole-archive materialization.
- `Archive.Archives.Opening.Tasks`: native Ada open worker. It must prepare
  archive results off the GUI thread, store them in a protected result box, and
  publish only `Open_Completed` through `Archive.Tasking.Services.Event_Bridge`.
- `Archive.Operations.Opening`: application operation coordinator for archive
  opening; it owns start/drain lifecycle, event bridge configuration, worker
  launch, main-thread publication, wakeup acknowledgement, and status reporting.
- `Archive.Archives.Entries`: format-neutral entry model.
- `Archive.Archives.Capabilities`: authoritative per-entry preview, extract,
  verify, link-follow, and write-action availability with stable reason codes.
- `Archive.Archives.Paths`: locale-neutral virtual path classification.
- `Archive.Extraction.Paths`: safe extraction-relative path planning and
  platform collision keys for POSIX, Windows, and macOS-like targets.
- `Archive.Compression.Zlib`: application-owned mapping around the public `zlib` API.
- `Archive.Resource_Limits`: configured limits, hard ceilings, and validation outcomes.

## Archive Mutation Scope

Do not fake TAR support. Consume `tarlib` public reader and writer APIs for TAR browsing, extraction, creation, and update workflows. Archive mutation must be planned first, validated for path safety and conflicts, and then published atomically enough that cancellation or failure cannot leave model state ahead of filesystem/archive state.

ZIP, gzip, bzip2, and Zstandard mutation must use `zlib` for compression boundaries and archive-owned ZIP structures for container metadata where applicable. ZIP BZip2, ZIP LZMA, and ZIP Zstandard payload reads, host-file publication, and source-aware rewrites use the zlib ZIP external-method bridge. Existing ZIP entries are streamed to a bounded temporary payload file before external-method recompression; keep that staging path contained and cleaned up. 7z mutation must use the public `zlib` Seven_Zip APIs for supported native layouts. Unsupported write formats should be reported as unavailable commands, not silently downgraded to extraction-only behavior.
Application-level write dialog completion must call model-owned typed planning operations for add-file, add-directory, remove-selected, and rename-selected. Do not mark pending writes without a write plan except for a newly created empty archive before its first save target exists.
Use `Archive.Writes.Service` for save-as publication from application commands. It is the boundary that combines model state, format dispatch, staged publish execution, and save lifecycle updates.
Represent write conflicts in `Archive.Writes.Plans` with stable decisions and
resolution records. Duplicate-target and file-directory conflicts may stay
prompt-required, or they may carry skip, overwrite, or deterministic-rename
decisions with an apply-to-all flag. Do not make a conflicted write plan
saveable unless every conflict is resolved.

Settings schema 2 owns write conflict policy, extraction conflict policy,
startup recent behavior, window maximized state, link handling, unsafe-entry
visibility, preview limits, extraction output limits, details columns, and
bounded recent archives. Persist stable tokens only; never persist localized
labels or transient dialog responses.

Use `Archive.Archives.Opening.Open_Path` for path-based archive opening. Do not
publish reader results directly into `Archive.Model`; the opening service owns
source fingerprint checks, file-backed reader dispatch, failed replacement
retention, and stale open completion rejection. Reader adapters should read
bounded probes, metadata slices, headers, trailers, and payload streams from
the source file instead of loading the complete archive into memory.
Use `Archive.Archives.Opening.Tasks.Open_Worker` for background open attempts;
workers must call `Prepare_Path` and must not mutate `Archive.Model`.
Use `Archive.Operations.Opening.Start_Open` and `Drain_Events` from runtime or
controller code instead of launching open workers directly from widgets.
Runtime callers should use `Archive.GUI_Runtime.Start_Open_Archive` and
`Archive.GUI_Runtime.Drain_Operations` so model publication remains centralized.
Live GUI dialog completion must enter through the typed `Archive.GUI_Runtime`
completion procedures for open, add file, add directory, rename, save-as, and
extraction destination dialogs. Do not let widgets plan writes, publish saves,
or execute extraction directly.
Desktop startup paths must enter through `Archive.Application.Windows.Run`,
which starts the runtime open coordinator and drains it from the live frame loop
before rendering snapshots.

Do not publish worker events directly to GUI code. Route them through `Archive.Tasking.Services.Event_Bridge`;
it owns stale-event rejection, bounded queue admission, progress coalescing,
terminal-event preservation, save/source-watch ownership tracking, shutdown
rejection, queue policy diagnostics, and wakeup coalescing.
