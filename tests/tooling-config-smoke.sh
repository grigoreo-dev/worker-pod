#!/bin/sh
set -eu

grep -Fq 'ARG INSTALL_GH=true' Dockerfile
grep -Fq 'https://cli.github.com/packages/githubcli-archive-keyring.gpg' Dockerfile
grep -Fq '172.17.0.1:2222:2222' docker-compose.yml
grep -Fq 'SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}' docker-compose.yml
grep -Fq 'GH_TOKEN=${GH_TOKEN}' docker-compose.yml
grep -Fq 'SSH_PUBLIC_KEY=' .env.sample
grep -Fq 'GH_TOKEN=' .env.sample
grep -Fq 'INSTALL_PLAYWRIGHT' README.md
grep -Fq 'INSTALL_CAMOUFOX' README.md
grep -Fq 'INSTALL_GH' README.md
