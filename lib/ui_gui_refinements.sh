#!/usr/bin/env bash

# GUI navigation refinements. Backend remains untouched.

# Keep the existing profile implementation and prepend the read-only GPU status
# view. This gives Performance Lab the requested "status, then tune" flow.
eval "$(declare -f bc250_gui_performance | sed '1s/^bc250_gui_performance /bc250_gui_performance_profiles /')"
bc250_gui_performance() {
  bc250_gui_gpu_status
  bc250_gui_performance_profiles
}

# Live Snapshot is an information view, not another menu entry.
bc250_gui_hardware() {
  while true; do
    local choice rc
    choice=$(yad --list --radiolist --markup --title="$BC250_GUI_TITLE — Hardware & Telemetry" --width=880 --height=470 \
      --text='<span size="x-large"><b>HARDWARE & TELEMETRY</b></span>\nLive Snapshot shows the complete current measurement set. Other entries open focused diagnostics.' \
      --column='' --column='View' --column='Description' \
      TRUE 'Memory / UMA' 'RAM / VRAM usage and workload guidance' FALSE 'CU / WGP' 'Compute-unit state and UMR diagnostics' \
      FALSE 'CPU Diagnostics' 'Topology, driver, governor, load and thermals' \
      --print-column=2 --button='Live Snapshot:10' --button='Open Selected:11' --button='Close:0' 2>/dev/null)
    rc=$?
    case "$rc" in
      10) bc250_gui_live_snapshot;;
      11) case "$choice" in
        'Memory / UMA') bc250_gui_memory;;
        'CU / WGP') bc250_gui_run 'CU / WGP Diagnostics' bc250_cu_status;;
        'CPU Diagnostics') bc250_gui_cpu_diagnostics;;
      esac;;
      *) return 0;;
    esac
  done
}

# Detailed status is intentionally removed: the main Extras screen already
# presents the relevant current state in a dedicated section.
bc250_gui_extras() {
  while true; do
    local zswap zram swap_state conf rdseed mitigations rc
    zswap=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo N)
    [ -e /dev/zram0 ] && zram='Active' || zram='Inactive'
    if swapon --show=NAME,TYPE,SIZE --noheadings 2>/dev/null | awk '$2 == "file" {found=1} END{exit !found}'; then swap_state='Enabled'; else swap_state='Not configured'; fi
    conf=$(bc250_boot_conf 2>/dev/null || echo 'Not found'); rdseed='Default'; mitigations='Default'
    [ -f "$conf" ] && grep -q 'loglevel=0' "$conf" 2>/dev/null && rdseed='Hidden'
    [ -f "$conf" ] && grep -q 'mitigations=off' "$conf" 2>/dev/null && mitigations='DISABLED'
    yad --form --markup --title="$BC250_GUI_TITLE — System Extras" --width=900 --height=560 --columns=2 \
      --text='<span size="x-large"><b>SYSTEM EXTRAS</b></span>\nCurrent state is separated from changes. Apply an action only after reviewing its effect.' \
      --field='<b>ACTIVE / CURRENT</b>:LBL' '' \
      --field='Swap:RO' "$swap_state" --field='ZRAM:RO' "$zram" --field='ZSWAP:RO' "$([ "$zswap" = Y ] && echo Enabled || echo Disabled)" \
      --field='Boot configuration:RO' "$conf" --field='RDSEED warning:RO' "$rdseed" --field='CPU mitigations:RO' "$mitigations" \
      --field='<b>ACTIONS / CHANGES</b>:LBL' '' --field='Changes may require a reboot.:LBL' '' \
      --button='Enable Swap:10' --button='Enable ZSWAP:11' --button='Hide RDSEED:12' --button='Disable Mitigations:13' \
      --button='CU / WGP + UMR:14' --button='Close:0' 2>/dev/null
    rc=$?
    case "$rc" in
      10) bc250_gui_confirm 'Enable Swap' 'Enable the persistent 16G swapfile?' ui_require_root extras swap enable 16G;;
      11) bc250_gui_confirm 'Enable ZSWAP' 'Enable ZSWAP and disable systemd ZRAM?\n\nA reboot may be required.' ui_require_root extras zswap enable;;
      12) bc250_gui_confirm 'Hide RDSEED Warning' 'Set boot loglevel=0 to hide the RDSEED warning?' ui_require_root extras rdseed hide;;
      13) bc250_gui_confirm 'Disable CPU Mitigations' 'Add mitigations=off to boot configuration?\n\nThis reduces security protections.' ui_require_root extras mitigations off;;
      14) bc250_gui_run 'CU / WGP + UMR' bc250_cu_status;;
      *) return 0;;
    esac
  done
}
