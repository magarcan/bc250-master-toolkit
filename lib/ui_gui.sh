#!/usr/bin/env bash

# BC250 Master Toolkit — YAD GUI
# Presentation layer only. Hardware/system logic remains in the existing backend.

BC250_GUI_TITLE='BC250 Master Toolkit'
BC250_GUI_WIDTH=920
BC250_GUI_HEIGHT=620
BC250_GUI_OK='<span foreground="#70d890"><b>● OK</b></span>'
BC250_GUI_WARN='<span foreground="#f0c75e"><b>● ACTION REQUIRED</b></span>'
BC250_GUI_INFO='<span foreground="#63c7e6"><b>● INFO</b></span>'

bc250_gui_require_yad() {
  command -v yad >/dev/null 2>&1 && return 0
  printf '%s\n' 'YAD is required. Install it with: sudo pacman -S yad' >&2
  return 1
}

bc250_gui_error() {
  yad --error --title="$BC250_GUI_TITLE" --width=560 --text="$*" --button='Close:0' 2>/dev/null || true
}

bc250_gui_info() {
  yad --info --title="$BC250_GUI_TITLE" --width=620 --text="$*" --button='Close:0' 2>/dev/null || true
}

bc250_gui_text() {
  local title="$1" content="$2"
  printf '%s\n' "$content" | yad --text-info --markup --title="$title" --width=920 --height=600 --fontname='monospace 10' --wrap --button='Close:0' 2>/dev/null || true
}

bc250_gui_capture() {
  local fn="$1"; shift
  NO_COLOR=1 "$fn" "$@" 2>&1
}

bc250_gui_run() {
  local title="$1" fn="$2"; shift 2
  local out rc
  out=$(bc250_gui_capture "$fn" "$@")
  rc=$?
  [ -n "$out" ] || out='No output was returned.'
  bc250_gui_text "$title" "$out"
  return "$rc"
}

bc250_gui_confirm() {
  local title="$1" message="$2" fn="$3"; shift 3
  yad --question --title="$title" --width=620 --text="$message" --button='Cancel:1' --button='Apply:0' 2>/dev/null || return 1
  bc250_gui_run "$title" "$fn" "$@"
}

bc250_gui_header() {
  printf '<span size="x-large"><b>BC250 MASTER TOOLKIT</b></span>\n'
  printf '<span foreground="#9aa0a6">Platform • Performance • Diagnostics</span>    <b>v%s</b>\n' "$VERSION"
}

bc250_gui_platform_state() {
  if bc250_bios_ok && bc250_kernel_ok && [ "$(bc250_cpu_cores)" -ge 8 ] 2>/dev/null && [ "$(bc250_cpu_threads)" -ge 16 ] 2>/dev/null && bc250_governor_ok; then
    printf 'READY'
  else
    printf 'ATTENTION REQUIRED'
  fi
}

bc250_gui_status() {
  local value="$1"
  case "$value" in
    OK*) printf '%s' "$BC250_GUI_OK";;
    ACTION*|WARN*|MISSING*|INACTIVE*) printf '%s' "$BC250_GUI_WARN";;
    *) printf '%s' "$BC250_GUI_INFO";;
  esac
}

