# Galaxy Book6 Pro på Omarchy — fikser og notater

`https://github.com/trollieske/galaxy-book6-pro-omarchy`

Hent på den nye maskinen:

```bash
git clone https://github.com/trollieske/galaxy-book6-pro-omarchy
cd galaxy-book6-pro-omarchy
bash book6-pro-fixes.sh status
```

Alt er trygt å lese først: `bash book6-pro-fixes.sh status` endrer ingenting.
Risikovurdering med rollback for hvert steg står i §0.

Maskin: Samsung Galaxy Book6 Pro 14", Core Ultra 7 356H (Panther Lake / Xe3),
32 GB, 512 GB, 14" OLED, Windows 11 Pro.
Søstermodell 16" = NP960XJG (Ultra X7 358H + Arc B390) — samme plattform.

Alt under er verifisert mot Omarchy-kildekoden (master, 11.11.2026),
`linux-firmware 20260916`, `samsung-galaxybook` i mainline, og
github.com/dszczyt/awesome-galaxy_book6 + to åpne Omarchy-issues.

---

## 0. Risiko og rekkefølge — les først

Maskinen kan **ikke** brikes av noe i denne mappa. Ingenting her rører disker,
partisjoner, bootloader, LUKS, firmware eller PAM. Men enkelte steg kan gi
irriterende tilstander, så gjør dem i denne rekkefølgen og ikke alt på én gang.

| Steg | Hva det endrer | Verste utfall | Vei tilbake |
|---|---|---|---|
| `status` | ingenting (kun lesing) | — | — |
| `vrr --enable` | legger 2 linjer i `~/.config/hypr/monitors.lua` | flimring/artefakter | slett linjene, `hyprctl reload`; backup lages automatisk |
| `camera` | `pacman -R intel-ipu7-camera` | mister en falsk kamera-enhet du ikke kan bruke uansett | `sudo pacman -S intel-ipu7-camera` |
| `audio --extract` | kopierer `.wmfw`/`.bin` til `/lib/firmware/cirrus` | feil tuning → dårlig/ingen lyd | slett filene, reboot (pakken eier dem ikke) |
| `fingerprint` | bygger libfprint fra GitHub-kilde og overskriver `/usr`-filer | fprintd slutter å virke | `sudo pacman -S libfprint-git` |
| `kernel` | **skriver ingenting**, viser bare kommandoer | — | — |

**De fire tingene som faktisk er risikable — ingen av dem er i skriptet:**

1. **Partisjoneringen under installasjonen.** Skal du beholde Windows (for
   BIOS-oppdateringer og garanti), krymp den fra Windows først og velg «manual
   partitioning». Standardvalget raserer hele disken.
2. **`fwupdmgr update`** (BIOS-kapsel). Strømbrudd midt i = ødelagt maskin. Kjør
   bare med lader tilkoblet, og bare hvis Samsung faktisk leverer en oppdatering.
3. **SPI/NVRAM-hacking for DVMT** (seksjon 6.3 i awesome-galaxy_book6). Det
   skriver til flash-brikken. **Ikke gjør det.** Det er den eneste oppskriften i
   hele det repoet som kan ødelegge maskinen.
4. **`pam_fprintd` i `/etc/pam.d/sudo`.** Populært tips, men en treg leser kan
   gjøre at `sudo` venter på en finger du ikke får avgitt — da er du låst ute av
   root uten en annen TTY. Skriptet setter det ikke opp, og du bør ikke gjøre det.

**Anbefalt rekkefølge de første dagene:** installer → `status` → bruk maskinen en
dag uten endringer → fiks bare det som faktisk ikke virker. `vrr` og `camera` er
ufarlige og kan tas med en gang; `fingerprint` kan vente en uke.

> exFAT lagrer ikke filrettigheter. Er skriptet ikke kjørbart på den nye
> maskinen, bruk `bash ./book6-pro-fixes.sh status`.

Vil du ha en ekstra livline før du begynner: `sudo omarchy-snapshot create` tar et
snapper-snapshot av rot-systemet, så alt kan rulles tilbake på sekunder med
`sudo omarchy-snapshot restore`.

