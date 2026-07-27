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
| ZIP traditional encryption | supported for stored/DEFLATE/zlib-backed external-method entries | supported with caller-supplied in-memory password | supported by decrypted CRC-32 | supported by password-backed extraction callers | writes unencrypted output only | archive ZIP adapter + `zlib` |
| ZIP BZip2 / LZMA / Zstandard | supported | supported | supported | supported | supported for host-file publication | archive ZIP adapter + `zlib` |
| split ZIP / spanning ZIP | supported by bounded numbered-volume reassembly | supported | supported | supported | save as non-split ZIP | archive ZIP adapter |
| gzip | supported | supported | supported | supported | supported single-file replacement | `zlib` |
| 7z | supported for native zlib-backed Copy, Deflate, BZip2, LZMA, LZMA2, PPMd, filtered, BCJ2, solid-substream, and bounded multi-volume layouts | supported, including password-backed AES payload extraction | supported | supported when required passwords are supplied in memory | supported by stored file-list publication | `zlib` |
| bzip2 | supported as one logical file | supported | supported | supported | supported single-file replacement | `zlib` |
| Zstandard | supported as one logical file | supported | supported | supported | supported single-file replacement | `zlib` |
| XZ | supported as one logical file for multi-block LZMA2 streams | supported | supported | supported | supported single-file replacement | `zlib` |
| AR | supported for stored members | supported | supported | supported | supported by stored-member rewrite publication | archive AR adapter |
| CPIO newc | supported for stored members | supported | supported | supported | supported by newc rewrite publication | archive CPIO adapter |
| CAB stored / MSZIP | supported for bounded single-folder, multi-file archives | supported | supported | supported | supported by stored-cabinet rewrite publication | archive CAB adapter + `zlib` |
| ISO 9660 | supported for stored directory records and files | supported | supported | supported | supported by flat-image rewrite publication | archive ISO adapter |

Recognized but unsupported in V1: RAR, non-contiguous multi-volume ZIP sets,
ZIP strong encryption, AES-wrapped ZIP external methods, encrypted 7z headers
without a supplied password, XZ layouts outside the supported native LZMA2
layout set, unsupported CAB folder methods outside stored/MSZIP, unsupported
non-bridge ZIP PPMd variants, and unsupported ZIP methods or 7z layouts outside
the zlib-backed native layout set. ZIP traditional encryption and WinZip AES
stored/DEFLATE entries are supported when a password is supplied in memory.

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
