# archive

`archive` is a graphical desktop archive manager, structured as a sibling of the existing `files` application.

V1 is intended to browse, preview, verify, extract, create, and update archive contents with stable entry IDs independent of paths, safe write/extraction planning, i18n-resolved user-visible text, guikit-based UI, Ada tasking, and Ada-only test/release tooling.

## Supported Formats

Current V1 support:

| Format | Browse | Preview | Verify | Extract | Create/Update | Backend |
| --- | --- | --- | --- | --- | --- | --- |
| TAR | supported | supported | supported | supported | supported by save-in-place and save-as publication | `tarlib` |
| TAR.GZ / TGZ | supported | supported | supported | supported | supported by save-in-place and save-as publication | `zlib` + `tarlib` |
| ZIP stored | supported | supported | supported | supported | supported by save-in-place and save-as publication | archive ZIP adapter |
| ZIP DEFLATE | supported | supported | supported | supported | supported by save-in-place and save-as publication | archive ZIP adapter + `zlib` |
| gzip | supported | supported | supported | supported | supported single-file replacement | `zlib` |
| 7z | supported for the native zlib-backed subset | supported | supported | supported | supported by stored file-list publication | `zlib` |
| Zstandard | supported as one logical file | supported | supported | supported | supported single-file replacement | `zlib` |

Recognized but unsupported in V1: RAR, XZ, bzip2, CAB, CPIO, ISO, AR, split ZIP, multi-volume ZIP, encrypted entries outside the supported 7z subset, and unsupported ZIP or 7z methods.

## Current Implementation Status

This repository currently contains the V1 archive-manager implementation:
manifests, GPR projects, executable entry point, core typed IDs, format probing,
TAR/ZIP/gzip reader adapters, zlib compression routing, immutable indexing,
path-safety classification, command registry, application model, settings
defaults, localization facade, extraction/write planning and execution,
headless GUI/runtime probes, release reporting, and Ada-owned validation gates.

The local `tarlib` dependency now exposes TAR reader and writer APIs. `archive` should consume those public APIs for TAR browse, extract, create, and update workflows instead of parsing TAR records directly.

The reconciled product scope is documented in
[`docs/PRODUCT_SCOPE.md`](docs/PRODUCT_SCOPE.md). The completion plan is in
[`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md). Current format
support is tracked in [`docs/FORMAT_SUPPORT.md`](docs/FORMAT_SUPPORT.md).
Testing, fixtures, and release workflow are documented in
[`docs/testing-guide.md`](docs/testing-guide.md),
[`docs/fixture-guide.md`](docs/fixture-guide.md), and
[`docs/release-guide.md`](docs/release-guide.md).
Settings migration/recovery rules are documented in
[`docs/settings-architecture.md`](docs/settings-architecture.md), and package
ownership boundaries are summarized in
[`docs/package-contracts.md`](docs/package-contracts.md).

## Commands

Build:

```sh
alr build
```

Run headless smoke:

```sh
bin/archive --headless-smoke
```

Run headless GUI runtime validation:

```sh
bin/archive --headless-gui
```

Validate startup archive opening through the headless GUI runtime:

```sh
bin/archive --headless-gui path/to/archive.zip
```

Run tests:

```sh
cd tests && alr build && bin/archive_tests
```

Run the Ada-owned repository gate:

```sh
tests/bin/check_all
```

Run a bounded live desktop smoke probe when the host has a display and Vulkan:

```sh
bin/archive --live-smoke
```

Generate the machine-readable release report:

```sh
tests/bin/release_report --check
```
