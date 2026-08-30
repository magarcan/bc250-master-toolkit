# BC-250 Master Toolkit

Validation-first toolkit for AMD BC-250 on CachyOS.

## v1.9.6

- Preflight validation of BIOS P3.00 telemetry profile and CachyOS BC-250 kernel.
- GPU telemetry: SCLK, busy, temperature, VRAM usage and MCLK.
- CPU telemetry: topology, frequency, governor and temperature.
- Cyan-Skillfish SMU governor status.
- CU/WGP live manager integration, downloaded from upstream.
- UMR installation from official upstream source when it is not available in enabled CachyOS repositories.
- UMA/RAM-VRAM reporting and recommendations; the toolkit does not change the BIOS memory split.
- Modular swap, ZSWAP and RDSEED boot options.
- Informational GPU OC/UV starting profiles. No benchmark and no automatic OC application.
- CPU OC deliberately remains outside the implementation until the research phase.

## Quick start

```bash
git clone https://github.com/magarcan/bc250-master-toolkit.git
cd bc250-master-toolkit
chmod +x bc250-master-toolkit
./bc250-master-toolkit preflight
```

Privileged components:

```bash
sudo ./bc250-master-toolkit cu install
sudo ./bc250-master-toolkit cu umr install
sudo ./bc250-master-toolkit cu status
```

## Commands

```text
preflight
status
cpu
gpu status
gpu oc profiles
memory
cu install
cu umr install
cu status
extras status
extras swap enable [size]
extras zswap enable
extras rdseed hide
```

The toolkit reports state and offers explicit operations. It does not silently apply OC/UV or UMA settings.

## Upstream references

- CU/WGP manager: https://github.com/WinnieLV/bc250-cu-live-manager
- UMR: https://gitlab.freedesktop.org/tomstdenis/umr
- CachyOS BC-250 kernel: https://github.com/MastaG/linux-cachyos-bc250
