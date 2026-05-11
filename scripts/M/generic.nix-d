{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  # Detect if we are already on ARM64, otherwise use the cross-compilation toolchain
  # This fixes the "unrecognized command-line option '-mlittle-endian'" error
  # by ensuring the build uses an aarch64-linux-gnu-gcc instead of host gcc.
  pkgsArm = if pkgs.stdenv.hostPlatform.isAarch64 then pkgs else pkgs.pkgsCross.aarch64-multiplatform;

  # The "Google Standard" GKI - Targeting Android 16 (6.12 LTS)
  kernelVersion = "6.12.x-gki";
  popcornVersion = "1.0.0M${if isRelease then "" else "b"}-generic";

  gkiSource = pkgs.fetchgit {
    url = "https://android.googlesource.com/kernel/common";
    rev = "android16-6.12";
    sha256 = "sha256-DlOyrE5txcqhwnYzIIIX173Hbw7pxVYa79mLW/apQQE="; # Remember to update after prefetch
  };

in
(pkgsArm.linux_6_12.override {
  argsOverride = {
    src = gkiSource;
    version = "${kernelVersion}-Popcorn-${popcornVersion}${if isRelease then "" else "-${gitHash}"}";
    # For GKI, modDirVersion usually needs to be the exact base version (e.g., 6.12.0)
    # to maintain module compatibility across different GKI builds.
    modDirVersion = "6.12.0";
  };
}).overrideAttrs
  (old: {
    # Ensure build tools are available in the native environment
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      pkgs.python3
      pkgs.bc
      pkgs.bison
      pkgs.flex
    ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      # --- PURE GKI BASELINE (Android 16 / 6.12) ---
      ANDROID = yes;
      ANDROID_BINDER_IPC = yes;
      ANDROID_BINDERFS = yes;

      # Standard Mobile Logic
      HZ_250 = yes;
      PREEMPT = yes;

      # Power Management
      CPU_IDLE = yes;
      CPU_FREQ_DEFAULT_GOV_SCHEDUTIL = yes;

      # Memory
      CMA = yes;
      ZRAM = yes;
      ZSMALLOC = yes;
    };

    # Note: We removed manual ARCH/CROSS_COMPILE from makeFlags because
    # pkgsCross.aarch64-multiplatform handles these automatically.
    makeFlags = (old.makeFlags or [ ]);

    postPatch = ''
      echo "=== Popcorn Forge: Variant M (Mobile Generic GKI - Android 16) ==="
      echo "[*] Cross-compiling for: ${pkgsArm.stdenv.hostPlatform.config}"

      patchShebangs scripts
      patchShebangs tools
    '';
  })
