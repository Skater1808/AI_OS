#!/bin/bash
set -e
set -o pipefail

# =====================================================================
# 0. HOST-BUILD-ABHÄNGIGKEITEN UND UMGEBUNG
# =====================================================================
export DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
export BUILD_DIR="$SCRIPT_DIR"
export ROOTFS="$BUILD_DIR/build/rootfs"
export ISO_DIR="$BUILD_DIR/build/iso"
export OUTPUT_ISO="$BUILD_DIR/build/aios.iso"
export ORIGINAL_OUTPUT_ISO="$OUTPUT_ISO"  # Store original path for later

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

# Check if we're in a container (Docker/Codespace) by default or if filesystem has constraints
echo "Checking build environment..."
USING_TMPFS=0
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -d /dev/console ]; then
    echo "Container environment detected, using /tmp for build..."
    USING_TMPFS=1
fi

if [ "$USING_TMPFS" -eq 0 ]; then
    # Try to create a test file to check noexec/nodev constraints
    TEST_DIR="$ROOTFS"
    mkdir -p "$TEST_DIR" 2>/dev/null || true
    if ! touch "$TEST_DIR/.test-exec-$$" 2>/dev/null; then
        echo "WARNING: Cannot write to build directory, using /tmp..."
        USING_TMPFS=1
    fi
    rm -f "$TEST_DIR/.test-exec-$$" 2>/dev/null || true
fi

if [ "$USING_TMPFS" -eq 1 ]; then
    echo "Using temporary /tmp directories for build..."
    export ROOTFS="/tmp/aios-rootfs-$$"
    export ISO_DIR="/tmp/aios-iso-$$"
    export OUTPUT_ISO="/tmp/aios-build-$$/aios.iso"
    mkdir -p "$ROOTFS"
    mkdir -p "$ISO_DIR/boot/grub"
    mkdir -p "$ISO_DIR/casper"
    mkdir -p "$(dirname "$OUTPUT_ISO")"
else
    echo "Using standard build directories"
fi

# =====================================================================
# 1. BASE TARGET SYSTEM (DEBOOTSTRAP)
# =====================================================================
echo "Executing Debootstrap for Minimal Base Target System..."
echo "Using ROOTFS: $ROOTFS"
debootstrap --variant=minbase --no-check-gpg noble "$ROOTFS" http://archive.ubuntu.com/ubuntu/

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
    umount -lf "$ROOTFS/proc" 2>/dev/null || true
    umount -lf "$ROOTFS/sys" 2>/dev/null || true
    umount -lf "$ROOTFS/dev/pts" 2>/dev/null || true
    umount -lf "$ROOTFS/dev" 2>/dev/null || true
}

cleanup_temp_dirs() {
    # Only called after ISO is successfully created or on error
    if [[ "$ROOTFS" == /tmp/aios-rootfs-* ]]; then
        echo "Removing temporary rootfs: $ROOTFS"
        rm -rf "$ROOTFS" 2>/dev/null || true
    fi
    # Only delete the ISO_DIR, not /tmp
    if [[ "$ISO_DIR" == /tmp/aios-iso-* ]]; then
        echo "Removing temporary ISO directory: $ISO_DIR"
        rm -rf "$ISO_DIR" 2>/dev/null || true
    fi
    # Remove the build temp directory (e.g., /tmp/aios-build-12345/) if it exists
    if [[ -d "/tmp/aios-build-"* ]]; then
        rm -rf /tmp/aios-build-* 2>/dev/null || true
    fi
}

trap 'cleanup; cleanup_temp_dirs; exit 1' ERR

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
    linux-modules-6.8.0-31-generic \
    casper \
    initramfs-tools

# Generate a matching initramfs for the installed kernel and include casper hooks
chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/sbin/mkinitramfs -o /boot/initrd.img-6.8.0-31-generic 6.8.0-31-generic

# =====================================================================
# 4. RUST CORE-DAEMON BAUEN (Optional)
# =====================================================================
echo "Building AiOS core daemon with generic x86_64 CPU optimizations..."

# Install Rust if not present
if ! command -v cargo &>/dev/null; then
    echo "Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable >/dev/null 2>&1 || {
        echo "WARNING: Rust installation failed. Checking for pre-built binary..."
    }
    # Source cargo environment
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env" || export PATH="/root/.cargo/bin:$PATH"
fi

if [ -d "$BUILD_DIR/core-daemon" ]; then
    if command -v cargo &>/dev/null; then
        pushd "$BUILD_DIR/core-daemon" >/dev/null
        export RUSTFLAGS="-C target-cpu=generic"
        cargo build --release 2>&1 || echo "WARNING: Cargo build may have partial failures, continuing..."
        popd >/dev/null
    else
        echo "WARNING: cargo not available, skipping Rust build. Using placeholder if available..."
    fi
else
    echo "NOTICE: Core-daemon directory not found, skipping Rust build"
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
    echo "Deploying compiled aios-core-daemon binary..."
    cp "$CORE_BIN" "$ROOTFS/usr/bin/"
