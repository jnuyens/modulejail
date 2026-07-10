{
  description = "modulejail: proactively shrink a Linux host's loaded-module attack surface";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Single source of truth: read VERSION='x.y.z' from the modulejail script,
      # the same value packaging/build.sh reads with awk.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./modulejail);
          verLine = builtins.head (builtins.filter (nixpkgs.lib.hasPrefix "VERSION='") lines);
          m = builtins.match "VERSION='([^']+)'.*" verLine;
        in
        builtins.head m;

      # Fixed date for the manpage .TH line. Reproducible (no wall-clock in the
      # sandbox). Set to the intended v1.5.0 release date.
      releaseDate = "2026-07-10";

      modulejailPkg = pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "modulejail";
          inherit version;
          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper pkgs.installShellFiles ];

          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall

            install -Dm755 modulejail $out/bin/modulejail

            substitute man/modulejail.8.in modulejail.8 \
              --replace-fail __VERSION__ "${version}" \
              --replace-fail __DATE__ "${releaseDate}"
            installManPage modulejail.8

            runHook postInstall
          '';

          postFixup = ''
            wrapProgram $out/bin/modulejail \
              --prefix PATH : ${pkgs.lib.makeBinPath [
                pkgs.kmod pkgs.gawk pkgs.coreutils pkgs.util-linux pkgs.gnused pkgs.gnugrep
              ]}
          '';

          meta = with pkgs.lib; {
            description = "Proactively shrink a Linux host's loaded-module attack surface";
            homepage = "https://github.com/jnuyens/modulejail";
            license = licenses.gpl3Only;
            platforms = platforms.linux;
            mainProgram = "modulejail";
          };
        };
    in
    {
      packages = forAllSystems (pkgs: rec {
        modulejail = modulejailPkg pkgs;
        default = modulejail;
      });

      apps = forAllSystems (pkgs: rec {
        modulejail = {
          type = "app";
          program = "${modulejailPkg pkgs}/bin/modulejail";
        };
        default = modulejail;
      });

      checks = forAllSystems (pkgs: {
        build = modulejailPkg pkgs;
        shellcheck = pkgs.runCommand "modulejail-shellcheck"
          { nativeBuildInputs = [ pkgs.shellcheck ]; }
          ''
            shellcheck -S warning ${./modulejail}
            touch $out
          '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.shellcheck pkgs.mandoc pkgs.kmod pkgs.gawk ];
        };
      });
    };
}
