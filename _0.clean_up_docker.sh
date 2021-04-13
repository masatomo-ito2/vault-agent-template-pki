#!/bin/bash

rm -rf cert template vault-agent.d  webapp_pki_policy.hcl default.conf
docker kill nginx_pki 
docker rm nginx_pki
