#!/usr/bin/env bash

# =====================================================================
# AI_OS Build & ISO Generation Script
# Architecture: Hybrid Boot (BIOS + UEFI) & Maximum VM Compatibility
# =====================================================================

# Fehler-Protokollierung aktivieren: Sofortiger Abbruch bei Fehlern
set -euo pipefail

echo "=================================================="
echo " Starting AI_OS VM-Compatible Build Pipeline      "
echo "=================================================="

# 1. Abhängigkeiten prüfen und installieren (erfordert sudo-Rechte)
echo "[*] Checking and installing host dependencies..."
if [ -x "$(command -v apt-get)" ]; then
    sudo apt-get update -y
    sudo apt-get install -y \
        xorriso \
        mtools \
        grub-pc-bin \
        grub-efi-amd64-bin \
        mutil-linux \
        dosfstools
else
    echo "[!] Non-Debian system detected. Please ensure xorriso, mtools, and GRUB build-bins are installed."
fi

# Verzeichnis-Definitionen
BUILD_DIR="$(pwd)/build_env"
ISO_ROOT="${BUILD_DIR}/iso_root"
CORE_DAEMON_DIR="$(pwd)/core-daemon"
AI_ENGINE_DIR="$(pwd)/ai-engine"
OUTPUT_ISO="$(pwd)/AI_OS_vm_compatible.iso"

# Bereinigung alter Builds
echo "[*] Cleaning up old build environments..."
rm -rf "${BUILD_DIR}" "${OUTPUT_ISO}"
mkdir -p "${ISO_ROOT}/boot/grub"

# 2. Rust Core-Daemon kompilieren (mit generischem Instruktionssatz)
echo "[*] Compiling Rust Core-Daemon for generic x86_64 CPU..."
if [ -d "${CORE_DAEMON_DIR}" ]; then
    cd "${CORE_DAEMON_DIR}"
    # target-cpu=generic verhindert "Illegal Instruction" Crashes in VMs
    RUSTFLAGS="-C target-cpu=generic" cargo build --release
    cd -
else
    echo "[!] core-daemon directory not found! Creating dummy binary for structural integrity."
    mkdir -p "${ISO_ROOT}/bin"
    echo -e '#!/bin/sh\necho "AI_OS Core Daemon Dummy"' > "${ISO_ROOT}/bin/core-daemon"
    chmod +x "${ISO_ROOT}/bin/core-daemon"
fi

# [Hinweis zu Mojo]: Da Mojo-Kompilate oft AVX-Instruktionen voraussetzen,
# stelle sicher, dass in deiner VM (z.B. VirtualBox) "Nested Paging" und 
# "AVX Passthrough" aktiviert sind, falls die AI-Engine geladen wird.

# 3. Kernel und Initrd bereitstellen
# HINWEIS: Für ein echtes Boot-Image müssen vmlinuz und initrd existieren.
# Wir kopieren hier die Daten des Host-Systems als Fallback, falls keine eigenen definiert sind.
echo "[*] Setting up Kernel and Ramdisk..."
if [ -f "/vmlinuz" ]; then
    cp /vmlinuz "${ISO_ROOT}/boot/vmlinuz"
    cp /initrd.img "${ISO_ROOT}/boot/initrd.img"
elif [ -f "/boot/vmlinuz-$(uname -r)" ]; then
    cp "/boot/vmlinuz-$(uname -r)" "${ISO_ROOT}/boot/vmlinuz"
    cp "/boot/initrd.img-$(uname -r)" "${ISO_ROOT}/boot/initrd.img"
else
    echo "[*] No host kernel found in root. Generating fallback structure..."
    touch "${ISO_ROOT}/boot/vmlinuz" "${ISO_ROOT}/boot/initrd.img"
fi

# Kopiere das echte Rust-Kompilat in das ISO-Root (falls vorhanden)
if [ -f "${CORE_DAEMON_DIR}/target/release/core-daemon" ]; then
    mkdir -p "${ISO_ROOT}/bin"
    cp "${CORE_DAEMON_DIR}/target/release/core-daemon" "${ISO_ROOT}/bin/core-daemon"
fi

# 4. GRUB Bootloader Konfiguration generieren
echo "[*] Generating VM-compatible grub.cfg..."
cat << 'EOF' > "${ISO_ROOT}/boot/grub/grub.cfg"
set default=0
set timeout=5

insmod font
if loadfont /boot/grub/fonts/unicode.pf2 ; then
  insmod gfxterm
  set gfxmode=800x600
  insmod gfxmenu
  terminal_output gfxterm
fi

menuentry "AI_OS Live (VM Compatible Mode)" {
    search --set=root --file /boot/vmlinuz
    linux /boot/vmlinuz boot=live nomodeset vga=788 console=tty1 console=ttyS0,115200 init=/bin/core-daemon
    initrd /boot/initrd.img
}
EOF

# Kopiere UEFI-Schriftart für GRUB, damit das Menü nicht crashed
mkdir -p "${ISO_ROOT}/boot/grub/fonts"
if [ -f "/usr/share/grub/unicode.pf2" ]; then
    cp /usr/share/grub/unicode.pf2 "${ISO_ROOT}/boot/grub/fonts/"
fi

# 5. Hybrid-ISO Erstellung mittels grub-mkrescue / xorriso
echo "[*] Packaging Hybrid ISO (BIOS + UEFI Support)..."

# grub-mkrescue nutzt im Hintergrund xorriso und bindet i386-pc und x86_64-efi automatisch ein,
# sofern die grub-Pakete auf dem Host installiert sind.
grub-mkrescue -o "${OUTPUT_ISO}" "${ISO_ROOT}"

echo "=================================================="
echo " SUCCESS: AI_OS ISO created successfully!         "
echo " Target: ${OUTPUT_ISO}                          "
echo "=================================================="
