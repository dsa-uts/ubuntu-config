#!/usr/bin/env nu

def fail [message: string] {
  error make { msg: $message }
}

def apply-configuration [] {
  ^system-manager --nix-option accept-flake-config true switch --flake path:.#default
}

def verify-cluster [] {
  let start = (^systemctl start k3s.service | complete)
  if $start.exit_code != 0 {
    fail $"failed to start k3s.service: ($start.stderr | str trim)"
  }

  let k3s = "/run/system-manager/sw/bin/k3s"
  let kubeconfig = "/home/dsa-admin/.kube/config"
  ^$k3s kubectl wait --for=condition=Ready nodes --all --timeout=300s

  let authorization = (
    ^runuser -u dsa-admin -- $k3s kubectl --kubeconfig $kubeconfig auth can-i '*' '*'
    | str trim
  )
  if $authorization != "yes" {
    fail "dsa-admin does not have full cluster authorization"
  }

  let encryption = ^$k3s secrets-encrypt status | complete
  print --no-newline $encryption.stdout
  if $encryption.exit_code != 0 or not ($encryption.stdout | str contains --ignore-case "Encryption Status: Enabled") {
    fail "k3s Secret encryption is not enabled"
  }
}

def main [] {
  if (id -u | into int) != 0 {
    fail "this script must run as root"
  }
  if not ((pwd | path join flake.nix) | path exists) {
    fail "run this script from the shared nixos-config checkout"
  }

  apply-configuration
  verify-cluster
  print "System Manager applied successfully; k3s is ready and verified."
}