elif [ -f "$BUILD_DIR/core-daemon/aios-core-daemon" ]; then
    echo "Deploying pre-built aios-core-daemon binary..."
    cp "$BUILD_DIR/core-daemon/aios-core-daemon" "$ROOTFS/usr/bin/"
else
    echo "WARNING: aios-core-daemon binary not found. It will be missing from the ISO."
    echo "If you need it, compile the Rust project locally or provide a pre-built binary at:"
    echo "  $BUILD_DIR/core-daemon/target/release/aios-core-daemon or $BUILD_DIR/core-daemon/aios-core-daemon"
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
echo "Securing kernel and initrd files before unmount..."
KERNEL_IMG=""
INITRD_IMG=""
KERNEL_COPY=""
INITRD_COPY=""

# Create staging directory for kernel files
mkdir -p "/tmp/kernel-staging-$$"

if [ -f "$ROOTFS/boot/vmlinuz-6.8.0-31-generic" ]; then
    KERNEL_IMG="$ROOTFS/boot/vmlinuz-6.8.0-31-generic"
    INITRD_IMG="$ROOTFS/boot/initrd.img-6.8.0-31-generic"
else
    KERNEL_IMG=$(ls -1 "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | head -n 1)
    INITRD_IMG=$(ls -1 "$ROOTFS/boot/initrd.img-"* 2>/dev/null | head -n 1)
fi

# Copy kernel files to safe location before unmount
if [ -f "$KERNEL_IMG" ]; then
    KERNEL_COPY="/tmp/kernel-staging-$$/vmlinuz"
    cp "$KERNEL_IMG" "$KERNEL_COPY"
    echo "Kernel secured to: $KERNEL_COPY"
fi

if [ -f "$INITRD_IMG" ]; then
    INITRD_COPY="/tmp/kernel-staging-$$/initrd"
    cp "$INITRD_IMG" "$INITRD_COPY"
    echo "Initrd secured to: $INITRD_COPY"
elif [ -f "$ROOTFS/boot/initrd.img" ]; then
    INITRD_COPY="/tmp/kernel-staging-$$/initrd"
    cp "$ROOTFS/boot/initrd.img" "$INITRD_COPY"
    echo "Initrd (fallback) secured to: $INITRD_COPY"
else
    echo "WARNING: No initrd found. Attempting to use kernel with fallback..."
fi

if [ -z "$KERNEL_COPY" ] || [ ! -f "$KERNEL_COPY" ]; then
    echo "CRITICAL ERROR: Kernel could not be secured!"
    exit 1
fi

# =====================================================================
# 7. UNMOUNT VIRTUAL FILESYSTEMS
# =====================================================================
echo "Unmounting virtual filesystems..."
cleanup

# =====================================================================
# 8. ISO DISTRIBUTION ASSEMBLY
# =====================================================================
echo "Assembling ISO distribution layout..."
mkdir -p "$ISO_DIR/boot/grub"
mkdir -p "$ISO_DIR/casper"

# Add live image metadata for Casper/Ubuntu-style boot support
chroot "$ROOTFS" dpkg-query -W --showformat='${Package} ${Version}\n' > "$ISO_DIR/casper/filesystem.manifest"
du -sx --block-size=1 "$ROOTFS" | cut -f1 > "$ISO_DIR/casper/filesystem.size"

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
    linux /boot/vmlinuz boot=casper quiet splash nomodeset console=tty1
    initrd /boot/initrd
}
EOF

echo "Creating SquashFS filesystem..."
mksquashfs "$ROOTFS" "$ISO_DIR/casper/filesystem.squashfs" -comp xz -e boot proc sys dev

echo "Copying kernel files to ISO..."
cp "$KERNEL_COPY" "$ISO_DIR/boot/vmlinuz"
if [ -f "$INITRD_COPY" ]; then
    cp "$INITRD_COPY" "$ISO_DIR/boot/initrd"
    echo "Initrd copied successfully"
else
    echo "WARNING: No initrd available, ISO may have reduced functionality"
fi

# Cleanup kernel staging directory
rm -rf "/tmp/kernel-staging-$$" 2>/dev/null || true

echo "Generating hybrid BIOS/UEFI ISO image..."
grub-mkrescue -o "$OUTPUT_ISO" "$ISO_DIR" \
    --modules="part_msdos iso9660 fat ext2 normal chain linux configfile search search_label"

if [ ! -f "$OUTPUT_ISO" ]; then
    echo "CRITICAL ERROR: ISO-Erstellung fehlgeschlagen!"
    exit 1
fi

# Copy ISO to original location if using temporary directory
if [ "$OUTPUT_ISO" != "$ORIGINAL_OUTPUT_ISO" ]; then
    echo "Copying ISO from temporary location to final destination..."
    mkdir -p "$(dirname "$ORIGINAL_OUTPUT_ISO")"
    cp "$OUTPUT_ISO" "$ORIGINAL_OUTPUT_ISO"
    OUTPUT_ISO="$ORIGINAL_OUTPUT_ISO"
fi

echo "====================================================================="
echo " SUCCESS: AiOS Distribution Assembly Complete -> $OUTPUT_ISO"
echo "====================================================================="

# Clean up temporary directories after successful build
cleanup_temp_dirs
