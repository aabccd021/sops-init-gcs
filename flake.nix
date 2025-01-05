{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    project-utils = {
      url = "github:aabccd021/project-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, treefmt-nix, project-utils }:
    let

      utilPkgs = project-utils.packages.x86_64-linux;

      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixpkgs-fmt.enable = true;
        programs.prettier.enable = true;
        settings.formatter.prettier.excludes = [ "secrets.yaml" ];

        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.options = [ "-s" "sh" ];

      };

      scripts.checkpoint = utilPkgs.checkpoint;

      sops-init-gcs = pkgs.writeShellApplication {
        name = "sops-init-gcs";
        runtimeInputs = [
          pkgs.google-cloud-sdk
          pkgs.jq
          pkgs.sops
        ];
        text = builtins.readFile ./script.sh;
      };

    in
    {

      formatter.x86_64-linux = treefmtEval.config.build.wrapper;

      packages.x86_64-linux = {
        default = sops-init-gcs;
        sops-init-gcs = sops-init-gcs;
      };

      checks.x86_64-linux = {
        sops-init-gcs = sops-init-gcs;
        formatting = treefmtEval.config.build.check self;
      };

      apps.x86_64-linux = builtins.mapAttrs
        (name: script: {
          type = "app";
          program = "${script}/bin/${name}";
        })
        scripts;

    };
}
