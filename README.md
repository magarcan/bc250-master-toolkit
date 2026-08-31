# CachyOS BC-250 Master Toolkit

Validation-first platform, performance and diagnostics toolkit for AMD BC-250 / Cyan Skillfish systems running CachyOS.

> **Status:** active development / community project. The toolkit is designed to make the BC-250 stack easier to inspect, configure and recover without hiding potentially dangerous changes behind a single "magic" setup operation.

## What makes this toolkit different

The project combines the useful parts of the existing BC-250 community tooling into one CachyOS-oriented workflow while keeping the implementation modular and explicit.

- **Preflight validation first** — read-only detection of BC-250 hardware, BIOS, kernel, CPU topology, GPU telemetry, DPM, services and CU/WGP tooling.
- **Platform Setup** — recommended BIOS and BC-250 kernel guidance, Cyan-Skillfish verification and CU/WGP manager installation.
- **Performance Lab** — one performance area with separate GPU and CPU paths. GPU OC/UV is currently implemented; CPU tuning remains a research/validation path until it is ready.
- **Hardware & Telemetry** — focused hardware views without repeatedly printing the same global system information.
- **System Extras** — swap, ZSWAP, RDSEED and boot-mitigation helpers.
- **Recovery & Revert** — supported rollback paths and configuration backups.
- **Read-only status commands** — useful both interactively and from scripts.

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
  [ P]  Preflight             Full read-only platform validation

Platform
  [ 1]  Platform Setup        BIOS / kernel / governor / CU-WGP
  [ 2]  Performance Lab       GPU and future CPU performance controls
  [ 3]  Hardware & Telemetry  Focused hardware measurements
  [ 4]  System Extras         Swap / ZSWAP / RDSEED / mitigations
  [ 5]  Recovery & Revert     Undo supported changes

System
  [ S]  Status                Current system summary
  [ U]  Update Toolkit        Update from Git checkout
  [ 0]  Exit
