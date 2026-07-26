# Settings Architecture

`Archive.Settings` is the only settings subsystem. It follows the public shape
used by `files`: compiled defaults are built first, persisted values are parsed
over those defaults, validation produces an effective model, and invalid loaded
files are quarantined before defaults are returned.

## Ownership

- `Archive.Settings` owns schema parsing, migration, validation, serialization,
  load, save, quarantine paths, and recent archive retention.
- `Archive.Model` owns the effective settings during application execution.
- `Archive.UI` exposes settings through immutable shell snapshots.
- `Guikit.Settings_Panel` renders and edits the snapshot surface.
- Domain packages consume validated settings values only; they do not read or
  write settings files.

## Schema

The current schema is `schema=2`. Serialized settings must start with the
current schema and must use stable tokens for view modes, details columns,
conflict policies, link policies, booleans, and recent archive paths. Localized
labels are never persisted as identifiers.

Schema 0 and schema 1 inputs migrate by applying recognized stable keys over
compiled defaults. New schema-2 policy fields receive conservative defaults:
`conflict_policy=ask`, `write_conflict_policy=ask`, and `link_policy=skip`.
Future schema numbers are invalid because this version cannot safely interpret
their semantics.

## Recovery

Parsing uses smallest-domain recovery where it is safe:

- unknown keys are tolerated for forward-compatible metadata;
- preview limits clamp to hard ceilings and recover from zero to one byte;
- extraction limits are validated by `Archive.Resource_Limits`;
- recent archive lists drop empty and duplicate entries and stop at
  `Max_Recent_Items`;
- invalid stable tokens make the parse fail while preserving already parsed
  valid fields in the result for diagnostics.

Loading an invalid settings file returns compiled defaults, reports the stable
message key `settings.invalid`, and renames the original file to
`<path>.invalid`. The quarantine operation preserves the invalid input bytes
where the filesystem permits it. If the file is missing, loading succeeds with
compiled defaults.

## Persistence

`Save` writes to `<path>.tmp`, closes it, removes any old target, and renames the
temporary file into place. Callers must treat the returned
`Settings_Write_Result` as authoritative. Settings must not persist preview
content, active selections, temporary paths, worker state, passwords, prompts,
or localized display strings.

## Fixtures

Fixed settings fixtures live under `tests/fixtures/settings/` and are listed in
`tests/fixtures/manifest.txt` with size and CRC32. AUnit loads the current
schema fixture, the schema-0 migration fixture, and an invalid future-schema
fixture copied into `obj/` to exercise quarantine without mutating repository
fixtures.
