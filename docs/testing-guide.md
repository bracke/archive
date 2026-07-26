# Testing Guide

`archive_tests` owns all test and repository-check tooling for `archive`.

Authoritative local gate:

```sh
tests/bin/check_all
```

That executable is written in Ada and currently runs architecture checks,
catalog checks, documentation checks, fixture manifest and CRC32 validation,
root and tests builds, the AUnit suite, the headless runtime smoke, and the
machine-readable release-report smoke.

AUnit coverage is organized around the format-neutral model and the required
V1 workflows: detection, ZIP, gzip, TAR through `tarlib`, immutable indexes,
view projections, command snapshots, settings, localization, preview,
verification, extraction, writes, stale events, task queues, source monitoring,
and temporary resources.

Tests must not require public network access, user settings, ambient locale,
desktop associations, or uncontrolled wall-clock timing.
