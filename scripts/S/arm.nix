{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "6.18.19";
  popcornVersion = "1.0.0S${if isRelease then "" else "b"}-arm";

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
      # No x86 GENERIC_CPU_V* flags for ARM64 servers

      HZ_100 = yes;
      HZ_1000 = no;
      SCHED_BORE = no;
      PREEMPT_NONE = yes;
      PREEMPT_DYNAMIC = no;

      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce no;
    };

    makeFlags = (old.makeFlags or [ ]);

    postPatch = ''
      echo "=== Popcorn Forge: Variant S (Server ARM Experimental) ==="
      echo "[*] Base: CachyOS 6.18.19-1 (LTS)"
      patchShebangs scripts tools
    '';
  })
