# archive

`archive` is a graphical desktop archive manager, structured as a sibling of the existing `files` application.

V1 is intended to browse, preview, verify, extract, create, and update archive contents with stable entry IDs independent of paths, safe write/extraction planning, i18n-resolved user-visible text, guikit-based UI, Ada tasking, and Ada-only test/release tooling.

## Supported Formats

Planned V1 support:

| Format | Browse | Preview | Verify | Extract | Create/Update | Backend |
| --- | --- | --- | --- | --- | --- | --- |
| TAR | partial | partial | partial | partial | partial | `tarlib` |
| TAR.GZ / TGZ | partial | partial | partial | partial | partial | `zlib` + `tarlib` |
| ZIP stored | partial | partial | partial | partial | partial | archive ZIP adapter |
| ZIP DEFLATE | partial | partial | partial | partial | partial | archive ZIP adapter + `zlib` |
| gzip | partial | partial | partial | partial | partial | `zlib` |

Recognized but unsupported in V1: 7z, RAR, XZ, bzip2, Zstandard, CAB, CPIO, ISO, AR, split ZIP, multi-volume ZIP, encrypted entries, and unsupported ZIP compression methods.

## Current Implementation Status

This repository currently contains a broad V1 foundation: manifests, GPR
projects, executable entry point, core typed IDs, format probing, TAR/ZIP/gzip
reader adapters, zlib compression routing, immutable indexing, path-safety
classification, command registry, application model, settings defaults,
localization facade, extraction/write planning and execution primitives,
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
