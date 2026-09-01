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
import sys
try:
    import tomllib
    data=tomllib.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)
points=data.get('safe-points') or data.get('safe_points')
if isinstance(points,list):
    out=[]
    for p in points:
        if isinstance(p,dict):
            f=p.get('frequency',p.get('freq_mhz'))
            v=p.get('voltage',p.get('voltage_mv'))
            if isinstance(f,(int,float)) and isinstance(v,(int,float)):
                out.append((int(f),int(v)))
    if out:
        out.sort()
        print(','.join(f'{f}:{v}' for f,v in out))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

bc250_gpu_oc_range() {
  local curve
  curve=$(bc250_gpu_oc_parse_config 2>/dev/null) || return 1
  python3 - "$curve" <<'PY'
import sys
pts=[]
for item in sys.argv[1].split(','):
    f,_=item.split(':',1)
    pts.append(int(f))
if pts:
    print(f'{min(pts)}|{max(pts)}')
    raise SystemExit(0)
raise SystemExit(1)
PY
}

bc250_gpu_oc_config_points() { bc250_gpu_oc_parse_config; }

bc250_gpu_oc_profile_file() { case "$1" in stock|balanced|aggressive|maximum-experimental) printf '%s\n' "$ROOT/profiles/gpu.toml";; *) printf '%s\n' "$ROOT/profiles/gpu-personal.toml";; esac; }

bc250_gpu_oc_profile_points() {
  local name="$1" file
  file=$(bc250_gpu_oc_profile_file "$name")
  [ -r "$file" ] || return 1
  python3 - "$file" "$name" <<'PY'
import sys,tomllib
try: data=tomllib.load(open(sys.argv[1],'rb'))
except Exception: raise SystemExit(1)
for p in data.get('profile',[]):
    if p.get('name')==sys.argv[2]:
        pts=p.get('safe_points') or p.get('safe-points') or []
        if pts:
            print(','.join(f"{int(x['frequency'])}:{int(x['voltage'])}" for x in pts))
            raise SystemExit(0)
raise SystemExit(1)
PY
}

