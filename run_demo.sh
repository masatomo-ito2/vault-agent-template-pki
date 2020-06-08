#!/bin/bash

# Vault address andn token
VAULT_ADDR=https://vault.masa:8200
VAULT_TOKEN=root
VAULT_PKI_ISSUE=pki_int/issue/masatomo_ito

# Configuration variables
WORK_DIR=$PWD
CONSUL_TEMPLATE_DIR=${WORK_DIR}/consul-template.d
VAULT_AGENT_DIR=${WORK_DIR}/vault-agent.d
TEMPLATE_DIR=${WORK_DIR}/template
CERT_DIR=${WORK_DIR}/cert
NGINX_FQDN=nginx.vault.masa
NGINX_DOCKER_NAME=nginx_pki

# Vault policy
cat <<EOF > webapp_pki_policy.hcl
path "pki_int/issue/*" {
	capabilities = [ "create", "update" ]
}

path "pki_int/certs" {
	capabilities = ["list"]
}

path "pki_int/revoke" {
	capabilities = ["create", "update"]
}

path "pki_int/tidy" {
	capabilities = ["create", "update"]
}

path "pki/cert/ca" {
	capabilities = ["read"]
}

path "auth/token/renew" {
	capabilities = ["update"]
}

path "auth/token/renew-self" {
	capabilities = ["update"]
}
EOF

vault policy write webapp_pki_policy ${WORK_DIR}/webapp_pki_policy.hcl

# Approle set up
mkdir -p ${VAULT_AGENT_DIR}
vault write auth/approle/role/webapp_pki policies=webapp_pki_policy
vault read -field=role_id auth/approle/role/webapp_pki/role-id > ${VAULT_AGENT_DIR}/roleid
vault write -f -field=secret_id auth/approle/role/webapp_pki/secret-id > ${VAULT_AGENT_DIR}/secretid

# Nginx docker image 
docker pull nginx:1.19.0-alpine 
docker create -p 80:80 -p 443:443 -v ${WORK_DIR}/default.conf:/etc/nginx/conf.d/default.conf -v ${WORK_DIR}:/nginx --name ${NGINX_DOCKER_NAME} nginx:1.19.0-alpine 

# Nginx conf
cat <<EOF > ${WORK_DIR}/default.conf
server {
	listen              80;
	listen              [::]:80;
	server_name         ${NGINX_FQDN} www.${NGINX_FQDN};
	return 301          https://${NGINX_FQDN}$request_uri;
	return 301          https://www.${NGINX_FQDN}$request_uri;
}

server {
	listen              443 ssl http2 default_server;
	server_name         ${NGINX_FQDN} www.${NGINX_FQDN};
	ssl_certificate     /nginx/cert/webapp.crt;
	ssl_certificate_key /nginx/cert/webapp.key;
	# ssl_crl 						/nginx/cert/crl.pem;
	# ssl_client_certificate /nginx/cert/intermediate.cert.pem;
	# ssl_verify_client 	on;
	ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
	ssl_ciphers         HIGH:!aNULL:!MD5;

	location / {
		root   /usr/share/nginx/html;
		index  index.html index.htm;
	}
}
EOF
mkdir -p ${CERT_DIR}

# vault-agent configuration
cat <<EOF > ${VAULT_AGENT_DIR}/vault-agent.hcl
pid_file = "${VAULT_AGENT_DIR}/pidfile"

auto_auth {
  method {
		type = "approle"
		config = {
			role_id_file_path = "${VAULT_AGENT_DIR}/roleid"
			secret_id_file_path = "${VAULT_AGENT_DIR}/secretid"
			remove_secret_id_file_after_reading = false
		}
  }

  sink {
		type = "file"
    config = {
      path = "${VAULT_AGENT_DIR}/vault-token-via-agent"
    }
  }
}

vault {
  address = "${DEMO_VAULT_ADDR}"
}

template {
  source      = "${TEMPLATE_DIR}/webapp_cert.tpl"
  destination = "${CERT_DIR}/webapp.crt"
	perms = "0644"
	command = "docker exec -i ${NGINX_DOCKER_NAME} nginx -s reload"
}

template {
  source      = "${TEMPLATE_DIR}/webapp_key.tpl"
  destination = "${CERT_DIR}/webapp.key"
	perms = "0600"
	command = "docker exec -i ${NGINX_DOCKER_NAME} nginx -s reload"
}
EOF


# Template
mkdir -p ${TEMPLATE_DIR}

cat <<EOF > ${TEMPLATE_DIR}/webapp_cert.tpl
{{ with secret "${VAULT_PKI_ISSUE}" "common_name=${NGINX_FQDN}" "ttl=10s" }}
{{ .Data.certificate }}
{{ .Data.issuing_ca }}
{{ end }}
EOF

cat <<EOF > ${TEMPLATE_DIR}/webapp_key.tpl
{{ with secret "${VAULT_PKI_ISSUE}" "common_name=${NGINX_FQDN}" "ttl=10s" }}
{{ .Data.private_key }}
{{ end }}
EOF

# Genearate initial certificate
vault write -format=json ${VAULT_PKI_ISSUE} common_name="${NGINX_FQDN}" ttl="1m" | tee \
	>(jq -r '.data.certificate' > ${CERT_DIR}/webapp.crt) \
	>(jq -r '.data.ca_issuing_ca' >> ${CERT_DIR}/webapp.crt) \
	>(jq -r '.data.private_key' > ${CERT_DIR}/webapp.key)

# Start nginx
docker start ${NGINX_DOCKER_NAME}

# Start vault-agent
vault agent -config=${VAULT_AGENT_DIR}/vault-agent.hcl
