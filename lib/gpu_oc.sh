#!/usr/bin/env bash

GPU_OC_CONFIG=/etc/cyan-skillfish-governor-smu/config.toml
GPU_OC_STATE_DIR=/etc/bc250-master-toolkit
GPU_OC_BACKUP="$GPU_OC_STATE_DIR/cyan-skillfish-governor-smu.config.toml.base"
GPU_OC_STATE="$GPU_OC_STATE_DIR/gpu-profile"
GPU_OC_PUBLIC_STATE="$GPU_OC_STATE_DIR/gpu-oc-public.env"
CYAN_SERVICE="${CYAN_SERVICE:-cyan-skillfish-governor-smu.service}"

bc250_gpu_oc_read_config() { [ -r "$GPU_OC_CONFIG" ] && cat "$GPU_OC_CONFIG"; }

bc250_gpu_oc_parse_config() {
  local content
  content=$(bc250_gpu_oc_read_config 2>/dev/null) || return 1
  python3 - "$content" <<'PY'
import sys, tomllib
try:
    data=tomllib.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)
points=data.get('safe-points') or data.get('safe_points')
if not isinstance(points,list): raise SystemExit(1)
out=[]
for p in points:
    if isinstance(p,dict):
        f=p.get('frequency',p.get('freq_mhz'))
        v=p.get('voltage',p.get('voltage_mv'))
        if isinstance(f,(int,float)) and isinstance(v,(int,float)): out.append((int(f),int(v)))
if not out: raise SystemExit(1)
out.sort()
print(','.join(f'{f}:{v}' for f,v in out))
PY
}

bc250_gpu_oc_range_from_curve() {
  local curve="$1"
  [ -n "$curve" ] || return 1
  python3 - "$curve" <<'PY'
import sys
pts=[]
try:
    for item in sys.argv[1].replace('\\,', ',').split(','):
        f,_=item.strip().split(':',1)
        pts.append(int(f))
except Exception:
    raise SystemExit(1)
if pts:
    print(f'{min(pts)}|{max(pts)}')
    raise SystemExit(0)
raise SystemExit(1)
PY
}

bc250_gpu_oc_range() { local curve; curve=$(bc250_gpu_oc_parse_config 2>/dev/null) || return 1; bc250_gpu_oc_range_from_curve "$curve"; }
bc250_gpu_oc_config_points() { bc250_gpu_oc_parse_config; }
bc250_gpu_oc_profile_file() { case "$1" in stock|balanced|aggressive|maximum-experimental) printf '%s\n' "$ROOT/profiles/gpu.toml";; *) printf '%s\n' "$ROOT/profiles/gpu-personal.toml";; esac; }
bc250_gpu_oc_profile_points() { local name="$1" file; file=$(bc250_gpu_oc_profile_file "$name"); [ -r "$file" ] || return 1; python3 - "$file" "$name" <<'PY'
import sys,tomllib
try: data=tomllib.load(open(sys.argv[1],'rb'))
except Exception: raise SystemExit(1)
for p in data.get('profile',[]):
    if p.get('name')==sys.argv[2]:
        pts=p.get('safe_points') or p.get('safe-points') or []
        if pts:
            print(','.join(f"{int(x['frequency'])}:{int(x['voltage'])}" for x in pts)); raise SystemExit(0)
raise SystemExit(1)
PY
}
bc250_gpu_oc_profile_value() { local name="$1" key="$2" file; file=$(bc250_gpu_oc_profile_file "$name"); [ -r "$file" ] || return 1; python3 - "$file" "$name" "$key" <<'PY'
import sys,tomllib
try: data=tomllib.load(open(sys.argv[1],'rb'))
except Exception: raise SystemExit(1)
for p in data.get('profile',[]):
    if p.get('name')==sys.argv[2]:
        v=p.get(sys.argv[3]);
        if v is not None: print(v)
        raise SystemExit(0)
raise SystemExit(1)
PY
}
bc250_gpu_oc_profile_exists() { [ -n "$(bc250_gpu_oc_profile_points "$1" 2>/dev/null || true)" ]; }
bc250_gpu_oc_active_profile() { [ -r "$GPU_OC_STATE" ] && cat "$GPU_OC_STATE" || echo none; }
bc250_gpu_oc_publish_state() { local curve="$1" p; mkdir -p "$GPU_OC_STATE_DIR" || return 1; p=$(bc250_gpu_oc_active_profile); umask 022; printf 'GPU_OC_PROFILE=%s\nGPU_OC_CURVE=%s\n' "$p" "$curve" > "$GPU_OC_PUBLIC_STATE" || return 1; chmod 0644 "$GPU_OC_PUBLIC_STATE" "$GPU_OC_STATE" 2>/dev/null || true; }
bc250_gpu_oc_curve_from_public() { local curve; [ -r "$GPU_OC_PUBLIC_STATE" ] || return 1; curve=$(sed -n 's/^GPU_OC_CURVE=//p' "$GPU_OC_PUBLIC_STATE" | head -n1); [ -n "$curve" ] || return 1; printf '%s\n' "${curve//\\,/,}"; }

