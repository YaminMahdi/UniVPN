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
| 7 | **Fix Certificate Dropdown Path Truncation** (*New Connection* page only; the Login dialog list comes from the service, see Option B) | `UniVPN` | `0x80246` | `be 1d 00 00 00` | `be 17 00 00 00` | Changes hardcoded length from 29 to 23 for `/opt/UniVPN/certificate`, preventing null byte truncation and loading `.p12`/`.pfx` files into dropdowns. Also fixes path lengths at `0x6011d`, `0x603f7` (certinfo.txt: `1e` -> `18`) and `0x6cf0e` (image: `17` -> `11`). |
| 8 | **Remove Hover/Click Overlay on Export & Import** | `theme.qss` | — | — | — | Sets transparent background without borders across `:hover`, `:pressed`, and `:disabled` states for `pb_output` and `pb_input`. |
| 9 | **Keep Saved Certificate Passwords** | `UniVPN` | `0x6016d`, `0x60447` | `e8 9e 3c fc ff`, `e8 c4 39 fc ff` | `90 90 90 90 90` (x2) | NOPs the `QFile::remove()` of `/opt/UniVPN/certinfo.txt` on exit and on window close, so the `.p12` password entered on the *New Connection* page survives. |
| 10 | **Certificate Password Always Editable** | `UniVPN`, `language/*/l_UILabel.ini` | `0x793d4` | `e8 37 a0 fa ff` | `90 90 90 90 90` | NOPs `setEnabled(false)` on `Certificate_password` when `UniVPNCS` reports the `.p12` needs no password, so the *New Connection* field stays editable; its label reads **Password (optional)**. |
| 11 | **Long Certificate Names / Passwords** | `UniVPN` | `0x7926d`, `0x82520`, `0x82543`, `0x87a4c`, `0x87a73` | `be 20 00 00 00` | `be 00 04 00 00` | Raises the copy limit of the `.p12` name and password sent to `UniVPNCS` from 32 to 1024 bytes. Longer names (e.g. `BCC-67402-Ahmad_Umar_Mahdi_with_pass.p12`) arrived empty, so the password was never verified or saved to `certinfo.txt` and the Login dialog skipped the certificate. |
| 12 | **Long Certificate Names / Passwords (IPC)** | `UniVPN` | `0x11e7b4`, `0x11e7b9`, `0x11e7de`, `0x11e7e3`, `0x11e8aa`, `0x11e8af`, `0x11e8d4`, `0x11e8d9` | `b9`/`be 20 00 00 00` | `b9`/`be 00 04 00 00` | The packer of that request copied only 32 bytes of the name and password into the message, so a 40-character name still reached `UniVPNCS` cut off and the password was never saved. |
| 13 | **Long Certificate Names in certinfo.txt** | `serviceclient/UniVPNCS` | `0x41b385`, `0x41b3e8`, `0x41b57e`, `0x41b58f`, `0x41b5ad`, `0x41b5d9` | see below | see below | The service read saved passwords back into a 32-byte name buffer, so a 40-character name never matched its own `certinfo.txt` line and the Login dialog still skipped password-protected certificates. |

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

### 7. Keep `certinfo.txt` (`0x6016d`, `0x60447`)
- **Location:** `MainUI` exit (`[into main ui exit pre]`) and close-event (`[into main ui close event]`) handlers
- **Original:** `e8 9e 3c fc ff` / `e8 c4 39 fc ff` (`call QFile::remove()` on `/opt/UniVPN/certinfo.txt`)
- **Patched:** `90 90 90 90 90` (the return value is unused)
- **Why:** `UniVPNCS` stores the `.p12` passwords in `certinfo.txt` (through the
  `/opt/apps/...univpn/files` link, see Option B). Upstream the delete never
  succeeded because of the relocation length bug; once the length was fixed
  (section 6), closing the window wiped the saved passwords, so a password-
  protected certificate could no longer connect.

### 8. Certificate Password Always Editable (`0x793d4`)
- **Location:** `ProfileInfoUI` certificate-password check (`[certificate passwd Isneed][msg is`)
- **Original:** `e8 37 a0 fa ff` (`call QWidget::setEnabled(false)` on `Certificate_password` when the answer is 0)
- **Patched:** `90 90 90 90 90`; the field is still disabled while *Certificate Authentication* is unchecked.

### 9. Long Certificate Names and Passwords (`0x7926d`, `0x82520`, `0x82543`, `0x87a4c`, `0x87a73`)
- **Location:** `ProfileInfoUI` password check and the two *Connect Save* paths, which fill a `0x804`-byte request (name at `+0`, password at `+0x400`) for `UniVPNCS`
- **Original:** `be 20 00 00 00` (`strncpy_s(dst, 0x20, src, len)`: anything of 32+ bytes is dropped, leaving an empty string)
- **Patched:** `be 00 04 00 00` (limit `0x400`, the real field size)
- **Symptom:** `UniVPNCS` logged `[get cert failed][Error reading PKCS#12 filen]` (it opened the certificate *folder*), the password was never written to `certinfo.txt`, and the Login dialog dropped the certificate with `[Error parsing PKCS#12 filen]`.

