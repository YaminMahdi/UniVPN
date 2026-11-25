#!/usr/bin/env python3
"""
UniVPN Binary Patcher & Verifier
Applies all usability and bugfix patches to the Linux x86_64 UniVPN binary.
Works on any Linux distribution (Arch, Ubuntu, Debian, Fedora, etc.).
"""

import sys
import os

PATCHES = {
    # Feature 1: Left-click tray icon directly opens home page (MainUI)
    # Replaces action 0x0e (tray menu) with 0x36 (MainUI_SysTrayIcon_ShowMain)
    0x4f649: (b'\x0e', b'\x36', "Left-click tray icon to show home page"),

    # Feature 2: Bypass Login dialog when password is saved for direct connection
    # NOPs out the conditional jump je 0x62728 in MainUI
    0x62582: (b'\x0f\x84\xa0\x01\x00\x00', b'\x90\x90\x90\x90\x90\x90', "Auto direct connect with saved password"),

    # Feature 4: Totally bypass untrusted VPN server certificate warning dialog
    # Replaces certificateDialog creation with direct jump to continue handler (jmp 0xe4790)
    0xe4640: (b'\x48\x8b\x45\x58\x8b\x40\x40', b'\xe9\x4b\x01\x00\x00\x90\x90', "Bypass untrusted server cert dialog"),

    # Feature 5: Remove redundant 'successfully connect!' popup window
    # NOPs out call 0xc6910 in LoginKeyUI
    0xe5825: (b'\xe8\xe6\x10\xfe\xff', b'\x90\x90\x90\x90\x90', "Remove success popup window"),

    # Feature 6: Suppress 'Connecting, please wait...' system tray notifications (13 calls)
    0x4ddcf: (b'\xe8\xcc\xfc\xff\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 1"),
    0x4e12a: (b'\xe8\x71\xf9\xff\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 2"),
    0x4f7e2: (b'\xe8\xb9\xe2\xff\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 3"),
    0x55e9d: (b'\xe8\xfe\x7b\xff\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 4"),
    0x608d5: (b'\xe8\xc6\xd1\xfe\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 5"),
    0x60cfa: (b'\xe8\xa1\xcd\xfe\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 6"),
    0x6181a: (b'\xe8\x81\xc2\xfe\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 7"),
    0x61a8d: (b'\xe8\x0e\xc0\xfe\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 8"),
    0x61cd2: (b'\xe8\xc9\xbd\xfe\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 9"),
    0x61f85: (b'\xe8\x16\xbb\xfe\xff', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 10"),
    0xe8d0d: (b'\xe8\x2e\x16\x01\x00', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 11"),
    0xe8fad: (b'\xe8\x8e\x13\x01\x00', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 12"),
    0xf23d5: (b'\xe8\x66\x7f\x00\x00', b'\x90\x90\x90\x90\x90', "Suppress connecting tray notification 13"),

    # Feature 7: Fix hardcoded string lengths for /opt/UniVPN paths (relocation bugfix)
    # Fixes certificate dropdown enumeration by passing length 23 (0x17) instead of 29 (0x1d)
    0x80246: (b'\xbe\x1d\x00\x00\x00', b'\xbe\x17\x00\x00\x00', "Fix certificate dropdown path length"),
    0x6011d: (b'\xbe\x1e\x00\x00\x00', b'\xbe\x18\x00\x00\x00', "Fix certinfo.txt path length 1"),
    0x603f7: (b'\xbe\x1e\x00\x00\x00', b'\xbe\x18\x00\x00\x00', "Fix certinfo.txt path length 2"),
    0x6cf0e: (b'\xbe\x17\x00\x00\x00', b'\xbe\x11\x00\x00\x00', "Fix image path length"),

    # Feature 9: Keep certinfo.txt (saved .p12 passwords) when the window closes
    # or UniVPN exits. MainUI deleted it there; with the path-length fix above the
    # delete started to work and wiped the passwords UniVPNCS stores in it.
    # NOPs both calls to QFile::remove().
    0x6016d: (b'\xe8\x9e\x3c\xfc\xff', b'\x90\x90\x90\x90\x90', "Keep certinfo.txt on exit"),
    0x60447: (b'\xe8\xc4\x39\xfc\xff', b'\x90\x90\x90\x90\x90', "Keep certinfo.txt on window close"),

    # Feature 10: Certificate password field always editable (optional).
    # ProfileInfoUI disabled the field when UniVPNCS reported the selected .p12
    # needs no password; NOPs that setEnabled(false) call.
    0x793d4: (b'\xe8\x37\xa0\xfa\xff', b'\x90\x90\x90\x90\x90', "Certificate password field always editable"),

    # Feature 11: Certificate names and passwords longer than 31 characters.
    # ProfileInfoUI copied the .p12 name and password into the request to
    # UniVPNCS with strncpy_s(dst, 0x20, ...); a longer name (for example
    # BCC-67402-Ahmad_Umar_Mahdi_with_pass.p12) came out empty, so the password
    # was never checked or saved and the Login dialog skipped the certificate.
    # The fields are 0x400 bytes: pass 0x400 as the limit.
    0x7926d: (b'\xbe\x20\x00\x00\x00', b'\xbe\x00\x04\x00\x00', "Long certificate name (password check)"),
    0x82520: (b'\xbe\x20\x00\x00\x00', b'\xbe\x00\x04\x00\x00', "Long certificate name (save)"),
    0x82543: (b'\xbe\x20\x00\x00\x00', b'\xbe\x00\x04\x00\x00', "Long certificate password (save)"),
    0x87a4c: (b'\xbe\x20\x00\x00\x00', b'\xbe\x00\x04\x00\x00', "Long certificate name (save 2)"),
    0x87a73: (b'\xbe\x20\x00\x00\x00', b'\xbe\x00\x04\x00\x00', "Long certificate password (save 2)"),

    # Feature 12: The IPC packer for that request copied only 32 bytes.
    # The certificate check request (UniVPN -> UniVPNCS) used memcpy_s(dst, 0x20,
    # src, 0x20) for the name and password, so names of 32+ characters reached
    # the service cut off and it could not open the .p12. The reply copy had
    # the same limits. Raise all of them to the 0x400-byte field size.
    0x11e7b4: (b'\xb9\x20\x00\x00\x00', b'\xb9\x00\x04\x00\x00', "Request: certificate name count"),
    0x11e7b9: (b'\xbe\x20\x00\x00\x00', b'\xbe\x00\x04\x00\x00', "Request: certificate name size"),
    0x11e7de: (b'\xb9\x20\x00\x00\x00', b'\xb9\x00\x04\x00\x00', "Request: certificate password count"),
    0x11e7e3: (b'\xbe\x20\x00\x00\x00', b'\xbe\x00\x04\x00\x00', "Request: certificate password size"),
    0x11e8aa: (b'\xb9\x20\x00\x00\x00', b'\xb9\x00\x04\x00\x00', "Reply: certificate name count"),
    0x11e8af: (b'\xbe\x20\x00\x00\x00', b'\xbe\x00\x04\x00\x00', "Reply: certificate name size"),
    0x11e8d4: (b'\xb9\x20\x00\x00\x00', b'\xb9\x00\x04\x00\x00', "Reply: certificate password count"),
    0x11e8d9: (b'\xbe\x20\x00\x00\x00', b'\xbe\x00\x04\x00\x00', "Reply: certificate password size"),
}

def check(file_path):
    with open(file_path, 'rb') as f:
        data = f.read()

    print(f"Checking '{file_path}' ({len(data)} bytes)...")
    patched_count = 0
    clean_count = 0

    for off, (orig, patch, desc) in sorted(PATCHES.items()):
        curr = data[off:off+len(orig)]
        if curr == patch:
            status = "[PATCHED]"
            patched_count += 1
        elif curr == orig:
            status = "[ORIGINAL]"
            clean_count += 1
        else:
            status = f"[UNKNOWN: {curr.hex()}]"
        print(f"  0x{off:06x}: {status:12s} {desc}")

    print(f"\nSummary: {patched_count}/{len(PATCHES)} patches applied, {clean_count}/{len(PATCHES)} original clean.")

def apply(file_path):
    with open(file_path, 'rb') as f:
        buf = bytearray(f.read())

    applied = 0
    for off, (orig, patch, desc) in sorted(PATCHES.items()):
        curr = buf[off:off+len(orig)]
        if curr == patch:
            continue
        if curr != orig:
            print(f"Error: byte mismatch at 0x{off:06x} ({desc}). Expected {orig.hex()}, found {curr.hex()}")
            sys.exit(1)
        buf[off:off+len(patch)] = patch
        applied += 1

    with open(file_path, 'wb') as f:
        f.write(buf)
    print(f"Successfully applied {applied} patches to '{file_path}'.")

def revert(file_path):
    with open(file_path, 'rb') as f:
        buf = bytearray(f.read())

    reverted = 0
    for off, (orig, patch, desc) in sorted(PATCHES.items()):
        curr = buf[off:off+len(orig)]
        if curr == orig:
            continue
        if curr != patch:
            print(f"Error: byte mismatch at 0x{off:06x} ({desc}). Expected {patch.hex()}, found {curr.hex()}")
            sys.exit(1)
        buf[off:off+len(orig)] = orig
        reverted += 1

    with open(file_path, 'wb') as f:
        f.write(buf)
    print(f"Successfully reverted {reverted} patches on '{file_path}'.")

if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print("Usage:")
        print("  python3 patch_univpn.py check  [path/to/UniVPN]")
        print("  python3 patch_univpn.py apply  [path/to/UniVPN]")
        print("  python3 patch_univpn.py revert [path/to/UniVPN]")
        sys.exit(0)

    cmd = sys.argv[1].lower()
    target = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), 'UniVPN')

    if not os.path.isfile(target):
        print(f"Error: target file '{target}' not found.")
        sys.exit(1)

    if cmd == 'check':
        check(target)
    elif cmd == 'apply':
        apply(target)
    elif cmd == 'revert':
        revert(target)
    else:
        print(f"Unknown command: '{cmd}'")
        sys.exit(1)
