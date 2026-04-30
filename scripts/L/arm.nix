{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "7.0.2";
  popcornVersion = "2.0.0L${if isRelease then "" else "b"}-arm";

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
      # We explicitly REMOVE the x86 GENERIC_CPU_V* logic here.
      # Nixpkgs will automatically apply standard ARM64 configs when built on an AArch64 host.

      # Performance & Core Logic (Tuned for Battery/Thermals)
      HZ_300 = yes; # Lower tick rate (300Hz vs 1000Hz) reduces CPU wakeups and saves battery
      HZ_1000 = no;
      SCHED_BORE = yes; # Keep BORE scheduler so the UI stays snappy even on lower power
      PREEMPT_DYNAMIC = yes;

      # Memory Management
      # Laptops benefit from MADVISE over ALWAYS to prevent power-hungry background memory compaction
      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce no;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce yes;
    };

    makeFlags = (old.makeFlags or [ ]);

    postPatch = ''
      echo "=== Popcorn Forge: Variant L (Laptop ARM Experimental) ==="
      echo "[*] Source: CachyOS cachyos-7.0.2-1"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      patchShebangs scripts
      patchShebangs tools
    '';
  })
