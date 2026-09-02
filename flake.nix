{
  description = "Getting started with LLMOps";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    nixpkgs-25_11.url = "github:NixOS/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default";
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-25_11,
      devenv,
      systems,
      ...
    }@inputs:
    let
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [
              (
                { config, ... }:
                {
                  # KubeOne writes the cluster's kubeconfig to the working directory. Pointing
                  # KUBECONFIG at it from devenv.root (rather than a relative path) means kubectl
                  # finds the cluster from any subdirectory of the repository.
                  env.KUBECONFIG = "${config.devenv.root}/kubeconfig.yaml";

                  packages = with pkgs; [
                    kubeone
                    kubectl

                    # Tanka only supports Helm v3. It feeds every repository from chartfile.yaml
                    # (including the oci:// ones) into 'helm repo update', which Helm v4 rejects,
                    # making 'tk tool charts vendor' fail.
                    # This issue is being tracked upstream in grafana/tanka#1749.
                    # nixos-25.11 is the most recent nixpkgs branch still shipping Helm v3.
                    (import inputs.nixpkgs-25_11 { inherit system; }).kubernetes-helm
                    tanka
                  ];
                }
              )
            ];
          };
        }
      );
    };
}
