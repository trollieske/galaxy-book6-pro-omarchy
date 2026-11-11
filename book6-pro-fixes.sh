#!/usr/bin/env bash
# Post-install fixes for Samsung Galaxy Book6 Pro (Panther Lake) on Omarchy.
#   NP940XJG (14") / NP960XJG (16") — Core Ultra 7 356H / Ultra X7 358H
#
# Usage:  ./book6-pro-fixes.sh [status|audio|fingerprint|camera|kernel]
#
# Nothing is changed by a bare run: 'status' only reports. Every other
# subcommand prints what it will do, asks first, and every root action has a
# documented way back (see README, "Risiko og rekkefølge"). Nothing here touches
# disks, bootloader, PAM or firmware.
set -uo pipefail

DRY_RUN=0
[[ ${1:-status} == --dry-run ]] && { DRY_RUN=1; shift; }
CMD=${1:-status}

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
ask()  { read -rp "  $1 [y/N] " a; [[ $a == [yY]* ]]; }

run() { # run <description> <command...>
  local desc=$1; shift
  if (( DRY_RUN )); then printf '  + %s\n' "$*"; return 0; fi
  "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }
need_root() { [[ $EUID -eq 0 ]] || { bad "kjør som root: sudo $0 $CMD"; exit 1; }; }

product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)

# ── status ──────────────────────────────────────────────────────────────────
status() {
  say "Maskin"
  echo "  $vendor $product"
  echo "  CPU:    $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)"
  echo "  Kernel: $(uname -r)"
  echo "  Omarchy: $(omarchy-version 2>/dev/null || echo ukjent)"

  say "Grafikk (skal bruke xe, ikke i915)"
  local gpu
  if lspci -nnk 2>/dev/null | grep -A2 -iE 'vga|3d' | grep -q 'Kernel driver in use: xe'; then
    ok "xe-driver i bruk"
  else
    warn "$(lspci 2>/dev/null | grep -iE 'vga|3d' | cut -d: -f3- | xargs) — sjekk 'lspci -nnk'"
  fi

  say "Samsung-plattformdriver (tastaturlys, ladegrense, Fn-taster)"
  if [[ -d /sys/bus/platform/drivers/samsung-galaxybook ]]; then
    if ls /sys/bus/platform/drivers/samsung-galaxybook/ 2>/dev/null | grep -q 'SAM'; then
      ok "bundle: $(ls /sys/bus/platform/drivers/samsung-galaxybook/ | grep SAM | tr '\n' ' ')"
    else
      bad "ingen enhet bundet — ACPI-HID mangler i driveren (SAM0426/27/28/29/30/SAMB430)"
    fi
  else
    bad "modul samsung_galaxybook ikke lastet (kernel 6.15+ kreves)"
  fi
  [[ -e /sys/class/leds/samsung-galaxybook::kbd_backlight ]] &&
    ok "tastaturbakgrunn tilgjengelig" ||
    warn "ingen tastaturbakgrunn-node"

  say "Lyd (SoundWire + Cirrus CS35L57)"
  local amps
  amps=$(ls -d /sys/bus/soundwire/devices/sdw:*/ 2>/dev/null | wc -l)
  (( amps > 0 )) && ok "$amps SoundWire-enheter" || warn "ingen SoundWire-enheter"
  local fw_ver sets
  fw_ver=$(pacman -Q linux-firmware-cirrus 2>/dev/null | awk '{print $2}')
  sets=$(ls /usr/lib/firmware/cirrus/ 2>/dev/null | grep -oE 'cs35l57-b2-dsp1-misc-144d[0-9a-f]{4}' |
         sed 's/.*144d/144d/' | sort -u | tr '\n' ' ')
  if [[ -n $fw_ver ]]; then
    ok "linux-firmware-cirrus $fw_ver"
    [[ -n $sets ]] && echo "      Samsung CS35L57-sett i pakken: $sets"
  else
    warn "linux-firmware-cirrus mangler — installer: sudo pacman -S linux-firmware-cirrus"
  fi
  if dmesg >/dev/null 2>&1; then
    grep -qiE 'firmware.*(missing|failed)|FIRMWARE_MISSING' <(dmesg) &&
      warn "dmesg melder firmware-problem — kjør: $0 audio" ||
      ok "ingen firmware-feil i dmesg"
    grep -qi 'Calibration applied' <(dmesg) && ok "høyttalerkalibrering lastet"
  else
    warn "kan ikke lese dmesg uten root (sudo sysctl kernel.dmesg_restrict=1?)"
  fi

  say "Kamera (Intel IPU7)"
  if [[ -e /sys/bus/acpi/devices/SSLC2000:00 ]]; then
    bad "sensor er Samsung SC200PC (SSLC2000) — ingen Linux-driver, kamera virker ikke (omarchy#12347)"
    if pacman -Qi intel-ipu7-camera >/dev/null 2>&1; then
      warn "intel-ipu7-camera er installert unødvendig (forventer OV08X40) — kjør: $0 camera"
    fi
  else
    grep -l OVTI08F4 /sys/bus/acpi/devices/*/hid >/dev/null 2>&1 &&
      warn "OVTI08F4-plassholder funnet (kan være phantom)" ||
      warn "ukjent kameramodell"
  fi

  say "Fingeravtrykk"
  local fp
  fp=$(for d in /sys/bus/usb/devices/*/; do
         [[ -r $d/idVendor && $(<"$d/idVendor") == 1c7a ]] && { echo "$(<"$d/idProduct")"; break; }
       done)
  if [[ $fp == 05d5 ]]; then
    warn "EGIS ETU906Axx-E (1c7a:05d5) — støttes ikke av upstream libfprint (omarchy#12351)"
    fprintd-list "$USER" 2>&1 | grep -qi 'no devices' &&
      warn "fprintd ser ingen enhet — kjør: $0 fingerprint" ||
      ok "fprintd ser leseren"
  elif [[ -n $fp ]]; then
    ok "LighTuning 1c7a:$fp"
  else
    warn "fant ingen LighTuning-leser"
  fi

  say "Søvn"
  local mem
  mem=$(cat /sys/power/mem_sleep 2>/dev/null)
  echo "  mem_sleep: ${mem:-ukjent}"
  [[ $mem == *'[s2idle]'* ]] &&
    warn "s2idle valgt — riktig for PTL, men test 'systemctl suspend' og se om den våkner"
}

