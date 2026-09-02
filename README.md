# CachyOS BC-250 Master Toolkit

Validation-first platform, performance and diagnostics toolkit for AMD BC-250 / Cyan Skillfish systems running CachyOS.

> **Status:** active development / community project. The toolkit is designed to make the BC-250 stack easier to inspect, configure and recover without hiding potentially dangerous changes behind a single "magic" setup operation.

## What makes this toolkit different

The project combines useful parts of the existing BC-250 community tooling into one CachyOS-oriented workflow while keeping the implementation modular and explicit.

- **Preflight first** — validates the BC-250 hardware, BIOS, kernel, CPU topology, ACPI support, GPU telemetry and required tooling before configuration.
- **Assisted setup** — when Preflight finds an actionable missing dependency, it can route the user to the appropriate setup path rather than blindly applying unrelated changes.
- **Native P3.00 baseline** — current BC-250 firmware is expected to provide native ACPI support; the toolkit verifies this and does not install the legacy ACPI override when native support is present.
- **BIOS-controlled CPU cores** — CPU core unlock is treated as a firmware setting and is validated through the detected CPU topology rather than implemented as a software core-unlock operation.
- **Performance Lab** — GPU and CPU tuning are deliberately separated. GPU OC/UV is implemented; CPU tuning remains a dedicated path for future validated work.
- **GPU Status in Performance Lab** — GPU telemetry, governor state and OC/UV state are presented together with the GPU controls instead of duplicating the information under Hardware & Telemetry.
- **Hardware & Telemetry** — focused live measurements and diagnostics without duplicating the global system summary.
- **System Extras** — current state is shown before actions, using the same status semantics as Preflight, followed by explicit optional changes.
- **Recovery & Revert** — supported rollback paths and configuration backups.
- **Consistent UI semantics** — `[ OK ]`, `[WARN]`, `[INFO]` and `[ERR ]` use the same visual language throughout the interactive interface.

The toolkit does **not** silently flash BIOS firmware, silently change UMA/VRAM allocation, run benchmarks on the user's behalf, or apply overclocking without an explicit user action.

## Quick start

```bash
git clone https://github.com/magarcan/bc250-master-toolkit.git
cd bc250-master-toolkit
chmod +x bc250-master-toolkit
./bc250-master-toolkit
```

Start with **Preflight** (`P`) before changing anything.

For command-line inspection:

```bash
./bc250-master-toolkit preflight
./bc250-master-toolkit status
./bc250-master-toolkit gpu status
./bc250-master-toolkit gpu oc status
./bc250-master-toolkit memory
./bc250-master-toolkit extras status
./bc250-master-toolkit cu status
```

Privileged installation/configuration operations request `sudo` only when required.

## Main menu

```text
Validation
──────────────────────────────────────────────────────────────
[ P]  Preflight             Validate and help configure missing components

Platform
──────────────────────────────────────────────────────────────
[ 1]  Platform Setup        BIOS / kernel / governor / CU-WGP
[ 2]  Performance Lab       GPU status, profiles and CPU tuning
[ 3]  Hardware & Telemetry  Live measurements and diagnostics
[ 4]  System Extras         Status + optional system changes
[ 5]  Recovery & Revert     Undo supported changes

System
──────────────────────────────────────────────────────────────
[ S]  Status                Current system summary
[ U]  Update Toolkit        Update from GitHub checkout
[ 0]  Exit
```

## Preflight

Preflight is the platform gate and is intentionally non-destructive. It validates the system and, when something actionable is missing, can offer the corresponding setup path.

Typical checks include:

- AMD BC-250 PCI device detection (`1002:13fe`)
- BIOS version / recommended P3.00 telemetry profile
- CachyOS BC-250 kernel
- CPU topology, driver and governor
- Native BC-250 ACPI support
- GPU card and telemetry
- Cyan-Skillfish binary, configuration and service
- GPU telemetry and DPM interfaces
- VRAM telemetry
- `cu-live` manager
- UMR

A correctly configured P3.00 system should report native BC-250 ACPI support and explicitly state that no ACPI override or software core-unlock action is required.

## Platform Setup

Platform Setup is for platform-level prerequisites rather than performance tuning.