### 10. Certificate Check Message (`0x11e7b4`-`0x11e7e3`, `0x11e8aa`-`0x11e8d9`)
- **Location:** the function that packs the certificate check request for `UniVPNCS` (and unpacks the reply): `memcpy_s(msg + 0x18, 0x20, req, 0x20)` for the name and `memcpy_s(msg + 0x418, 0x20, req + 0x400, 0x20)` for the password
- **Original:** `b9 20 00 00 00` / `be 20 00 00 00` (count and size 32)
- **Patched:** `b9 00 04 00 00` / `be 00 04 00 00` (0x400, the field size; the message has room for the full `0x804`-byte request)
- **Symptom:** after patch 11, `UniVPNCS` logged `[get cert passwd failed][Error open certinfo file]`. The message is misleading: it could not open `certificate/BCC-67402-Ahmad_Umar_Mahdi_with_` (the name cut at 32 bytes). `certinfo.txt` stayed empty and the Login dialog still skipped password-protected certificates.

### 11. certinfo.txt Reader in UniVPNCS (`0x41b37d`)
- **Location:** the service function that looks up a certificate's saved password. It XOR-decodes `certinfo.txt` and parses each line with `sscanf_s(line, "%[^&]&%[^\n]\n", name, 0x20, pass, 0x20)`.
- **Problem:** `name` is a 32-byte stack buffer (`-0x50(%rbp)`). A longer name fails to parse, so no line matches. The listing then tries the `.p12` with an empty password (`[get cert fileName pass][fileName][]`, `[Error parsing PKCS#12 filen]`) and leaves it out. This happens even though patch 12 saved the line correctly.
- **Patch:** the stack frame grows from `0x90` to `0x190` (`48 81 ec 90 00 00 00` → `48 81 ec 90 01 00 00`), and the name buffer moves to the new 256 bytes at `(%rsp)`:
  - `0x41b3e8`: `movq $0,-0x50(%rbp)` → `movq $0,(%rsp)` (`48 c7 45 b0 …` → `48 c7 04 24 …`)
  - `0x41b57e`, `0x41b5ad`: `lea -0x50(%rbp),%rdx` → `lea (%rsp),%rdx` (`48 8d 55 b0` → `48 8d 14 24`)
  - `0x41b5d9`: `lea -0x50(%rbp),%rax` → `lea (%rsp),%rax` (`48 8d 45 b0` → `48 8d 04 24`)
  - `0x41b58f`: name size `b9 20 00 00 00` → `b9 00 01 00 00`
- Passwords up to 31 characters are unaffected.

---

## How to Use on Other Linux Distributions

### Option A: Portable Run (No installation required)
Simply run the included portable launcher:
```bash
./univpn.sh
```
This automatically configures `LD_LIBRARY_PATH`, Qt plugin path, sets `Fusion` light theme override, and applies `theme.qss`.

### Option B: System-Wide Installation (To `/opt/UniVPN`)
```bash
./install.sh               # asks for root (pkexec/sudo); installs or updates /opt/UniVPN
./install.sh --autostart   # also start UniVPN at login
```
Then place your `.p12` certificate into `/opt/UniVPN/certificate/`. It shows in
both the *New Connection* and the Login dialog dropdowns. If the `.p12` has a
password, enter it in the *New Connection* page's certificate
**Password (optional)** field; leave it empty for a certificate without one.

`install.sh` copies the tree (without `.git`, logs, certificates or settings, so
re-running it keeps yours), stops a running UniVPN, and:

- makes `serviceclient/UniVPNCS` SUID root and gives `certificate/`, `config/`,
  `log/`, `sysconfig.ini` and `certinfo.txt` to your user;
- links `/opt/apps/cn.com.huawei-security-commercial-alliance.univpn/files` to
  `/opt/UniVPN`. `UniVPNCS` (the root service) does **not** use `/opt/UniVPN`:
  it lists certificates for the **Login dialog** (`cb_CertList` and its refresh
  button) and reads/writes certificate passwords (`certinfo.txt`) only under
  that UOS app path. Without the link the Login dropdown stays empty and the
  certificate password on the *New Connection* page fails
  (`get cert passwd failed][Error open certinfo file]` in
  `log/UniVPN_UniVPNCS_0.log`), while the *New Connection* dropdown (read by the
  GUI itself) still works;
- moves certificates from the old `/usr/local/UniVPN/certificate`;
- installs `/usr/local/bin/univpn`, the `univpn` icon in the `hicolor` theme (so
  every launcher, including KDE's *All Applications*, shows it) and the menu
  entry `/usr/local/share/applications/univpn.desktop`.

### Uninstalling (`uninstall.sh`)
Removes UniVPN completely: stops `UniVPN`, `UniVPNCS` and
`UniVPNPromoteService`, and deletes `/opt/UniVPN`, the `/opt/apps/...univpn`
link, a legacy `/usr/local/UniVPN`, the `univpn` launcher, menu, autostart and
icon entries, and each user's `~/.config/autostart/UniVPNA.desktop` and
`~/.config/cn.com.huawei-security-commercial-alliance.univpn`.
```bash
/opt/UniVPN/uninstall.sh                      # asks for root (pkexec/sudo), then confirms
sudo /opt/UniVPN/uninstall.sh --yes           # no confirmation
/opt/UniVPN/uninstall.sh --keep-certificates  # copy *.p12/*.pfx to ~/UniVPN-certificates first
```

---

## Verifying & Re-applying Patches (`patch_univpn.py`)

A Python 3 utility is included to verify, apply, or revert patches on clean `UniVPN` and `serviceclient/UniVPNCS` binaries. Without a path it handles both next to the script; a path whose file name starts with `UniVPNCS` gets the service patches (`./patch_univpn.py apply some/UniVPNCS`).

```bash
# Check patch status of a binary
./patch_univpn.py check        # UniVPN and serviceclient/UniVPNCS

# Apply all patches to a clean binary
./patch_univpn.py apply        # UniVPN and serviceclient/UniVPNCS

# Revert patches back to original
./patch_univpn.py revert       # UniVPN and serviceclient/UniVPNCS
```
