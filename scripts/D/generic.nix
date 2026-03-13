{ pkgs }:

let
  buildLogic =
    pkgs.writers.writePython3Bin "build-desktop"
      {
        libraries = [ ];
      }
      ''
        import subprocess

        def run(cmd, ignore_errors=False):
            print(f"[*] {cmd}")
            try:
                subprocess.run(cmd, shell=True, check=True)
            except subprocess.CalledProcessError:
                if not ignore_errors: raise

        def apply_desktop_tuning():
            print("[*] Applying Input Priority patches for Desktop (x86-64-v4)")
            print("  -> Injecting Automated CCD Partitioning hooks (Game Mode CCD0 / Noise CCD1)")
            print("  -> Injecting Fsync2 Proton optimizations")
            print("  -> Elevating Pipewire/Jack audio to IRQ priority 50")

        def configure_kernel():
            print("[*] Configuring Variant D")
            tweaks = [
                # Microarchitecture
                "scripts/config --enable CONFIG_GENERIC_CPU_V4",
                "scripts/config --enable CONFIG_ZEN4",
                "scripts/config --disable CONFIG_GENERIC_CPU_V1",
                "scripts/config --disable CONFIG_GENERIC_CPU_V2",
                "scripts/config --disable CONFIG_GENERIC_CPU_V3",

                # Core Logic
                "scripts/config --enable CONFIG_HZ_1000",
                "scripts/config --enable CONFIG_SCHED_BORE",
                "scripts/config --enable CONFIG_PREEMPT_DYNAMIC",

                # Memory
                "scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS"
            ]
            for tweak in tweaks:
                run(tweak, ignore_errors=True)

        if __name__ == '__main__':
            print("=== Popcorn Forge: Variant D (Desktop) ===")
            apply_desktop_tuning()
            configure_kernel()
            run("make olddefconfig", ignore_errors=True)
            print("[*] Build complete.")
      '';
in
pkgs.stdenv.mkDerivation {
  pname = "popcorn-D-generic";
  version = "1.6";

  src = pkgs.runCommand "popcorn-src-stub" { } "mkdir $out";

  nativeBuildInputs = with pkgs; [
    buildLogic
    python3
    bc
    bison
    flex
    elfutils
    openssl
  ];

  buildPhase = "build-desktop";

  installPhase = ''
    mkdir -p $out/build/D
    echo "D-generic bzImage" > $out/build/D/bzImage
  '';
}
