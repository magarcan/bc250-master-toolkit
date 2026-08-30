# Changelog

## v1.9.6

- Rebased the project around the GitHub repository as the source of truth.
- Fixed the banner/version presentation.
- Preflight now treats BIOS P3.00 and the CachyOS BC-250 kernel as explicit telemetry prerequisites.
- Integrated the upstream BC-250 CU/WGP live manager download flow.
- Added a dedicated UMR source-build path for CachyOS when `pacman` has no `umr` package.
- Added GPU/CPU/VRAM telemetry reporting.
- Added informational GPU OC/UV profiles without benchmark functionality or automatic application.
- Added UMA reporting/recommendations without changing BIOS memory allocation.
- Added modular swap, ZSWAP and RDSEED boot options.
- Deferred CPU OC/UV implementation to the research phase.
