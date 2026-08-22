#!/usr/bin/env bash
set -euo pipefail

admin_source=/etc/rancher/k3s/k3s.yaml
server_ca=/var/lib/rancher/k3s/server/tls/server-ca.crt
client_ca=/var/lib/rancher/k3s/server/tls/client-ca.crt
client_ca_key=/var/lib/rancher/k3s/server/tls/client-ca.key

until kubectl --kubeconfig "$admin_source" get --raw=/readyz >/dev/null 2>&1; do
  sleep 1
done

install -d -o k3s-admin -g users -m 0700 /home/k3s-admin/.kube
install -o k3s-admin -g users -m 0600 "$admin_source" /home/k3s-admin/.kube/config

install -d -o mizokami -g users -m 0700 /home/mizokami/.kube

work_dir=$(mktemp -d /run/k3s-mizokami.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT

openssl genpkey \
  -algorithm EC \
  -pkeyopt ec_paramgen_curve:P-256 \
  -out "$work_dir/client.key"
openssl req \
  -new \
  -key "$work_dir/client.key" \
  -subj /CN=mizokami \
  -out "$work_dir/client.csr"
serial=$(openssl rand -hex 16)
openssl x509 \
  -req \
  -in "$work_dir/client.csr" \
  -CA "$client_ca" \
  -CAkey "$client_ca_key" \
  -set_serial "0x$serial" \
  -days 3650 \
  -sha256 \
  -out "$work_dir/client.crt"

kubectl config --kubeconfig "$work_dir/config" set-cluster k3s \
  --server=https://127.0.0.1:6443 \
  --certificate-authority="$server_ca" \
  --embed-certs=true
kubectl config --kubeconfig "$work_dir/config" set-credentials mizokami \
  --client-certificate="$work_dir/client.crt" \
  --client-key="$work_dir/client.key" \
  --embed-certs=true
kubectl config --kubeconfig "$work_dir/config" set-context mizokami@k3s \
  --cluster=k3s \
  --user=mizokami
kubectl config --kubeconfig "$work_dir/config" use-context mizokami@k3s

install -o mizokami -g users -m 0600 "$work_dir/config" /home/mizokami/.kube/config