It covers:

- recommended BIOS validation
- CachyOS BC-250 kernel installation/activation
- Cyan-Skillfish governor verification
- CU/WGP tooling installation/update
- Preflight re-validation

### BIOS and CPU cores

The toolkit **does not flash the BIOS**. P3.00 is treated as the recommended BC-250 firmware baseline for the current platform workflow.

CPU core unlock is a **BIOS operation**. The toolkit detects the resulting CPU topology and reports whether the expected BC-250 cores/threads are enabled. It does not provide a software core-unlock mechanism.

Recommended firmware project:

- **AMD BC-250 UEFI v2.2 Firmware Menu Script / P3.00** — Forbidden-Darkness
  - https://github.com/Forbidden-Darkness/AMD-BC-250-UEFI-v2.2-Firmware-Menu-Script
  - Releases: https://github.com/Forbidden-Darkness/AMD-BC-250-UEFI-v2.2-Firmware-Menu-Script/releases/latest

Firmware flashing remains a manual, user-controlled operation following the upstream project's instructions.

## CachyOS BC-250 kernel

When the active kernel is not the BC-250 kernel, Platform Setup can offer installation after explicit user confirmation.

- **linux-cachyos-bc250** — MastaG
  - Source: https://github.com/MastaG/linux-cachyos-bc250
  - Package repository used by the setup helper: https://github.com/MastaG/linux-cachyos-bc250/releases/download/repo

The toolkit installs the kernel and matching headers but does not pretend that the new kernel is active until the user reboots.

## ACPI

With the current P3.00 BIOS and BC-250 CachyOS kernel, the supported baseline is **native ACPI support**.

The toolkit therefore treats the ACPI fix as a validation item rather than a setup feature:

- native support present → `[ OK ]`, no ACPI override required
- BIOS/kernel combination not sufficient to validate native support → warning
- the legacy `DSDT`/`SSDT` ACPI override path is not automatically installed

Historical ACPI tooling remains documented as community reference material only:

- **bc250-acpi-fix-updated-8c** — mendesrr
  - https://github.com/mendesrr/bc250-acpi-fix-updated-8c

## Performance Lab

Performance is split into separate GPU and CPU paths so that the two tuning domains do not become one ambiguous profile system.

### GPU

The GPU section contains:

```text
GPU
──────────────────────────────────────────────────────────────
[ 1]  GPU Status            Telemetry + governor + OC/UV state
[ 2]  Stock                 1850 MHz @ 930 mV
[ 3]  Balanced              2000 MHz @ 1000 mV
[ 4]  Aggressive            2100 MHz @ 1025 mV  [EXPERIMENTAL]
[ 5]  Maximum Experimental  2200 MHz @ 1050 mV  [EXPERIMENTAL]
[ C]  Custom                Enter MHz / mV / minimum MHz
[ R]  Reset                 Restore saved GPU configuration
[ 0]  Back
```

GPU Status combines the relevant GPU runtime information in one place:

- GPU device
- SCLK
- GPU busy percentage
- GPU temperature
- VRAM usage
- MCLK when available
- CPU temperature
- VRM temperature
- governor state
- current OC/UV configuration

Experimental profiles are explicitly labelled and are not presented as guarantees of stability.

### GPU OC/UV safety model

- Hardware DPM envelope and configured governor envelope are displayed separately.
- Profile application requires administrator privileges.
- The existing Cyan-Skillfish configuration is backed up before modification.
- The governor service is restarted and checked after applying a profile.
- The toolkit does not run a benchmark automatically.
- `Reset` restores the saved pre-profile configuration.

GPU governor and OC/UV support are built around the Cyan-Skillfish SMU governor ecosystem.

- **Cyan-Skillfish governor** — filippor
  - https://github.com/filippor/cyan-skillfish-governor

### CPU

CPU tuning has its own path in Performance Lab. It is deliberately separate from GPU profiles.

CPU core unlocking is not part of CPU tuning: core availability is controlled by BIOS and validated by Preflight.

CPU overclocking/tuning is not presented as a finished feature until the relevant controls and safety model have been validated.

Relevant community projects that inform the BC-250 CPU ecosystem include:

