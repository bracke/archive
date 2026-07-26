# check_all Workflow

`archive_tests` owns the authoritative Ada `check_all` executable.

Current mandatory gates:

- architecture scan over `src/` and `tests/src/`;
- product-scope documentation validation;
- files-mapping documentation validation;
- implementation-plan documentation validation;
- dependency-audit documentation validation;
- fixture manifest and CRC32 validation;
- malformed/security corpus validation;
- dependency/license manifest validation;
- root `alr build`;
- tests `alr build`;
- AUnit suite through `./bin/archive_tests`;
  The suite includes named extraction security, deterministic mutation, and
  completion gate format workflow gates.
- integration tests through a second explicit `./bin/archive_tests` run;
- headless runtime smoke through `./bin/archive --headless-smoke`;
- headless GUI runtime validation through `./bin/archive --headless-gui`.
- live desktop smoke planning is validated in AUnit, and the bounded native
  smoke path exercises repeated event polling, multiple render attempts,
  runtime validation, and a resize step when a display/Vulkan host is available.
- full graph release builds through root and tests `alr build --release`;
- project-local GNATprove proof target through `gnatprove -P tests/proof/archive_release_proof.gpr`;
  the proof target includes checked count arithmetic, stable entry-position
  bounds, extraction output publication gating, save-as publication gating, and
  progress coalescing count invariants.
- packaged smoke test through the release-built `./bin/archive --headless-smoke`;
- machine-readable release report validation through `./bin/release_report --check`;
- persisted release report generation through `./bin/release_report --write obj/release-report.json`;
- release report JSON contract validation for package checksums and release gate tracking.
- release cleanliness scan for leftover staging and temporary publication artifacts.

The architecture scan currently rejects:

- script files and shebang helper tooling;
- CI definitions that do not delegate to the Ada `tests/bin/check_all` workflow;
- direct shell-process helpers in application source;
- direct imports of internal zlib packages such as raw internal inflater packages;
- direct imports of internal `tarlib` packages;
- obvious raw archive-path joining to the extraction destination root.
- file publication outside extraction/write execution packages.
- raw megabyte-scale resource ceilings outside `Archive.Resource_Limits`.
- direct inflate, deflate, or gzip output outside `Archive.Compression.Zlib`.

This is intentionally narrower than the final release gate, but it is real and fails the process when a mandatory check fails.
