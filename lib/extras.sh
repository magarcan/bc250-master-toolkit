#!/usr/bin/env bash
EXTRAS_SWAP=/var/swap/swapfile
EXTRAS_BACKUP=/etc/bc250-master-toolkit
bc250_boot_conf() { if [ -f /etc/default/limine ]; then echo /etc/default/limine; elif [ -f /etc/default/grub ]; then echo /etc/default/grub; else return 1; fi; }
bc250_boot_cmdline_var() { [ -f /etc/default/limine ] && echo 'KERNEL_CMDLINE[default]' || echo GRUB_CMDLINE_LINUX_DEFAULT; }
bc250_set_cmdline_flag() {
  local flag="$1" conf; conf=$(bc250_boot_conf) || return 1
  mkdir -p "$EXTRAS_BACKUP"; [ -f "$conf.orig" ] || cp -a "$conf" "$conf.orig"
  grep -qF "$flag" "$conf" && return 0
  python3 - "$conf" "$flag" <<'PY'
import sys,re
p,flag=sys.argv[1:]
s=open(p).read(); lines=s.splitlines(True)
for i,line in enumerate(lines):
    if line.startswith('KERNEL_CMDLINE[default]') or line.startswith('GRUB_CMDLINE_LINUX_DEFAULT'):
        if line.rstrip().endswith('"'):
            line=line.rstrip('\n'); line=line[:-1]+' '+flag+'"\n'; lines[i]=line
        break
open(p,'w').writelines(lines)
PY
}
bc250_swap_status() { swapon --show --noheadings 2>/dev/null || true; }
bc250_swap_enable() {
  local size="${1:-16G}"; mkdir -p /var/swap
  if [ ! -f "$EXTRAS_SWAP" ]; then
    if findmnt -n -o FSTYPE / | grep -qx btrfs && command -v btrfs >/dev/null 2>&1; then
      btrfs subvolume create /var/swap 2>/dev/null || true
      btrfs filesystem mkswapfile --size "$size" "$EXTRAS_SWAP" 2>/dev/null || true
    fi
    if [ ! -f "$EXTRAS_SWAP" ]; then fallocate -l "$size" "$EXTRAS_SWAP"; chmod 600 "$EXTRAS_SWAP"; mkswap "$EXTRAS_SWAP" >/dev/null; fi
  fi
  grep -qF "$EXTRAS_SWAP none swap" /etc/fstab || echo "$EXTRAS_SWAP none swap defaults,nofail 0 0" >> /etc/fstab
  swapon "$EXTRAS_SWAP" 2>/dev/null || true
}
bc250_zswap_enable() { bc250_set_cmdline_flag systemd.zram=0; bc250_set_cmdline_flag zswap.enabled=1; bc250_set_cmdline_flag zswap.compressor=lz4; bc250_set_cmdline_flag zswap.max_pool_percent=25; bc250_update_boot; }
bc250_rdseed_hide() { bc250_set_cmdline_flag loglevel=0; bc250_update_boot; }
bc250_update_boot() { if command -v limine-update >/dev/null 2>&1; then limine-update; elif command -v grub-mkconfig >/dev/null 2>&1; then grub-mkconfig -o /boot/grub/grub.cfg; fi; }
bc250_extras_status() { echo 'Swap:'; bc250_swap_status; printf 'ZSWAP: '; [ "$(cat /sys/module/zswap/parameters/enabled 2>/dev/null)" = Y ] && echo Y || echo N; printf 'ZRAM: '; [ -e /dev/zram0 ] && echo present || echo not-exposed; printf 'Boot config: '; bc250_boot_conf 2>/dev/null || echo not-found; }
