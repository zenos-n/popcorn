{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "6.18.19";
  popcornVersion = "1.0.0S${if isRelease then "" else "b"}-nzserver";

  cachySource = pkgs.fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux";
    rev = "cachyos-6.18.19-1";
    hash = "sha256-nbYxfasUK7VXDPU5IBzlPxChpF4U7zOO9Yvy8h9EJ1M=";
  };

in
(pkgs.linux_6_18.override {
  argsOverride = {
    src = cachySource;
    version = "${kernelVersion}-Popcorn-${popcornVersion}${if isRelease then "" else "-${gitHash}"}";
    modDirVersion = kernelVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      # 9th Gen Intel (Coffee Lake) maps to Skylake architecture.
      GENERIC_CPU_V3 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V4 = no;

      # Server Core Logic: EEVDF + Throughput Focus
      HZ_100 = yes;
      HZ_1000 = no;
      SCHED_BORE = no; # Explicitly disable BORE to use EEVDF's native logic
      PREEMPT_NONE = yes; # No forced preemption for maximum throughput
      PREEMPT_DYNAMIC = no;

      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce yes;

      # --- NEGATIVE ZERO SERVER SPECIFICS ---

      # GPU: Intel i5-9400F SKU means NO integrated graphics silicon.
      # Nvidia GT card used for display-out.
      DRM_I915 = no; # Nuke Intel Graphics
      DRM_AMDGPU = no; # Nuke AMD Graphics
      DRM_RADEON = no;
      # DRM_NOUVEAU is kept enabled by default so the Nvidia GT card works for TTY/HDMI.

      # Networking: Hardwired Ethernet Server
      WLAN = no; # Nuke Wi-Fi completely
      IWLWIFI = no;
      MAC80211 = no;
      CFG80211 = no;

      # not having this made the build process scream
      HID = yes;
      INPUT_MISC = yes;
      HID_HAPTIC = pkgs.lib.mkForce no;
    };

    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=skylake -O3"
      "KCPPFLAGS=-march=skylake -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant S (Negative Zero Server) ==="
      echo "[*] Base: CachyOS 6.18.19-1 (LTS)"
      echo "[*] Target: Intel i5-9400F (Skylake arch) + Nvidia GT"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      patchShebangs scripts tools
    '';
  })