bc250_gui_dashboard() {
  while true; do
    local card h vr bios kernel cores threads driver governor cpu_freq cpu_temp
    local gpu_sclk gpu_busy gpu_temp gpu_mclk vr_used vr_total vrm_temp platform rc
    card=$(bc250_gpu_card 2>/dev/null || true)
    bios=$(bc250_bios 2>/dev/null || echo Unknown); kernel=$(uname -r)
    cores=$(bc250_cpu_cores); threads=$(bc250_cpu_threads); driver=$(bc250_cpu_driver); governor=$(bc250_cpu_governor)
    cpu_freq=$(bc250_cpu_freq); cpu_temp=$(bc250_cpu_temp)
    gpu_sclk=N/A; gpu_busy=N/A; gpu_temp=N/A; gpu_mclk=N/A; vr_used=N/A; vr_total=N/A
    vrm_temp=$(bc250_vrm_temp 2>/dev/null || echo N/A)
    if [[ "$card" == card* ]]; then
      h=$(bc250_hwmon "$card" 2>/dev/null || true); vr=$(bc250_gpu_vram "$card" 2>/dev/null || echo 'N/A N/A')
      gpu_sclk=$(bc250_gpu_sclk "$h"); gpu_busy=$(bc250_gpu_busy "$card"); gpu_temp=$(bc250_gpu_temp "$h"); gpu_mclk=$(bc250_gpu_mclk "$h")
      vr_used=${vr% *}; vr_total=${vr#* }
    else
      card='Not detected'
    fi
    platform=$(bc250_gui_platform_state)

    yad --form --markup --title="$BC250_GUI_TITLE — Dashboard" --width=940 --height=640 --columns=2 \
      --text="$(bc250_gui_header)\n\n<span size=\"large\"><b>Dashboard</b></span>    Platform: <b>${platform}</b>" \
      --field='<b>PLATFORM</b>:LBL' '' \
      --field='BIOS:RO' "$bios" --field='Kernel:RO' "$kernel" \
      --field='CPU topology:RO' "${cores}C / ${threads}T" --field='CPU driver:RO' "$driver" \
      --field='CPU governor:RO' "$governor" \
      --field='<b>CPU LIVE</b>:LBL' '' \
      --field='Frequency:RO' "${cpu_freq} MHz" --field='Temperature:RO' "${cpu_temp} °C" \
      --field='<b>GPU LIVE</b>:LBL' '' \
      --field='GPU device:RO' "$card" --field='GPU SCLK:RO' "${gpu_sclk} MHz" \
      --field='GPU load:RO' "${gpu_busy} %" --field='GPU temperature:RO' "${gpu_temp} °C" \
      --field='GPU MCLK:RO' "${gpu_mclk} MHz" --field='VRAM:RO' "${vr_used} / ${vr_total} MB" \
      --field='VRM temperature:RO' "${vrm_temp} °C" \
      --button='Preflight:10' --button='Platform Setup:11' --button='Performance Lab:12' \
      --button='Telemetry:13' --button='System Extras:14' --button='Recovery:15' \
      --button='Refresh:16' --button='Exit:0' 2>/dev/null
    rc=$?
    case "$rc" in
      10) bc250_gui_preflight;; 11) bc250_gui_platform;; 12) bc250_gui_performance;;
      13) bc250_gui_hardware;; 14) bc250_gui_extras;; 15) bc250_gui_recovery;;
      16) continue;; *) return 0;;
    esac
  done
}

