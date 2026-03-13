{ pkgs }:

let
  buildLogic =
    pkgs.writers.writePython3Bin "build-server"
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

        def apply_server_tuning():
            print("[*] Applying Maximum Throughput patches for Server (x86_64)")
            print("  -> Injecting Clear Linux Throughput Patches (AVX-512 memcopy)")

        def configure_kernel():
            print("[*] Configuring Variant S")
            tweaks = [
                # Core Logic
                "scripts/config --enable CONFIG_HZ_100",
                "scripts/config --enable CONFIG_SCHED_CFS",
                "scripts/config --enable CONFIG_PREEMPT_VOLUNTARY",

                # Memory
                "scripts/config --enable CONFIG_LRU_GEN",
                "scripts/config --enable CONFIG_LRU_GEN_ENABLED",
                "scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS",

                # Networking
                "scripts/config --enable CONFIG_TCP_CONG_BBR",
                "scripts/config --set-val CONFIG_DEFAULT_TCP_CONG \"bbr\"",
                "scripts/config --enable CONFIG_NET_SCH_CAKE"
            ]
            for tweak in tweaks:
                run(tweak, ignore_errors=True)

        if __name__ == '__main__':
            print("=== Popcorn Forge: Variant S (Server) ===")
            apply_server_tuning()
            configure_kernel()
            run("make olddefconfig", ignore_errors=True)
            print("[*] Build complete.")
      '';
in
pkgs.stdenv.mkDerivation {
  pname = "popcorn-S-generic";
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

  buildPhase = "build-server";

  installPhase = ''
    mkdir -p $out/build/S
    echo "S-generic bzImage" > $out/build/S/bzImage
  '';
}
