# Format Support

This document records the current implementation state. Capability metadata is
owned by `Archive.Archives.Formats`; this document must stay consistent with
that registry and the AUnit format tests.

| Format | Browse/Index | Payload Read | Verify | Extract | Create/Update | Backend |
| --- | --- | --- | --- | --- | --- | --- |
| TAR | supported for regular files, directories, links, devices, FIFOs, duplicates, and PAX long paths | supported for regular-file payloads through `tarlib` | supported according to `tarlib` checksum/truncation behavior | supported through safe extraction planning/execution | supported by create/rewrite through `tarlib` | `tarlib` |
| TAR.GZ / TGZ | supported after gzip-wrapped inflate into TAR reader input | supported through gzip inflate plus `tarlib` payload traversal | supported by gzip stream checks plus `tarlib` validation | supported through safe extraction planning/execution | supported by TAR payload generation plus gzip wrapping | `zlib` + `tarlib` |
| ZIP stored | supported through authoritative central directory plus local-header validation | supported for stored payloads | supported with CRC-32 before payload publication | supported through safe extraction planning/execution | supported by create/rewrite adapter | archive ZIP adapter |
| ZIP DEFLATE | supported through authoritative central directory plus local-header validation | supported through raw-DEFLATE zlib adapter | supported with CRC-32 after inflate before payload publication | supported through safe extraction planning/execution | supported by create/rewrite adapter | archive ZIP adapter + `zlib` |
| gzip | supported as one logical regular-file archive | supported through gzip-wrapped zlib adapter | supported by zlib gzip trailer checks; bounded header CRC is validated during indexing | supported through safe extraction planning/execution | supported by gzip writer adapter | `zlib` |

Current covered edge cases include ZIP comments, Unicode path extra fields,
ZIP64 per-entry size extras within host bounds, data descriptors with and
without signatures, encrypted-entry detection, unsupported compression-method
reporting, multi-disk rejection, duplicate ZIP names, explicit ZIP directories,
gzip optional fields, gzip header CRC, unsafe gzip filename fallback, truncated
gzip payload rejection, TAR duplicate paths, TAR symbolic and hard links, TAR
device and FIFO metadata, PAX long paths, invalid TAR checksum, and TAR
truncation.

Recognized but unsupported:

- 7z
- RAR
- XZ
- bzip2
- Zstandard
- CAB
- CPIO
- ISO
- AR
- split ZIP / spanning ZIP

Unsupported ZIP methods remain visible as unsupported entries where the central
directory can be safely parsed.

Current write support is create/rewrite oriented. In-place archive mutation is
not a supported implementation strategy.