# ── audio ───────────────────────────────────────────────────────────────────
# Since linux-firmware 20260916 the Samsung CS35L57 tunings (144dc1dc, 144dc1de,
# 144dc910, 144dca0a) ship upstream, pulled in by linux-firmware-cirrus. Only if
# the SSID for this exact model is missing do you need the Windows driver store.
audio() {
  say "CS35L57-høyttalerfirmware"
  local fw_ver sets
  fw_ver=$(pacman -Q linux-firmware-cirrus 2>/dev/null | awk '{print $2}')
  sets=$(ls /usr/lib/firmware/cirrus/ 2>/dev/null | grep -oE 'cs35l57-b2-dsp1-misc-144d[0-9a-f]{4}' |
         sed 's/.*144d/144d/' | sort -u | tr '\n' ' ')
  if [[ -n $sets ]]; then
    ok "linux-firmware-cirrus $fw_ver har: $sets"
    echo "  Maskinen velger sett selv ut fra SoundWire-oppsettet. Sjekk etter reboot:"
    echo "    sudo dmesg | grep -iE 'cs35l57|calibrat'"
    echo "  Står det FIRMWARE_MISSING her, er SSID-en din ikke i pakken — da: $0 audio --extract"
    [[ ${1:-} == --extract ]] || return 0
  else
    warn "ingen Samsung CS35L57-sett funnet (linux-firmware-cirrus $fw_ver)"
    echo "  Prøv først: sudo pacman -Syu linux-firmware-cirrus"
  fi
  need_root

  local win src found=0
  win=$(findmnt -rno TARGET -t ntfs3,ntfs,lowntfs-3g 2>/dev/null | head -1)
  if [[ -z $win ]]; then
    warn "ingen Windows-partisjon montert. Monter den først, f.eks.:"
    echo "    sudo mkdir -p /mnt/win"
    echo "    sudo mount -t ntfs3 -o ro /dev/nvme0n1p3 /mnt/win"
    echo "  (finn riktig partisjon med: lsblk -f)"
    return 1
  fi
  echo "  Windows montert på $win"

  src=$(find "$win/Windows/System32/DriverStore/FileRepository" -maxdepth 1 -type d -iname 'xucsmeext_*' 2>/dev/null | head -1)
  if [[ -z $src ]]; then
    bad "fant ikke xucsmeext_*-mappen i DriverStore"
    echo "    Søk manuelt: find '$win/Windows/System32/DriverStore' -iname '*35l57*' | head"
    return 1
  fi
  echo "  kilde: ${src#$win}"

  install -d /lib/firmware/cirrus

  # SSID from the tuning directory name, e.g. .../tn/35L57/C1DE/dflt/
  local ssid wmfw
  ssid=$(find "$src/tn" -type d -ipath '*35L57*' -maxdepth 3 2>/dev/null |
         awk -F/ '{print $NF}' | grep -E '^[0-9A-Fa-f]{4}$' | head -1)
  [[ -z $ssid ]] && { bad "fant ikke SSID-katalog under tn/35L57/"; return 1; }
  echo "  SSID: $ssid"

  wmfw=$(find "$src/fw" -ipath '*35L5*' -name '*.wmfw' 2>/dev/null | head -1)
  if [[ -n $wmfw ]]; then
    run "kopierer DSP-firmware" cp -f "$wmfw" "/lib/firmware/cirrus/cs35l57-b2-dsp1-misc-144d${ssid,,}.wmfw"
    ok "cs35l57-b2-dsp1-misc-144d${ssid,,}.wmfw"
    found=1
  else
    warn "fant ikke .wmfw (DSP-firmware)"
  fi

  # One tuning .bin per amplifier: LW/LT/RW/RT → l1u0/l1u1/l2u2/l2u3
  local bin role addr
  while IFS= read -r bin; do
    role=$(basename "$bin" | grep -oE '_(LW|LT|RW|RT)_' | tr -d '_')
    addr=$(basename "$bin" | grep -oE 'l[0-9]u[0-9]')
    [[ -n $role && -n $addr ]] || continue
    run "kopierer $role → $addr" cp -f "$bin" \
      "/lib/firmware/cirrus/cs35l57-b2-dsp1-misc-144d${ssid,,}-${addr}.bin"
    ok "$role ($addr)"
    found=1
  done < <(find "$src/tn" -ipath "*35L57*" -name '*.bin' 2>/dev/null)

  (( found )) || { bad "fant ingen firmware-filer"; return 1; }
  say "Ferdig. Reboot og sjekk:"
  echo "    sudo dmesg | grep -iE 'cs35l|calibrat|tuning'   # forvent 'Calibration applied'"
  echo "    pw-play /usr/share/sounds/freedesktop/stereo/audio-channel-front-left.oga"
}

