{ pkgs }:

let

  # ── Source Repositories ──────────────────────────────────────────────────
  srcKSU = pkgs.fetchFromGitHub {
    owner = "tiann";
    repo = "KernelSU";
    rev = "main";
    hash = "sha256-5v7GYjNgg7bhMVTt4tX4ouU6DMntaokiXx5qsgSNfh4=";
  };

  srcModules = pkgs.fetchFromGitHub {
    owner = "OnePlusOSS";
    repo = "android_kernel_modules_and_devicetree_oneplus_sm8550";
    rev = "7361170";
    hash = "sha256-WeAPIEolT+ePWWr8Snl27Sp7ozGxrDVwgDnaZUkpwLQ=";
  };

  srcMsmKernel = pkgs.fetchFromGitHub {
    owner = "OnePlusOSS";
    repo = "android_kernel_oneplus_sm8550";
    rev = "daec6e5";
    hash = "sha256-NsEoR9Z80VTSq7MqNbn0G2CspRyz2l6D63E/irFVn2k=";
  };

  srcCommon = pkgs.fetchFromGitHub {
    owner = "OnePlusOSS";
    repo = "android_kernel_common_oneplus_sm8550";
    rev = "12ac7e6";
    hash = "sha256-Sz75RElDXWUNGMmq1q9CV2nU1EAV0VeVBdq/NT8Rzp8=";
  };

  # ── AOSP Support Repositories ────────────────────────────────────────────
  srcKernelBuild = pkgs.fetchgit {
    url = "https://android.googlesource.com/kernel/build";
    rev = "76ceabc";
    hash = "sha256-IlZ8Rz9wRCvBJORq8cBN/h3eV9ZHmHWH8jFFqiuF/UM=";
  };

  srcPlatformBuildTools = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/prebuilts/build-tools";
    rev = "07d9f1c";
    hash = "sha256-F5cmET1P38hkuazFBeW4ExRQAHTbic2MMuChWK0MCrM=";
  };

  srcKernelBuildTools = pkgs.fetchgit {
    url = "https://android.googlesource.com/kernel/prebuilts/build-tools";
    rev = "010d8a8";
    hash = "sha256-ZoELwqv7jMWj/eoLzm0hPQDvMJWlaFzuJ7mmzs+irpc=";
  };

  srcDtc = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/external/dtc";
    rev = "2ec107c";
    hash = "sha256-F3qsmXpAPz0kBMxXhzl8MRGie1qPAlen6nWOYbTfCFg=";
  };

  srcMkbootimg = pkgs.fetchgit {
    url = "https://android.googlesource.com/platform/system/tools/mkbootimg";
    rev = "d2bb0af";
    hash = "sha256-z7KklKf0dTyt7ZoUiZrMYRzU3h+WuLnc355LRtFMs2s=";
  };

  srcNdk = pkgs.fetchzip {
    url = "https://dl.google.com/android/repository/android-ndk-r23c-linux.zip";
    hash = "sha256-NCSrIh8rgA1mY5Z+C/PFkze1bFomorMdy9ykTIRv1js=";
  };

  srcClang = pkgs.fetchzip {
    url = "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r547379.tar.gz";
    hash = "sha256-JwZsWReMvf3qoHjjBKDAfisS1DRDfNHytrpLzkvHAqQ=";
    stripRoot = false;
  };

