# Implementation Plan

This plan completes `archive` as a read/write graphical archive manager while
preserving the architecture and safety boundaries from the initial browser
scope.

## Phase Status Snapshot

The repository now has an enforced Ada `check_all` gate and a named
`completion gate format workflows` AUnit routine. That routine drives ZIP
stored, ZIP DEFLATE, TAR, TAR.GZ, and standalone gzip through open, index,
shell display, navigation, view switching, sorting, filtering, selection,
preview, verification, extraction, and clean close. ZIP, TAR, and TAR.GZ also
exercise update, save, reopen, and verification of the saved archive through
the current write dispatcher. Standalone gzip remains read/extract/verify in
the completion gate because dispatch publication is currently limited to ZIP,
TAR, and TAR.GZ.

Status by area:

- Phases 0-3 are gated for identity, command surface, settings-backed model
  state, dirty/save lifecycle, and stale generation behavior.
- Phases 4-7 are gated for TAR through `tarlib`, zlib streaming, ZIP indexing
  and payload streaming, immutable indexes, duplicate preservation, and
  virtual directory projection.
- Phases 8-10 are gated for extraction planning/execution, write planning and
  staged publication, preview, properties, and verification overlays.
- Phases 11-13 are gated for schema-2 settings, catalog coverage, task/event
  ownership, headless GUI shell snapshots, command dispatch, dialogs, focus,
  overlays, and `guikit` frame rendering.
- Phases 14-15 are gated for generated fixture hashes, malformed/security
  corpus breadth, release builds, local GNATprove proof target, package smoke,
  release report JSON, and CI delegation to Ada tooling.

Remaining depth is tracked as expansion work, not as unchecked placeholder
code: deeper live desktop interaction, broader malformed archive corpora,
stronger SPARK contracts over production packages, and standalone gzip archive
publication.

## Phase 0: Baseline And Scope Lock

Acceptance:

- `docs/PRODUCT_SCOPE.md` defines the current read/write scope.
- `docs/IMPLEMENTATION_PLAN.md` is validated by `tests/bin/check_all`.
- README, manifests, localization text, and AI guide do not describe the app
  as read-only.
- `tests/bin/check_all` passes.

Current status: mostly complete.

## Phase 1: Files/Dependency Mapping

Deliverables:

- Update `docs/phase-0-dependency-audit.md` into a complete dependency mapping.
- Add exact mapping from `files` concepts to `archive` packages for startup,
  commands, settings, snapshots, GUI surfaces, tests, and release tooling.
- Record public APIs consumed from `guikit`, `i18n`, `tarlib`, `zlib`, and
  `project_tools`.

Acceptance:

- No private `files` packages are imported.
- `check_all` validates required mapping documents.

## Phase 2: Format Capabilities And Command Surface

Deliverables:

- Add authoritative format registry capability fields for read and write.
- Add per-entry capability records for preview, verify, extract, add, replace,
  remove, rename, and open externally.
- Extend command registry with create archive, save archive, save as, add files,
  add directory, replace selected, remove selected, rename entry, and discard
  changes.
- Add unavailable reason codes for unsupported write operations.

Acceptance:

- Commands are side-effect-free during availability checks.
- Catalog contains every command name, description, and unavailable reason.
- AUnit covers command availability for no archive, read-only format, writable
  format, dirty session, and active operation states.

## Phase 3: Archive Session And Mutation Model

Deliverables:

- Add session phases for opening, ready, dirty, saving, failed save, closing,
  and cancelled.
- Add staged mutation plan model keyed by `Entry_Id`.
- Add generation IDs for mutation and save operations.
- Preserve immutable published index; represent changes as overlay state until
  save publishes a new archive/index.

Acceptance:

- Widgets never own adapter handles.
- Stale mutation/save events are rejected.
- Closing a dirty session requires explicit command policy.
- Tests cover dirty overlay, discard, failed save retaining old archive, and
  successful save publishing a new generation.

## Phase 4: TAR Adapter Integration

Deliverables:

- Implement `Archive.Archives.Readers.Tar` using `Tarlib.Readers` and
  `Tarlib.Files`.
- Map `tarlib` metadata into format-neutral entries.
- Implement TAR payload preview/extract streams.
- Implement TAR create/rewrite writer using `Tarlib.Writers` and safe staging.
- Add TAR and TAR.GZ fixtures generated through `tarlib`.

Acceptance:

- No TAR header parsing exists in `archive`.
- Tests cover TAR browse, duplicate paths, links, PAX paths, sparse metadata
  where exposed, invalid checksum, truncation, extraction, and rewrite.

## Phase 5: Zlib Streaming Adapter

Deliverables:

- Replace one-shot-only usage with bounded incremental zlib adapter.
- Support raw DEFLATE, zlib wrapper, gzip wrapper, counters, output limits,
  ratio limits, cancellation, unused input, and deterministic error mapping.
- Implement gzip logical archive reader and writer.

Acceptance:

- ZIP method 8 uses raw DEFLATE.
- gzip and TAR.GZ use gzip-wrapped mode.
- Tests cover chunk boundaries, corrupt streams, checksum failures, output
  limit, ratio limit, cancellation, and concatenated gzip members.

