{
  pkgs,
  gitHash ? "unknown",
}:

let
  kernelVersion = "6.19.9";
  popcornVersion = "1.0.0Db-doromitul";

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
    modDirVersion = kernelVersion; # Matches kernel's internal Makefile
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      # --- CPU & MICROARCHITECTURE ---
      GENERIC_CPU_V4 = yes;
      ZEN4 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V3 = no;

      # CCD Logic: Symmetrical 6+6 confirmed.
      # This enables AMD's cache prioritization sysfs tools to keep threads local.
      SCHED_MC_PRIO = yes;
      AMD_3D_VCACHE = yes;

      # Core Performance (Targeted for Max UX/Responsiveness)
      HZ_1000 = yes;
      SCHED_BORE = yes;
      PREEMPT_DYNAMIC = yes;

      # Memory
      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce no;

      # --- GPU STRIPPING (AMD Full, No Nvidia/Intel) ---
      DRM_NOUVEAU = no;
      DRM_I915 = no;
      DRM_XE = no;

      # --- NETWORKING (Ethernet + BT, No Wi-Fi) ---
      # Nuking the massive 802.11 Wi-Fi stack and specific Wi-Fi chip drivers
      WLAN = no;
      IWLWIFI = no;
      RTW88 = no;
      MAC80211 = no;
      CFG80211 = no;

      # --- PERIPHERALS & LEGACY ---
      # Kept: USB 1.1 and Floppy support
      USB_OHCI_HCD = yes;
      USB_UHCI_HCD = yes;
      BLK_DEV_FD = yes;

      # Nuked: Pre-USB legacy junk
      SERIO_I8042 = no; # No PS/2
      MOUSE_PS2 = no;
      KEYBOARD_ATKBD = no;
      SERIAL_8250 = no; # No RS-232 COM ports
      PARPORT = no; # No Parallel ports

      # Storage and Filesystems (EXT4, BTRFS, NTFS, SATA, NVMe) are implicitly
      # left alone to inherit NixOS/Cachy defaults.
    };

    # Aggressive compiler tuning specifically for Zen 4
    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=znver4 -O3"
      "KCPPFLAGS=-march=znver4 -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant D (Doromitul Optimized) ==="
      echo "[*] Source: CachyOS cachyos-6.19.9-1"
      echo "[*] Target: Ryzen 9 7900 (6+6) + RX 6900XT"

      patchShebangs scripts
      patchShebangs tools
    '';
  })
