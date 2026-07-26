# Package Contracts

This document is the compact package-boundary map for `archive`. Public
contracts are stable within the repository; private implementation choices
should remain behind the owning package.

## Application And GUI

- `Archive.Application` selects runtime mode and delegates desktop execution.
- `Archive.Application.Windows` owns the live GLFW/Vulkan event loop and
  startup archive paths.
- `Archive.GUI_Runtime` owns the initialized model, runtime configuration,
  command dispatch, dialog completion, background operation draining, resize,
  validation, and shutdown request boundary.
- `Archive.UI` builds immutable, localized shell snapshots from model state.
- `Archive.GUI_Frame` converts shell snapshots into guikit draw commands,
  accessibility nodes, and Vulkan-ready submission batches.
- `Archive.Commands` is the only user-action executor. Widgets, menus,
  toolbars, keyboard handlers, context menus, and command palette rows route
  through stable command IDs.

## Archive Domain

- `Archive.Archives.Formats` owns format detection, format descriptors, and
  static capability metadata.
- `Archive.Archives.Entries` owns the format-neutral entry model and stable
  `Entry_Id` usage.
- `Archive.Archives.Index` owns immutable virtual filesystem publication,
  physical entries, synthetic directories, child lookup, duplicates, sorting,
  and filtering.
- `Archive.Archives.Opening` owns source validation, fingerprinting,
  file-backed dispatch, source-change checks, and model publication.
- `Archive.Archives.Opening.Tasks` is the native Ada worker boundary for open
  attempts.
- `Archive.Archives.Capabilities` owns per-entry action availability and stable
  unavailable reason codes.

## Format And Compression

- `Archive.Archives.Readers.Tar` consumes public `tarlib` reader APIs only.
- `Archive.Writes.Tar` and `Archive.Writes.Tar_Gzip` consume public `tarlib`
  writer APIs only.
- `Archive.Archives.Readers.Zip` owns ZIP central-directory parsing, ZIP64
  validation, data descriptor handling, local-header consistency checks, CRC32,
  stored payloads, and raw-DEFLATE payload streaming through zlib.
- `Archive.Archives.Readers.Gzip` owns gzip header/trailer interpretation and
  logical single-entry presentation while delegating compression to zlib.
- `Archive.Compression.Zlib` is the only package family that maps low-level
  zlib behavior into archive error codes.

## Extraction, Writes, And Verification

- `Archive.Extraction.Paths` owns platform-aware safe relative path planning.
- `Archive.Extraction.Plans` owns immutable extraction plans and conflict
  records.
- `Archive.Extraction.Execution` owns secure temporary output and publication.
- `Archive.Writes.Plans` owns write mutation plans, conflict decisions, and
  saveability.
- `Archive.Writes.Dispatch` routes format-specific archive construction.
- `Archive.Writes.Service` combines model state, dispatcher output, staged
  publication, and save lifecycle updates.
- `Archive.Verification.*` owns CRC32, entry verification, full archive
  verification, and immutable verification overlays.

## Tasking And Resources

- `Archive.Tasking.Services.Event_Bridge` is the protected worker-to-main
  thread boundary. It rejects stale generations, coalesces progress, preserves
  terminal events, tracks operation ownership, and blocks ordinary events after
  shutdown begins.
- `Archive.Tasking.Cancellation` owns cooperative cancellation tokens.
- `Archive.Temporary_Resources` owns application temporary resource registry
  state and cleanup policy.
- `Archive.Resource_Limits` owns all hard ceilings and configured limit
  validation. User settings cannot disable hard safety checks.

## Prohibited Crossings

Do not parse TAR outside `tarlib`, do not call zlib outside the compression
adapter, do not mutate guikit widgets from workers, do not join raw archive
paths to output roots, do not identify entries by paths, do not persist
localized labels, do not invoke external archive tools, and do not add script
tooling or plugins.
