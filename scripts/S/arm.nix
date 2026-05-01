{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "6.18.25";
  popcornVersion = "1.0.0S${if isRelease then "" else "b"}-arm";

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
      # No x86 GENERIC_CPU_V* flags for ARM64 servers

      HZ_100 = yes;
      HZ_1000 = no;
      SCHED_BORE = no;
      PREEMPT_NONE = yes;
      PREEMPT_DYNAMIC = no;

      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce no;

      # not having this made the build process scream
      HID = yes;
      INPUT_MISC = yes;
      HID_HAPTIC = pkgs.lib.mkForce no;
    };

    makeFlags = (old.makeFlags or [ ]);

    postPatch = ''
      echo "=== Popcorn Forge: Variant S (Server ARM Experimental) ==="
      echo "[*] Base: CachyOS 6.18.19-1 (LTS)"
      patchShebangs scripts tools

      sed -i "s/^EXTRAVERSION =.*/EXTRAVERSION = -${popcornSuffix}/" Makefile

      echo "[*] Nuking HID_HAPTIC select..."
      find drivers/hid -name 'Kconfig' -exec sed -i '/select HID_HAPTIC/d' {} +
      sed -i '/hid-haptic/d' drivers/hid/Makefile
      sed -i '/hid-multitouch/d' drivers/hid/Makefile
    '';
  })
