#!/bin/bash
set -eux -o pipefail
chown -R {{.User}}:{{.User}} /usr/local/share
groupadd -f docker
usermod -aG docker {{.User}}
(dockerd > /dev/null 2>&1)&