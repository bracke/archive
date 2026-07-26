# Format Support

This document records the current implementation state. Capability metadata is
owned by `Archive.Archives.Formats`; this document must stay consistent with
that registry and the AUnit format tests.

| Format | Browse/Index | Payload Read | Verify | Extract | Create/Update | Backend |
| --- | --- | --- | --- | --- | --- | --- |
| TAR | supported for regular files, directories, links, devices, FIFOs, duplicates, and PAX long paths | supported for regular-file payloads through `tarlib` | supported according to `tarlib` checksum/truncation behavior | supported through safe extraction planning/execution | supported by save-in-place and save-as publication through `tarlib` | `tarlib` |
| TAR.GZ / TGZ | supported after gzip-wrapped inflate into TAR reader input | supported through gzip inflate plus `tarlib` payload traversal | supported by gzip stream checks plus `tarlib` validation | supported through safe extraction planning/execution | supported by save-in-place and save-as publication through TAR payload generation plus gzip wrapping | `zlib` + `tarlib` |
| ZIP stored | supported through authoritative central directory plus local-header validation | supported for stored payloads | supported with CRC-32 before payload publication | supported through safe extraction planning/execution | supported by save-in-place and save-as publication through the ZIP adapter | archive ZIP adapter |
| ZIP DEFLATE | supported through authoritative central directory plus local-header validation | supported through raw-DEFLATE zlib adapter | supported with CRC-32 after inflate before payload publication | supported through safe extraction planning/execution | supported by save-in-place and save-as publication through the ZIP adapter | archive ZIP adapter + `zlib` |
| ZIP BZip2 | supported through authoritative central directory plus local-header validation | supported through the zlib ZIP external-method bridge | supported with CRC-32 after decode before payload publication | supported through safe extraction planning/execution | not emitted directly; save publication uses the configured ZIP stored/Deflate writer path | archive ZIP adapter + `zlib` |
| ZIP LZMA | supported for streams emitted by the zlib ZIP external-method bridge | supported through the zlib ZIP external-method bridge | supported with CRC-32 after decode before payload publication | supported through safe extraction planning/execution | not emitted directly; save publication uses the configured ZIP stored/Deflate writer path | archive ZIP adapter + `zlib` |
| ZIP Zstandard | supported through authoritative central directory plus local-header validation | supported through the zlib ZIP external-method bridge | supported with CRC-32 after decode before payload publication | supported through safe extraction planning/execution | not emitted directly; save publication uses the configured ZIP stored/Deflate writer path | archive ZIP adapter + `zlib` |
| gzip | supported as one logical regular-file archive | supported through gzip-wrapped zlib adapter | supported by zlib gzip trailer checks; bounded header CRC is validated during indexing | supported through safe extraction planning/execution | supported by gzip writer adapter | `zlib` |
| 7z | supported for the native zlib-backed subset | supported through `zlib` native 7z extraction | supported through zlib header, size, CRC, and method validation | supported through safe extraction planning/execution | supported by stored file-list publication through `zlib` | `zlib` |
| bzip2 | supported as one logical regular-file archive | supported through `zlib` bzip2 decoding | supported by bzip2 block and combined CRC validation | supported through safe extraction planning/execution | supported by bzip2 writer adapter | `zlib` |
| Zstandard | supported as one logical regular-file archive | supported through `zlib` Zstandard decoding | supported by zlib frame validation and optional content checksum | supported through safe extraction planning/execution | supported by Zstandard writer adapter | `zlib` |

Current covered edge cases include ZIP comments, Unicode path extra fields,
ZIP64 per-entry size extras within host bounds, data descriptors with and
without signatures, ZIP BZip2, LZMA, and Zstandard payload decoding through zlib,
encrypted-entry detection, unsupported compression-method reporting,
multi-disk rejection, duplicate ZIP names, explicit ZIP directories,
gzip optional fields, gzip header CRC, unsafe gzip filename fallback, truncated
gzip payload rejection, TAR duplicate paths, TAR symbolic and hard links, TAR
device and FIFO metadata, PAX long paths, invalid TAR checksum, and TAR
truncation, zlib-backed native 7z listing and payload extraction, and
zlib-backed stored 7z file-list publication, zlib-backed bzip2 single-file
decoding and publication, and zlib-backed Zstandard single-file decoding and
publication.

Recognized but unsupported:

- RAR
- XZ
- CAB
- CPIO
- ISO
- AR
- split ZIP / spanning ZIP

Unsupported ZIP methods, including ZIP PPMd and non-bridge LZMA variants, remain
visible as unsupported entries where the central directory can be safely parsed. Broader 7z layouts outside the native subset
accepted by `zlib` fail closed with typed unsupported-method or invalid-format
results.

Save-in-place writes target the currently open archive path, validate the source
fingerprint, stage the replacement archive beside the target, verify the staged
archive, and publish it over the original path only after validation succeeds.
Save-as publication uses the same staged writer path for a distinct target.
