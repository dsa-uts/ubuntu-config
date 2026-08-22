{ config, lib, ... }:

{
  environment.shellInit = ''
    . /opt/orbstack-guest/etc/profile-early
    . /opt/orbstack-guest/etc/profile-late
  '';

  documentation = {
    man.enable = true;
    doc.enable = true;
    info.enable = true;
  };

  services.resolved.enable = false;
  networking.resolvconf.enable = false;
  environment.etc."resolv.conf".source = "/opt/orbstack-guest/etc/resolv.conf";
  networking.dhcpcd.extraConfig = ''
    noarp
    noipv6
  '';

  services.openssh.enable = false;

  systemd.services = {
    "systemd-oomd".serviceConfig.WatchdogSec = 0;
    "systemd-userdbd".serviceConfig.WatchdogSec = 0;
    "systemd-udevd".serviceConfig.WatchdogSec = 0;
    "systemd-timesyncd".serviceConfig.WatchdogSec = 0;
    "systemd-timedated".serviceConfig.WatchdogSec = 0;
    "systemd-portabled".serviceConfig.WatchdogSec = 0;
    "systemd-nspawn@".serviceConfig.WatchdogSec = 0;
    "systemd-machined".serviceConfig.WatchdogSec = 0;
    "systemd-localed".serviceConfig.WatchdogSec = 0;
    "systemd-logind".serviceConfig.WatchdogSec = 0;
    "systemd-journald@".serviceConfig.WatchdogSec = 0;
    "systemd-journald".serviceConfig.WatchdogSec = 0;
    "systemd-journal-remote".serviceConfig.WatchdogSec = 0;
    "systemd-journal-upload".serviceConfig.WatchdogSec = 0;
    "systemd-importd".serviceConfig.WatchdogSec = 0;
    "systemd-hostnamed".serviceConfig.WatchdogSec = 0;
    "systemd-homed".serviceConfig.WatchdogSec = 0;
    "systemd-networkd".serviceConfig.WatchdogSec = lib.mkIf config.systemd.network.enable 0;
  };

  programs.ssh.extraConfig = ''
    Include /opt/orbstack-guest/etc/ssh_config
  '';

  nix.settings.extra-platforms = [
    "x86_64-linux"
    "i686-linux"
  ];

  users.groups.orbstack.gid = 67278;
}
