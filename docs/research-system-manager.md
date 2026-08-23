# Ubuntu + System Manager implementation research

Research date: 2026-08-23 (Asia/Tokyo). This note uses only first-party documentation and source. System Manager details were checked against commit [`05e08c6`](https://github.com/numtide/system-manager/tree/05e08c6dd739d7f3204e71322594bb8095334cfb) on `release-26.05`; Nixpkgs details against commit [`5880666`](https://github.com/NixOS/nixpkgs/tree/5880666fd9eb563038431edb35c2d0aa595884e6) on `nixos-26.05`.

## Recommended implementation shape

### Flake outputs for both VM architectures

System Manager `release-26.05` is intentionally paired with Nixpkgs `nixos-26.05`; its library rejects other Nixpkgs releases unless `allowUnsupportedNixpkgs` is explicitly set. Every configuration must set `nixpkgs.hostPlatform`. The CLI first looks for `systemConfigs.<current-system>.<hostname-or-default>`, then falls back to `systemConfigs.<hostname-or-default>`. Therefore the least ambiguous two-architecture output is:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    system-manager = {
      url = "github:numtide/system-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { system-manager, ... }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
    in {
      systemConfigs = builtins.listToAttrs (map (system: {
        name = system;
        value.default = system-manager.lib.makeSystemConfig {
          modules = [
            { nixpkgs.hostPlatform = system; }
            ./system.nix
          ];
        };
      }) systems);
    };
}
```

Sources: [official compatibility table and stable-input example](https://github.com/numtide/system-manager/tree/05e08c6dd739d7f3204e71322594bb8095334cfb#nixpkgs-compatibility), [`makeSystemConfig` release check and API](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/nix/lib.nix#L8-L55), [CLI attribute selection](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/crates/system-manager-engine/src/register.rs#L79-L178).

Apply inside the VM with:

```sh
nix run github:numtide/system-manager/release-26.05 -- \
  switch --flake /path/to/shared/checkout --sudo
```

`switch` builds, registers a generation, and activates it. Activation manages `/etc`, reloads systemd, restarts changed units, starts new units, stops removed units, and runs managed tmpfiles rules. There is no automatic rollback-on-failure in this release, so the Task verification phase remains necessary. Sources: [CLI reference](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/docs/site/reference/cli.md#switch), [activation overview](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/docs/site/explanation/how-it-works.md#the-activation-phase), [tmpfiles activation implementation](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/crates/system-manager-engine/src/activate/tmp_files.rs#L8-L46).

### Manage the Nix configuration with System Manager

On `release-26.05`, `nix.enable` defaults to `false`. Enable it explicitly when System Manager should own the system-wide Nix settings. The module generates `/etc/nix/nix.conf` from `nix.settings` with `replaceExisting = true`; the file installed by `nix-installer` is backed up and restored if the managed entry is later deactivated. Because the generated file replaces the installer configuration, keep required features such as `nix-command` and `flakes` explicit in `nix.settings`. Sources: [release-26.05 Nix compatibility module](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/nix/modules/upstream/nixpkgs/nix.nix#L7-L38), [managing pre-existing Nix configuration](https://system-manager.net/main/how-to/manage-existing-files/#nix-configuration).

### `/etc` files and pre-activation validation

`environment.etc.<name>` targets `/etc/<name>`. A numeric `mode` causes a real copy (rather than a store symlink), and then `user`/`group` ownership is applied. Existing unmanaged paths are rejected by default; `replaceExisting = true` backs them up and restores them on deactivation/removal. Sources: [`environment.etc` option implementation](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/nix/modules/etc.nix#L19-L143), [existing-file behavior](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/docs/site/how-to/manage-existing-files.md).

For the sudoers fragment, create one store value and validate that exact candidate before `/etc` activation:

```nix
{ pkgs, ... }:
let
  sudoersDsaAdmin = pkgs.writeText "sudoers-dsa-admin" ''
    dsa-admin ALL=(ALL:ALL) NOPASSWD: ALL
  '';
in {
  environment.etc."sudoers.d/dsa-admin" = {
    source = sudoersDsaAdmin;
    mode = "0440";
    user = "root";
    group = "root";
  };

  system-manager.preActivationAssertions = {
    dsa-admin-exists = {
      enable = true;
      script = "getent passwd dsa-admin >/dev/null";
    };
    sudoers-valid = {
      enable = true;
      script = "/usr/sbin/visudo -cf ${sudoersDsaAdmin}";
    };
  };
}
```

Pre-activation assertions run before `/etc` files are changed and abort activation if any enabled script fails. Source: [assertion option and activation script](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/nix/modules/default.nix#L144-L170), [engine ordering](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/crates/system-manager-engine/src/activate.rs#L126-L179).

### Persistent directories and custom systemd units

Use structured tmpfiles rules for persistent paths; `d` creates a directory without treating it as generation-owned state:

```nix
systemd.tmpfiles.settings."10-k3s" = {
  "/var/lib/rancher/k3s".d = {
    mode = "0700";
    user = "root";
    group = "root";
  };
};
```

System Manager writes the rules beneath `/etc/tmpfiles.d`, then calls `systemd-tmpfiles --create --remove` during activation. Sources: [structured tmpfiles syntax](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/nix/modules/tmpfiles.nix#L17-L137), [rule installation](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/nix/modules/tmpfiles.nix#L140-L205).

Custom units use the NixOS-style `systemd.services.<name>` schema. `wantedBy = [ "multi-user.target" ]` is automatically rewritten to `system-manager.target`; spelling `system-manager.target` directly is also supported. Changed unit definitions are reload-or-restarted; removed units are stopped; new units are started by starting `system-manager.target`. Sources: [service option example](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/docs/site/reference/modules.md#systemdservices), [target substitution and unit generation](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/nix/modules/systemd.nix#L11-L24), [activation behavior](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/crates/system-manager-engine/src/activate/services.rs#L59-L122).

Recommended k3s unit core:

```nix
systemd.services.k3s = {
  description = "Lightweight Kubernetes";
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "notify";
    KillMode = "process";
    Delegate = true;
    LimitNOFILE = 1048576;
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
```

Keep the admin kubeconfig at its canonical path and set its group to `dsa-admin` with mode `0640`. This preserves root ownership, limits access to the administrator group, lets the bundled `kubectl` use its default path, and avoids synchronizing a copy after certificate renewal. Source: [K3s admin kubeconfig flags](https://docs.k3s.io/cli/server#admin-kubeconfig-options).

## Pinned official NixOS `nix-installer`

Use the NixOS Foundation installer, not `DeterminateSystems/nix-installer`. The current latest stable release is [`2.35.1`](https://github.com/NixOS/nix-installer/releases/tag/2.35.1), which bundles Nix 2.35.1 and therefore exceeds System Manager's tested minimum of Nix 2.32. The repository explicitly identifies itself as the community-maintained official installer. Sources: [NixOS installer README](https://github.com/NixOS/nix-installer/blob/d8d388055db624fb2f1e27f9e2107b230117eefb/README.md#nix-installer), [System Manager supported Nix statement](https://github.com/numtide/system-manager/tree/05e08c6dd739d7f3204e71322594bb8095334cfb#supported-nix).

| Nix system | Release asset | SHA-256 (hex) |
|---|---|---|
| `aarch64-linux` | `https://github.com/NixOS/nix-installer/releases/download/2.35.1/nix-installer-aarch64-linux` | `7e6e2f753144d7f19b16a9fce4b354cb0f46d1d47e6908bfb9186c89e0e0e649` |
| `x86_64-linux` | `https://github.com/NixOS/nix-installer/releases/download/2.35.1/nix-installer-x86_64-linux` | `3b49a0b91820accb76e3d9ff7ed64fc430121b9fafb3869b0d549721fbeb4c85` |

These values are from the release's official [`SHA256SUMS`](https://github.com/NixOS/nix-installer/releases/download/2.35.1/SHA256SUMS) asset. Download the architecture-specific binary, verify it with `sha256sum -c`, make it executable, then run as root:

```sh
./nix-installer install --enable-flakes --no-confirm
```

`--no-confirm` is the documented unattended mode; `--enable-flakes` enables both flakes and `nix-command`. Do not override `--nix-package-url`: upstream warns that installer/Nix combinations other than the associated one are not tested. Sources: [install and flakes instructions](https://github.com/NixOS/nix-installer/blob/d8d388055db624fb2f1e27f9e2107b230117eefb/README.md#install-nix), [noninteractive flag](https://github.com/NixOS/nix-installer/blob/d8d388055db624fb2f1e27f9e2107b230117eefb/README.md#skip-confirmation), [version pinning guidance](https://github.com/NixOS/nix-installer/blob/d8d388055db624fb2f1e27f9e2107b230117eefb/README.md#accessing-other-versions).

Bootstrap should be idempotent by checking for a working `nix` command (and preferably `nix --version`) before downloading or executing the installer. After a fresh multi-user installation, invoke Nix through the installer-created profile environment (for example by sourcing `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`) rather than assuming the current non-login shell's `PATH` was refreshed.

## k3s on Ubuntu 26.04

Nixpkgs `nixos-26.05` currently maps `pkgs.k3s` to `k3s_1_35`, specifically version `1.35.6+k3s1`. The package wrapper already puts these host tools on k3s's `PATH`: `kmod`, `socat`, `iptables`, `nftables`, `iproute2`, `ipset`, `bridge-utils`, `ethtool`, `util-linux` (`nsenter`, `mount`), `conntrack-tools`, `runc`, `bash`, and `shadow`; it also propagates its CNI plugins and k3s-built containerd components. There is no need to apt-install duplicate copies merely for executable discovery. Sources: [Nixpkgs default k3s alias](https://github.com/NixOS/nixpkgs/blob/5880666fd9eb563038431edb35c2d0aa595884e6/pkgs/top-level/all-packages.nix#L9339-L9345), [1.35 version pin](https://github.com/NixOS/nixpkgs/blob/5880666fd9eb563038431edb35c2d0aa595884e6/pkgs/applications/networking/cluster/k3s/1_35/versions.nix#L1-L22), [runtime dependency wrapper](https://github.com/NixOS/nixpkgs/blob/5880666fd9eb563038431edb35c2d0aa595884e6/pkgs/applications/networking/cluster/k3s/builder.nix#L333-L391).

Host/runtime requirements still belong to Ubuntu/the kernel:

- Enable `net.ipv4.ip_forward=1` persistently, for example with a managed `/etc/sysctl.d/90-k3s.conf`; apply it during activation or bootstrap because System Manager only installs the file and does not provide the NixOS `boot.kernel.sysctl` machinery.
- Modern Ubuntu is within K3s's expected “modern Linux” scope. K3s specifically says the extra Raspberry Pi VXLAN package is not needed on Ubuntu 24.04 and later. On a normal OrbStack Ubuntu 26.04 kernel, do not add speculative package/module workarounds unless testing shows a missing facility.
- K3s uses embedded containerd by default, so Docker is not a prerequisite.
- If UFW is enabled, K3s recommends disabling it or allowing API port 6443 and the default pod/service CIDRs (`10.42.0.0/16`, `10.43.0.0/16`). The agreed design adds no special isolation; verify the fresh image's UFW state rather than silently changing unrelated firewall policy.
- K3s supports both `x86_64` and `arm64/aarch64`; minimum server sizing is 2 cores and 2 GiB RAM.

Source: [official K3s requirements](https://docs.k3s.io/installation/requirements). The upstream requirements page does not prescribe extra Ubuntu 24.04+ kernel packages for these architectures.

K3s's default state path is `/var/lib/rancher/k3s`. The state tree is retained across ordinary applies. This local development cluster deliberately leaves secrets encryption at rest disabled; production-like environments should evaluate it separately. Source: [server data path](https://docs.k3s.io/cli/server#data).

The required verification maps directly to first-party commands:

```sh
systemctl is-active --quiet k3s.service
k3s kubectl wait --for=condition=Ready node --all --timeout=180s
sudo -u dsa-admin k3s kubectl auth can-i '*' '*'
```

Require the authorization command's output to equal `yes`.

## Implementation cautions

- Do not import the NixOS `services.k3s` module wholesale. System Manager only guarantees the subset it implements; NixOS modules tied to `boot.*`, activation scripts, or deeper NixOS infrastructure need stubs or are unsuitable. The explicit package + unit approach stays within supported `environment`, `systemd`, `/etc`, and tmpfiles interfaces. Source: [official NixOS-module import caveats](https://github.com/numtide/system-manager/blob/05e08c6dd739d7f3204e71322594bb8095334cfb/docs/site/how-to/import-nixos-module.md#limitations-and-considerations).
- `/var/lib/rancher/k3s` must not be expressed as generation-owned state. Its tmpfiles rule preserves mutable cluster state, while k3s owns and refreshes the admin kubeconfig at `/etc/rancher/k3s/k3s.yaml`.
- Activation restarts a changed k3s unit. Because the data directory is outside the generation, ordinary applies preserve cluster data.
- `replaceExisting` should be exceptional. It is appropriate only when takeover is intentional and reviewed; it is specifically inappropriate for `/etc/nix/nix.conf` in this design.
