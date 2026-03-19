{
  pkgs,
  gitHash ? "unknown",
}:

let
  kernelVersion = "6.19.9";
  popcornVersion = "1.0.0Lb-doromipad";

  # Fetching the official CachyOS 6.19.9-1 source tree.
  cachySource = pkgs.fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux";
    rev = "cachyos-6.19.9-1";
    hash = "sha256-fsCAaCdAGg3PoAFKUndGiWaGgV09Z/+3V+pbk/qBtt0=";
  };

in
(pkgs.linux_6_19.override {
  argsOverride = {
    src = cachySource;
    version = "${kernelVersion}-Popcorn-${popcornVersion}-${gitHash}";
    modDirVersion = kernelVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      # Microarchitecture: Intel Comet Lake (10th Gen) uses the Skylake/v3 instruction set
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

      # --- DOROMIPAD SPECIFIC STRIPPING & ADDITIONS ---

      # GPU: Intel UHD Graphics (Keep i915, nuke AMD/Nvidia to save compile time/size)
      DRM_I915 = yes;
      DRM_AMDGPU = no;
      DRM_RADEON = no;
      DRM_NOUVEAU = no;

      # Networking: Intel Wi-Fi
      IWLWIFI = yes;

      # Thinkpad & Yoga Specifics
      THINKPAD_ACPI = yes; # Crucial for Thinkpad fan control and hotkeys
      HID_WACOM = yes; # Wacom digitizer (Yoga stylus)
      HID_MULTITOUCH = yes; # General touchscreen support
      I2C_HID_ACPI = yes; # Modern laptop touchpads/touchscreens
    };

    # Compiler optimization flags targeting Comet Lake (which is based on the Skylake architecture)
    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=skylake -O3"
      "KCPPFLAGS=-march=skylake -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant L (Doromipad Optimized) ==="
      echo "[*] Source: CachyOS cachyos-6.19.9-1"
      echo "[*] Target: ThinkPad L13 Yoga Gen 1 (Comet Lake)"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      patchShebangs scripts
      patchShebangs tools
    '';
  })
