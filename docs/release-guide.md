# Release Guide

Release validation is owned by Ada tooling in the `archive_tests` subcrate.

Required local preflight:

```sh
tests/bin/check_all
```

Release report:

```sh
tests/bin/release_report --check
```

Persisted release report:

```sh
tests/bin/release_report --write obj/release-report.json
```

The report is machine-readable JSON and currently records the repository root,
tests root, missing input count, invalid input count, package input counts,
package byte totals, an aggregate package CRC32 checksum, the mandatory release
gate count, the currently enforced release gate count, the release gate matrix,
the check list, and readiness status. Missing or invalid release inputs,
including malformed/security corpus manifest records, cause `--check` mode to
fail.

`packaging/manifest.txt` is the package contents contract. The release report
validates every `package-file` record, verifies required inputs exist, and
rejects malformed records before a package can be considered ready. The report
also hashes every present package input so package contents changes are visible
in machine-readable release metadata.

Every required release gate from the product scope is represented in the report
as a stable `release_gates` entry. The current Ada tooling marks all required
gates as `enforced` and `check_all` must fail if an enforced command or
repository validation step fails.

The malformed-input corpus gate is enforced by Ada tooling: `check_all`
executes the corpus against production path, extraction, and detection code,
and `release_report` validates that the corpus manifest is present and
well-formed.
The corpus remains deterministic and network-free: newly added archive cases
must be generated or checked in with stable identifiers, and local-header ZIP
corruption is validated before release as part of the same Ada gate.

Extraction security tests, deterministic mutation tests, and the per-format completion gate workflow
are enforced by Ada tooling through named AUnit routines. The release report also marks
dependency/license checks as enforced after validating the root and tests Alire
manifests, local pins, required dependencies, license expression, and dependency
audit documentation. In short, dependency/license checks are enforced by Ada tooling, not by CI shell logic.

Full graph release builds are enforced by Ada tooling through root and tests
`alr build --release` invocations. In short, release builds are enforced by Ada tooling.

Integration tests are enforced by Ada tooling through an explicit integration
test pass that runs the AUnit executable after the development builds. In short,
integration tests are enforced by Ada tooling.

GNATprove is enforced by Ada tooling through the project-local
`tests/proof/archive_release_proof.gpr` target. That target covers checked
count arithmetic, stable entry-position bounds, output publication gating,
save-as publication gating, and progress coalescing count invariants. The intended full-project
command is `alr exec -- gnatprove -P archive.gpr --level=0 --mode=check`; this
currently reaches a GNATprove crash in the transitive `utilada` dependency, so
the enforced release target proves the local release invariants that can be
checked without that dependency crash.

Packaged smoke tests are enforced by Ada tooling by validating
`packaging/manifest.txt` and running the release-built archive executable in
headless smoke mode. In short, packaged smoke tests are enforced by Ada tooling.

Release cleanliness is enforced by Ada tooling through a repository tree scan
that rejects leftover release staging and temporary publication artifacts. In
short, release cleanliness is enforced by Ada tooling.

CI must delegate to the Ada `tests/bin/check_all` workflow. Do not duplicate
test, fixture, architecture, localization, or release validation logic in YAML
or shell snippets.

The final release workflow should keep expanding package artifact construction,
but the release report, package manifest inspection, release builds, packaged
smoke probe, GNATprove proof target, dependency/license checks, artifact
checksums, and persisted release report are all represented by enforced Ada
gates.