bc250_gui_preflight_rows() {
  local card bios kernel cores threads
  card=$(bc250_gpu_card 2>/dev/null || true); bios=$(bc250_bios 2>/dev/null || echo Unknown); kernel=$(uname -r)
  cores=$(bc250_cpu_cores); threads=$(bc250_cpu_threads)
  if [[ "$card" == card* ]]; then printf 'TRUE|%s|AMD BC-250 GPU|Detected|PCI 1002:13fe\n' "$BC250_GUI_OK"; else printf 'TRUE|%s|AMD BC-250 GPU|Missing|PCI 1002:13fe\n' "$BC250_GUI_WARN"; fi
  if bc250_bios_ok; then printf 'FALSE|%s|BIOS|%s|P3.00 active\n' "$BC250_GUI_OK" "$bios"; else printf 'FALSE|%s|BIOS|%s|P3.00 recommended\n' "$BC250_GUI_WARN" "$bios"; fi
  if bc250_kernel_ok; then printf 'FALSE|%s|CachyOS BC-250 kernel|%s|Active\n' "$BC250_GUI_OK" "$kernel"; else printf 'FALSE|%s|CachyOS BC-250 kernel|%s|Install recommended kernel\n' "$BC250_GUI_WARN" "$kernel"; fi
  if [ "$cores" -ge 8 ] 2>/dev/null && [ "$threads" -ge 16 ] 2>/dev/null; then printf 'FALSE|%s|CPU topology|%sC / %sT|Expected 8C / 16T\n' "$BC250_GUI_OK" "$cores" "$threads"; else printf 'FALSE|%s|CPU topology|%sC / %sT|Expected 8C / 16T\n' "$BC250_GUI_WARN" "$cores" "$threads"; fi
  if command -v cpupower >/dev/null 2>&1; then printf 'FALSE|%s|cpupower|Installed|Ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|cpupower|Missing|Install dependency\n' "$BC250_GUI_WARN"; fi
  if command -v vulkaninfo >/dev/null 2>&1; then printf 'FALSE|%s|Vulkan tools|Installed|Ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|Vulkan tools|Missing|Install dependency\n' "$BC250_GUI_WARN"; fi
  if [ -x /usr/bin/cyan-skillfish-governor-smu ]; then printf 'FALSE|%s|Cyan-Skillfish governor|Installed|Binary present\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|Cyan-Skillfish governor|Missing|Setup required\n' "$BC250_GUI_WARN"; fi
  if [ -f /etc/cyan-skillfish-governor-smu/config.toml ]; then printf 'FALSE|%s|Cyan-Skillfish configuration|Present|Configured\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|Cyan-Skillfish configuration|Missing|Setup required\n' "$BC250_GUI_WARN"; fi
  if bc250_governor_ok; then printf 'FALSE|%s|GPU governor service|Active|Running\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|GPU governor service|Inactive|Setup required\n' "$BC250_GUI_WARN"; fi
  if bc250_telemetry_ok; then printf 'FALSE|%s|GPU telemetry|Available|Interfaces ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|GPU telemetry|Incomplete|Inspect interfaces\n' "$BC250_GUI_WARN"; fi
  if [[ "$card" == card* ]] && [ -r "/sys/class/drm/$card/device/pp_dpm_sclk" ]; then printf 'FALSE|%s|GPU DPM|Available|SCLK interface ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|GPU DPM|Unavailable|Interface missing\n' "$BC250_GUI_WARN"; fi
  if [[ "$card" == card* ]] && [ -r "/sys/class/drm/$card/device/mem_info_vram_total" ]; then printf 'FALSE|%s|VRAM telemetry|Available|Interface ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|VRAM telemetry|Unavailable|Interface missing\n' "$BC250_GUI_WARN"; fi
  if [ -x /usr/local/bin/bc250-cu-live-manager ]; then printf 'FALSE|%s|CU / WGP manager|Installed|Ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|CU / WGP manager|Missing|Install manager\n' "$BC250_GUI_WARN"; fi
  if bc250_umr_present; then printf 'FALSE|%s|UMR|Available|Ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|UMR|Missing|Install diagnostic dependency\n' "$BC250_GUI_WARN"; fi
}

bc250_gui_fix_component() {
  case "$1" in
    BIOS) bc250_bios_setup_menu_action;;
    'CachyOS BC-250 kernel') bc250_kernel_setup_menu_action;;
    'CU / WGP manager') bc250_cu_setup_menu_action;;
    UMR) bc250_umr_setup_menu_action;;
    'Cyan-Skillfish governor'|'Cyan-Skillfish configuration'|'GPU governor service') bc250_gui_run 'GPU Governor / Status' ui_gpu_status;;
    cpupower) bc250_gui_confirm 'Install cpupower' 'Install cpupower with pacman?' bash -c 'sudo pacman -S --needed cpupower';;
    'Vulkan tools') bc250_gui_confirm 'Install Vulkan tools' 'Install vulkan-tools (vulkaninfo) with pacman?' bash -c 'sudo pacman -S --needed vulkan-tools';;
    'GPU telemetry'|'GPU DPM'|'VRAM telemetry') bc250_gui_info 'Hardware interface' 'The required kernel interface is not available.\n\nNo software installer can safely manufacture this interface. Inspect the kernel/driver state.';;
    'AMD BC-250 GPU') bc250_gui_error 'The BC-250 GPU is not detected. No setup action can continue safely.';;
    'CPU topology') bc250_gui_info 'CPU Topology' "Detected: $(bc250_cpu_cores)C / $(bc250_cpu_threads)T\n\nCore unlocking is a BIOS operation; the toolkit does not patch or unlock CPU cores in software.";;
    *) bc250_gui_info 'No automatic action' "No safe installer is associated with '$1'.";;
  esac
}

bc250_gui_preflight() {
  while true; do
    local rows choice rc
    rows=$(bc250_gui_preflight_rows)
    choice=$(printf '%s' "$rows" | yad --list --radiolist --markup --title="$BC250_GUI_TITLE — Preflight" \
      --width=980 --height=650 \
      --text='<span size="x-large"><b>PLATFORM PREFLIGHT</b></span>\nValidate the complete environment. <span foreground="#70d890"><b>● OK</b></span> is ready; <span foreground="#f0c75e"><b>● ACTION REQUIRED</b></span> can be fixed from this screen.' \
      --column='' --column='Status' --column='Component' --column='Current state' --column='Check / next step' \
      --print-column=3 --button='Fix Selected:10' --button='Refresh:11' --button='Close:0' 2>/dev/null)
    rc=$?
    case "$rc" in
      10) [ -n "$choice" ] && bc250_gui_fix_component "$choice";;
      11) continue;; *) return 0;;
    esac
  done
}

