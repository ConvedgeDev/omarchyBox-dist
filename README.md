# Linux ARM64 Desktop Apps

Verified Linux ARM64 installer mirrors for **Claude Desktop** and **ChatGPT / Codex App**. Each GitHub Release contains the exact installer files published by Anthropic and OpenAI, plus a checksum file and machine-readable metadata for offline installs and reproducible downloads.

**English** · [中文说明](#中文说明)

## Download v0.1.13

| App | Version | Package format | Size | Release download |
| --- | --- | --- | --- | --- |
| Claude Desktop | 5.1231.2 | Debian ARM64 (`.deb`) | 167 MiB | [claude-desktop_5.1231.2_arm64.deb](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.13/claude-desktop_5.1231.2_arm64.deb) |
| ChatGPT / Codex App | 26.1106.51428-1 | Arch Linux AArch64 (`.pkg.tar.zst`) | 550 MiB | [chatgpt-bin-26.1106.51428-1-aarch64.pkg.tar.zst](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.13/chatgpt-bin-26.1106.51428-1-aarch64.pkg.tar.zst) |

Release files:

- [SHA256SUMS](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.13/SHA256SUMS) — SHA-256 for both installer files.
- [desktop-arm64.json](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.13/desktop-arm64.json) — versions, file sizes, vendor source URLs, signed-index URLs, signing-key fingerprints and verification methods.

The original vendor downloads remain available at the URLs recorded in `desktop-arm64.json`. The GitHub Release copies let you download and verify a known-good ARM64 build even when a vendor URL changes or a pinned version is removed from the live index.

Verified on 2026-11-11.

## Verify the downloads

Place the installer files and `SHA256SUMS` in the same directory, keeping the filenames shown above, then run:

```sh
# Linux
sha256sum --ignore-missing --check SHA256SUMS

# macOS
shasum --ignore-missing -a 256 --check SHA256SUMS
```

Each installer should report `OK`. You can verify either file by keeping only its line in `SHA256SUMS`.

The release checksums are generated from the downloaded package bytes after the vendor signatures and signed indexes have been checked:

- **Claude Desktop** — the `.deb` is listed in Anthropic's OpenPGP-signed APT `InRelease` file. The publisher pins Anthropic's signing-key fingerprint `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`, verifies the ARM64 `Packages.gz` digest from `InRelease`, and then verifies the package size and SHA-256. See [Anthropic's Linux installation guide](https://support.claude.com/en/articles/10065433-install-claude-desktop).
- **ChatGPT / Codex App** — the package is recorded in OpenAI's OpenPGP-signed Arch repository index, and OpenAI also publishes a detached signature for the package. The publisher pins OpenAI's signing-key fingerprint `3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4`, verifies the repository index and package signature, and then verifies the signed size and SHA-256. See [OpenAI's Linux installation guide](https://learn.chatgpt.com/docs/linux/linux-app).

## Install on Linux

Download the package that matches your distribution and architecture, verify it with `SHA256SUMS`, then install it with the system package manager or the procedure described by the vendor.

- **Claude Desktop** — the Debian package targets the Ubuntu / Debian systems listed by Anthropic. Install the `.deb` with the distribution's package tooling and resolve any dependencies requested by the vendor package.
- **ChatGPT / Codex App** — the Arch Linux package targets Arch Linux AArch64. Install the `.pkg.tar.zst` with the distribution's package tooling and resolve any dependencies requested by the vendor package.

Only Linux ARM64 (`aarch64`) packages are mirrored here. For other distributions or architectures, use the vendor documentation and official download channels.

## Distribution

Vendor application packages, updates and support remain the responsibility of Anthropic and OpenAI. Use of each application is governed by its vendor terms: [Anthropic terms](https://www.anthropic.com/legal/consumer-terms) · [OpenAI terms](https://openai.com/policies/row-terms-of-use/).

## Maintainer publishing

Download the current official packages, refresh every generated file, tag the repository and publish the release assets with:

```sh
bash scripts/build-release.sh
```

Without `--release`, the script increments the latest release's patch version. To refresh assets on an existing release, use `--replace-existing --release vX.Y.Z`. Add `--if-changed` to skip publishing when the verified vendor versions already match the current manifest. It requires `curl`, `gpg`, `python3`, `git` and an authenticated `gh` CLI; the GitHub workflow runs the same command on an Ubuntu runner.

The GitHub Actions workflow also runs daily at 09:17 Asia/Singapore. Scheduled runs verify the vendor indexes and publish the next patch only when a package version changes; unchanged runs exit without creating a release.

---

## 中文说明

这里镜像两个 Linux ARM64 桌面应用的官方安装包：**Claude Desktop** 和 **ChatGPT / Codex App**。每个 GitHub Release 都包含 Anthropic 与 OpenAI 发布的原始安装文件，以及校验文件和机器可读清单元数据，方便离线安装、固定版本和重复下载。

## 下载 v0.1.13

| 应用 | 版本 | 安装包格式 | 大小 | Release 下载 |
| --- | --- | --- | --- | --- |
| Claude Desktop | 5.1231.2 | Debian ARM64（`.deb`） | 167 MiB | [claude-desktop_5.1231.2_arm64.deb](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.13/claude-desktop_5.1231.2_arm64.deb) |
| ChatGPT / Codex App | 26.1106.51428-1 | Arch Linux AArch64（`.pkg.tar.zst`） | 550 MiB | [chatgpt-bin-26.1106.51428-1-aarch64.pkg.tar.zst](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.13/chatgpt-bin-26.1106.51428-1-aarch64.pkg.tar.zst) |

Release 中的其他文件：

- [SHA256SUMS](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.13/SHA256SUMS)：两个安装包的 SHA-256。
- [desktop-arm64.json](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.13/desktop-arm64.json)：版本、字节数、厂商原始地址、签名索引地址、签名密钥指纹和验证方式。

`desktop-arm64.json` 里保留了厂商原始下载地址。GitHub Release 的副本用于在厂商链接变化或固定版本从实时索引移除后，仍能下载并核对已知可用的 ARM64 版本。

校验日期：2026-11-11。

## 校验下载

把安装包和 `SHA256SUMS` 放在同一目录，保留上表中的文件名，然后运行：

```sh
# Linux
sha256sum --ignore-missing --check SHA256SUMS

# macOS
shasum --ignore-missing -a 256 --check SHA256SUMS
```

安装包显示 `OK` 后再安装。只下载其中一个包时，也可以只保留 `SHA256SUMS` 中对应的那一行。

Release 里的校验值由已经通过厂商签名和签名索引验证的安装包字节生成：

- **Claude Desktop**：`.deb` 记录在 Anthropic 进行 OpenPGP 签名的 APT `InRelease` 中。发布脚本固定校验 Anthropic 签名密钥指纹 `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`，验证 `InRelease` 中 ARM64 `Packages.gz` 的摘要，再核对安装包大小和 SHA-256。[Anthropic Linux 安装说明](https://support.claude.com/en/articles/10065433-install-claude-desktop)
- **ChatGPT / Codex App**：安装包记录在 OpenAI 进行 OpenPGP 签名的 Arch 仓库索引中，OpenAI 还提供安装包的独立签名。发布脚本固定校验 OpenAI 签名密钥指纹 `3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4`，验证仓库索引签名、安装包签名，再核对签名索引中的大小和 SHA-256。[OpenAI Linux 安装说明](https://learn.chatgpt.com/docs/linux/linux-app)

## 在 Linux 安装

下载与发行版和架构匹配的安装包，用 `SHA256SUMS` 校验后，通过系统包管理工具或厂商说明中的方式安装。

- **Claude Desktop**：Debian 安装包面向 Anthropic 列出的 Ubuntu / Debian 系统。使用发行版的软件包工具安装 `.deb`，并处理厂商安装包要求的依赖。
- **ChatGPT / Codex App**：Arch Linux 安装包面向 Arch Linux AArch64。使用发行版的软件包工具安装 `.pkg.tar.zst`，并处理厂商安装包要求的依赖。

本仓库只镜像 Linux ARM64（`aarch64`）安装包。其他发行版或架构请使用厂商文档和官方下载渠道。

## 分发范围

第三方安装包、更新和支持由 Anthropic 与 OpenAI 提供，软件使用遵循各厂商条款：[Anthropic 条款](https://www.anthropic.com/legal/consumer-terms) · [OpenAI 条款](https://openai.com/policies/row-terms-of-use/)。

## 维护者发布

运行下面的命令即可从官网下载当前安装包、刷新自动生成的文件、打 tag 并上传 GitHub Release：

```sh
bash scripts/build-release.sh
```

不传 `--release` 时，脚本会把最新 Release 的补丁版本加一。要刷新已有 Release 的文件，使用 `--replace-existing --release vX.Y.Z`。加上 `--if-changed` 后，如果官网版本与当前清单一致，脚本会直接结束，不再发布新 Release。脚本依赖 `curl`、`gpg`、`python3`、`git` 和已登录的 `gh`；仓库内的 GitHub Actions 工作流会在 Ubuntu runner 上执行同一脚本。

GitHub Actions 工作流还会每天新加坡时间 09:17 自动运行。定时任务会验证厂商签名索引，只在安装包版本变化时发布下一个补丁版本；版本未变化时不会创建重复 Release。
