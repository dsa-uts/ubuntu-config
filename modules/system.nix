{
  lib,
  pkgs,
  ...
}:

let
  sudoersDsaAdmin = pkgs.writeText "sudoers-dsa-admin" ''
    dsa-admin ALL=(ALL:ALL) NOPASSWD: ALL
  '';

  provisionKubeconfig = pkgs.writeShellApplication {
    name = "provision-k3s-kubeconfig";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = ''
      source_config=/etc/rancher/k3s/k3s.yaml
      target_dir=/home/dsa-admin/.kube
      target_config="$target_dir/config"

      install -d -o dsa-admin -g dsa-admin -m 0700 "$target_dir"
      temporary=$(mktemp "$target_dir/.config.XXXXXX")
      trap 'rm -f -- "$temporary"' EXIT
      install -o dsa-admin -g dsa-admin -m 0600 "$source_config" "$temporary"
      mv -f -- "$temporary" "$target_config"
      trap - EXIT
    '';
  };
in
{
  nix.enable = false;
  services.userborn.enable = false;
  security.enableWrappers = false;

  environment = {
    systemPackages = [ pkgs.k3s ];

    etc = {
      "sudoers.d/dsa-admin" = {
        source = sudoersDsaAdmin;
        mode = "0440";
        user = "root";
        group = "root";
      };

      "sysctl.d/90-k3s.conf".text = ''
        net.ipv4.ip_forward = 1
      '';
    };
  };

  system-manager.preActivationAssertions = {
    dsa-admin-exists = {
      enable = true;
      script = ''
        /usr/bin/getent passwd dsa-admin >/dev/null
        /usr/bin/getent group dsa-admin >/dev/null
      '';
    };

    sudoers-valid = {
      enable = true;
      script = "${pkgs.sudo}/bin/visudo -cf ${sudoersDsaAdmin}";
    };
  };

  systemd = {
    tmpfiles.settings."10-k3s" = {
      "/var/lib/rancher/k3s".d = {
        mode = "0700";
        user = "root";
        group = "root";
      };
      "/home/dsa-admin/.kube".d = {
        mode = "0700";
        user = "dsa-admin";
        group = "dsa-admin";
      };
    };

    services = {
      k3s = {
        description = "Lightweight Kubernetes";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        preStart = ''
          ${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=1
        '';
        serviceConfig = {
          Type = "notify";
          KillMode = "process";
          Delegate = true;
          LimitNOFILE = 1048576;
          LimitNPROC = "infinity";
          LimitCORE = "infinity";
          TasksMax = "infinity";
          Restart = "always";
          RestartSec = "5s";
          ExecStart = lib.concatStringsSep " " [
            "${pkgs.k3s}/bin/k3s"
            "server"
            "--secrets-encryption"
            "--secrets-encryption-provider=secretbox"
            "--write-kubeconfig-mode=0600"
          ];
        };
      };

      k3s-kubeconfig = {
        description = "Provision the dsa-admin k3s kubeconfig";
        after = [ "k3s.service" ];
        requires = [ "k3s.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecCondition = "${pkgs.coreutils}/bin/test -s /etc/rancher/k3s/k3s.yaml";
          ExecStart = lib.getExe provisionKubeconfig;
        };
      };
    };

    paths.k3s-kubeconfig = {
      description = "Refresh the dsa-admin kubeconfig when k3s rotates it";
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = "/etc/rancher/k3s/k3s.yaml";
    };
  };
}
