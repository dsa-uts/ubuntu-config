{ pkgs, ... }:

{
  home = {
    username = "mizokami";
    homeDirectory = "/home/mizokami";
    stateVersion = "26.05";
    sessionVariables.KUBECONFIG = "/home/mizokami/.kube/config";
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