# ── fingerprint ─────────────────────────────────────────────────────────────
fingerprint() {
  say "EGIS ETU906Axx-E (1c7a:05d5) — patch av libfprint"
  echo "  Upstream libfprint (og Omarchys libfprint-git) mangler PID 05d5 i egismoc."
  echo "  Fiksen er én tabellinje, men den må bygges inn i et eget libfprint-bygg."
  echo "  Kilde: github.com/likeablob/libfprint-fmv-etu906axx-e"
  echo
  echo "  [33mDette er det ENESTE steget som rører systemfiler:[0m"
  echo "    - overskriver filer som tilhører pakken libfprint-git i /usr"
  echo "    - rollback:  sudo pacman -S libfprint-git"
  echo "    - påvirker IKKE innlogging, sudo eller LUKS"
  echo "  [31mLegg aldri 'auth sufficient pam_fprintd.so' i /etc/pam.d/sudo[0m"
  echo "  (vanlig tips på nettet, men en treg/feil leser kan låse deg ute av sudo)."
  echo
  ask "Bygge og installere patchet libfprint nå?" || return 1

  local dir=$HOME/dev/github.com/likeablob/libfprint-fmv-etu906axx-e
  if [[ ! -d $dir ]]; then
    run "kloner repo" git clone https://github.com/likeablob/libfprint-fmv-etu906axx-e "$dir" || return 1
  fi
  cd "$dir" || return 1

  local entry='{ .vid = 0x1c7a, .pid = 0x05d5, .driver_data = EGISMOC_DRIVER_CHECK_PREFIX_TYPE2 | EGISMOC_DRIVER_MAX_ENROLL_STAGES_20 },'
  if ! grep -q '0x05d5' libfprint/drivers/egismoc/egismoc.c; then
    run "legger til PID 05d5" sed -i "/0x1c7a.*0x05b1/a\\        $entry" \
      libfprint/drivers/egismoc/egismoc.c || return 1
  fi

  need_root
  run "meson setup" meson setup build --prefix=/usr -Ddrivers=egismoc
  run "ninja" ninja -C build
  run "installerer (overskriver pakkens filer)" ninja -C build install
  run "restarter fprintd" systemctl restart fprintd
  say "Registrer finger:"
  echo "    fprintd-enroll -f right-index-finger && fprintd-verify"
  warn "Omarchy-oppdateringer kan reinstallere libfprint-git — kjør denne på nytt etterpå."
}