bc250_gui_platform() {
  while true; do
    local rows choice rc
    rows=$(printf '%s\n' \
      "TRUE|$(bc250_gui_status "$(bc250_bios_ok && echo OK || echo ACTION REQUIRED)")|BIOS|$(bc250_bios_ok && echo 'P3.00 active' || echo 'P3.00 recommended')|Firmware is never flashed by the toolkit" \
      "FALSE|$(bc250_gui_status "$(bc250_kernel_ok && echo OK || echo ACTION REQUIRED)")|CachyOS BC-250 Kernel|$(bc250_kernel_ok && uname -r || echo 'Not active')|Install if the recommended kernel is missing" \
      "FALSE|$(bc250_gui_status "$(bc250_governor_ok && echo OK || echo ACTION REQUIRED)")|GPU Governor|$(bc250_governor_ok && echo 'Service active' || echo 'Service inactive')|Cyan-Skillfish SMU governor" \
      "FALSE|$(bc250_gui_status "$( ([ "$(bc250_cpu_cores)" -ge 8 ] && [ "$(bc250_cpu_threads)" -ge 16 ]) && echo OK || echo ACTION REQUIRED )")|CPU Topology|$(bc250_cpu_cores)C / $(bc250_cpu_threads)T|8C / 16T expected; BIOS controls unlock" \
      "FALSE|$(bc250_gui_status "$(test -x /usr/local/bin/bc250-cu-live-manager && echo OK || echo ACTION REQUIRED)")|CU / WGP Manager|$(test -x /usr/local/bin/bc250-cu-live-manager && echo 'Installed' || echo 'Missing')|External compute-unit manager" \
      "FALSE|$(bc250_gui_status "$(bc250_umr_present && echo OK || echo ACTION REQUIRED)")|UMR|$(bc250_umr_present && echo 'Available' || echo 'Missing')|Register-level diagnostics")
    choice=$(printf '%s' "$rows" | yad --list --radiolist --markup --title="$BC250_GUI_TITLE — Platform Setup" --width=980 --height=540 \
      --text='<span size="x-large"><b>PLATFORM SETUP</b></span>\nInspect the platform first. If a prerequisite is missing, <b>Fix Selected</b> runs the existing setup path.' \
      --column='' --column='Status' --column='Component' --column='Current state' --column='Purpose' \
      --print-column=3 --button='Fix Selected:10' --button='Preflight:11' --button='Close:0' 2>/dev/null)
    rc=$?
    case "$rc" in
      10) case "$choice" in BIOS) bc250_bios_setup_menu_action;; 'CachyOS BC-250 Kernel') bc250_kernel_setup_menu_action;; 'GPU Governor') bc250_gui_run 'GPU Governor / Status' ui_gpu_status;; 'CPU Topology') bc250_gui_info 'CPU Topology' "Detected: $(bc250_cpu_cores)C / $(bc250_cpu_threads)T\n\nCore unlocking is performed by BIOS.";; 'CU / WGP Manager') bc250_cu_setup_menu_action;; UMR) bc250_umr_setup_menu_action;; esac;;
      11) bc250_gui_preflight;; *) return 0;;
    esac
  done
}

