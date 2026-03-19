{
  pkgs,
  gitHash ? "unknown",
}:

let
  kernelVersion = "6.19.9";
  popcornVersion = "1.0.0Lb-asus-f15";

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
      # Microarchitecture: Intel 11th Gen (Tiger Lake-H) supports AVX-512.
      # We bump this to v4 to take full advantage of those wide vectors.
      GENERIC_CPU_V4 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V3 = no;

      # Performance & Core Logic (Tuned for Battery/Thermals)
      HZ_300 = yes;
      HZ_1000 = no;
      SCHED_BORE = yes;
      PREEMPT_DYNAMIC = yes;

      # Memory Management
      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce no;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce yes;

      # --- ASUS TUF F15 SPECIFIC STRIPPING & ADDITIONS ---

      # GPU: Intel UHD + Nvidia RTX 3050 (Hybrid setup)
      DRM_I915 = yes;
      DRM_AMDGPU = no; # Nuke AMD to save compile time
      DRM_RADEON = no;
      # Note: We do NOT set DRM_NOUVEAU to 'no' here so Nvidia proprietary/open drivers still work.

      # Input & Platform Specifics
      ASUS_WMI = yes; # Crucial for Asus keyboard RGB, fan profiles, and Fn keys
      ASUS_LAPTOP = yes; # General Asus ACPI support
    };

    # Compiler optimization flags targeting Tiger Lake (11th Gen)
    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=tigerlake -O3"
      "KCPPFLAGS=-march=tigerlake -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant L (Asus F15 Optimized) ==="
      echo "[*] Source: CachyOS cachyos-6.19.9-1"
      echo "[*] Target: Asus TUF F15 (i7-11800H, RTX 3050)"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      patchShebangs scripts
      patchShebangs tools
    '';
  })