bc250_gpu_oc_status() {
  local range min max profile curve card dpm source
  profile=$(bc250_gpu_oc_active_profile)
  curve=$(bc250_gpu_oc_curve_from_public 2>/dev/null || true); source=public
  if [ -z "$curve" ]; then curve=$(bc250_gpu_oc_config_points 2>/dev/null || true); source=config; fi
  range=$(bc250_gpu_oc_range 2>/dev/null || true)
  [ -n "$range" ] || range=$(bc250_gpu_oc_range_from_curve "$curve" 2>/dev/null || true)
  card=$(bc250_gpu_card 2>/dev/null || true)
  dpm=$(bc250_gpu_dpm_range "$card" "$(bc250_card_path "$card")" 2>/dev/null || true)
  printf 'GPU OC/UV control\n  Active profile        : %s\n' "$profile"
  if [[ "$dpm" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then printf '  DPM hardware          : %s–%s MHz\n' "${dpm% *}" "${dpm#* }"; else printf '  DPM hardware          : N/A\n'; fi
  if [ -n "$range" ]; then min=${range%%|*}; max=${range#*|}; printf '  Governor range        : %s–%s MHz\n' "$min" "$max"; else printf '  Governor range        : Unknown\n'; fi
  printf '  Safe-points           : %s\n  Config                : %s\n\n' "${curve:-N/A}" "$GPU_OC_CONFIG"
  if [ -n "$range" ] && [ -n "$curve" ]; then
    info 'The governor uses a frequency/voltage safe-point curve; the displayed range is derived from its lowest and highest points.'
    [ "$source" = public ] && [ ! -r "$GPU_OC_CONFIG" ] && info 'Status is read from the toolkit public runtime state because the Cyan-Skillfish configuration is root-only.'
  else warn 'GPU safe-point state is unavailable. Apply a GPU profile once to publish the read-only runtime state.'; fi
}

bc250_gpu_oc_validate_curve() {
  local curve="$1"
  python3 - "$curve" <<'PY'
import sys
raw=sys.argv[1]; pts=[]
try:
    for item in raw.replace('\\,',',').split(','):
        f,v=item.strip().split(':',1); pts.append((int(f),int(v)))
except Exception as e:
    print(f'Invalid safe-point curve: {e}',file=sys.stderr); raise SystemExit(1)
if len(pts)<2: print('At least two safe-points are required.',file=sys.stderr); raise SystemExit(1)
pts.sort()
if len({f for f,v in pts}) != len(pts): print('Safe-point frequencies must be unique.',file=sys.stderr); raise SystemExit(1)
for f,v in pts:
    if not 300 <= f <= 2230: print(f'Invalid frequency: {f} MHz',file=sys.stderr); raise SystemExit(1)
    if not 600 <= v <= 1200: print(f'Invalid voltage: {v} mV',file=sys.stderr); raise SystemExit(1)
for (f1,v1),(f2,v2) in zip(pts,pts[1:]):
    if v2 < v1: print(f'Voltage must not decrease ({f1}:{v1} -> {f2}:{v2}).',file=sys.stderr); raise SystemExit(1)
print(','.join(f'{f}:{v}' for f,v in pts))
PY
}

bc250_gpu_oc_write() {
  local curve="$1" tmp
  mkdir -p "$GPU_OC_STATE_DIR" || return 1
  [ -f "$GPU_OC_CONFIG" ] || { die "Cyan-Skillfish configuration not found: $GPU_OC_CONFIG"; return 1; }
  [ -f "$GPU_OC_BACKUP" ] || cp -a "$GPU_OC_CONFIG" "$GPU_OC_BACKUP" || { die 'Could not create governor configuration backup.'; return 1; }
  tmp=$(mktemp) || { die 'Could not create temporary configuration.'; return 1; }
  python3 - "$GPU_OC_CONFIG" "$tmp" "$curve" <<'PY'
import sys,re
src,dst,curve=sys.argv[1:]
s=open(src,encoding='utf-8').read()
s=re.sub(r'(?ms)^\[frequency-range\]\s*.*?(?=^\[|\Z)', '', s)
s=re.sub(r'(?ms)^\[\[safe-points\]\]\s*.*?(?=^\[|\Z)', '', s)
s=re.sub(r'(?ms)^safe-points\s*=\s*\[.*?\]\s*\n?', '', s)
s=re.sub(r'(?ms)^safe_points\s*=\s*\[.*?\]\s*\n?', '', s)
pts=[]
for item in curve.replace('\\,',',').split(','):
    f,v=item.split(':',1); pts.append((int(f),int(v)))
block='\n# BC-250 Master Toolkit frequency/voltage safe-point curve\n'
for f,v in pts: block += f'[[safe-points]]\nfrequency = {f}\nvoltage = {v}\n\n'
open(dst,'w',encoding='utf-8').write(s.rstrip()+block)
PY
  python3 - "$tmp" <<'PY'
import sys,tomllib
tomllib.load(open(sys.argv[1],'rb'))
PY
  if [ "$?" -ne 0 ]; then rm -f "$tmp"; die 'Generated Cyan-Skillfish configuration is invalid TOML.'; return 1; fi
  mv "$tmp" "$GPU_OC_CONFIG" || { die 'Could not update governor configuration.'; return 1; }
}

bc250_gpu_oc_service_verify() {
  local expected="$1" actual pid cmd errors
  systemctl is-active --quiet "$CYAN_SERVICE" || { die 'Cyan-Skillfish governor is not active after profile application.'; return 1; }
  actual=$(bc250_gpu_oc_parse_config 2>/dev/null || true)
  [ "$actual" = "$expected" ] || { die "Governor configuration mismatch after restart. Expected: $expected ; Found: ${actual:-unreadable}"; return 1; }
  pid=$(systemctl show -p MainPID --value "$CYAN_SERVICE" 2>/dev/null || true)
  if [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 0 ] && [ -r "/proc/$pid/cmdline" ]; then
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline")
    [[ "$cmd" == *"$GPU_OC_CONFIG"* ]] || warn 'Governor is active, but its process command line does not expose the expected config path; runtime config loading cannot be independently confirmed.'
  fi
  errors=$(journalctl -u "$CYAN_SERVICE" -b --no-pager -n 30 2>/dev/null | grep -Ei 'error|failed|panic|invalid.*toml|config.*(error|fail)' || true)
  [ -z "$errors" ] || { warn 'Cyan-Skillfish reported recent configuration/runtime errors:'; printf '%s\n' "$errors"; return 1; }
  return 0
}

bc250_gpu_oc_apply_curve() {
  [ "$EUID" -eq 0 ] || { die 'GPU OC/UV application requires root privileges.'; return 1; }
  local name="$1" requested curve previous_profile previous_curve r
  requested="$2"
  curve=$(bc250_gpu_oc_validate_curve "$requested") || { die 'Invalid GPU safe-point curve.'; return 1; }
  previous_profile=$(bc250_gpu_oc_active_profile)
  previous_curve=$(bc250_gpu_oc_config_points 2>/dev/null || true)
  bc250_gpu_oc_write "$curve" || return 1
  systemctl restart "$CYAN_SERVICE" 2>/dev/null
  if [ "$?" -ne 0 ] || ! bc250_gpu_oc_service_verify "$curve"; then
    warn "GPU profile '$name' was not verified after restart. Restoring previous configuration."
    if [ -n "$previous_curve" ]; then
      bc250_gpu_oc_write "$previous_curve" >/dev/null 2>&1 || true
      systemctl restart "$CYAN_SERVICE" >/dev/null 2>&1 || true
      printf '%s\n' "$previous_profile" > "$GPU_OC_STATE" 2>/dev/null || true
      bc250_gpu_oc_publish_state "$previous_curve" >/dev/null 2>&1 || true
    fi
    return 1
  fi
  printf '%s\n' "$name" > "$GPU_OC_STATE" || { die 'Could not save active GPU profile.'; return 1; }
  bc250_gpu_oc_publish_state "$curve" || { die 'Could not publish read-only GPU OC state.'; return 1; }
  r=$(bc250_gpu_oc_range_from_curve "$curve" 2>/dev/null || true)
  ok "GPU OC/UV applied and verified: $name — safe-point curve"
  [ -n "$r" ] && printf '  Governor range        : %s–%s MHz\n' "${r%%|*}" "${r#*|}"
  info 'Configuration was validated, Cyan-Skillfish restarted successfully, and the loaded configuration was re-read. No benchmark was run.'
}

bc250_gpu_oc_apply() { local n="${1:-}" curve; [ -n "$n" ] || { die 'Use: gpu oc apply <profile>'; return 1; }; bc250_gpu_oc_profile_exists "$n" || { die "Unknown GPU OC profile: $n"; return 1; }; curve=$(bc250_gpu_oc_profile_points "$n") || { die "Could not read safe-point curve for profile: $n"; return 1; }; bc250_gpu_oc_apply_curve "$n" "$curve"; }
bc250_gpu_oc_manual() { local a="${1:-}" b="${2:-}" c="${3:-}" curve; if [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ ]]; then if (( a <= 1000 )); then curve="${c}:700,${a}:${b}"; elif (( a <= 1500 )); then curve="${c}:700,1000:700,${a}:${b}"; elif (( a <= 1850 )); then curve="${c}:700,1000:800,1500:900,${a}:${b}"; elif (( a <= 2000 )); then curve="${c}:700,1000:800,1500:900,1850:930,${a}:${b}"; else curve="${c}:700,1000:800,1500:900,1850:930,2000:1000,${a}:${b}"; fi; bc250_gpu_oc_apply_curve "custom-${a}mhz-${b}mv" "$curve"; else [ -n "$a" ] || { die 'Use: gpu oc manual <freq:mv[,freq:mv,...]> or <maxMHz> <mV> [minMHz]'; return 1; }; bc250_gpu_oc_apply_curve 'custom' "$a"; fi; }
bc250_gpu_oc_reset() { [ "$EUID" -eq 0 ] || { die 'GPU OC/UV reset requires root privileges.'; return 1; }; [ -f "$GPU_OC_BACKUP" ] || { die 'No saved pre-profile configuration exists; nothing to reset.'; return 1; }; cp -a "$GPU_OC_BACKUP" "$GPU_OC_CONFIG" || { die 'Could not restore the saved Cyan-Skillfish configuration.'; return 1; }; rm -f "$GPU_OC_STATE" "$GPU_OC_PUBLIC_STATE"; systemctl restart "$CYAN_SERVICE" 2>/dev/null || { die 'Cyan-Skillfish governor failed to restart after reset.'; return 1; }; ok 'GPU OC/UV reset; original Cyan-Skillfish configuration restored.'; }
bc250_gpu_oc_profiles() { local file="$ROOT/profiles/gpu.toml"; python3 - "$file" <<'PY'
import sys,tomllib
try: data=tomllib.load(open(sys.argv[1],'rb'))
except Exception as e: print(f'[ERR ] Could not read GPU profiles: {e}'); raise SystemExit(1)
print('GPU OC profiles — frequency/voltage safe-point curves')
for p in data.get('profile',[]):
    pts=p.get('safe_points',[])
    curve=' → '.join(f"{x['frequency']} MHz/{x['voltage']} mV" for x in pts)
    print(f"\n{p.get('name','unknown')}: {curve}")
    print(f"  classification: {p.get('classification','unspecified')}")
PY
}