bc250_gui_performance() {
  while true; do
    local choice rc
    choice=$(yad --list --radiolist --markup --title="$BC250_GUI_TITLE — Performance Lab" --width=920 --height=540 \
      --text='<span size="x-large"><b>PERFORMANCE LAB</b></span>\nValidated GPU OC/UV profiles use the existing backend. Experimental points are clearly marked.' \
      --column='' --column='Profile / Action' --column='Operating point' --column='Classification' \
      TRUE 'GPU Status' 'Live telemetry + OC/UV state' 'Read-only' \
      FALSE 'Stock' '1850 MHz @ 930 mV' 'Safe baseline' \
      FALSE 'Balanced' '2000 MHz @ 1000 mV' 'Validated' \
      FALSE 'Aggressive' '2100 MHz @ 1025 mV' '<span foreground="#f0c75e"><b>EXPERIMENTAL</b></span>' \
      FALSE 'Maximum Experimental' '2200 MHz @ 1050 mV' '<span foreground="#f0c75e"><b>EXPERIMENTAL</b></span>' \
      FALSE 'Custom' 'Frequency / voltage / minimum frequency' 'Backend validated' \
      FALSE 'Reset GPU OC/UV' 'Restore saved configuration' 'Recovery' \
      FALSE 'CPU Performance' 'No settings changed' 'Validation / research' \
      --print-column=2 --button='Select:10' --button='Close:0' 2>/dev/null)
    rc=$?; [ "$rc" -eq 10 ] || return 0
    case "$choice" in
      'GPU Status') bc250_gui_run 'GPU Status' ui_gpu_status;;
      Stock) bc250_gui_confirm 'Apply Stock GPU Profile' 'Apply 1850 MHz @ 930 mV?' ui_require_root gpu oc apply stock;;
      Balanced) bc250_gui_confirm 'Apply Balanced GPU Profile' 'Apply 2000 MHz @ 1000 mV?' ui_require_root gpu oc apply balanced;;
      Aggressive) bc250_gui_confirm 'Experimental GPU Profile' 'Apply 2100 MHz @ 1025 mV?\n\nThis profile is EXPERIMENTAL.' ui_require_root gpu oc apply aggressive;;
      'Maximum Experimental') bc250_gui_confirm 'Experimental GPU Profile' 'Apply 2200 MHz @ 1050 mV?\n\nThis profile is EXPERIMENTAL.' ui_require_root gpu oc apply maximum-experimental;;
      Custom)
        local values freq volt minimum
        values=$(yad --form --title='Custom GPU OC/UV' --width=620 --text='<b>Custom operating point</b>\nThe existing backend performs validation and application.' \
          --field='Maximum frequency (MHz):NUM' '2000!600..2400!1' --field='Voltage (mV):NUM' '1000!800..1200!1' --field='Minimum frequency (MHz):NUM' '600!300..2200!1' \
          --separator='|' --button='Cancel:1' --button='Continue:0' 2>/dev/null) || continue
        IFS='|' read -r freq volt minimum _ <<< "$values"
        bc250_gui_confirm 'Apply Custom GPU OC/UV' "Apply ${freq%.*} MHz @ ${volt%.*} mV (minimum ${minimum%.*} MHz)?" ui_require_root gpu oc manual "${freq%.*}" "${volt%.*}" "${minimum%.*}";;
      'Reset GPU OC/UV') bc250_gui_confirm 'Reset GPU OC/UV' 'Restore the saved GPU configuration?' ui_require_root gpu oc reset;;
      'CPU Performance') bc250_gui_info 'CPU Performance' 'CPU tuning is still validation-only.\n\nNo CPU settings are changed by this GUI.';;
    esac
  done
}

