{ pkgs, ... }:

{
  home = {
    username = "k3s-admin";
    homeDirectory = "/home/k3s-admin";
    stateVersion = "26.05";
    sessionVariables.KUBECONFIG = "/home/k3s-admin/.kube/config";
    packages = with pkgs; [
      kubectl
      kubernetes-helm
    ];
  };

  programs = {
    bash.enable = true;
    bash.enableCompletion = true;
    home-manager.enable = true;
  };
}