# ── camera ──────────────────────────────────────────────────────────────────
# intel-ipu7-camera is installed because the installer greps for OVTI08F4 in
# ACPI, and the Book6 keeps _STA=0 phantom nodes for it. The real sensor is an
# SSLC2000 (Samsung SC200PC) with no Linux driver, so the package only sets up
# a v4l2loopback device that never delivers frames.
camera() {
  need_root
  say "Kamera: rydde bort feil IPU7-stack"
  if ! pacman -Qi intel-ipu7-camera >/dev/null 2>&1; then
    ok "intel-ipu7-camera er ikke installert — ingenting å gjøre"
    return 0
  fi
  ask "Fjerne intel-ipu7-camera (kamera vil fortsatt ikke virke, men du slipper falsk enhet)?" || return 1
  # -R uten -s: fjerner bare pakken, ikke avhengigheter andre kan trenge.
  run "fjerner pakken" pacman -R --noconfirm intel-ipu7-camera
  run "fjerner v4l2-relayd" systemctl disable --now v4l2-relayd@ipu7 2>/dev/null
  ok "ryddet"
}

# ── vrr ─────────────────────────────────────────────────────────────────────
# The panel is 30-120 Hz adaptive (Samsung "Dynamic AMOLED 2X"). Linux only gets
# that range through VRR: DRM must report vrr_capable on the eDP connector and
# Hyprland must ask for it. Fixed modes are just 120/60/48/30.
vrr() {
  local enable=${1:-}
  say "Adaptiv oppdatering (30-120 Hz)"
  local edp
  edp=$(hyprctl monitors all 2>/dev/null | awk '/^Monitor eDP/{print $2; exit}')
  edp=${edp:-eDP-1}

  local edid
  for f in /sys/class/drm/card*-"${edp}"/edid; do [[ -r $f ]] && { edid=$f; break; }; done
  if [[ -n ${edid:-} ]] && have edid-decode; then
    echo "  Panelets VRR-vindu (fra EDID/DisplayID):"
    edid-decode "$edid" 2>/dev/null | grep -iE 'adaptive sync|refresh range|min.*max.*hz|vrr' |
      head -5 | sed 's/^/    /' || echo "    ingen Adaptive-Sync-blokk funnet i EDID"
  fi

  echo "  Hyprland:"
  hyprctl monitors all 2>/dev/null | grep -E '^Monitor|vrr:|availableModes' | sed 's/^/    /'
  echo "  misc:vrr = $(hyprctl getoption misc:vrr 2>/dev/null | tr '\n' ' ')"

  echo "  DRM-egenskaper (krever root):"
  if [[ $EUID -eq 0 ]] && have modetest; then
    modetest -c 2>/dev/null | grep -B2 -A12 "eDP-1" |
      grep -iE 'vrr|adaptive' | sed 's/^/    /' || warn "ingen VRR-egenskap på connectoren"
  else
    echo "    sudo modetest -c | grep -i vrr      # vrr_capable=1 betyr støttet"
    echo "    (uten root: kjør 'sudo $0 vrr')"
  fi

  if [[ $enable == --enable ]]; then
    local f=$HOME/.config/hypr/monitors.lua
    [[ -f $f ]] || { bad "finner ikke $f"; return 1; }
    if grep -q 'misc = { vrr' "$f"; then
      warn "misc:vrr er allerede satt i $f — rediger manuelt"
    else
      cp -a "$f" "$f.bak.$(date +%s)"
      cat >>"$f" <<'LUA'

-- Adaptiv oppdatering 30-120 Hz paa det innebygde panelet.
-- 1 = alltid, 2 = kun fullskjerm, 3 = fullskjerm + video. Prov 2 forst om 1 gir flimring.
hl.config({ misc = { vrr = 2 } })
LUA
      ok "la til misc:vrr = 2 i $f (backup laget)"
      echo "  Laster Hyprland-konfigurasjonen på nytt ..."
      hyprctl reload >/dev/null 2>&1 && ok "lastet på nytt" || warn "kjør 'hyprctl reload' selv"
    fi
  else
    echo
    echo "  Slå på (skriver til ~/.config/hypr/monitors.lua):"
    echo "    $0 vrr --enable"
  fi
}

