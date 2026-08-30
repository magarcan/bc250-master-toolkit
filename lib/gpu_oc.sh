#!/usr/bin/env bash

GPU_OC_CONFIG=/etc/cyan-skillfish-governor-smu/config.toml
GPU_OC_STATE_DIR=/etc/bc250-master-toolkit
GPU_OC_BACKUP="$GPU_OC_STATE_DIR/cyan-skillfish-governor-smu.config.toml.base"
GPU_OC_STATE="$GPU_OC_STATE_DIR/gpu-profile"
GPU_OC_PUBLIC_STATE="$GPU_OC_STATE_DIR/gpu-oc-public.env"
CYAN_SERVICE="${CYAN_SERVICE:-cyan-skillfish-governor-smu.service}"

bc250_gpu_oc_read_config() { [ -r "$GPU_OC_CONFIG" ] && cat "$GPU_OC_CONFIG"; }
bc250_gpu_oc_range() {
  local content
  content=$(bc250_gpu_oc_read_config 2>/dev/null) || return 1
  awk '/^\[frequency-range\]/{r=1;next}/^\[/{r=0} r&&/^[[:space:]]*min[[:space:]]*=/{min=$0} r&&/^[[:space:]]*max[[:space:]]*=/{max=$0} END{gsub(/.*=[[:space:]]*/,"",min);gsub(/.*=[[:space:]]*/,"",max);if(min!=""&&max!="")print min "|" max}' <<< "$content"
}
bc250_gpu_oc_active_profile() { [ -r "$GPU_OC_STATE" ] && cat "$GPU_OC_STATE" || echo none; }
bc250_gpu_oc_profile_file() { case "$1" in stock|balanced|aggressive|maximum-experimental) printf '%s\n' "$ROOT/profiles/gpu.toml";; *) printf '%s\n' "$ROOT/profiles/gpu-personal.toml";; esac; }
bc250_gpu_oc_profile_value() { local name="$1" key="$2" file; file=$(bc250_gpu_oc_profile_file "$name"); [ -r "$file" ] || return 1; awk -v n="$name" -v k="$key" '$0~/^name = /{cur=$0;gsub(/^name = |"/,"",cur)} cur==n && $0~("^" k "[[:space:]]*="){sub(/^[^=]*=[[:space:]]*/,"");gsub(/"/,"");print;exit}' "$file"; }
bc250_gpu_oc_profile_exists() { [ -n "$(bc250_gpu_oc_profile_value "$1" frequency_mhz)" ] && [ -n "$(bc250_gpu_oc_profile_value "$1" voltage_mv)" ]; }

bc250_gpu_oc_publish_state() {
  local f="$1" v="$2" m="$3"
  mkdir -p "$GPU_OC_STATE_DIR"
  umask 022
  printf 'GPU_OC_PROFILE=%q\nGPU_OC_MAX_MHZ=%s\nGPU_OC_MIN_MHZ=%s\nGPU_OC_VOLTAGE_MV=%s\n' "$(bc250_gpu_oc_active_profile)" "$f" "$m" "$v" > "$GPU_OC_PUBLIC_STATE"
  chmod 0644 "$GPU_OC_PUBLIC_STATE" "$GPU_OC_STATE" 2>/dev/null || true
}

bc250_gpu_oc_range_from_public() {
  local m x
  [ -r "$GPU_OC_PUBLIC_STATE" ] || return 1
  m=$(sed -n 's/^GPU_OC_MIN_MHZ=//p' "$GPU_OC_PUBLIC_STATE")
  x=$(sed -n 's/^GPU_OC_MAX_MHZ=//p' "$GPU_OC_PUBLIC_STATE")
  [ -n "$m" ] && [ -n "$x" ] && printf '%s|%s\n' "$m" "$x"
}

