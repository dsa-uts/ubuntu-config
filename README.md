# ubuntu-config

OrbStack 上の Ubuntu 26.04 LTS VM `dsa-dev` に、System Manager で単一ノードの
k3s クラスタを構築する設定です。リポジトリ名は旧構成に由来しますが、NixOS は使用しません。

System Manager が扱うのはディストリビューションレベルの設定だけです。ユーザーの
dotfiles、シェル、`kubectl`、Helm などは別の Home Manager リポジトリで管理します。

## 必要なもの

- OrbStack 2.2.3 以降
- Nix
- [direnv](https://direnv.net/) と [nix-direnv](https://github.com/nix-community/nix-direnv)
  （シェルへの hook 設定済み）

初回だけ、このリポジトリの開発環境を許可します。Task と Nushell は devShell から
提供されます。

```console
direnv allow
```

## VM の作成と適用

```console
task up
```

`task up` は次の処理を非破壊かつ冪等に実行します。

1. 存在しない場合だけ `ubuntu:26.04` VM `dsa-dev` を作成
2. ログインユーザー `dsa-admin` の存在を確認
3. 公式 `NixOS/nix-installer` 2.35.1 を SHA-256 検証後に非対話で導入
   （既存 Nix はバージョンを検証）
4. ホストの現在の checkout を OrbStack の共有マウント越しに評価して System Manager を適用
5. k3s、ノード、管理者権限、Secret encryption を検証

個別のターゲットも利用できます。

```console
task vm:create
task apply
```

## アーキテクチャ

デフォルトでは macOS ホストと同じアーキテクチャを選びます。明示する場合は
`ARCH=arm64` または `ARCH=amd64` を指定します。

```console
ARCH=amd64 task up
```

既存 VM と要求したアーキテクチャが異なる場合、`task up` は VM を削除せず失敗します。
切り替えるには、次の破壊的ターゲットを明示的に実行してください。

```console
ARCH=amd64 task vm:recreate
```

> **警告:** `task vm:recreate` は `dsa-dev` を完全に削除します。VM 内のファイル、
> 開発データ、k3s の全状態、Secret encryption の鍵は復元できません。

## 管理される設定

- Nixpkgs `nixos-26.05` と System Manager `release-26.05`
- Nixpkgs で固定された k3s と systemd サービス
- `net.ipv4.ip_forward=1`
- `dsa-admin` の passwordless sudo（適用前に `visudo` で検証）
- `/home/dsa-admin/.kube/config`（所有者 `dsa-admin`、mode `0600`）

k3s の状態と暗号鍵は `/var/lib/rancher/k3s` に保存され、通常の `task apply` では
保持されます。k3s はデフォルト構成の Traefik、ServiceLB などを有効にし、Secret は
`secretbox` provider で暗号化します。

## 適用後の検証

`task apply` は最大 5 分待ち、次をすべて満たさなければ失敗します。

- `k3s.service` が active
- 単一ノードが `Ready`
- `dsa-admin` の kubeconfig で `auth can-i '*' '*'` が `yes`
- `k3s secrets-encrypt status` が encryption enabled

VM への接続後、同じ状態を手動で確認できます。

```console
orb shell dsa-dev
sudo k3s kubectl get nodes
k3s kubectl --kubeconfig ~/.kube/config auth can-i '*' '*'
sudo k3s secrets-encrypt status
```
