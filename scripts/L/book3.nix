{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "7.0.2";
  popcornVersion = "2.0.0L${if isRelease then "" else "b"}-book3";

  # Fetching the official CachyOS 6.19.9-1 source tree.
  cachySource = pkgs.fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux";
    rev = "cachyos-7.0.2-1";
    hash = "sha256-iEaR1I1cIGBF5bEzyt9sz0N6XkxFqtb51To3PFF5CTQ=";
  };

in
(pkgs.linux_7_0.override {
  argsOverride = {
    src = cachySource;
    version = "${kernelVersion}-Popcorn-${popcornVersion}${if isRelease then "" else "-${gitHash}"}";
    modDirVersion = kernelVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      # Microarchitecture: Intel 13th Gen (Raptor Lake) uses the x86_64-v3 instruction set
      # (Intel dropped AVX-512 for Alder/Raptor Lake hybrid chips)
      GENERIC_CPU_V3 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V4 = no;

      # Performance & Core Logic (Tuned for Battery/Thermals)
      HZ_300 = yes;
      HZ_1000 = no;
      SCHED_BORE = yes;
      PREEMPT_DYNAMIC = yes;

      # Memory Management
      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce no;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce yes;

      # --- GALAXY BOOK 3 SPECIFIC STRIPPING & ADDITIONS ---

      # GPU: Intel Iris Xe Graphics (Keep i915, nuke AMD/Nvidia to save compile time/size)
      DRM_I915 = yes;
      DRM_AMDGPU = no;
      DRM_RADEON = no;
      DRM_NOUVEAU = no;

      # Networking: Intel Wi-Fi 6 (AX) and Bluetooth
      IWLWIFI = yes;
      BT_INTEL = yes;

      # Input & Platform Specifics
      SAMSUNG_LAPTOP = yes; # Crucial for Samsung ACPI (hotkeys, battery limiters)
      I2C_HID_ACPI = yes; # Required for the ELAN0B00 Touchpad
      I2C_DESIGNWARE_PLATFORM = yes; # Companion driver usually needed for Intel I2C touchpads
    };

    # Compiler optimization flags targeting the Alder/Raptor Lake hybrid architecture
    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=alderlake -O3"
      "KCPPFLAGS=-march=alderlake -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant L (Book3 Optimized) ==="
      echo "[*] Source: CachyOS cachyos-7.0.2-1"
      echo "[*] Target: Samsung Galaxy Book3 (i5-1335U, Raptor Lake)"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      patchShebangs scripts
      patchShebangs tools
    '';
  })
