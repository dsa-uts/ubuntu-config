const admin_source = "/etc/rancher/k3s/k3s.yaml"
const server_ca = "/var/lib/rancher/k3s/server/tls/server-ca.crt"
const client_ca = "/var/lib/rancher/k3s/server/tls/client-ca.crt"
const client_ca_key = "/var/lib/rancher/k3s/server/tls/client-ca.key"

loop {
  let readiness = (
    ^kubectl --kubeconfig $admin_source get --raw /readyz
    | complete
  )

  if $readiness.exit_code == 0 {
    break
  }

  sleep 1sec
}

^install -d -o k3s-admin -g users -m "0700" /home/k3s-admin/.kube
^install -o k3s-admin -g users -m "0600" $admin_source /home/k3s-admin/.kube/config

^install -d -o mizokami -g users -m "0700" /home/mizokami/.kube

let work_dir = (^mktemp -d /run/k3s-mizokami.XXXXXX | str trim)
let client_key = ($work_dir | path join client.key)
let client_csr = ($work_dir | path join client.csr)
let client_crt = ($work_dir | path join client.crt)
let config = ($work_dir | path join config)

try {
  ^openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out $client_key
  ^openssl req -new -key $client_key -subj /CN=mizokami -out $client_csr

  let serial = (^openssl rand -hex 16 | str trim)
  ^openssl x509 -req -in $client_csr -CA $client_ca -CAkey $client_ca_key -set_serial $"0x($serial)" -days 3650 -sha256 -out $client_crt

  ^kubectl config --kubeconfig $config set-cluster k3s --server https://127.0.0.1:6443 --certificate-authority $server_ca --embed-certs
  ^kubectl config --kubeconfig $config set-credentials mizokami --client-certificate $client_crt --client-key $client_key --embed-certs
  ^kubectl config --kubeconfig $config set-context mizokami@k3s --cluster k3s --user mizokami
  ^kubectl config --kubeconfig $config use-context mizokami@k3s

  ^install -o mizokami -g users -m "0600" $config /home/mizokami/.kube/config
} catch { |err|
  do --ignore-errors { ^rm -rf -- $work_dir }
  error make $err
}

^rm -rf -- $work_dir
