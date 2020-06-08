# Vault agentによる証明書の自動更新デモ

## 事前準備

### Vault server

VaultのPKI Secret engineの設定
- RootCAもしくはIntermediate CAの設定
- 例：
	- vault secret enable pki   # Root CA
	- vault secret enable -path=pki_int pki # Intermediate CA
- 証明書を`issue`できる設定
	- 参考：[Build your own certificate authority](https://learn.hashicorp.com/vault/secrets-management/sm-pki-engine)
- そのSecret engineのMount pathとRoleをスクリプトで設定
	- 例：
		- `VAULT_PKI_ISSUE=pki_int/issue/nginx`

### Root CAもしくはIntermediateのcertをOSもしくはブラウザのキーチェーンに追加（信頼する）


### セットアップ用のトークン

Vault addressとRoot tokenなど十分な権限を持つVault tokenをスクリプトに設定

```shell
VAULT_ADDR=https://vault.masa:8200
VAULT_TOKEN=root
```

### Dockerがインストールされていること

もし、Docker実行に`sudo`権限が必要な場合、スクリプト内のDocker実行の際に`sudo`で実行する。

### NginxサーバーのFQDNが名前解決できること

`/etc/hosts`などに追加
```
echo 127.0.0.1 nginx.vault.masa >> /etc/hosts
```

## Demoの実行

1. スクリプトを実行

```
./run_demo.sh
```

実行されると、各種設定ファイルなどが作成されNginxのサーバーも起動される。
Vault agentが実行されたシェルが表示される。
問題なければ１０秒おきに新しい証明書がRenderingされる。

2. ブラウザから確認

ブラウザを開き、`https://<NGINX_FQDN>`　へアクセスする。
正しい証明書がサーバーに設定され、Secureなアクセスができることを確認。