bc250_gpu_oc_profile_value() {
  local name="$1" key="$2" file
  file=$(bc250_gpu_oc_profile_file "$name")
  [ -r "$file" ] || return 1
  python3 - "$file" "$name" "$key" <<'PY'
import sys,tomllib
try: data=tomllib.load(open(sys.argv[1],'rb'))
except Exception: raise SystemExit(1)
for p in data.get('profile',[]):
    if p.get('name')==sys.argv[2]:
        v=p.get(sys.argv[3])
        if v is not None: print(v)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

bc250_gpu_oc_profile_exists() { [ -n "$(bc250_gpu_oc_profile_points "$1" 2>/dev/null || true)" ]; }
bc250_gpu_oc_active_profile() { [ -r "$GPU_OC_STATE" ] && cat "$GPU_OC_STATE" || echo none; }

bc250_gpu_oc_publish_state() {
  local curve="$1" p
  mkdir -p "$GPU_OC_STATE_DIR" || return 1
  p=$(bc250_gpu_oc_active_profile)
  umask 022
  printf 'GPU_OC_PROFILE=%s\nGPU_OC_CURVE=%s\n' "$p" "$curve" > "$GPU_OC_PUBLIC_STATE" || return 1
  chmod 0644 "$GPU_OC_PUBLIC_STATE" "$GPU_OC_STATE" 2>/dev/null || true
}

bc250_gpu_oc_curve_from_public() {
  [ -r "$GPU_OC_PUBLIC_STATE" ] || return 1
  sed -n 's/^GPU_OC_CURVE=//p' "$GPU_OC_PUBLIC_STATE" | head -n1
}

bc250_gpu_oc_status() {
  local range min max profile curve card dpm
  profile=$(bc250_gpu_oc_active_profile)
  range=$(bc250_gpu_oc_range 2>/dev/null || true)
  curve=$(bc250_gpu_oc_curve_from_public 2>/dev/null || true)
  [ -n "$curve" ] || curve=$(bc250_gpu_oc_config_points 2>/dev/null || true)
  if [ -z "$range" ]; then
    printf 'GPU OC/UV control\n  Active profile        : %s\n' "$profile"
    [ -n "$curve" ] && printf '  Safe-points           : %s\n' "$curve"
    printf '  Governor range        : Unknown\n  Config                : %s\n' "$GPU_OC_CONFIG"
    echo
    warn 'GPU safe-point curve could not be read from the Cyan-Skillfish configuration.'
    return 0
  fi
  min=${range%%|*}; max=${range#*|}
  card=$(bc250_gpu_card 2>/dev/null || true)
  dpm=$(bc250_gpu_dpm_range "$card" "$(bc250_card_path "$card")" 2>/dev/null || true)
  printf 'GPU OC/UV control\n  Active profile        : %s\n' "$profile"
  if [[ "$dpm" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
    printf '  DPM hardware          : %s–%s MHz\n' "${dpm% *}" "${dpm#* }"
  else
    printf '  DPM hardware          : N/A\n'
  fi
  printf '  Governor range        : %s–%s MHz\n' "$min" "$max"
  printf '  Safe-points           : %s\n' "${curve:-N/A}"
  printf '  Config                : %s\n' "$GPU_OC_CONFIG"
  echo
  info 'The governor now uses a frequency/voltage safe-point curve; the displayed range is derived from its lowest and highest points.'
}

bc250_gpu_oc_validate_curve() {
  local curve="$1"
  python3 - "$curve" <<'PY'
import sys
raw=sys.argv[1]
pts=[]
try:
    for item in raw.split(','):
        f,v=item.strip().split(':',1)
        f,v=int(f),int(v)
        if not 300 <= f <= 2230: raise ValueError('frequency must be 300-2230 MHz')
        if not 600 <= v <= 1200: raise ValueError('voltage must be 600-1200 mV')
        pts.append((f,v))
except Exception as e:
    print(f'Invalid safe-point curve: {e}',file=sys.stderr); raise SystemExit(1)
if len(pts)<2: print('At least two safe-points are required.',file=sys.stderr); raise SystemExit(1)
if len({f for f,v in pts}) != len(pts): print('Safe-point frequencies must be unique.',file=sys.stderr); raise SystemExit(1)
pts.sort()
print(','.join(f'{f}:{v}' for f,v in pts))
PY
}

bc250_gpu_oc_write() {
  local curve="$1" tmp
  mkdir -p "$GPU_OC_STATE_DIR"
  [ -f "$GPU_OC_BACKUP" ] || cp -a "$GPU_OC_CONFIG" "$GPU_OC_BACKUP" || die 'Could not create governor configuration backup.'
  tmp=$(mktemp) || die 'Could not create temporary configuration.'
  python3 - "$GPU_OC_CONFIG" "$tmp" "$curve" <<'PY'
import re,sys
src,dst,curve=sys.argv[1:]
s=open(src,encoding='utf-8').read()
# Remove all legacy range representations and every existing safe-point form.
s=re.sub(r'(?m)^\s*\[frequency-range\]\s*\n(?:^[^\[]*\n?)*', '', s)
s=re.sub(r'(?m)^\s*(?:safe-points|safe_points)\s*=\s*\[[\s\S]*?\]\s*\n?', '', s)
s=re.sub(r'(?m)^\s*\[\[safe-points\]\]\s*\n(?:^[^\[]*\n?)*', '', s)
pts=[]
for item in curve.split(','):
    f,v=item.split(':',1); pts.append((int(f),int(v)))
block='\n# BC-250 Master Toolkit frequency/voltage safe-point curve\n'
for f,v in pts:
    block += f'[[safe-points]]\nfrequency = {f}\nvoltage = {v}\n\n'
s=s.rstrip()+block
open(dst,'w',encoding='utf-8').write(s)
PY
  # Validate the generated TOML before replacing the live configuration.
  python3 - "$tmp" <<'PY' || { rm -f "$tmp"; die 'Generated Cyan-Skillfish configuration is invalid TOML.'; }
import sys,tomllib
tomllib.load(open(sys.argv[1],'rb'))
PY
  mv "$tmp" "$GPU_OC_CONFIG" || die 'Could not update governor configuration.'
}

bc250_gpu_oc_apply_curve() {
  [ "$EUID" -eq 0 ] || die 'GPU OC/UV application requires root privileges.'
  local name="$1" curve r
  curve=$(bc250_gpu_oc_validate_curve "$2") || die 'Invalid GPU safe-point curve.'
  bc250_gpu_oc_write "$curve"
  printf '%s\n' "$name" > "$GPU_OC_STATE" || die 'Could not save active GPU profile.'
  bc250_gpu_oc_publish_state "$curve" || die 'Could not publish read-only GPU OC state.'
  systemctl restart "$CYAN_SERVICE" 2>/dev/null || die 'Cyan-Skillfish governor failed to restart.'
  systemctl is-active --quiet "$CYAN_SERVICE" || die 'Cyan-Skillfish governor is not active after profile application.'
  r=$(bc250_gpu_oc_range 2>/dev/null || true)
  ok "GPU OC/UV applied: $name — safe-point curve"
  [ -n "$r" ] && printf '  Governor range        : %s–%s MHz\n' "${r%%|*}" "${r#*|}"
  info 'No benchmark was run. Validate the selected curve with your own workload.'
}

bc250_gpu_oc_apply() {
  local n="${1:-}" curve
  [ -n "$n" ] || die 'Use: gpu oc apply <profile>'
  bc250_gpu_oc_profile_exists "$n" || die "Unknown GPU OC profile: $n"
  curve=$(bc250_gpu_oc_profile_points "$n") || die "Could not read safe-point curve for profile: $n"
  bc250_gpu_oc_apply_curve "$n" "$curve"
}

bc250_gpu_oc_manual() {
  local a="${1:-}" b="${2:-}" c="${3:-}" curve
  if [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ ]]; then
    if (( a <= 1000 )); then
      curve="${c}:700,${a}:${b}"
    elif (( a <= 1500 )); then
      curve="${c}:700,1000:700,${a}:${b}"
    elif (( a <= 1850 )); then
      curve="${c}:700,1000:800,1500:900,${a}:${b}"
    elif (( a <= 2000 )); then
      curve="${c}:700,1000:800,1500:900,1850:930,${a}:${b}"
    else
      curve="${c}:700,1000:800,1500:900,1850:930,2000:1000,${a}:${b}"
    fi
    bc250_gpu_oc_apply_curve "custom-${a}mhz-${b}mv" "$curve"
  else
    [ -n "$a" ] || die 'Use: gpu oc manual <freq:mv[,freq:mv,...]> or <maxMHz> <mV> [minMHz]'
    bc250_gpu_oc_apply_curve 'custom' "$a"
  fi
}

bc250_gpu_oc_reset() {
  [ "$EUID" -eq 0 ] || die 'GPU OC/UV reset requires root privileges.'
  [ -f "$GPU_OC_BACKUP" ] || die 'No saved pre-profile configuration exists; nothing to reset.'
  cp -a "$GPU_OC_BACKUP" "$GPU_OC_CONFIG" || die 'Could not restore the saved Cyan-Skillfish configuration.'
  rm -f "$GPU_OC_STATE" "$GPU_OC_PUBLIC_STATE"
  systemctl restart "$CYAN_SERVICE" 2>/dev/null || die 'Cyan-Skillfish governor failed to restart after reset.'
  ok 'GPU OC/UV reset; original Cyan-Skillfish configuration restored.'
}

bc250_gpu_oc_profiles() {
  local file="$ROOT/profiles/gpu.toml"
  python3 - "$file" <<'PY'
import sys,tomllib
try: data=tomllib.load(open(sys.argv[1],'rb'))
except Exception as e: print(f'[ERR ] Could not read GPU profiles: {e}'); raise SystemExit(1)
print('GPU OC profiles — frequency/voltage safe-point curves')
for p in data.get('profile',[]):
    pts=p.get('safe_points',[])
    curve=', '.join(f"{x['frequency']} MHz/{x['voltage']} mV" for x in pts)
    print(f"\n{p.get('name','unknown')}: {curve}")
    print(f"  classification: {p.get('classification','unspecified')}")
PY
}
