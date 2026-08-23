#!/usr/bin/env nu

const VM_NAME = "dsa-dev"
const VM_IMAGE = "ubuntu:26.04"
const VM_USER = "dsa-admin"
const NIX_INSTALLER_VERSION = "2.35.1"
const NIX_INSTALLER_BASE_URL = "https://github.com/NixOS/nix-installer/releases/download"
const ARCHITECTURES = {
  arm64: {
    nix_system: "aarch64-linux"
    installer_sha256: "7e6e2f753144d7f19b16a9fce4b354cb0f46d1d47e6908bfb9186c89e0e0e649"
  }
  amd64: {
    nix_system: "x86_64-linux"
    installer_sha256: "3b49a0b91820accb76e3d9ff7ed64fc430121b9fafb3869b0d549721fbeb4c85"
  }
}
const NIX = "/nix/var/nix/profiles/default/bin/nix"

def fail [message: string] {
  error make { msg: $message }
}

def normalize-arch [arch: string] {
  match $arch {
    "arm64" | "aarch64" | "aarch64-linux" => "arm64"
    "amd64" | "x86_64" | "x86_64-linux" => "amd64"
    _ => { fail $"unsupported architecture '($arch)'; expected arm64 or amd64" }
  }
}

def requested-arch [] {
  let override = $env.ARCH? | default ""
  if ($override | is-empty) {
    normalize-arch (^uname -m | str trim)
  } else {
    normalize-arch $override
  }
}

def vm-exists [] {
  let result = (^orb list --quiet | complete)
  if $result.exit_code != 0 {
    fail $"failed to list OrbStack VMs: ($result.stderr | str trim)"
  }
  $VM_NAME in ($result.stdout | lines)
}

def existing-arch [] {
  normalize-arch (^orb run --machine $VM_NAME --user root uname -m | str trim)
}

def assert-matching-arch [] {
  let wanted = requested-arch
  let actual = existing-arch
  if $actual != $wanted {
    fail $"($VM_NAME) uses ($actual), but ($wanted) was requested; run 'ARCH=($wanted) task vm:recreate' to replace it explicitly"
  }
}

def create-vm [] {
  let arch = requested-arch
  if (vm-exists) {
    assert-matching-arch
    print $"($VM_NAME) already exists [($arch)]"
  } else {
    ^orb create --arch $arch --user $VM_USER $VM_IMAGE $VM_NAME
  }
}

def require-target [] {
  let distro_check = (
    ^orb run --machine $VM_NAME --user root grep --fixed-strings --line-regexp ID=ubuntu /etc/os-release
    | complete
  )
  let version_check = (
    ^orb run --machine $VM_NAME --user root grep --fixed-strings --line-regexp 'VERSION_ID="26.04"' /etc/os-release
    | complete
  )
  if $distro_check.exit_code != 0 or $version_check.exit_code != 0 {
    fail $"($VM_NAME) is not Ubuntu 26.04"
  }

  let user_check = (^orb run --machine $VM_NAME --user root id $VM_USER | complete)
  if $user_check.exit_code != 0 {
    fail $"required login account ($VM_USER) does not exist"
  }
}

def install-prerequisites [] {
  ^orb run --machine $VM_NAME --user root apt-get update
  ^orb run --machine $VM_NAME --user root /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends ca-certificates curl sudo
}

def install-nix [] {
  let installed = (^orb run --machine $VM_NAME --user root test -x $NIX | complete)
  if $installed.exit_code == 0 {
    let version_result = (^orb run --machine $VM_NAME --user root $NIX --version | complete)
    if $version_result.exit_code != 0 {
      fail $"failed to query the installed Nix version: ($version_result.stderr | str trim)"
    }
    let actual_version = $version_result.stdout | str trim | split row ' ' | last
    if $actual_version != $NIX_INSTALLER_VERSION {
      fail $"Nix ($actual_version) is installed, but ($NIX_INSTALLER_VERSION) is required"
    }
    print --no-newline $version_result.stdout
    return
  }

  let machine = ^orb run --machine $VM_NAME --user root uname -m | str trim
  let arch = normalize-arch $machine
  let architecture = $ARCHITECTURES | get $arch
  let system = $architecture.nix_system
  let expected = $architecture.installer_sha256
  let installer = "/tmp/nix-installer"
  let url = $"($NIX_INSTALLER_BASE_URL)/($NIX_INSTALLER_VERSION)/nix-installer-($system)"

  try {
    ^orb run --machine $VM_NAME --user root curl --fail --location --proto '=https' --tlsv1.2 $url --output $installer
    let actual = (
      ^orb run --machine $VM_NAME --user root sha256sum $installer
      | split row --regex '\s+'
      | first
    )
    if $actual != $expected {
      fail $"nix-installer checksum verification failed: expected ($expected), got ($actual)"
    }
    ^orb run --machine $VM_NAME --user root chmod 0755 $installer
    ^orb run --machine $VM_NAME --user root $installer install linux --enable-flakes --no-confirm
  } catch {|error|
    do --ignore-errors { ^orb run --machine $VM_NAME --user root rm -f -- $installer }
    error make { msg: $error.msg }
  }
  ^orb run --machine $VM_NAME --user root rm -f -- $installer
}

def apply-system [] {
  if not (vm-exists) {
    fail $"($VM_NAME) does not exist; run 'task vm:create' or 'task up' first"
  }
  assert-matching-arch
  require-target
  install-prerequisites
  install-nix

  let repo = pwd | path expand
  ^orb run --machine $VM_NAME --user root --path --workdir $repo $NIX --accept-flake-config develop path:. --command nu ./scripts/apply-system.nu
}

def recreate-vm [] {
  if (vm-exists) {
    print $"Deleting ($VM_NAME) permanently..."
    ^orb delete --force $VM_NAME
  }
  create-vm
}

def main [action: string] {
  if (which orb | is-empty) {
    fail "OrbStack CLI 'orb' was not found"
  }

  match $action {
    "create" => { create-vm }
    "apply" => { apply-system }
    "recreate" => { recreate-vm }
    _ => { fail "usage: vm.nu {create|apply|recreate}" }
  }
}