## 1. Hva Omarchy 4.5.0 allerede gjør automatisk

Installasjonen detekterer maskinvaren og kjører quirk-skriptene i
`install/hardware/`:

| Deteksjon | Skript | Effekt på Book6 Pro |
|---|---|---|
| Intel Panther Lake GPU | `omarchy-hw-intel-ptl` | brukes for PTL-spesifikk oppsett |
| Intel SOF-lydkort | `intel/sof-firmware.sh` | installerer `sof-firmware` — **nødvendig**, ellers Dummy Output |
| Intel GPU | `intel/video-acceleration.sh` | VA-API/vulkan for Xe3 |
| Intel CPU | `intel/lpmd.sh`, `intel/thermald.sh` | strøm/termisk-daemon |
| `OVTI08F4` i ACPI | `intel/ipu7-camera.sh` | installerer `intel-ipu7-camera` — **feil på denne maskinen**, se §4 |
| USB-vendor `1c7a` | `omarchy-hw-fingerprint` | ser leseren, men libfprint mangler PID, se §5 |

Kernel 7.2.x (`linux-omarchy`) har `samsung-galaxybook`-driveren (mainline siden
6.15). Den gir tastaturbakgrunn (`/sys/class/leds/samsung-galaxybook::kbd_backlight`),
ladegrense, platform-profile og Fn-taster — forutsatt at ACPI-HID-en er
`SAM0426/27/28/29/30/SAMB430`. Sjekk med:

```bash
ls /sys/bus/platform/drivers/samsung-galaxybook/
```

## 2. Høyttalere — trenger IKKE lenger Windows-uttrekk

Samsung CS35L57-tuningene er kommet inn i `linux-firmware-cirrus`
(pakke 20260916-1), som `linux-firmware` drar inn automatisk. Settene som ligger der:

```
cs35l57-b2-dsp1-misc-144d{c1dc,c1de,c910,ca0a}
```

16"-maskinen (NP960XJG) bruker `144dc1de`. 14"-modellen bruker ett av de andre
settene — maskinen plukker riktig selv via SoundWire. Etter installasjon:

```bash
sudo dmesg | grep -iE 'cs35l57|calibrat'    # forvent "Calibration applied"
```

Kommer `FIRMWARE_MISSING`, er SSID-en din ikke i pakken — da må firmware
hentes fra Windows-partisjonen (`DriverStore/FileRepository/xucsmeext_*`).
Skriptet her gjør det: `./book6-pro-fixes.sh audio --extract`.

> **Ikke slett Windows-partisjonen med en gang.** Den trengs (a) for BIOS/firmware
> via `fwupdmgr` hvis Samsung ikke leverer LVFS-kapsler, (b) som fallback for
> Dolby/lyd-tuning, (c) for garanti. Krymp den heller.

## 3. Kjente, åpne feil på GitHub

