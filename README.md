# UniVPN Custom Linux Build & Usability Patches

This repository contains a full, portable copy of **UniVPN (v10781.21.0.0831)** for Linux (x86_64), patched for optimal usability, automated connection, and dark desktop environment compatibility.

---

## Change Points & Patch Summary

| # | Feature / Issue | File | Offset | Original Bytes | Patched Bytes | Purpose |
|---|-----------------|------|--------|----------------|---------------|---------|
| 1 | **Left-Click Tray Icon Action** | `UniVPN` | `0x4f649` | `0e` | `36` | Left-clicking tray icon directly opens Home Page (`MainUI_SysTrayIcon_ShowMain`) instead of context menu. |
| 2 | **Saved Password Auto/Direct Connect** | `UniVPN` | `0x62582` | `0f 84 a0 01 00 00` | `90 90 90 90 90 90` | NOPs out `je 0x62728`. Directly connects when saved password exists without showing Login dialog. |
| 3 | **Down-Arrow Indicator & Custom Theme** | `theme.qss` | — | — | — | Adds `arrow-down.png` dropdown indicators to ComboBoxes and fixes dark palette contrast in KDE/Kvantum. |
| 4 | **Bypass Untrusted Server Certificate Dialog** | `UniVPN` | `0xe4640` | `48 8b 45 58 8b 40 40` | `e9 4b 01 00 00 90 90` | Jumps (`jmp 0xe4790`) directly to continue handler, bypassing "Safety warning : untrusted VPN server certificate!" prompt completely. |
| 5 | **Remove "successfully connect!" Popup** | `UniVPN` | `0xe5825` | `e8 e6 10 fe ff` | `90 90 90 90 90` | NOPs `call 0xc6910`, removing the redundant standalone popup window on login success. |
| 6 | **Suppress "Connecting..." Tray Notifications** | `UniVPN` | 13 offsets | `e8 ...` | `90 90 90 90 90` (x13) | NOPs out all 13 call sites emitting `UI_MAIN_CONNECTING`, silencing repetitive connecting bubbles. |
| 7 | **Fix Certificate Dropdown Path Truncation** | `UniVPN` | `0x80246` | `be 1d 00 00 00` | `be 17 00 00 00` | Changes hardcoded length from 29 to 23 for `/opt/UniVPN/certificate`, preventing null byte truncation and loading `.p12`/`.pfx` files into dropdowns. Also fixes path lengths at `0x6011d`, `0x603f7` (certinfo.txt: `1e` -> `18`) and `0x6cf0e` (image: `17` -> `11`). |
| 8 | **Remove Hover/Click Overlay on Export & Import** | `theme.qss` | — | — | — | Sets transparent background without borders across `:hover`, `:pressed`, and `:disabled` states for `pb_output` and `pb_input`. |

---

## Detailed Technical Offsets

### 1. Left-Click Tray Icon (`0x4f649`)
- **Location:** `MainUI::slotSysTrayIconClicked`
- **Original:** `80 f9 0e` (checks if click reason is `0x0e`)
- **Patched:** `80 f9 36` (triggers `MainUI_SysTrayIcon_ShowMain` / Display Home Page)

### 2. Direct Connect with Saved Password (`0x62582`)
- **Location:** `MainUI::on_pushButton_connect_clicked`
- **Original:** `0f 84 a0 01 00 00` (`je 0x62728` -> pops up `LoginKeyUI`)
- **Patched:** `90 90 90 90 90 90` (falls through directly to `Connection_GetLoginReturn_Update` / `StartConnect`)

### 3. Server Certificate Dialog Bypass (`0xe4640`)
- **Location:** `LoginKeyUI::Connection_GetLoginReturn_Update`
- **Original:** `48 8b 45 58 8b 40 40` (reads error code and prepares modal dialog)
- **Patched:** `e9 4b 01 00 00 90 90` (`jmp 0xe4790` -> calls acceptance handler `fa460(1)`, clears error `*rbx = 0`, returns 1)

### 4. Remove Success Popup (`0xe5825`)
- **Location:** `LoginKeyUI::Connection_GetLoginReturn_Update`
- **Original:** `e8 e6 10 fe ff` (`call 0xc6910` -> creates 3s auto-closing popup window)
- **Patched:** `90 90 90 90 90` (standalone window suppressed; tray notification and main window status remain intact)

### 5. Suppress "Connecting, please wait..." Notifications (13 Call Sites)
NOPed out 5 bytes (`90 90 90 90 90`) at each call site loading `UI_MAIN_CONNECTING` (`0x150a32`):
- `0x4ddcf`, `0x4e12a`, `0x4f7e2`, `0x55e9d`, `0x608d5`, `0x60cfa`, `0x6181a`, `0x61a8d`, `0x61cd2`, `0x61f85` (calls to `MainUI_SysTrayIcon_showMessage`)
- `0xe8d0d`, `0xe8fad`, `0xf23d5` (calls to `signal_SysTrayTcon_ShowMessage`)

### 6. Relocated Path String Lengths
`relocate.py` truncated `/usr/local/UniVPN` into `/opt/UniVPN\0\0\0\0\0\0`. The binary hardcoded length arguments to `QString::fromAscii_helper(str, len)`:
- `0x80246`: `be 1d 00 00 00` -> `be 17 00 00 00` (length 29 -> 23 for `/opt/UniVPN/certificate`)
- `0x6011d`: `be 1e 00 00 00` -> `be 18 00 00 00` (length 30 -> 24 for `/opt/UniVPN/certinfo.txt`)
- `0x603f7`: `be 1e 00 00 00` -> `be 18 00 00 00` (length 30 -> 24 for `/opt/UniVPN/certinfo.txt`)
- `0x6cf0e`: `be 17 00 00 00` -> `be 11 00 00 00` (length 23 -> 17 for `/opt/UniVPN/image`)

---

## How to Use on Other Linux Distributions

### Option A: Portable Run (No installation required)
Simply run the included portable launcher:
```bash
./univpn.sh
```
This automatically configures `LD_LIBRARY_PATH`, Qt plugin path, sets `Fusion` light theme override, and applies `theme.qss`.

### Option B: System-Wide Installation (To `/opt/UniVPN`)
1. Copy the directory to `/opt/UniVPN`:
   ```bash
   sudo cp -r /path/to/UniVPN /opt/UniVPN
   ```
2. Place your `.p12` certificate into:
   ```bash
   /opt/UniVPN/certificate/
   ```
3. Copy `univpn.sh` into your PATH (e.g. `/usr/local/bin/univpn` or `~/.local/bin/univpn`):
   ```bash
   sudo cp /opt/UniVPN/univpn.sh /usr/local/bin/univpn
   sudo chmod +x /usr/local/bin/univpn
   ```

---

## Verifying & Re-applying Patches (`patch_univpn.py`)

A Python 3 utility is included to verify, apply, or revert patches on any clean `UniVPN` binary:

```bash
# Check patch status of a binary
./patch_univpn.py check ./UniVPN

# Apply all patches to a clean binary
./patch_univpn.py apply ./UniVPN

# Revert patches back to original
./patch_univpn.py revert ./UniVPN
```