## Phase 6: ZIP Adapter Completion

Deliverables:

- Complete central-directory reader with ZIP64, local-header validation, data
  descriptors, UTF-8 names, comments, encryption detection, unsupported method
  reporting, and multi-disk rejection.
- Implement stored and DEFLATE payload access.
- Implement ZIP create/rewrite for stored and DEFLATE entries.

Acceptance:

- Central directory is authoritative.
- CRC failure prevents preview/extract/save publication.
- Tests cover required ZIP cases from the product scope.

## Phase 7: Immutable Index And Virtual Filesystem

Deliverables:

- Complete physical and synthetic directory indexing.
- Preserve duplicates and malformed/undecodable names.
- Add deterministic child ordering, filtering, sorting, and limits.
- Add partial/complete-with-warning outcomes where adapters can prove safety.

Acceptance:

- GUI snapshots only observe complete immutable indexes.
- Tests cover duplicate paths, synthetic parents, deterministic sorting,
  filtering, limits, and malformed names.

## Phase 8: Extraction Planner And Executor

Deliverables:

- Expand extraction path models for POSIX, Windows, and macOS-like behavior.
- Add conflict detection and resolution policy.
- Implement secure temporary output, bounded copy, checksum verification, safe
  metadata application, atomic publish, cancellation, and cleanup.

Acceptance:

- No output escapes destination.
- Failed checksum never publishes content.
- Overwrite preserves old target until replacement succeeds.
- Security tests cover traversal, absolute paths, Windows paths, symlink races,
  duplicates, disk/write faults, and cancellation.

## Phase 9: Archive Write Planner And Publisher

Deliverables:

- Add create/update plans separate from extraction plans.
- Stage new archive output to session-owned temporary paths.
- Verify staged archive before replacement.
- Atomically replace target where supported and preserve original on failure.
- Support save-as and direct save policies.

Acceptance:

- Failed save leaves original archive intact.
- Cancellation before publication removes staged output.
- Tests cover add, replace, remove, rename, save-as, overwrite conflict, source
  replacement, and archive verification after save.

## Phase 10: Preview, Properties, And Verification

Deliverables:

- Add bounded text, hex, directory, link, metadata, and image preview where
  existing infrastructure supports images.
- Add archive and entry properties snapshots.
- Add full-archive verification task and per-entry verification overlay.

Acceptance:

- Preview follows focus through replaceable requests.
- Stale previews are rejected.
- Verification overlays do not mutate immutable indexes.
- Tests cover preview limits, truncation, checksum failures, and cancellation.

## Phase 11: Settings And Localization

Deliverables:

- Align settings architecture with `files`: schema versioning, migrations,
  validation, recovery, atomic persistence, recent archives, window/panel
  layout, view modes, preview limits, extraction/write policies.
- Expand `share/archive.catalog` to cover all commands, errors, settings,
  columns, formats, properties, and accessibility labels.

Acceptance:

- No known user-visible registry string is hard-coded.
- Catalog checks validate every command and unavailable reason.
- Settings migration/recovery fixtures are tested.

## Phase 12: Tasking And Event Bridge

Deliverables:

- Add bounded protected queues, progress coalescing, terminal-event priority,
  cancellation hierarchy, source watcher, cleanup service, and operation
  ownership tree.
- Integrate with the `guikit` main-thread wake-up mechanism.

Acceptance:

- No unbounded inter-task queues.
- Terminal events cannot be displaced by progress.
- Tests cover queue saturation, stale results, shutdown, and cancellation.

## Phase 13: GUI Shell And View Modes

Deliverables:

- Implement window, menu bar, toolbar, breadcrumb, virtualized grid/compact/
  details views, preview panel, status bar, command palette, dialogs,
  notifications, focus, and accessibility.
- Wire every user action through `Archive.Commands`.

Acceptance:

- Headless GUI tests cover startup, menus, toolbar, command dispatch, view
  switching, focus restoration, locale refresh, and clean shutdown where
  `guikit` supports it.

## Phase 14: Fixtures, Corpus, And Hardening

Deliverables:

- Add machine-readable fixture manifest with hashes.
- Add deterministic TAR, TAR.GZ, ZIP, and gzip fixtures.
- Add malformed-input corpus and deterministic mutation tests.
- Add overflow/allocation/concurrency audits.

Acceptance:

- Fixtures are hash-validated by `check_all`.
- Tests require no public network and no user-local state.

## Phase 15: Release Tooling And Packaging

Deliverables:

- Expand `tests/bin/check_all` into authoritative development gate.
- Add release mode build, GNATprove gate, package preparation, package
  inspection, packaged smoke test, checksums, and release report.
- Add CI that invokes only Ada tooling.

Acceptance:

- Release fails on any mandatory build, test, proof, localization,
  architecture, security, documentation, dependency, packaging, or smoke gate.

## Completion Gate

The app is complete when this workflow passes for ZIP stored, ZIP DEFLATE, TAR,
TAR.GZ, and standalone gzip:

open archive -> index -> display root -> navigate -> switch views -> sort ->
filter -> select -> preview -> verify -> extract safely -> validate output ->
create/update where supported -> save -> reopen -> verify -> close cleanly.
