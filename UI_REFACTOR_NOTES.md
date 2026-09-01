# UI refactor notes

The interactive UI is intentionally kept in the `bc250-master-toolkit` entrypoint for this release. Duplicate menu modules are inert compatibility shims.

## Semantics

- **Preflight**: exhaustive, read-only platform validation.
- **Status**: concise current system state.
- **GPU Status**: combines live GPU telemetry with Cyan-Skillfish governor and GPU OC/UV state. The backend `bc250_gpu_oc_status` remains unchanged.
- **Platform Setup**: BIOS, kernel, governor and CU/WGP actions.
- **Performance Lab**: CPU/GPU tuning.
- **Hardware & Telemetry**: focused hardware diagnostics.
- **System Extras**: optional system changes.
- **Recovery & Revert**: supported reversions.

No GPU OC, UMR, CU/WGP or setup backend logic is intentionally changed by this refactor.