bc250_gui_live_snapshot() {
  while true; do
    local card h vr load result cpu_freq cpu_temp cores threads gpu_sclk gpu_busy gpu_temp gpu_mclk vr_used vr_total vrm_temp
    card=$(bc250_gpu_card 2>/dev/null || true); [[ "$card" == card* ]] || { bc250_gui_error 'BC-250 GPU not detected.'; return 1; }
    h=$(bc250_hwmon "$card" 2>/dev/null || true); vr=$(bc250_gpu_vram "$card"); load=$(ui_cpu_load_percent)
    cpu_freq=$(bc250_cpu_freq); cpu_temp=$(bc250_cpu_temp); cores=$(bc250_cpu_cores); threads=$(bc250_cpu_threads)
    gpu_sclk=$(bc250_gpu_sclk "$h"); gpu_busy=$(bc250_gpu_busy "$card"); gpu_temp=$(bc250_gpu_temp "$h"); gpu_mclk=$(bc250_gpu_mclk "$h")
    vr_used=${vr% *}; vr_total=${vr#* }; vrm_temp=$(bc250_vrm_temp)
    yad --form --markup --title="$BC250_GUI_TITLE — Live Telemetry" --width=820 --height=520 --columns=2 \
      --text='<span size="x-large"><b>LIVE TELEMETRY</b></span>\nRead-only hardware snapshot. Refresh to sample again.' \
      --field='<b>CPU</b>:LBL' '' --field='Load:RO' "${load} %" --field='Frequency:RO' "${cpu_freq} MHz" --field='Temperature:RO' "${cpu_temp} °C" --field='Topology:RO' "${cores}C / ${threads}T" \
      --field='<b>GPU</b>:LBL' '' --field='Device:RO' "$card" --field='SCLK:RO' "${gpu_sclk} MHz" --field='Load:RO' "${gpu_busy} %" --field='Temperature:RO' "${gpu_temp} °C" --field='MCLK:RO' "${gpu_mclk} MHz" --field='VRAM:RO' "${vr_used} / ${vr_total} MB" \
      --field='<b>VRM</b>:LBL' '' --field='Temperature:RO' "${vrm_temp} °C" \
      --button='Refresh:10' --button='Close:0' 2>/dev/null
    result=$?; [ "$result" -eq 10 ] || return 0
  done
}

bc250_gui_memory() {
  local mem total avail vused vtotal used rec
  mem=$(bc250_memory_status); read -r total avail vused vtotal <<< "$mem"; used=$((total-avail)); rec=$(bc250_memory_recommendations)
  yad --form --markup --title="$BC250_GUI_TITLE — Memory / UMA" --width=820 --height=480 --columns=2 \
    --text='<span size="x-large"><b>MEMORY / UMA</b></span>\nInformational view. The BIOS controls the UMA split; this GUI does not alter it.' \
    --field='System RAM total:RO' "${total} MB" --field='System RAM used:RO' "${used} MB" --field='System RAM available:RO' "${avail} MB" \
    --field='VRAM used:RO' "${vused} MB" --field='VRAM total:RO' "${vtotal} MB" --field='Recommendations:TXT' "$rec" --button='Close:0' 2>/dev/null || true
}

bc250_gui_cpu_diagnostics() {
  yad --form --markup --title="$BC250_GUI_TITLE — CPU Diagnostics" --width=760 --height=440 --columns=2 \
    --text='<span size="x-large"><b>CPU DIAGNOSTICS</b></span>\nRead-only CPU topology, policy and thermal data.' \
    --field='Cores / Threads:RO' "$(bc250_cpu_cores)C / $(bc250_cpu_threads)T" --field='Driver:RO' "$(bc250_cpu_driver)" \
    --field='Governor:RO' "$(bc250_cpu_governor)" --field='Current frequency:RO' "$(bc250_cpu_freq) MHz" \
    --field='Load:RO' "$(ui_cpu_load_percent) %" --field='Temperature:RO' "$(bc250_cpu_temp) °C" --button='Close:0' 2>/dev/null || true
}

bc250_gui_hardware() {
  while true; do
    local choice rc
    choice=$(yad --list --radiolist --markup --title="$BC250_GUI_TITLE — Hardware & Telemetry" --width=880 --height=470 \
      --text='<span size="x-large"><b>HARDWARE & TELEMETRY</b></span>\nMeasurements and diagnostics. No tuning changes are made from this section.' \
      --column='' --column='View' --column='Description' \
      TRUE 'Live System Snapshot' 'CPU / GPU / VRM / VRAM live measurements' FALSE 'Memory / UMA' 'RAM / VRAM usage and workload guidance' \
      FALSE 'CU / WGP' 'Compute-unit state and UMR diagnostics' FALSE 'CPU Diagnostics' 'Topology, driver, governor, load and thermals' \
      --print-column=2 --button='Open:10' --button='Close:0' 2>/dev/null)
    rc=$?; [ "$rc" -eq 10 ] || return 0
    case "$choice" in
      'Live System Snapshot') bc250_gui_live_snapshot;; 'Memory / UMA') bc250_gui_memory;;
      'CU / WGP') bc250_gui_run 'CU / WGP Diagnostics' bc250_cu_status;; 'CPU Diagnostics') bc250_gui_cpu_diagnostics;;
    esac
  done
}

