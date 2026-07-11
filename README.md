# OpenCode Docker

This repository provides a Docker image for running [OpenCode](https://github.com/anomalyco/opencode).
The image is automatically built and updated via GitHub Actions whenever a new release of OpenCode is published.

Published images are available on GitHub Container Registry at `ghcr.io/pilinux/opencode`,
tagged with the corresponding OpenCode version (e.g., `ghcr.io/pilinux/opencode:1.2.5`) and `latest`.

List of available versions can be found on the [GitHub Container Registry page](https://github.com/pilinux/opencode-docker/pkgs/container/opencode).

## Prerequisites

- Docker
- Docker Compose

## Usage

You can run the OpenCode server using the provided `docker-compose.yml`:

```bash
docker compose up -d
```

This will start the OpenCode web interface on `http://localhost:4096`.

## Configuration

### Environment Variables

- `TZ` - Timezone setting
- `OPENCODE_SERVER_USERNAME` - Server username
- `OPENCODE_SERVER_PASSWORD` - Server password

### Volumes

For persistent data and configuration, the following volumes can be mounted:

- `./data/share:/home/opencode/.local/share/opencode` - For shared data, including `auth.json` for LLM provider pre-configuration
- `./data/state:/home/opencode/.local/state/opencode`
- `./data/config:/home/opencode/.config/opencode` - For configuration files, including `opencode.json` for OpenCode pre-configuration

### LLM Provider Authentication

To authenticate with LLM providers, you can create an `auth.json` file in the `/home/opencode/.local/share/opencode` directory with the following structure:

```json
{
  "github-copilot": {
    "type": "oauth",
    "access": "",
    "refresh": "",
    "expires": 0
  }
}
```

### LLM Provider Configuration

`opencode.json` can be used and saved to the `/home/opencode/.config/opencode` directory to pre-configure LLM providers.
For example, to whitelist specific models for the GitHub Copilot provider, you can use the following configuration:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "github-copilot/gpt-5-mini",
  "provider": {
    "github-copilot": {
      "whitelist": ["gpt-5-mini", "gpt-4.1"]
    }
  }
}
```

## Optional Tools

The image supports four optional tools, all enabled by default via build arguments:

| Build Argument     | Default | Description                                         |
|--------------------|---------|-----------------------------------------------------|
| `INSTALL_SSH`      | `true`  | Installs OpenSSH server/client for remote access    |
| `INSTALL_PLAYWRIGHT` | `true` | Installs Playwright CLI and Chromium browser binary |
| `INSTALL_CAMOUFOX` | `true`  | Installs Camoufox CLI and browser binary            |
| `INSTALL_GH`       | `true`  | Installs the official GitHub CLI (`gh`)             |

To customize which tools are included at build time:

```bash
docker build -t opencode-custom \
  --build-arg INSTALL_SSH=true \
  --build-arg INSTALL_PLAYWRIGHT=true \
  --build-arg INSTALL_CAMOUFOX=true \
  --build-arg INSTALL_GH=true .
```

### SSH access

SSH starts only when the `SSH_PUBLIC_KEY` environment variable is **non-empty** at container startup.
Authentication is key-only (password authentication is disabled).

```bash
ssh -p 2222 opencode@localhost
```

### Browser tools

Playwright and Camoufox browser binaries are preloaded into the image during the build phase,
so no network download is required at runtime.

```bash
playwright-cli open https://example.com
camoufox-cli open https://example.com
```

### GitHub CLI

The `gh` binary is installed from GitHub's official apt repository.
GitHub tokens must only be provided at **runtime** via the `GH_TOKEN` environment variable —
never baked into the image.

```bash
GH_TOKEN=... gh auth status
```

### Skills

OpenCode skills are installed under `~/.agents/skills` inside the container.

## Building

The Docker image is built for both `linux/amd64` and `linux/arm64` architectures.
Images are automatically pushed to GitHub Container Registry (`ghcr.io/pilinux/opencode`) with version tags matching OpenCode releases and a `latest` tag for the most recent release.

## Contributing

Feel free to open issues or submit pull requests for improvements to the Docker setup.

## License

Released under the [MIT license](LICENSE).

## Disclaimer

This repository is not affiliated with the OpenCode project. It is an independent effort to provide a Docker image for OpenCode users.
The OpenCode project is developed and maintained by the Anomaly team.
For any issues or contributions related to OpenCode itself, please refer to the [OpenCode repository](https://github.com/anomalyco/opencode).
