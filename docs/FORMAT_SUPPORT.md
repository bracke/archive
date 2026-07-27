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
| ZIP BZip2 | supported through authoritative central directory plus local-header validation | supported through the zlib ZIP external-method bridge | supported with CRC-32 after decode before payload publication | supported through safe extraction planning/execution | supported for host-file publication and source-aware rewrite through the zlib ZIP external-method bridge | archive ZIP adapter + `zlib` |
| ZIP LZMA | supported for streams emitted by the zlib ZIP external-method bridge | supported through the zlib ZIP external-method bridge | supported with CRC-32 after decode before payload publication | supported through safe extraction planning/execution | supported for host-file publication and source-aware rewrite through the zlib ZIP external-method bridge | archive ZIP adapter + `zlib` |
| ZIP Zstandard | supported through authoritative central directory plus local-header validation | supported through the zlib ZIP external-method bridge | supported with CRC-32 after decode before payload publication | supported through safe extraction planning/execution | supported for host-file publication and source-aware rewrite through the zlib ZIP external-method bridge | archive ZIP adapter + `zlib` |
| ZIP PPMd | supported for default-parameter PPMd streams emitted by the zlib ZIP external-method bridge | supported through the zlib ZIP external-method bridge | supported with CRC-32 after decode before payload publication | supported through safe extraction planning/execution | supported for host-file publication and source-aware rewrite through the zlib ZIP external-method bridge | archive ZIP adapter + `zlib` |
| ZIP traditional encryption | supported for stored, DEFLATE, and zlib-backed external-method entries with caller-supplied in-memory passwords | supported through PKZIP traditional decrypt before stored/raw-DEFLATE/zlib-backed external-method payload publication | supported with password header validation and CRC-32 over decrypted bytes | supported where the extraction caller supplies the password and safe extraction planning succeeds | not supported for encrypted publication; update by writing unencrypted output | archive ZIP adapter + `zlib` |
| split ZIP / spanning ZIP | supported by bounded `.z01`, `.z02`, ... plus final `.zip` reassembly into a retained backing file | supported through the normal ZIP reader after reassembly | supported through normal ZIP CRC and metadata validation after reassembly | supported through safe extraction planning/execution | not supported; update by saving as a non-split ZIP archive | archive ZIP adapter |
| gzip | supported as one logical regular-file archive | supported through gzip-wrapped zlib adapter | supported by zlib gzip trailer checks; bounded header CRC is validated during indexing | supported through safe extraction planning/execution | supported by gzip writer adapter | `zlib` |
| 7z | supported for native zlib-backed Copy, Deflate, BZip2, LZMA, LZMA2, PPMd, filtered, BCJ2, solid-substream, and bounded `.7z.001` first-volume layouts | supported through `zlib` native 7z extraction, including password-backed AES payload extraction and bounded multi-volume reassembly | supported through zlib header, size, CRC, method, password, and joined-volume limit validation | supported through safe extraction planning/execution when required passwords are supplied in memory | supported by Deflate file-list publication through `zlib` | `zlib` |
| bzip2 | supported as one logical regular-file archive | supported through `zlib` bzip2 decoding | supported by bzip2 block and combined CRC validation | supported through safe extraction planning/execution | supported by bzip2 writer adapter | `zlib` |
| Zstandard | supported as one logical regular-file archive | supported through `zlib` Zstandard decoding | supported by zlib frame validation and optional content checksum | supported through safe extraction planning/execution | supported by Zstandard writer adapter | `zlib` |
| XZ | supported as one logical regular-file archive for one-stream, one-or-more-block LZMA2 files | supported through `zlib` XZ/LZMA2 decoding | supported by zlib XZ header, block, index, footer, CRC32, and CRC64 validation | supported through safe extraction planning/execution | supported by XZ LZMA2 writer adapter | `zlib` |
| AR | supported for stored members, symbol tables, GNU string tables, and BSD long names | supported for stored regular-file members | supported by bounded member header and size validation | supported through safe extraction planning/execution | supported by stored-member rewrite publication | archive AR adapter |
| CPIO newc/crc | supported for stored members and trailer termination | supported for regular-file members | supported by bounded fixed-header, name, size, and alignment validation | supported through safe extraction planning/execution | supported by newc rewrite publication | archive CPIO adapter |
| CAB stored / MSZIP | supported for one bounded stored or MSZIP folder with multiple files | supported for stored file payloads and MSZIP raw-DEFLATE payloads through `zlib` | supported by bounded MSCF header, folder, file-record, data-block, and inflate-size validation | supported through safe extraction planning/execution | supported by stored-cabinet rewrite publication | archive CAB adapter + `zlib` |
| ISO 9660 | supported for primary-volume directory records | supported for stored regular-file extents | supported by bounded descriptor, directory-record, extent, and size validation | supported through safe extraction planning/execution | supported by flat-image rewrite publication | archive ISO adapter |
| RAR4 stored | supported for stored file records and duplicate names | supported for stored regular-file payloads | supported with CRC-32 over stored bytes | supported through safe extraction planning/execution | not supported | archive RAR adapter |

