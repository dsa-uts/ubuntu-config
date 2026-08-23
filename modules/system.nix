{
  lib,
  pkgs,
  ...
}:

let
  sudoersDsaAdmin = pkgs.writeText "sudoers-dsa-admin" ''
    dsa-admin ALL=(ALL:ALL) NOPASSWD: ALL
  '';
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
    };

    services = {
      k3s = {
        description = "Lightweight Kubernetes";
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
            "--write-kubeconfig-group=dsa-admin"
            "--write-kubeconfig-mode=0640"
          ];
        };
      };
    };
  };
}
