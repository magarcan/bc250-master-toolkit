# YAD GUI frontend

The toolkit now has an optional graphical frontend built with **YAD (Yet Another Dialog)**.

## Launch

From the toolkit checkout:

```bash
./bc250-master-toolkit --gui
```

The normal terminal interface is unchanged:

```bash
./bc250-master-toolkit
```

## Install YAD on CachyOS / Arch

```bash
sudo pacman -S yad
```

The GUI checks for YAD at startup and does not install it automatically.

## Architecture

The GUI is deliberately a presentation layer. It does not contain a second implementation of BC-250 hardware operations.

```text
                    BC250 Master Toolkit
                            |
                 +----------+----------+
                 |                     |
                CLI                   YAD
                 |                     |
                 +----------+----------+
                            |
                    existing backend
```

The GUI delegates supported operations to the existing `bc250-master-toolkit` command dispatcher. This keeps the CLI as a first-class interface and avoids maintaining two independent implementations of GPU OC/UV or platform logic.

## Current scope

### Dashboard

- compact system status
- BIOS
- kernel
- CPU topology
- CPU driver/governor
- detected GPU
- navigation to the main GUI areas

### Preflight

Runs the existing non-destructive `preflight` command and displays its complete output in a YAD text window.

### Performance Lab

The first GUI version exposes the existing GPU OC/UV backend:

- GPU status
- Stock — 1850 MHz @ 930 mV
- Balanced — 2000 MHz @ 1000 mV
- Aggressive — 2100 MHz @ 1025 mV (experimental)
- Maximum Experimental — 2200 MHz @ 1050 mV (experimental)
- Custom frequency / voltage / minimum frequency
- GPU OC/UV reset
- CPU tuning status message only

Profile application still goes through the existing CLI path, including its existing privilege handling and validation.

### Hardware & Telemetry

The first version deliberately exposes the existing read-only status path rather than creating a second telemetry implementation.

### System Extras and Recovery

These areas are intentionally informational in the first GUI revision. Their existing CLI menus remain authoritative until each action can be delegated directly to an existing backend command without duplicating implementation.

## Design rule

The GUI should grow by **calling existing backend operations**, not by copying shell logic from `ui.sh`, `ui_main.sh`, `extras.sh`, `gpu_oc.sh`, or other backend modules into the GUI.

That rule is intentional: it lets the terminal UI and YAD UI evolve independently without creating divergent behavior or silently changing the tested backend.