Current covered edge cases include ZIP comments, Unicode path extra fields,
ZIP64 per-entry size extras within host bounds, data descriptors with and
 without signatures, ZIP BZip2, LZMA, Zstandard, and default-parameter PPMd payload decoding through zlib,
ZIP traditional encrypted stored/DEFLATE password-backed payload streaming,
ZIP traditional encrypted stored/DEFLATE/zlib-backed external-method password-backed payload streaming,
ZIP strong encrypted-entry detection, unsupported compression-method reporting,
multi-disk rejection, duplicate ZIP names, explicit ZIP directories,
gzip optional fields, gzip header CRC, unsafe gzip filename fallback, truncated
gzip payload rejection, TAR duplicate paths, TAR symbolic and hard links, TAR
device and FIFO metadata, PAX long paths, invalid TAR checksum, and TAR
truncation, zlib-backed native 7z listing and payload extraction for supported
Copy, Deflate, BZip2, LZMA, LZMA2, PPMd, filtered, BCJ2, solid-substream,
and password-backed AES payload layouts, bounded 7z first-volume reassembly for `.7z.001` sources,
bounded split ZIP reassembly for contiguous numbered `.z01`, `.z02`, ... sets
with a final `.zip` segment,
supported native 7z layouts in documentation and validation,
and zlib-backed Deflate 7z file-list publication, zlib-backed bzip2 single-file
decoding and publication, zlib-backed Zstandard single-file decoding and
publication, zlib-backed XZ multi-block LZMA2 decoding and publication, supported ZIP PPMd method 98 bridge decoding and publication, stored Unix AR member indexing, payload streaming, and rewrite publication, CPIO newc member indexing, payload streaming, and rewrite publication, bounded stored and MSZIP CAB multi-file folder indexing, payload streaming, and stored-cabinet rewrite publication, ISO 9660 directory-record indexing, stored file-extent streaming, and flat-image rewrite publication, plus RAR4 stored entry indexing with CRC-checked payload streaming.

RAR4 stored archive support is intentionally narrow. RAR5 archives, encrypted
RAR entries, and compressed RAR entries remain visible where possible but fail
closed with typed unsupported-format or unsupported-method results.

Supported formats may still contain unsupported sublayouts. ZIP strong
encryption remains visible but unavailable until a dedicated decrypting backend
is added. WinZip AES entries using stored, DEFLATE, or zlib-backed external ZIP
methods are supported when a password is supplied in memory.
Unsupported ZIP methods, including non-bridge PPMd variants and non-bridge
LZMA variants, remain visible as unsupported entries where the central
directory can be safely parsed.
7z layouts outside the supported native layout set accepted by `zlib` fail closed
with typed unsupported-method or invalid-format results.
XZ layouts outside the supported one-stream LZMA2 layout set fail closed
with typed unsupported-method or invalid-format results.
CAB MSZIP folders may contain multiple files in one bounded data block. Unsupported CAB folder methods remain visible only as unsupported-method results
until a compression adapter is explicitly added for that CAB folder method.

Save-in-place writes target the currently open archive path and validate the
source fingerprint. ZIP stored single-entry same-size replacement can patch the
payload and CRC fields in place when the existing entry is unencrypted, non-ZIP64,
and has no data descriptor. All other save-in-place operations stage a
replacement archive beside the target, verify the staged archive, and publish it
over the original path only after validation succeeds. Save-as publication always
uses the staged writer path for a distinct target.