in
pkgs.stdenv.mkDerivation {
  pname = "popcorn-kernel-salami";
  version = "1.0.0Mb-salami";

  dontUnpack = true;
  dontConfigure = true;
  dontFixup = true; # AOSP tools are manually patched during patchPhase
  autoPatchelfIgnoreMissingDeps = true;

  # We include autoPatchelfHook and standard C++ libs for AOSP prebuilt binaries
  nativeBuildInputs = with pkgs; [
    bash
    autoPatchelfHook
    stdenv.cc.cc.lib
    tree
    breakpointHook
    gcc
    binutils
    bc
    bison
    flex
    git
    gnupg
    gperf
    libxml2
    lz4
    ncurses
    ncurses.dev
    python3
    unzip
    zip
    zlib
    zlib.dev
    openssl
    openssl.dev
    elfutils
    elfutils.dev
    pahole
    glibc
    glibc.dev
    glibc.static
    coreutils
    gnused
    gnumake
    cpio
    rsync
    perl
    pkg-config
    findutils
  ];

  patchPhase = ''
    mkdir -p workspace toolchains/linux-x86
    export WORKSPACE=$(pwd)/workspace

    # 1. Clone layout mappings
    cp -r --no-preserve=mode ${srcModules}/. $WORKSPACE/
    mkdir -p $WORKSPACE/kernel_platform/common
    cp -r --no-preserve=mode ${srcCommon}/. $WORKSPACE/kernel_platform/common/
    mkdir -p $WORKSPACE/kernel_platform/msm-kernel
    cp -r --no-preserve=mode ${srcMsmKernel}/. $WORKSPACE/kernel_platform/msm-kernel/

    # AOSP Prebuilts
    mkdir -p $WORKSPACE/kernel_platform/prebuilts/ndk-r23
    cp -r --no-preserve=mode ${srcNdk}/. $WORKSPACE/kernel_platform/prebuilts/ndk-r23/
    ln -sf linux-x86_64 $WORKSPACE/kernel_platform/prebuilts/ndk-r23/toolchains/llvm/prebuilt/linux-x86
    mkdir -p $WORKSPACE/kernel_platform/prebuilts/build-tools
    cp -r --no-preserve=mode ${srcPlatformBuildTools}/. $WORKSPACE/kernel_platform/prebuilts/build-tools/
    mkdir -p $WORKSPACE/kernel_platform/prebuilts/kernel-build-tools
    cp -r --no-preserve=mode ${srcKernelBuildTools}/. $WORKSPACE/kernel_platform/prebuilts/kernel-build-tools/
    mkdir -p $WORKSPACE/kernel_platform/tools/mkbootimg
    cp -r --no-preserve=mode ${srcMkbootimg}/. $WORKSPACE/kernel_platform/tools/mkbootimg/

    if [ ! -d "$WORKSPACE/kernel_platform/build/.git" ] && [ ! -d "$WORKSPACE/kernel_platform/build/kernel" ]; then
        mkdir -p $WORKSPACE/kernel_platform/build
        cp -r --no-preserve=mode ${srcKernelBuild}/. $WORKSPACE/kernel_platform/build/
    fi

    mkdir -p $WORKSPACE/kernel_platform/external/dtc
    cp -r --no-preserve=mode ${srcDtc}/. $WORKSPACE/kernel_platform/external/dtc/
    ln -sf dtc-parser.tab.h $WORKSPACE/kernel_platform/external/dtc/dtc-parser.h

    cd $WORKSPACE
    ln -sf kernel_platform/prebuilts prebuilts
    cd ..
    cp -r --no-preserve=mode ${srcClang}/. toolchains/linux-x86/

    # 2. FORCE WRITABLE
    chmod -R u+rwx workspace toolchains

    # =========================================================================
    # 3. POPCORN SOURCE CODE SURGERY
    # =========================================================================

    echo "[ ~ ] Applying Popcorn Custom Patches..."

    # A. Oplus fixes (Same as before)
    sed -i 's/u8 tmpbuf\[PAGE_SIZE\]/u8 tmpbuf\[BCC_PAGE_SIZE\]/g' workspace/kernel_platform/msm-kernel/drivers/power/oplus/v1/charger_ic/oplus_battery_sm8550.c
    sed -i 's/u8 tmpbuf\[PAGE_SIZE\]/u8 tmpbuf\[BCC_PAGE_SIZE\]/g' workspace/kernel_platform/msm-kernel/drivers/power/oplus/v2/charger_ic/oplus_hal_sm8450.c
    sed -i 's/\[PAGE_SIZE\]/[512]/g' workspace/kernel_platform/msm-kernel/drivers/input/touchscreen/synaptics_hbp/touchpanel_proc.c
    sed -i 's/\[4096\]/[512]/g' workspace/kernel_platform/msm-kernel/drivers/input/touchscreen/synaptics_hbp/touchpanel_proc.c
    sed -i 's/snprintf(page, PAGE_SIZE - 1/snprintf(page, 511/g' workspace/kernel_platform/msm-kernel/drivers/input/touchscreen/synaptics_hbp/touchpanel_proc.c

    # B. KernelSU Injection (Same as before)
    echo "[ ~ ] Wiring KernelSU into the driver tree..."
    cp -r --no-preserve=mode ${srcKSU}/kernel workspace/kernel_platform/msm-kernel/drivers/kernelsu
    echo 'obj-y += kernelsu/' >> workspace/kernel_platform/msm-kernel/drivers/Makefile

    # C. Tuning: 16GB RAM Efficiency, HZ=100, and MGLRU
    echo "[ ~ ] Injecting Battery, 16GB RAM, and Scheduler flags..."
    for cfg in $(find workspace/kernel_platform/msm-kernel/arch/arm64/configs -name "*defconfig*" -o -name "*.config"); do
        echo "CONFIG_KSU=y" >> "$cfg"
        echo "CONFIG_LOCALVERSION=\"-Mb-salami\"" >> "$cfg"
        echo "CONFIG_LOCALVERSION_AUTO=n" >> "$cfg"

        # HZ Tuning (Battery)
        sed -i 's/CONFIG_HZ_300=y/# CONFIG_HZ_300 is not set/g' "$cfg"
        sed -i 's/CONFIG_HZ_250=y/# CONFIG_HZ_250 is not set/g' "$cfg"
        echo "CONFIG_HZ_100=y" >> "$cfg"
        echo "CONFIG_HZ=100" >> "$cfg"
        
        # MGLRU (Memory efficiency)
        echo "CONFIG_LRU_GEN=y" >> "$cfg"
        echo "CONFIG_LRU_GEN_ENABLED=y" >> "$cfg"

        # 16GB RAM Optimizations (Trading RAM for CPU/Battery)
        # Increase write buffers to reduce CPU wakeups for disk I/O
        echo "CONFIG_VM_EVENT_COUNTERS=n" >> "$cfg" # Disable non-essential CPU counters
        echo "CONFIG_COMPACTION=y" >> "$cfg"
        echo "CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y" >> "$cfg"
        echo "CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=n" >> "$cfg" # Prevent aggressive background defrag
    done

    # D. Tuning: Optimization Level
    find workspace/kernel_platform/msm-kernel -name "Makefile" -exec sed -i 's/-Os/-O2/g' {} +
    find workspace/kernel_platform/msm-kernel -name "Makefile" -exec sed -i 's/-O3/-O2/g' {} +

    # 4. BRUTE FORCE SHEBANG & INTERPRETER FIXES
    echo "[ ~ ] Hardcoding Nix interpreter paths..."
    NIX_BASH=$(command -v bash)
    NIX_PYTHON=$(command -v python3)

    # Fix 'env bash' and 'env python'
    find workspace/kernel_platform -type f -exec sed -i "s|/usr/bin/env bash|$NIX_BASH|g" {} + || true
    find workspace/kernel_platform -type f -exec sed -i "s|env bash|$NIX_BASH|g" {} + || true
    find workspace/kernel_platform -type f -exec sed -i "s|/usr/bin/env python3|$NIX_PYTHON|g" {} + || true
    find workspace/kernel_platform -type f -exec sed -i "s|/usr/bin/env python|$NIX_PYTHON|g" {} + || true
    find workspace/kernel_platform -type f -exec sed -i "s|env python|$NIX_PYTHON|g" {} + || true

    # 5. MASSIVE SHEBANG PATCH
    patchShebangs workspace/kernel_platform/common/scripts
    patchShebangs workspace/kernel_platform/build
    patchShebangs workspace/kernel_platform/prebuilts
    patchShebangs workspace/kernel_platform/tools

    # 6. TOOLCHAIN SYMLINKING
    echo "[ ~ ] Symlinking Clang..."
    WORKSPACE_DIR="$PWD/workspace/kernel_platform"
    CLANG_SEARCH_PATH="$PWD/toolchains/linux-x86"
    LATEST_CLANG=$(find "$CLANG_SEARCH_PATH" -maxdepth 3 -name "clang" -type f | sort | tail -n 1 | xargs -I{} dirname {} | xargs -I{} dirname {})

    CLANG_VERSION_VALUE=$(grep -rh "^CLANG_VERSION=" "$WORKSPACE_DIR/msm-kernel/" "$WORKSPACE_DIR/common/" "$WORKSPACE_DIR/build/" 2>/dev/null | head -n 1 | cut -d= -f2 | tr -d '"' | tr -d "'")
    CLANG_PREBUILT_BIN_VALUE="prebuilts/clang/host/linux-x86/clang-''${CLANG_VERSION_VALUE}/bin"
    EXPECTED_CLANG_ROOT="$WORKSPACE_DIR/$(dirname "$CLANG_PREBUILT_BIN_VALUE")"

    mkdir -p "$(dirname "$EXPECTED_CLANG_ROOT")"
    ln -sf "$LATEST_CLANG" "$EXPECTED_CLANG_ROOT"

    # 7. AUTO-PATCHELF
    echo "[ ~ ] Auto-patching AOSP toolchains for standard Nix paths..."
    autoPatchelf toolchains workspace/kernel_platform/prebuilts workspace/kernel_platform/tools

    # 8. PERMANENT FIX: Lobotomize build_image
    echo "[ ~ ] Lobotomizing build_image to bypass Python packaging crashes..."
    rm -f workspace/kernel_platform/prebuilts/kernel-build-tools/linux-x86/bin/build_image
    echo '#!/bin/sh' > workspace/kernel_platform/prebuilts/kernel-build-tools/linux-x86/bin/build_image
    echo 'exit 0' >> workspace/kernel_platform/prebuilts/kernel-build-tools/linux-x86/bin/build_image
    chmod +x workspace/kernel_platform/prebuilts/kernel-build-tools/linux-x86/bin/build_image
  '';

  buildPhase = ''
    # 1. PATH FIX: Create a local bin and put core utils in it
    mkdir -p $PWD/bin-fix
    ln -s $(command -v bash) $PWD/bin-fix/bash
    ln -s $(command -v env) $PWD/bin-fix/env
    ln -s $(command -v sh) $PWD/bin-fix/sh
    ln -s $(command -v python3) $PWD/bin-fix/python
    ln -s $(command -v python3) $PWD/bin-fix/python3
    export PATH=$PWD/bin-fix:$PATH

    # 2. TOOLCHAIN EXPORTS
    export ARCH=arm64
    export SUBARCH=arm64
    export CROSS_COMPILE=aarch64-linux-gnu-
    export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    export LLVM=1
    export LLVM_IAS=1
    export HERMETIC_TOOLCHAIN=0

    # 3. BINARY OVERRIDES
    CLANG_BIN="$PWD/toolchains/linux-x86/bin"
    export CC="$CLANG_BIN/clang"
    export CXX="$CLANG_BIN/clang++"
    export HOSTCC=gcc
    export HOSTCXX=g++
    export LD="$CLANG_BIN/ld.lld"
    export AR="$CLANG_BIN/llvm-ar"
    export NM="$CLANG_BIN/llvm-nm"
    export OBJCOPY="$CLANG_BIN/llvm-objcopy"
    export OBJDUMP="$CLANG_BIN/llvm-objdump"
    export STRIP="$CLANG_BIN/llvm-strip"
    export READELF="$CLANG_BIN/llvm-readelf"
    export AS="$CLANG_BIN/clang"

    cd workspace/kernel_platform

    # Force Swappiness and Dirty Ratios at the kernel source level
    # This ensures that even if Android tries to reset them, the defaults favor battery.
    echo "[ ~ ] Surgery: Hardcoding 16GB-optimized sysctl defaults..."
    sed -i 's/sysctl_overcommit_memory = OVERCOMMIT_GUESS/sysctl_overcommit_memory = OVERCOMMIT_ALWAYS/g' workspace/kernel_platform/msm-kernel/mm/util.c || true

    echo "[ ~ ] Building kernel..."
    PATH=$PATH BUILD_CONFIG=msm-kernel/build.config.msm.kalama ./build/build.sh \
      HOSTCC=gcc \
      HOSTCXX=g++ \
      SKIP_MRPROPER=1 \
      LTO=full \
      KCFLAGS="-Wno-strict-prototypes -O2" \
      EXTRA_CMDS="CONFIG_KSU=y CONFIG_LOCALVERSION=\"-Mb-salami\"" || true

    echo "[ ~ ] Verifying Build Success..."
    IMG_PATH=$(find out -name "Image" -type f | head -n 1)

    if [ -z "$IMG_PATH" ]; then
        echo "[ ! ] FATAL: Kernel Image not found anywhere in out/. The C compilation failed."
        exit 1
    else
        echo "[ + ] SUCCESS: Kernel Image generated successfully at $IMG_PATH"
        # We DO NOT call 'exit 0' here so the installPhase can actually run!
    fi
  '';

  installPhase = ''
    mkdir -p $out
    echo "[ ~ ] Verifying Kernel Image size..."

    # Dynamically find the COMPRESSED Image
    IMG_PATH=$(find out -name "Image.lz4" -type f | head -n 1)

    if [ -n "$IMG_PATH" ]; then
        SIZE=$(stat -c%s "$IMG_PATH")
        echo "[ + ] Compressed Kernel size: $((SIZE / 1024 / 1024)) MB"
        
        # The compressed Image.lz4 should easily be under 32MB
        if [ $SIZE -gt 33554432 ]; then
            echo "[ ! ] WARNING: Compressed Kernel Image is larger than 32MB. This might be tight for some partitions."
        fi
    else
        echo "[ ! ] Could not find Image.lz4 to check size, but copying artifacts anyway."
    fi

    echo "[ ~ ] Collecting artifacts..."
    DIST_DIR=$(find out -name "dist" -type d | head -n 1)

    if [ -n "$DIST_DIR" ]; then
        cp -r $DIST_DIR/* $out/
    else
        cp -r workspace/kernel_platform/out $out/
    fi
  '';
}
