# nixos-config

NixOS 26.05 上に単一サーバーの k3s クラスタを構築する flake です。OrbStack の
`nixos-dsa` (`aarch64-linux`) 向け設定を含みます。

## 適用

```console
sudo nixos-rebuild switch --flake .#nixos-dsa
```

Home Manager で `kubectl` と Helm が次のユーザーへ導入されます。

- `k3s-admin`: k3s の `system:admin` kubeconfig を持つクラスタ管理者
- `mizokami`: 全 Namespace の一般的なアプリリソースと Namespace 作成のみ許可

各ユーザーの kubeconfig は `/home/<user>/.kube/config` に生成されます。

## RBAC の確認

```console
sudo -u k3s-admin kubectl auth can-i '*' '*'
sudo -u mizokami kubectl auth can-i create deployments.apps --all-namespaces
sudo -u mizokami kubectl auth can-i create namespaces
sudo -u mizokami kubectl auth can-i get secrets --all-namespaces
sudo -u mizokami kubectl auth can-i create clusterroles.rbac.authorization.k8s.io
sudo -u mizokami kubectl auth can-i get nodes
```

想定結果は順に `yes`, `yes`, `yes`, `no`, `no`, `no` です。

`mizokami` は Pod や Deployment を作成できます。Kubernetes の性質上、作成した
workload から、その Namespace 内で workload にマウント可能な Secret の内容へ
間接的に到達できる場合があります。この RBAC は Secret API の直接操作を禁止しますが、
信頼境界の異なる利用者を同じ Namespace に隔離するものではありません。