# ── kernel ──────────────────────────────────────────────────────────────────
kernel() {
  say "Kernel-parametre (Panther Lake / xe)"
  echo "  Gjeldende cmdline:"
  sed 's/^/    /' /etc/kernel/cmdline 2>/dev/null || warn "fant ikke /etc/kernel/cmdline"
  echo
  echo "  Panel Replay var ustabilt (krasj i skjermbilde/display) på kernel 7.1rc7."
  echo "  På 7.2+ er det verdt å teste uten fiksen først. Ved problemer:"
  echo "    echo 'xe.enable_panel_replay=0' | sudo tee -a /etc/kernel/cmdline"
  echo "    sudo omarchy-update-boot      # eller: sudo mkinitcpio -P"
  echo
  echo "  Sjekk driver-tilstand etter reboot:"
  echo "    cat /sys/module/xe/parameters/enable_psr /sys/module/xe/parameters/enable_panel_replay"
  echo "  C-states (intel_idle gir ~4x lavere idle-forbruk på PTL):"
  echo "    cpuidle driver: $(cat /sys/devices/system/cpu/cpuidle/current_driver 2>/dev/null)"
}

case $CMD in
  status|"")     status ;;
  audio)         audio "${2:-}" ;;
  fingerprint)   fingerprint ;;
  camera)        camera ;;
  vrr)           vrr "${2:-}" ;;
  kernel)        kernel ;;
  -h|--help)     sed -n '2,12p' "$0" ;;
  *) echo "Ukjent kommando: $CMD (status|audio|fingerprint|camera|vrr|kernel)" >&2; exit 2 ;;
esac
