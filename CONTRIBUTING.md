# Contributing

Work in small passes and keep `tests/bin/check_all` green.

Implementation rules:

- use `tarlib` for TAR reading and writing;
- use the archive zlib adapter for gzip and DEFLATE behavior;
- keep user-visible strings in `share/archive.catalog`;
- route user actions through `Archive.Commands`;
- preserve stable entry IDs independent of archive paths;
- keep extraction and write publication behind validated plans;
- add Ada tests and Ada tooling, not scripts.

Before sending changes, run:

```sh
tests/bin/check_all
```