```

### Preflight

Preflight is intentionally read-only. It verifies the BC-250 platform and reports the state of the major dependencies before the user starts changing the system.

Typical checks include:

- AMD BC-250 PCI device detection (`1002:13fe`)
- BIOS version / recommended P3.00 telemetry profile
- CachyOS BC-250 kernel
- CPU topology, driver and governor
- GPU card and telemetry
- Cyan-Skillfish binary, configuration and service
- GPU telemetry and DPM interfaces
- VRAM telemetry
- CU/WGP live manager

## BIOS

The toolkit **does not flash the BIOS**. If the recommended firmware is not detected, the user is shown the community firmware project and can choose to open it in a browser.

Recommended firmware project:

- **AMD BC-250 UEFI v2.2 Firmware Menu Script / P3.00** — Forbidden-Darkness
  - https://github.com/Forbidden-Darkness/AMD-BC-250-UEFI-v2.2-Firmware-Menu-Script
  - Releases: https://github.com/Forbidden-Darkness/AMD-BC-250-UEFI-v2.2-Firmware-Menu-Script/releases/latest

P3.00 is treated by the toolkit as the recommended BC-250 telemetry firmware. Firmware flashing remains a manual user-controlled operation following the upstream project's instructions.

## CachyOS BC-250 kernel

When the active kernel is not the BC-250 kernel, Platform Setup can offer installation after explicit user confirmation.

- **linux-cachyos-bc250** — MastaG
  - Source: https://github.com/MastaG/linux-cachyos-bc250
  - Package repository used by the setup helper: https://github.com/MastaG/linux-cachyos-bc250/releases/download/repo

The toolkit installs the kernel and matching headers but does not pretend that the new kernel is active until the user reboots.

## GPU: Cyan-Skillfish

GPU governor and GPU OC/UV support are built around the Cyan-Skillfish SMU governor ecosystem.

- **Cyan-Skillfish governor** — filippor
  - https://github.com/filippor/cyan-skillfish-governor

The toolkit reads the configured governor envelope and, when available, the kernel-advertised DPM hardware envelope. GPU OC/UV profiles are explicit and are applied only after the user selects them.

Current GPU profiles are maintained in the repository under `profiles/`. They are deliberately presented as tuning presets rather than guarantees of stability.

### GPU OC/UV safety model

- Hardware DPM envelope and configured governor envelope are displayed separately.
- Profile application requires administrator privileges.
- The existing Cyan-Skillfish configuration is backed up before modification.
- The governor service is restarted and checked after applying a profile.
- The toolkit does not run a benchmark automatically.
- `Reset` restores the saved pre-profile configuration.

## CU / WGP and UMR

The toolkit integrates the BC-250 community live CU/WGP manager and UMR for diagnostics.

- **bc250-cu-live-manager** — WinnieLV
  - https://github.com/WinnieLV/bc250-cu-live-manager
- **UMR (User Mode Register debugger)** — upstream freedesktop.org / Tom St Denis
  - https://gitlab.freedesktop.org/tomstdenis/umr

The CU manager is downloaded from its upstream script when installed. UMR is built from its official upstream source if it is not available in the enabled CachyOS repositories.

## Memory / UMA

The Memory / UMA view is informational. It reports current system RAM and VRAM state and provides workload-oriented recommendations.

**The toolkit does not change the BIOS UMA/RAM-VRAM split.**

The BC-250 memory configuration work in the wider community includes:

- **bc250_memcfg** — fanoush
  - https://github.com/fanoush/bc250_memcfg

That project is a reference for the underlying BC-250 memory configuration ecosystem; it is not silently invoked by this toolkit's informational Memory / UMA screen.

## CPU support

CPU overclocking is intentionally not presented as a finished feature yet. The Performance Lab has a dedicated CPU path so that validated CPU tuning can be added without creating a second, disconnected performance subsystem.

Relevant community projects that inform the BC-250 CPU ecosystem include:

- **bc250_smu_oc** — BC-250 Collective
  - https://github.com/bc250-collective/bc250_smu_oc
- **bc250-core-unlock** — rw-r-r-0644
  - https://github.com/rw-r-r-0644/bc250-core-unlock
- **bc250-efi-core-unlock** — Hexxeh
  - https://github.com/Hexxeh/bc250-efi-core-unlock

These are upstream references, not a claim that all of their functionality is currently implemented by this toolkit.

## ACPI / firmware ecosystem

The BC-250 community has multiple ACPI/core-unlock approaches. The current toolkit deliberately keeps firmware flashing and legacy ACPI installation out of the automatic path while the P3.00 firmware workflow is the recommended platform baseline.

- **bc250-acpi-fix-updated-8c** — mendesrr
  - https://github.com/mendesrr/bc250-acpi-fix-updated-8c

This is documented as a community reference because it is part of the BC-250 history and tooling ecosystem; it is not silently installed by the current toolkit.

## System Extras

The toolkit includes explicit helpers for:

- swapfile creation / activation
- ZRAM → ZSWAP configuration
- hiding the RDSEED boot warning via kernel command line
- disabling CPU mitigations via kernel command line
- restoration of supported boot configuration backups

These operations can modify the boot configuration and therefore require administrator privileges and should be used knowingly.

## Relationship to existing BC-250 toolkits

This project is intentionally informed by existing community work rather than pretending the BC-250 ecosystem starts here.

In particular:

- **redbeard1083/bc250-toolkit** — the original CachyOS-oriented unified setup toolkit that provided a useful baseline for setup, status, governors, swap/ZSWAP and other BC-250 operations.
  - https://github.com/redbeard1083/bc250-toolkit
- **keyboardspecialist/bc250-steamos** — broader BC-250 SteamOS tooling and a useful reference for unified management of ACPI, power, memory, CU, audio and other platform components.
  - https://github.com/keyboardspecialist/bc250-steamos
- **rpf16rj/bc250-steamos-real-toolkit** — another community toolkit/reference with a broad collection of BC-250 integrations.
  - https://github.com/rpf16rj/bc250-steamos-real-toolkit

The goal here is not to duplicate every feature of those projects. It is to provide a focused CachyOS BC-250 master toolkit with a clear separation between validation, platform setup, performance, diagnostics and recovery.

## External references

| Component | Upstream project | Role in this toolkit |
|---|---|---|
| Recommended BIOS / P3.00 | https://github.com/Forbidden-Darkness/AMD-BC-250-UEFI-v2.2-Firmware-Menu-Script | Manual firmware reference; never auto-flashed |
| BC-250 CachyOS kernel | https://github.com/MastaG/linux-cachyos-bc250 | Recommended kernel and headers |
| GPU governor | https://github.com/filippor/cyan-skillfish-governor | GPU SMU governor and OC/UV backend |
| CU/WGP manager | https://github.com/WinnieLV/bc250-cu-live-manager | Live CU/WGP management |
| UMR | https://gitlab.freedesktop.org/tomstdenis/umr | GPU register diagnostics |
| UMA memory tooling | https://github.com/fanoush/bc250_memcfg | BC-250 memory configuration reference |
| CPU SMU tooling | https://github.com/bc250-collective/bc250_smu_oc | CPU governor/SMU ecosystem reference |
| CPU core unlock | https://github.com/rw-r-r-0644/bc250-core-unlock | BC-250 core-unlock reference |
| EFI core unlock | https://github.com/Hexxeh/bc250-efi-core-unlock | EFI core-unlock reference |
| ACPI fix | https://github.com/mendesrr/bc250-acpi-fix-updated-8c | BC-250 ACPI reference |
| CachyOS BC-250 toolkit reference | https://github.com/redbeard1083/bc250-toolkit | Original CachyOS toolkit reference |
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
