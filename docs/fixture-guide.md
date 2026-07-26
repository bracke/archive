# Fixture Guide

`tests/fixtures/manifest.txt` is the fixture manifest for `archive_tests`.

Each fixture record uses this form:

```text
fixture id=<stable-id> path=<repository-relative-path> format=<format> purpose=<purpose> size=<bytes> crc32=<eight-hex-digits>
```

`tests/bin/check_all` validates the manifest and every listed fixture in Ada.
Checked-in fixture paths must stay under `tests/fixtures/`, listed files must
exist, byte sizes must match, and CRC32 values must match the manifest.
Deterministic generated fixtures use `path=generated:<id>` and are still
hash-validated against the manifest.

Required generated fixture IDs cover the V1 matrix:

```text
tar-basic
tar-gzip-basic
zip-stored-basic
zip-deflate-basic
gzip-basic
zip-bad-crc
zip-unsupported-method
zip-encrypted
gzip-bad-trailer
```

`tests/fixtures/corpus.txt` is the malformed/security corpus manifest. Each
case record is executed by `tests/bin/check_all` against the real format
detector, archive path classifier, platform key projection, extraction path
planner, or archive dispatch reader. The corpus covers traversal, absolute
paths, Windows drive and drive-relative paths, UNC style paths, alternate data
streams, reserved names, case folding, macOS-style normalization, recognized
unsupported signatures, invalid random input, TAR, TAR.GZ, ZIP stored, ZIP
DEFLATE, standalone gzip, unsupported ZIP compression methods, encrypted ZIP
entries, corrupt ZIP CRCs, corrupt gzip trailers, and malformed archive inputs.

Archive corpus records use this form:

```text
case id=<stable-id> kind=archive input=<generated-fixture-or-malformed-id> source=<source-name> open=<error-code> entries=<physical-count> [payload=<error-code>]
```

`payload` is used when the format can publish an index but the malformed stream
must fail when payload bytes are read.

Fixture IDs are stable API for tests and docs. Do not rename a fixture ID just
because the file layout changes. Update the manifest whenever fixture content
changes intentionally.

Valid TAR fixtures should be generated through public `tarlib` writer APIs
where possible. Gzip and ZIP fixtures should be generated through application
or dependency APIs, not external archive commands.
