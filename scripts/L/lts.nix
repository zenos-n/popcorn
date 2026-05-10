{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "6.18.25";
  popcornVersion = "1.1.0L${if isRelease then "" else "b"}-lts";

  # Fetching the official LTS release from CachyOS
  cachySource = pkgs.fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux";
    rev = "cachyos-6.18.25-1";
    hash = "sha256-E7656WzsVUnac71xdx2S2Zt67TOBmY9BSbziwIpn4Vs=";
  };
  finalVersion = "${kernelVersion}-Popcorn-${popcornVersion}${
    if isRelease then "" else "-${gitHash}"
  }";

  popcornSuffix = "Popcorn-${popcornVersion}${if isRelease then "" else "-${gitHash}"}";
in
(pkgs.linux_6_18.override {
  argsOverride = {
    src = cachySource;
    version = finalVersion;
    modDirVersion = finalVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      GENERIC_CPU_V3 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V4 = no;

      # Performance & Core Logic (Tuned for Battery/Thermals)
      HZ_300 = yes; # Lower tick rate (300Hz vs 1000Hz) reduces CPU wakeups and saves battery
      HZ_1000 = no;
      SCHED_BORE = yes; # Keep BORE scheduler so the UI stays snappy even on lower power
      PREEMPT_DYNAMIC = yes;

      # Memory Management
      # Laptops benefit from MADVISE over ALWAYS to prevent power-hungry background memory compaction
      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce no;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce yes;

      HID = pkgs.lib.mkForce yes;
      HID_GENERIC = pkgs.lib.mkForce yes;
      INPUT_MISC = yes;
    };

    # Compiler optimization flags targeting x86-64-v3
    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=x86-64-v3 -O3"
      "KCPPFLAGS=-march=x86-64-v3 -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant L (Laptop LTS) ==="
      echo "[*] Source: CachyOS cachyos-6.18.25-1"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      echo "[*] Nuking HID_HAPTIC select..."
      find drivers/hid -name 'Kconfig' -exec sed -i '/select HID_HAPTIC/d' {} +
      sed -i '/hid-haptic/d' drivers/hid/Makefile
      sed -i '/hid-multitouch/d' drivers/hid/Makefile

      sed -i "s/^EXTRAVERSION =.*/EXTRAVERSION = -${popcornSuffix}/" Makefile

      echo "[*] Bundling headers for ZenOS dev output..." 
      mkdir -p $out/lib/modules/${finalVersion}/build 
      cp -r .config System.map vmlinux $out/lib/modules/${finalVersion}/build/ 
      cp -r certs scripts include Makefile arch $out/lib/modules/${finalVersion}/build/ 
      cp -r $out/lib/modules/${finalVersion}/* $out/lib/modules/${finalVersion}/build/ 
      ln -s $out/lib/modules/${finalVersion}/build $out/build

      patchShebangs scripts
      patchShebangs tools
    '';
  })
