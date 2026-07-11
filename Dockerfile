FROM node:24.15.0-bookworm

ARG OPENCODE_VERSION=latest
ARG INSTALL_SSH=true

# set working directory
WORKDIR /app

# check architecture
RUN uname -m

# install opencode globally
RUN npm i -g "opencode-ai@${OPENCODE_VERSION}" && \
  installed_version_raw="$(opencode --version)" && \
  installed_version="${installed_version_raw#v}" && \
  echo "Installed opencode version: ${installed_version}" && \
  if [ "${OPENCODE_VERSION}" != "latest" ] && [ "${installed_version}" != "${OPENCODE_VERSION}" ]; then \
    echo "Expected opencode version ${OPENCODE_VERSION}, got ${installed_version}" >&2; \
    exit 1; \
  fi

RUN if [ "$INSTALL_SSH" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends openssh-server openssh-client && \
      rm -rf /var/lib/apt/lists/*; \
    fi

# non-root user (recommended)
RUN adduser --disabled-password opencode

# create necessary directories and set permissions
RUN mkdir -p /home/opencode/.local/share/opencode/ && \
  mkdir -p /home/opencode/.local/state/opencode && \
  mkdir -p /home/opencode/.config/opencode/ && \
  chown -R opencode:opencode /home/opencode

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY sshd_config /etc/ssh/sshd_config_opencode

# switch to non-root user
USER opencode

ENTRYPOINT ["docker-entrypoint.sh"]

# docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/pilinux/opencode:0.0.1 --output type=docker .