- **bc250_smu_oc** — BC-250 Collective
  - https://github.com/bc250-collective/bc250_smu_oc
- **bc250-core-unlock** — rw-r-r-0644
  - https://github.com/rw-r-r-0644/bc250-core-unlock
- **bc250-efi-core-unlock** — Hexxeh
  - https://github.com/Hexxeh/bc250-efi-core-unlock

These are upstream references, not a claim that all of their functionality is currently implemented by this toolkit.

## CU / WGP

CU/WGP unlocking is handled through the external **cu-live** tooling rather than being implemented as a separate unlock mechanism inside the toolkit.

The toolkit detects the CU/WGP manager during Preflight and provides access to its status/setup path.

- **bc250-cu-live-manager** — WinnieLV
  - https://github.com/WinnieLV/bc250-cu-live-manager

UMR is integrated for low-level GPU register diagnostics:

- **UMR (User Mode Register debugger)** — upstream freedesktop.org / Tom St Denis
  - https://gitlab.freedesktop.org/tomstdenis/umr

## Hardware & Telemetry

Hardware & Telemetry is intentionally focused on measurements and diagnostics rather than global platform status.

Current views include:

- **Live System Snapshot** — CPU/GPU/VRM/VRAM telemetry
- **Memory / UMA** — current RAM/VRAM split and recommendations
- **CU / WGP** — compute-unit state and diagnostics
- **CPU Diagnostics** — topology, driver, governor and thermal information

GPU status is kept under Performance Lab to avoid maintaining two competing GPU status screens.

## Memory / UMA

The Memory / UMA view is informational. It reports current system RAM and VRAM state and provides workload-oriented recommendations.

**The toolkit does not change the BIOS UMA/RAM-VRAM split.**

The BC-250 memory configuration work in the wider community includes:

- **bc250_memcfg** — fanoush
  - https://github.com/fanoush/bc250_memcfg

That project is a reference for the underlying BC-250 memory configuration ecosystem; it is not silently invoked by this toolkit's informational Memory / UMA screen.

## System Extras

System Extras first displays the current state and then presents explicit actions.

Current state covers:

- Swapfile
- ZRAM
- ZSWAP
- boot configuration path
- RDSEED warning state
- CPU mitigation state

Actions include:

- enable a persistent swapfile
- enable ZSWAP and disable systemd ZRAM
- hide the RDSEED boot warning via kernel command line
- disable CPU mitigations via kernel command line
- open CU/WGP + UMR diagnostics
- refresh the displayed state

The interface deliberately keeps each state/action on a compact single line where practical, while retaining enough description to make potentially consequential operations clear.

These operations can modify the boot configuration and therefore require administrator privileges and should be used knowingly.

## Status

The standalone **Status** view is intentionally a compact global system summary rather than another telemetry dashboard. Detailed runtime measurements belong in Live System Snapshot or GPU Status.

This separation avoids duplicating the same temperature, utilization and governor information across several menus.

## Recovery & Revert

Recovery & Revert provides supported rollback paths, including GPU configuration reset and restoration of available boot configuration backups.

The toolkit does not claim to be able to undo arbitrary changes made outside its own managed paths.

## Relationship to existing BC-250 toolkits

This project is intentionally informed by existing community work rather than pretending the BC-250 ecosystem starts here.

In particular:

- **redbeard1083/bc250-toolkit** — an important CachyOS-oriented unified BC-250 toolkit and reference for setup, status, governors, swap/ZSWAP and other platform operations.
  - https://github.com/redbeard1083/bc250-toolkit
- **movacx/bc250-control-center** — a broader graphical BC-250 control center that combines monitoring, GPU SMU control, CPU tuning, CU controls and fan management. Its dashboard/module organization is a useful reference for future UI evolution, particularly its compact real-time monitoring, explicit hardware state, diagnostics/history and separation of advanced controls.
  - https://github.com/movacx/bc250-control-center
- **keyboardspecialist/bc250-steamos** — broader BC-250 SteamOS tooling and a useful reference for unified management of ACPI, power, memory, CU, audio and other platform components.
  - https://github.com/keyboardspecialist/bc250-steamos
