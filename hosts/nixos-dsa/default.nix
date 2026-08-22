{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
    ./orbstack.nix
  ];

  networking = {
    hostName = "nixos-dsa";
    dhcpcd.enable = false;
    useDHCP = false;
    useHostResolvConf = false;
  };

  systemd.network = {
    enable = true;
    networks."50-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  users = {
    mutableUsers = false;

    users.mizokami = {
      uid = 501;
      isSystemUser = true;
      group = "users";
      extraGroups = [
        "audio"
        "orbstack"
      ];
      createHome = true;
      home = "/home/mizokami";
      homeMode = "0700";
      useDefaultShell = true;
    };

    users.k3s-admin = {
      isNormalUser = true;
      createHome = true;
      homeMode = "0700";
    };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  security.pki.certificateFiles = [ ./orbstack-ca.pem ];
  time.timeZone = "Asia/Tokyo";

  system.stateVersion = "26.05";
}