| Issue | Status | Betydning |
|---|---|---|
| [#12347](https://github.com/omacom/omarchy/issues/12347) — IPU7-kamera er SSLC2000/SC200PC, Omarchy antar OV08X40 | åpen | **Kamera virker ikke** i Linux. Ingen driver for Samsung SC200PC finnes. Omarchy installerer feil stack → falsk "Hardware ISP Camera"-enhet som aldri gir bilder. |
| [#12351](https://github.com/omacom/omarchy/issues/12351) — fingeravtrykk `1c7a:05d5` (EGIS ETU906Axx-E) mangler i libfprint | åpen | Fingeravtrykk virker ikke med Omarchys `libfprint-git`. Fiks finnes (én tabellinje), se §5. |

Begge er rapportert på 16"-modellen, men 14" bruker samme Samsung-kamera og
samme EGIS-leser etter alt å dømme. Sjekk selv på maskinen:

```bash
ls /sys/bus/acpi/devices/ | grep -i SSLC2000     # kamera = Samsung SC200PC
grep -r 1c7a /sys/bus/usb/devices/*/idVendor     # fingeravtrykk
```

## 4. Kamera — rydd bort feil stack

```bash
sudo pacman -Rns intel-ipu7-camera
sudo systemctl disable --now v4l2-relayd@ipu7
```

Eller: `./book6-pro-fixes.sh camera`. Du får ikke kamera tilbake, men slipper
en `v4l2loopback`-enhet som ser ut som et kamera og feiler stille.
Følg #12347 for driver (krever `ipu-bridge`-oppføring for `SSLC2000`).

Kamera i mellomtiden: telefon som USB-webkamera, eller Elgato Cam Link.

## 5. Fingeravtrykk (EGIS ETU906Axx-E, `1c7a:05d5`)

Upstream libfprint har ikke PID-en. Fiksen er dokumentert i
[awesome-galaxy_book6 §11](https://github.com/dszczyt/awesome-galaxy_book6) og er
én linje i `libfprint/drivers/egismoc/egismoc.c`:

```c
{ .vid = 0x1c7a, .pid = 0x05d5, .driver_data = EGISMOC_DRIVER_CHECK_PREFIX_TYPE2 | EGISMOC_DRIVER_MAX_ENROLL_STAGES_20 },
```

```bash
./book6-pro-fixes.sh fingerprint      # kloner likeablob/libfprint-fmv-etu906axx-e,
                                      # patcher, bygger, installerer, restarter fprintd
fprintd-enroll -f right-index-finger && fprintd-verify
```

Merk: dette overskriver `libfprint-git`-filene. En `omarchy-update` som
reinstallerer pakken nullstiller patchen — kjør skriptet igjen.

## 6. Skjerm / GPU (Xe3)

Book6 Pro 16" trengte `xe.enable_panel_replay=0` på kernel 7.1rc7 (krasj i
skjermbilde/utsending). På 7.2 er dette trolig rettet — test uten først, og
legg til parameteret bare hvis skjermbilder/ekstern skjerm krasjer:

```bash
echo 'xe.enable_panel_replay=0' | sudo tee -a /etc/kernel/cmdline
sudo omarchy-update-boot
```

Verifiser at `xe` (ikke `i915`) driver GPU-en: `lspci -nnk | grep -A2 VGA`.

## 7. Strøm, ytelse, kjøling

Valgfritt, fra awesome-galaxy_book6 (målt på 16"-modellen):

```bash
# hybrid-scheduler for P/E-kjerner
sudo pacman -S scx-scheds scx-tools && sudo systemctl enable --now scx_loader
printf 'default_sched = "scx_lavd"\ndefault_mode = "Auto"\n' | sudo tee /etc/scx_loader.toml
sudo systemctl restart scx_loader

# Wi-Fi uten strømsparing (mindre drops)
printf '[connection]\nwifi.powersave = 2\n' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf

# BIOS/firmware
sudo fwupdmgr refresh && sudo fwupdmgr get-updates
```

`intel_idle` (kernel 7.1+) gir C10 og ca. 4x lavere idle-forbruk på PTL — allerede
aktivt i Omarchy-kjernen. Sjekk: `cat /sys/devices/system/cpu/cpuidle/current_driver`.

zram-swap er satt opp av Omarchy fra før; ikke lag egen swapfile på denne maskinen.


## 8. Adaptiv 30-120 Hz (viktigst for batteriet)

Panelet er Samsungs «Dynamic AMOLED 2X» med **30-120 Hz adaptiv** oppdatering.
Samsung oppgir ca. 40 % lavere panelbruk på 14"-modellen og 15 % på 16" med
adaptiv frekvens — dette er den enkeltfaktoren som monner mest på batteritid.

Under Linux er «adaptiv» = **VRR** (variabel oppdateringsfrekvens). Kjeden må
henge sammen hele veien:

1. **Panelet** må oppgi et Adaptive-Sync-vindu i EDID/DisplayID (30-120 Hz).
2. **Kjernen** må eksponere `vrr_capable=1` + `VRR_ENABLED` på eDP-connectoren
   (`xe`-driveren på Panther Lake, kernel 7.x i Omarchy).
3. **Hyprland** må be om VRR: `misc:vrr` (0 = av, 1 = alltid, 2 = fullskjerm,
   3 = fullskjerm + video). `misc:vfr` er noe annet — kompositor-oppdatering
   bare ved endring — og bør stå på uansett.

### Slå på

```bash
./book6-pro-fixes.sh vrr            # rapport: hva sier EDID, DRM og Hyprland?
sudo ./book6-pro-fixes.sh vrr       # samme + modetest (vrr_capable / VRR_ENABLED)
./book6-pro-fixes.sh vrr --enable   # legger misc:vrr = 2 i ~/.config/hypr/monitors.lua
```

Manuelt i `~/.config/hypr/monitors.lua` (lastes etter Omarchys defaults):

```lua
hl.config({ misc = { vrr = 2 } })                     -- 1 = alltid, 2 = fullskjerm, 3 = +video
hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = "auto",
             scale = 1, vrr = 2 })                    -- egen vrr per skjerm
```

Start på `2`. `1` gir VRR også i vinduer — mest batterigevinst, men på enkelte
OLED-paneler gir det flimring ved lave frekvenser (PWM/30 Hz). `3` er en mellomting.

### Verifiser

```bash
hyprctl monitors all | grep -E 'Monitor|vrr|availableModes'   # vrr: true = på
sudo modetest -c | grep -i vrr                                # vrr_capable=1, VRR_ENABLED=1
edid-decode /sys/class/drm/card*-eDP-1/edid | grep -i adaptive
```

### Hvis `vrr_capable = 0` selv om panelet er 30-120 Hz

Da er det EDID-parseren som ikke forstår panelet: 2025-2026-OLED-paneler oppgir
ofte Adaptive-Sync i en **DisplayID v2-blokk** i stedet for den gamle
range-limits-deskriptoren, og DRM fyller da ikke ut `monitor_range`. Det finnes
en patch-serie for nettopp dette (rapportert på Panther Lake, panel med 20-120 Hz).
Følg med i kjernen; bruk nyeste `linux-omarchy` først og fremst.

### Interaksjon med PSR / Panel Replay

VRR, PSR (panel self refresh) og Panel Replay er tre forskjellige ting, og Intel
slår typisk PSR av når VRR er aktivt. På PTL-OLED er Panel Replay rapportert
ustabilt (krasj ved skjermbilde/ekstern skjerm) — se §6. Rekkefølgen å teste i:

1. Default kernel, `misc:vrr = 2` → virker VRR, er bildet stabilt?
2. Flimring/korrupsjon ved lav Hz → prøv `1` og `3`, deretter av.
3. Krasjer skjermbilder/ekstern skjerm → `xe.enable_panel_replay=0` (§6).

### Fallback uten VRR

Fungerer ikke VRR, er beste kompromiss fast **60 Hz** på batteri og **120 Hz**
på strøm (bytt med monitor-panelet i topplinja, eller to `hl.monitor`-linjer per
profil). Det gir halve strømforbruket på panelet sammenlignet med 120 Hz, men
ikke de 30 Hz Samsung markedsfører.

## 9. Rekkefølge etter installasjon

```bash
./book6-pro-fixes.sh status           # hva virker / hva mangler
sudo pacman -Syu                      # oppdater til nyeste kernel/firmware
./book6-pro-fixes.sh audio            # verifiser høyttalerfirmware
./book6-pro-fixes.sh camera           # fjern feil kamerastack
./book6-pro-fixes.sh vrr --enable     # adaptiv 30-120 Hz (batteri)
./book6-pro-fixes.sh fingerprint      # valgfritt
./book6-pro-fixes.sh kernel           # sjekk cmdline/C-states
systemctl suspend && sleep 5          # test at den våkner
```

## Kilder

- Omarchy-kildekode: `install/hardware/`, `bin/omarchy-hw-*` (master 11.11.2026)
- [omacom/omarchy#12347](https://github.com/omacom/omarchy/issues/12347) — kamera
- [omacom/omarchy#12351](https://github.com/omacom/omarchy/issues/12351) — fingeravtrykk
- [dszczyt/awesome-galaxy_book6](https://github.com/dszczyt/awesome-galaxy_book6) — full oppsettguide (16")
- [joshuagrisham/samsung-galaxybook-extras](https://github.com/joshuagrisham/samsung-galaxybook-extras) — plattformdriver
- `drivers/platform/x86/samsung-galaxybook.c` i mainline
