{

  nixConfig.allow-import-from-derivation = false;

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = { self, nixpkgs, treefmt-nix, }:
    let

      overlay = (final: prev: {
        sops-init-gcs = final.writeShellApplication {
          name = "sops-init-gcs";
          runtimeInputs = [
            final.google-cloud-sdk
            final.jq
            final.sops
          ];
          text = builtins.readFile ./script.sh;
        };
      });

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay ];
      };

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixpkgs-fmt.enable = true;
        programs.prettier.enable = true;
        settings.formatter.prettier.excludes = [ "secrets.yaml" ];
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.options = [ "-s" "sh" ];
        settings.global.excludes = [ "LICENSE" ];
      };

    in
    {

      formatter.x86_64-linux = treefmtEval.config.build.wrapper;

      packages.x86_64-linux = {
        default = pkgs.sops-init-gcs;
        sops-init-gcs = pkgs.sops-init-gcs;
      };

      checks.x86_64-linux = {
        sops-init-gcs = pkgs.sops-init-gcs;
        formatting = treefmtEval.config.build.check self;
      };

      overlays.default = overlay;

    };
}
