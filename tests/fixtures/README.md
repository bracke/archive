# Fixtures

`manifest.txt` is the authoritative fixture inventory for `archive_tests`.

Each `fixture` record declares a stable ID, repository-relative path,
format label, purpose, byte size, and CRC32. `tests/bin/check_all`
validates the manifest and hashes in Ada before builds and tests run.
