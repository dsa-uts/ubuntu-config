{ pkgs, ... }:

let
  kubeconfigProvisioner = pkgs.writeShellApplication {
    name = "provision-k3s-kubeconfigs";
    runtimeInputs = with pkgs; [
      coreutils
      k3s
      kubectl
      openssl
    ];
    text = builtins.readFile ../scripts/provision-kubeconfigs.sh;
  };
in
{
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = [ "--write-kubeconfig-mode=0600" ];
    manifests.mizokami-rbac.source = ../kubernetes/mizokami-rbac.yaml;
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall = {
    allowedTCPPorts = [ 6443 ];
    trustedInterfaces = [
      "cni0"
      "flannel.1"
    ];
  };

  environment.systemPackages = with pkgs; [
    k3s
    kubectl
  ];

  systemd.services.k3s-user-kubeconfigs = {
    description = "Provision per-user kubeconfigs for k3s";
    after = [ "k3s.service" ];
    requires = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${kubeconfigProvisioner}/bin/provision-k3s-kubeconfigs";
      RemainAfterExit = true;
    };
  };
}
