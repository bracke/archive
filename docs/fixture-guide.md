# Fixture Guide

`tests/fixtures/manifest.txt` is the fixture manifest for `archive_tests`.

Each fixture record uses this form:

```text
fixture id=<stable-id> path=<repository-relative-path> format=<format> purpose=<purpose> size=<bytes> crc32=<eight-hex-digits>
```

`tests/bin/check_all` validates the manifest and every listed fixture in Ada.
Checked-in fixture paths must stay under `tests/fixtures/`, listed files must
exist, byte sizes must match, and CRC32 values must match the manifest.
Deterministic generated fixtures use `path=generated:<id>` and the generated
path suffix must match the stable fixture ID. Generated fixture size and CRC32
metadata are still hash-validated against the manifest.

Required generated fixture IDs cover the V1 matrix:

```text
tar-basic
tar-gzip-basic
tar-duplicate-path
cab-unsupported-method
xz-unsupported-check
seven-zip-encrypted
rar-unsupported
split-zip-unsupported
bzip2-basic
zstd-basic
zip-stored-basic
zip-deflate-basic
zip-data-descriptor
zip-zip64-basic
zip-unicode-path
gzip-basic
gzip-empty
zip-bad-crc
zip-central-crc-mismatch
zip-unicode-path-bad-crc
zip-unicode-path-bad-version
zip-unsupported-method
zip-ppmd
zip-encrypted
zip-zip64-missing-extra
zip-zip64-too-large
zip-local-size-mismatch
zip-bad-local-signature
zip-truncated-central
zip-multi-disk
gzip-bad-header-crc
gzip-truncated
gzip-bad-trailer
tar-truncated
```

`tests/fixtures/corpus.txt` is the malformed/security corpus manifest. Each
case record is executed by `tests/bin/check_all` against the real format
detector, archive path classifier, platform key projection, extraction path
planner, or archive dispatch reader. The corpus covers traversal, absolute
paths, Windows drive and drive-relative paths, UNC style paths, alternate data
streams, reserved names, case folding, macOS-style normalization, recognized
unsupported signatures, invalid random input, TAR, TAR.GZ, ZIP stored, ZIP
DEFLATE, standalone gzip, unsupported ZIP compression methods, encrypted ZIP
entries, split and multi-disk ZIP rejection, corrupt ZIP CRCs, corrupt gzip
trailers, and malformed archive inputs.
The in-repository corpus is deterministic and network-free; it includes
local-header mismatch/signature cases, central/local CRC divergence, ZIP data
descriptors, ZIP64 metadata, ZIP64 overflow rejection, missing ZIP64 extra
fields, ZIP Unicode path extra fields and invalid Unicode-path CRC/version
records, duplicate TAR paths, gzip empty payloads, gzip header CRC failures, and
normalized safe-path and platform-collision cases in addition to attack paths.
Larger externally sourced corpora can be added only as checked-in or generated
records with stable hashes and Ada validation.

Archive corpus records use this form:

```text
case id=<stable-id> kind=archive input=<generated-fixture-or-malformed-id> source=<source-name> open=<error-code> entries=<physical-count> [payload=<error-code>]
```

Archive corpus `input` values must be registered generated fixture IDs or
registered malformed-input IDs. Unknown archive corpus inputs fail the Ada release checks.

Format corpus `input` values must be registered structural probe IDs. Unknown format corpus inputs fail the Ada release checks.

Path corpus platform, safety, decision, and collision values must use registered
stable IDs. Unknown path corpus classification values fail the Ada release checks.

Format IDs, detection statuses, archive error codes, payload error codes, and
entry counts in corpus records must use registered stable values. Unknown corpus result values fail the Ada release checks.

`payload` is used when the format can publish an index but the malformed stream
must fail when payload bytes are read.

Fixture IDs are stable API for tests and docs. Do not rename a fixture ID just
because the file layout changes. Update the manifest whenever fixture content
changes intentionally.

Valid TAR fixtures should be generated through public `tarlib` writer APIs
where possible. Gzip and ZIP fixtures should be generated through application
or dependency APIs, not external archive commands.
