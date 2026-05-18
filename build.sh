#!/bin/bash
set -e

# =====================================================================
# 1. UMGEBUNG & PFADE DEFINIEREN
# =====================================================================
export ROOTFS=/build/rootfs
export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.cargo/bin:$PATH" # Stellt sicher, dass Cargo im Host-Pfad liegt

mkdir -p "$ROOTFS"

# =====================================================================
# 2. RUST SYSTEM DAEMON ENGINE (HOST COMPILATION)
# =====================================================================
# Wir bauen den Daemon ZUERST auf dem Host, da hier die Toolchain 
# aus der GitHub Action ('dtolnay/rust-toolchain') bereitliegt.
echo "Compiling Rust System Daemon Engine on Host..."
cd /build/core-daemon

if command -v cargo &> /dev/null; then
    cargo build --release
else
    echo "WARNUNG: Cargo nicht im PATH, versuche Standard-Installationspfad..."
    $HOME/.cargo/bin/cargo build --release
fi

# =====================================================================
# 3. BASE TARGET SYSTEM (DEBOOTSTRAP)
# =====================================================================
echo "Executing Debootstrap for Minimal Base Target System..."
debootstrap --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu/

# =====================================================================
# 4. VIRTUAL FILESYSTEMS MOUNTEN
# =====================================================================
echo "Mounting Virtual Filesystems into Target Environment..."
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount -t devpts devpts "$ROOTFS/dev/pts"

# Trap sorgt dafür, dass die Mounts bei Fehlern oder Abbruch sauber gelöst werden
cleanup() {
    echo "Unmounting Virtual Filesystems..."
    umount -lf "$ROOTFS/proc" || true
    umount -lf "$ROOTFS/sys" || true
    umount -lf "$ROOTFS/dev/pts" || true
    umount -lf "$ROOTFS/dev" || true
}
trap cleanup EXIT

# =====================================================================
# 5. KERNEL & DEPENDENCIES INJEKTION (CHROOT)
# =====================================================================
echo "Configuring Core Dependencies inside Target Environment..."
chroot "$ROOTFS" apt-get update

# Wir installieren den nackten Kernel und umgehen die Python-Abhängigkeiten
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
    systemd-sysv \
    bubblewrap \
    libgomp1 \
    grub-pc-bin \
    linux-image-6.8.0-31-generic \
    linux-modules-6.8.0-31-generic

# =====================================================================
# 6. ARTIFAKTE & KONFIGURATIONEN PLATZIEREN
# =====================================================================
echo "Deploying Compiled Binaries and AI Frameworks..."
mkdir -p "$ROOTFS/usr/bin"
mkdir -p "$ROOTFS/etc/systemd/system"
mkdir -p "$ROOTFS/run/aios"
mkdir -p "$ROOTFS/opt/aios/ai-engine"
mkdir -p "$ROOTFS/opt/aios/models"

# Kopieren der auf dem Host gebauten Rust-Engine ins Rootfs
cp /build/core-daemon/target/release/aios-core-daemon "$ROOTFS/usr/bin/"

# Mojo Skripte & Systemd-Konfigurationen kopieren
if [ -f /build/ai-engine/engine.mojo ]; then
    cp /build/ai-engine/engine.mojo "$ROOTFS/opt/aios/ai-engine/"
fi

if [ -f /build/config/aios-core.service ]; then
    cp /build/config/aios-core.service "$ROOTFS/etc/systemd/system/"
    # Service im Systemd des Target-Systems aktivieren
    chroot "$ROOTFS" systemctl enable aios-core.service
fi

# Offline LLM-Modelle provisionieren
if [ -f /build/scripts/download_model.sh ]; then
    echo "Triggering Offline LLM Model Provisioning Pipeline..."
    /bin/bash /build/scripts/download_model.sh "$ROOTFS/opt/aios/models/" || echo "Modell-Download übersprungen oder simuliert."
fi

# =====================================================================
# 7. ISO DISTRIBUTION ASSEMBLY
# =====================================================================
echo "Assembling ISO Distribution Framework..."
mkdir -p /build/iso/boot/grub
mkdir -p /build/iso/casper

# Grub Config kopieren
if [ -f /build/config/grub.cfg ]; then
    cp /build/config/grub.cfg /build/iso/boot/grub/
fi

# Kernel-Images lokalisieren, bevor wir das Rootfs packen
KERNEL_IMG=$(ls -1 $ROOTFS/boot/vmlinuz-* 2>/dev/null | head -n 1)
INITRD_IMG=$(ls -1 $ROOTFS/boot/initrd.img-* 2>/dev/null | head -n 1)

# Das Filesystem in das komprimierte SquashFS packen
mksquashfs "$ROOTFS" /build/iso/casper/filesystem.squashfs -comp xz -e boot

# Bereite die Boot-Dateien für die ISO vor
if [ -n "$KERNEL_IMG" ] && [ -n "$INITRD_IMG" ]; then
    cp "$KERNEL_IMG" /build/iso/boot/vmlinuz
    cp "$INITRD_IMG" /build/iso/boot/initrd
else
    echo "CRITICAL ERROR: Kernel vmlinuz oder initrd fehlt im rootfs!"
    exit 1
fi

# Mounts explizit vor dem finalen Grub-ISO-Bau lösen
cleanup
trap - EXIT

echo "Generating Final ISO Boot Medium..."
grub-mkrescue -o /build/aios.iso /build/iso

echo "====================================================================="
echo " SUCCESS: AiOS Distribution Assembly Complete -> /build/aios.iso"
echo "====================================================================="