bc250_gui_extras() {
  while true; do
    local zswap zram swap_state conf rdseed mitigations rc
    zswap=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo N); [ -e /dev/zram0 ] && zram='Active' || zram='Inactive'
    if swapon --show=NAME,TYPE,SIZE --noheadings 2>/dev/null | awk '$2 == "file" {found=1} END{exit !found}'; then swap_state='Enabled'; else swap_state='Not configured'; fi
    conf=$(bc250_boot_conf 2>/dev/null || echo 'Not found'); rdseed='Default'; mitigations='Default'
    [ -f "$conf" ] && grep -q 'loglevel=0' "$conf" 2>/dev/null && rdseed='Hidden'
    [ -f "$conf" ] && grep -q 'mitigations=off' "$conf" 2>/dev/null && mitigations='DISABLED'
    yad --form --markup --title="$BC250_GUI_TITLE — System Extras" --width=900 --height=600 --columns=2 \
      --text='<span size="x-large"><b>SYSTEM EXTRAS</b></span>\nSeparate <b>current state</b> from <b>changes</b>. Actions are explicit and reversible where supported.' \
      --field='<b>ACTIVE / CURRENT</b>:LBL' '' \
      --field='Swap:RO' "$swap_state" --field='ZRAM:RO' "$zram" --field='ZSWAP:RO' "$([ "$zswap" = Y ] && echo Enabled || echo Disabled)" \
      --field='Boot configuration:RO' "$conf" --field='RDSEED warning:RO' "$rdseed" --field='CPU mitigations:RO' "$mitigations" \
      --field='<b>ACTIONS / CHANGES</b>:LBL' '' --field='Select an action from the buttons below.:LBL' '' \
      --button='Enable Swap:10' --button='Enable ZSWAP:11' --button='Hide RDSEED:12' --button='Disable Mitigations:13' \
      --button='CU / WGP + UMR:14' --button='Detailed Status:15' --button='Close:0' 2>/dev/null
    rc=$?
    case "$rc" in
      10) bc250_gui_confirm 'Enable Swap' 'Enable the persistent 16G swapfile?' ui_require_root extras swap enable 16G;;
      11) bc250_gui_confirm 'Enable ZSWAP' 'Enable ZSWAP and disable systemd ZRAM?\n\nA reboot may be required.' ui_require_root extras zswap enable;;
      12) bc250_gui_confirm 'Hide RDSEED Warning' 'Set boot loglevel=0 to hide the RDSEED warning?' ui_require_root extras rdseed hide;;
      13) bc250_gui_confirm 'Disable CPU Mitigations' 'Add mitigations=off to boot configuration?\n\nThis reduces security protections.' ui_require_root extras mitigations off;;
      14) bc250_gui_run 'CU / WGP + UMR' bc250_cu_status;;
      15) bc250_gui_run 'System Extras — Detailed Status' ui_extras_status;;
      *) return 0;;
    esac
  done
}

bc250_gui_restore_boot() {
  yad --question --title='Restore Boot Configuration' --width=640 --text='Restore /etc/default/limine from the toolkit backup when available?' --button='Cancel:1' --button='Restore:0' 2>/dev/null || return 1
  local out rc
  out=$(sudo bash -c 'if [ -f /etc/default/limine.orig ]; then cp -a /etc/default/limine.orig /etc/default/limine; command -v limine-update >/dev/null 2>&1 && limine-update || true; echo "Boot configuration restored."; else echo "No boot configuration backup found."; exit 2; fi' 2>&1); rc=$?
  bc250_gui_text 'Restore Boot Configuration' "$out"; return "$rc"
}

bc250_gui_recovery() {
  while true; do
    local choice rc
    choice=$(yad --list --radiolist --markup --title="$BC250_GUI_TITLE — Recovery & Revert" --width=880 --height=470 \
      --text='<span size="x-large"><b>RECOVERY & REVERT</b></span>\nRollback only supported toolkit changes. No destructive action is performed without confirmation.' \
      --column='' --column='Action' --column='Description' TRUE 'Reset GPU OC/UV' 'Restore saved GPU configuration' FALSE 'Restore Boot Configuration' 'Restore toolkit boot backup when available' FALSE 'Show System Status' 'Inspect current state before reverting' \
      --print-column=2 --button='Select:10' --button='Close:0' 2>/dev/null)
    rc=$?; [ "$rc" -eq 10 ] || return 0
    case "$choice" in
      'Reset GPU OC/UV') bc250_gui_confirm 'Reset GPU OC/UV' 'Restore the saved GPU configuration?' ui_require_root gpu oc reset;;
      'Restore Boot Configuration') bc250_gui_restore_boot;; 'Show System Status') bc250_gui_run 'System Status' ui_status;;
    esac
  done
}

bc250_gui_main() {
  bc250_gui_require_yad || { printf '%s\n' 'YAD is required for the graphical interface.' >&2; return 1; }
  bc250_gui_dashboard
}