bc250_gpu_oc_status() {
  local range min max profile freq volt dpm card
  range=$(bc250_gpu_oc_range 2>/dev/null || bc250_gpu_oc_range_from_public 2>/dev/null || true)
  profile=$(bc250_gpu_oc_active_profile)
  if [ -r "$GPU_OC_PUBLIC_STATE" ]; then
    freq=$(sed -n 's/^GPU_OC_MAX_MHZ=//p' "$GPU_OC_PUBLIC_STATE")
    volt=$(sed -n 's/^GPU_OC_VOLTAGE_MV=//p' "$GPU_OC_PUBLIC_STATE")
  elif [[ "$profile" =~ ^manual-([0-9]+)mhz-([0-9]+)mv$ ]]; then
    freq="${BASH_REMATCH[1]}"; volt="${BASH_REMATCH[2]}"
  else
    freq=$(bc250_gpu_oc_profile_value "$profile" frequency_mhz 2>/dev/null || true)
    volt=$(bc250_gpu_oc_profile_value "$profile" voltage_mv 2>/dev/null || true)
  fi
  if [ -z "$range" ]; then
    if [ "$profile" = none ] && [ -z "$freq" ]; then warn 'GPU OC state is not available; apply a profile or manual setting once.'; return 1; fi
    printf 'GPU OC/UV control\n  Active profile        : %s\n' "$profile"
    [ -n "$freq" ] && [ -n "$volt" ] && printf '  Target                : %s MHz @ %s mV\n' "$freq" "$volt"
    printf '  Governor range        : N/A (legacy state)\n  Config                : %s\n' "$GPU_OC_CONFIG"
    echo; info 'Run a GPU OC operation once to publish the read-only runtime state.'; return 0
  fi
  min=${range%%|*}; max=${range#*|}; card=$(bc250_gpu_card 2>/dev/null || true); dpm=$(bc250_gpu_dpm_range "$card" "$(bc250_card_path "$card")" 2>/dev/null || true)
  printf 'GPU OC/UV control\n  Active profile        : %s\n' "$profile"
  if [[ "$dpm" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then printf '  DPM hardware          : %s–%s MHz\n' "${dpm% *}" "${dpm#* }"; else printf '  DPM hardware          : N/A\n'; fi
  printf '  Governor range        : %s–%s MHz\n' "$min" "$max"
  [ -n "$freq" ] && [ -n "$volt" ] && printf '  Target                : %s MHz @ %s mV\n' "$freq" "$volt"
  printf '  Config                : %s\n' "$GPU_OC_CONFIG"
  echo; info 'DPM hardware is the kernel-advertised envelope; the governor range is the configured operating envelope.'
}

bc250_gpu_oc_validate() { local f="$1" v="$2" m="${3:-300}"; [[ "$f" =~ ^[0-9]+$ && "$v" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]] || die 'Frequency, minimum frequency and voltage must be integer values.'; ((f>=300&&f<=2230)) || die 'Maximum frequency must be between 300 and 2230 MHz.'; ((m>=300&&m<=2230&&m<=f)) || die 'Minimum frequency must be between 300 and maximum frequency.'; ((v>=600&&v<=1200)) || die 'Voltage must be between 600 and 1200 mV.'; }
bc250_gpu_oc_write() { local f="$1" v="$2" m="$3" tmp; mkdir -p "$GPU_OC_STATE_DIR"; [ -f "$GPU_OC_BACKUP" ] || cp -a "$GPU_OC_CONFIG" "$GPU_OC_BACKUP" || die 'Could not create governor configuration backup.'; tmp=$(mktemp) || die 'Could not create temporary configuration.'; python3 - "$GPU_OC_CONFIG" "$tmp" "$m" "$f" "$v" <<'PY'
import re,sys
src,dst,mn,mx,v=sys.argv[1:]; s=open(src,encoding='utf-8').read(); sec=re.search(r'^\[frequency-range\][\s\S]*?(?=^\[|\Z)',s,re.M); block=sec.group(0) if sec else '[frequency-range]\n'; block=re.sub(r'^min\s*=.*$',f'min = {mn}',block,flags=re.M); block=re.sub(r'^max\s*=.*$',f'max = {mx}',block,flags=re.M); block += '' if re.search(r'^min\s*=',block,re.M) else f'min = {mn}\n'; block += '' if re.search(r'^max\s*=',block,re.M) else f'max = {mx}\n'; s=s[:sec.start()]+block+s[sec.end():] if sec else s.rstrip()+'\n\n'+block; open(dst,'w',encoding='utf-8').write(s)
PY
  mv "$tmp" "$GPU_OC_CONFIG" || die 'Could not update governor configuration.'; }
bc250_gpu_oc_apply_values() { need_root; local name="$1" f="$2" v="$3" m="${4:-}" r; [ -f "$GPU_OC_CONFIG" ] || die "Cyan-Skillfish configuration not found: $GPU_OC_CONFIG"; r=$(bc250_gpu_oc_range 2>/dev/null || true); [ -z "$m" ] && m=${r%%|*}; [ -z "$m" ] && m=300; bc250_gpu_oc_validate "$f" "$v" "$m"; bc250_gpu_oc_write "$f" "$v" "$m"; printf '%s\n' "$name" > "$GPU_OC_STATE"; bc250_gpu_oc_publish_state "$f" "$v" "$m"; systemctl restart "$CYAN_SERVICE" 2>/dev/null || die 'Cyan-Skillfish governor failed to restart.'; systemctl is-active --quiet "$CYAN_SERVICE" || die 'Cyan-Skillfish governor is not active after profile application.'; ok "GPU OC/UV applied: $name — ${f} MHz @ ${v} mV"; printf '  Governor range        : %s–%s MHz\n' "$m" "$f"; info 'No benchmark was run. Validate the selected setting with your own workload.'; }
bc250_gpu_oc_apply() { local n="${1:-}" f v m; [ -n "$n" ] || die 'Use: gpu oc apply <profile>'; bc250_gpu_oc_profile_exists "$n" || die "Unknown GPU OC profile: $n"; f=$(bc250_gpu_oc_profile_value "$n" frequency_mhz); v=$(bc250_gpu_oc_profile_value "$n" voltage_mv); m=$(bc250_gpu_oc_profile_value "$n" min_frequency_mhz 2>/dev/null || true); bc250_gpu_oc_apply_values "$n" "$f" "$v" "$m"; }
bc250_gpu_oc_manual() { local f="${1:-}" v="${2:-}" m="${3:-}"; [ -n "$f" ]&&[ -n "$v" ]||die 'Use: gpu oc manual <maxMHz> <mV> [minMHz]'; bc250_gpu_oc_apply_values "manual-${f}mhz-${v}mv" "$f" "$v" "$m"; }
bc250_gpu_oc_reset() { need_root; [ -f "$GPU_OC_BACKUP" ] || die 'No saved pre-profile configuration exists; nothing to reset.'; cp -a "$GPU_OC_BACKUP" "$GPU_OC_CONFIG" || die 'Could not restore the saved Cyan-Skillfish configuration.'; rm -f "$GPU_OC_STATE" "$GPU_OC_PUBLIC_STATE"; systemctl restart "$CYAN_SERVICE" 2>/dev/null || die 'Cyan-Skillfish governor failed to restart after reset.'; ok 'GPU OC/UV reset; original Cyan-Skillfish configuration restored.'; }
