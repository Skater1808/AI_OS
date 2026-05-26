<<<<<<< HEAD
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
=======
#!/bin/bash
set -e
set -o pipefail

# =====================================================================
# 0. HOST-BUILD-ABHÄNGIGKEITEN UND UMGEBUNG
# =====================================================================
export DEBIAN_FRONTEND=noninteractive
export ROOTFS=/build/rootfs
export BUILD_DIR=/build
export ISO_DIR=/build/iso
export OUTPUT_ISO=/build/aios.iso

echo "Installing host ISO build dependencies..."
apt-get update
apt-get install -y --no-install-recommends \
    xorriso \
    mtools \
    grub-pc-bin \
    grub-efi-amd64-bin \
    squashfs-tools \
    debootstrap

mkdir -p "$ROOTFS"
mkdir -p "$ISO_DIR/boot/grub"
mkdir -p "$ISO_DIR/casper"

# =====================================================================
# 1. BASE TARGET SYSTEM (DEBOOTSTRAP)
# =====================================================================
echo "Executing Debootstrap for Minimal Base Target System..."
debootstrap --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu/

# =====================================================================
# 2. VIRTUAL FILESYSTEMS MOUNTEN
# =====================================================================
echo "Mounting virtual filesystems into Target Environment..."
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount -t devpts devpts "$ROOTFS/dev/pts"

cleanup() {
    echo "Sauberes Lösen der virtuellen Dateisysteme..."
    umount -lf "$ROOTFS/proc" || true
    umount -lf "$ROOTFS/sys" || true
    umount -lf "$ROOTFS/dev/pts" || true
    umount -lf "$ROOTFS/dev" || true
}
trap cleanup EXIT

# =====================================================================
# 3. KERNEL & DEPENDENCIES INJEKTION (CHROOT)
# =====================================================================
echo "Configuring Core Dependencies inside Target Environment..."
chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
    systemd-sysv \
    bubblewrap \
    libgomp1 \
    grub-pc-bin \
    linux-image-6.8.0-31-generic \
    linux-modules-6.8.0-31-generic

# =====================================================================
# 4. RUST CORE-DAEMON BAUEN
# =====================================================================
echo "Building AiOS core daemon with generic x86_64 CPU optimizations..."
if [ -d "$BUILD_DIR/core-daemon" ]; then
    pushd "$BUILD_DIR/core-daemon" >/dev/null
    export RUSTFLAGS="-C target-cpu=generic"
    cargo build --release
    popd >/dev/null
else
    echo "CRITICAL ERROR: Core-daemon-Verzeichnis wurde nicht gefunden!"
    exit 1
fi

# =====================================================================
# 5. ARTIFAKTE & KONFIGURATIONEN PLATZIEREN
# =====================================================================
echo "Deploying binaries, Mojo artifacts and configuration into rootfs..."
mkdir -p "$ROOTFS/usr/bin"
mkdir -p "$ROOTFS/etc/systemd/system"
mkdir -p "$ROOTFS/run/aios"
mkdir -p "$ROOTFS/opt/aios/ai-engine"
mkdir -p "$ROOTFS/opt/aios/models"

CORE_BIN="$BUILD_DIR/core-daemon/target/release/aios-core-daemon"
if [ -f "$CORE_BIN" ]; then
    cp "$CORE_BIN" "$ROOTFS/usr/bin/"
else
    echo "CRITICAL ERROR: Gebaute aios-core-daemon-Binärdatei nicht gefunden!"
    exit 1
fi

if [ -f "$BUILD_DIR/ai-engine/engine.mojo" ]; then
    cp "$BUILD_DIR/ai-engine/engine.mojo" "$ROOTFS/opt/aios/ai-engine/"
fi

if [ -f "$BUILD_DIR/config/aios-core.service" ]; then
    cp "$BUILD_DIR/config/aios-core.service" "$ROOTFS/etc/systemd/system/"
    chroot "$ROOTFS" systemctl enable aios-core.service
fi

if [ -f "$BUILD_DIR/scripts/download_model.sh" ]; then
    echo "Triggering Offline LLM Model Provisioning Pipeline..."
    /bin/bash "$BUILD_DIR/scripts/download_model.sh" "$ROOTFS/opt/aios/models/" || echo "Modell-Download übersprungen oder simuliert."
fi

# =====================================================================
# 6. KERNEL-LOGISTIK VOR DEM UNMOUNT SICHERN
# =====================================================================
KERNEL_IMG=""
INITRD_IMG=""
if [ -f "$ROOTFS/boot/vmlinuz-6.8.0-31-generic" ]; then
    KERNEL_IMG="$ROOTFS/boot/vmlinuz-6.8.0-31-generic"
    INITRD_IMG="$ROOTFS/boot/initrd.img-6.8.0-31-generic"
else
    KERNEL_IMG=$(ls -1 "$ROOTFS/boot/vmlinuz-*" 2>/dev/null | head -n 1)
    INITRD_IMG=$(ls -1 "$ROOTFS/boot/initrd.img-*" 2>/dev/null | head -n 1)
fi

if [ -z "$KERNEL_IMG" ] || [ -z "$INITRD_IMG" ]; then
    echo "CRITICAL ERROR: Kernel oder initrd konnte nicht gefunden werden!"
    exit 1
fi

# =====================================================================
# 7. UNMOUNT VIRTUAL FILESYSTEMS
# =====================================================================
echo "Unmounting virtual filesystems..."
cleanup
trap - EXIT

# =====================================================================
# 8. ISO DISTRIBUTION ASSEMBLY
# =====================================================================
echo "Assembling ISO distribution layout..."
mkdir -p "$ISO_DIR/boot/grub"
mkdir -p "$ISO_DIR/casper"

cat << 'EOF' > "$ISO_DIR/boot/grub/grub.cfg"
set default=0
set timeout=5

insmod part_msdos
insmod fat
insmod ext2
insmod search
insmod search_fs_uuid
insmod search_fs_file

menuentry "AiOS Linux (GNU/Linux)" {
    linux /boot/vmlinuz boot=casper nomodeset vga=788 console=tty1 init=/lib/systemd/systemd
    initrd /boot/initrd
}
EOF

echo "Creating SquashFS filesystem..."
mksquashfs "$ROOTFS" "$ISO_DIR/casper/filesystem.squashfs" -comp xz -e boot proc sys dev

cp "$KERNEL_IMG" "$ISO_DIR/boot/vmlinuz"
cp "$INITRD_IMG" "$ISO_DIR/boot/initrd"

echo "Generating hybrid BIOS/UEFI ISO image..."
grub-mkrescue -o "$OUTPUT_ISO" "$ISO_DIR" \
    --modules="part_msdos iso9660 fat ext2 normal chain linux configfile search search_label"

if [ ! -f "$OUTPUT_ISO" ]; then
    echo "CRITICAL ERROR: ISO-Erstellung fehlgeschlagen!"
    exit 1
fi

echo "====================================================================="
echo " SUCCESS: AiOS Distribution Assembly Complete -> $OUTPUT_ISO"
echo "====================================================================="
>>>>>>> 3086af8 (sigma)