- **rpf16rj/bc250-steamos-real-toolkit** — another community toolkit/reference with a broad collection of BC-250 integrations.
  - https://github.com/rpf16rj/bc250-steamos-real-toolkit

### UI ideas worth studying from BC250 Control Center

The `movacx/bc250-control-center` project is particularly interesting as a UI/UX reference, not as a dependency of this toolkit. Its current README describes several ideas that may be useful when the terminal interface evolves:

- a **single dashboard-oriented view** for the most important live hardware state
- grouping CPU temperature, GPU temperature, GPU power, GPU clock, SMU voltage and fan RPM into a compact status band
- showing **current/live CU state separately from the saved next-boot CU profile**
- explicit distinction between **monitoring and controls**, rather than mixing every operation into one screen
- system-health checks, diagnostics and metric history
- clear warnings around potentially dangerous hardware changes
- optional controller/gamepad navigation for SteamOS-style use
- interface scaling and localization
- fan control presented as a dedicated module rather than hidden among unrelated platform settings

We should use these as design references while preserving the Master Toolkit's validation-first philosophy and its deliberate separation of platform setup, GPU/CPU performance, diagnostics and recovery.

## External references

| Component | Upstream project | Role in this toolkit |
|---|---|---|
| Recommended BIOS / P3.00 | https://github.com/Forbidden-Darkness/AMD-BC-250-UEFI-v2.2-Firmware-Menu-Script | Manual firmware reference; never auto-flashed |
| BC-250 CachyOS kernel | https://github.com/MastaG/linux-cachyos-bc250 | Recommended kernel and headers |
| GPU governor | https://github.com/filippor/cyan-skillfish-governor | GPU SMU governor and OC/UV backend |
| CU/WGP manager | https://github.com/WinnieLV/bc250-cu-live-manager | External CU/WGP management |
| UMR | https://gitlab.freedesktop.org/tomstdenis/umr | GPU register diagnostics |
| UMA memory tooling | https://github.com/fanoush/bc250_memcfg | BC-250 memory configuration reference |
| CPU SMU tooling | https://github.com/bc250-collective/bc250_smu_oc | CPU tuning ecosystem reference |
| CPU core unlock | https://github.com/rw-r-r-0644/bc250-core-unlock | BIOS/core-unlock ecosystem reference |
| EFI core unlock | https://github.com/Hexxeh/bc250-efi-core-unlock | EFI core-unlock reference |
| ACPI fix | https://github.com/mendesrr/bc250-acpi-fix-updated-8c | Historical BC-250 ACPI reference |
| CachyOS BC-250 toolkit reference | https://github.com/redbeard1083/bc250-toolkit | Community toolkit reference |
| BC-250 Control Center | https://github.com/movacx/bc250-control-center | UI/UX and broader monitoring/control reference |
| SteamOS BC-250 toolkit reference | https://github.com/keyboardspecialist/bc250-steamos | Broader BC-250 toolkit reference |
| Real BC-250 toolkit reference | https://github.com/rpf16rj/bc250-steamos-real-toolkit | Broader community integration reference |

## Requirements

Designed for:

- AMD BC-250 / Cyan Skillfish hardware
- CachyOS / Arch Linux environment
- `bash`
- `pacman` for kernel/setup operations
- `sudo` for privileged operations
- `systemd` for Cyan-Skillfish service management
- Python 3 with TOML support for GPU configuration parsing

Some diagnostics are optional and are detected rather than blindly assumed (`cpupower`, `vulkaninfo`, UMR, etc.).

## Safety and responsibility

This is community-developed low-level hardware tooling. GPU OC/UV, CPU tuning, CU/WGP changes, boot arguments, swap configuration and firmware changes can affect stability, thermals and hardware behavior.

**Back up important data and understand each operation before applying it.**

The toolkit's philosophy is explicit confirmation, validation and recoverability rather than silent automation.

## License

No license has been declared yet. Individual upstream components remain subject to their own licenses and terms.

## Contributing / testing

Testing on real BC-250 hardware is especially valuable. When reporting an issue, include:

```bash
./bc250-master-toolkit preflight
./bc250-master-toolkit status
./bc250-master-toolkit gpu status
./bc250-master-toolkit gpu oc status
```

Also include the toolkit version and the relevant command/menu path that failed.
