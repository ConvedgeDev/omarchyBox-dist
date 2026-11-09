# omarchyBox-dist

<img src="assets/omarchybox.png" alt="omarchyBox App 图标" width="112" height="112">

这里记录 omarchyBox 配套桌面应用的 Linux ARM64 安装包版本、厂商下载地址和校验值。安装包由 Anthropic 和 OpenAI 的服务器提供。

## v0.1.12 配套下载

| 应用 | 固定版本 | 格式 | 厂商下载 |
| --- | --- | --- | --- |
| Claude Desktop | 4.23118.0 | Debian ARM64 | [claude-desktop_4.23118.0_arm64.deb](https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_4.23118.0_arm64.deb) |
| ChatGPT / Codex App | 26.1103.60933-1 | Arch Linux AArch64 | [chatgpt-bin-26.1103.60933-1-aarch64.pkg.tar.zst](https://persistent.oaistatic.com/codex-app-prod/linux/arch/26.1103.60933/aarch64/chatgpt-bin-26.1103.60933-1-aarch64.pkg.tar.zst) |

[Release v0.1.12](https://github.com/ConvedgeDev/omarchyBox-dist/releases/tag/v0.1.12) 提供 [SHA256SUMS](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.12/SHA256SUMS) 和 [desktop-arm64.json](https://github.com/ConvedgeDev/omarchyBox-dist/releases/download/v0.1.12/desktop-arm64.json)。JSON 还记录文件字节数、厂商签名密钥指纹、签名和索引地址。

## 校验下载

把下载的安装包和 `SHA256SUMS` 放在同一目录，保留表中的文件名。在该目录运行以下命令，看到相应文件显示 `OK` 再安装。只下载其中一个安装包也可以校验。

```sh
# Linux
sha256sum --ignore-missing --check SHA256SUMS

# macOS
shasum --ignore-missing -a 256 --check SHA256SUMS
```

- **Claude Desktop** 的 SHA-256 来自 Anthropic 签署的 APT `InRelease`，其中包含 ARM64 `Packages.gz` 的摘要。发布时已验证签名、索引和完整安装包。使用 APT 安装时，按厂商说明核对密钥指纹 `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`，由 APT 验证当前有效的仓库索引。 [Anthropic 安装与密钥说明](https://support.claude.com/en/articles/10065433-install-claude-desktop)
- **ChatGPT / Codex App** 的 SHA-256 来自 OpenAI 签署的 Arch 仓库索引。发布时还验证了完整安装包的独立签名。复核时，在临时 GPG 密钥环中导入厂商公钥前核对指纹 `3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4`，再用 `gpg --verify <签名文件> <安装包>` 验证。 [OpenAI 公钥](https://persistent.oaistatic.com/codex-app-prod/linux/arch/26.1103.60933/repository-signing-key.gpg) · [安装包签名](https://persistent.oaistatic.com/codex-app-prod/linux/arch/26.1103.60933/aarch64/chatgpt-bin-26.1103.60933-1-aarch64.pkg.tar.zst.sig) · [OpenAI Linux 安装说明](https://learn.chatgpt.com/docs/linux/linux-app)

## 在 omarchyBox 安装

在启动器的 **Agent Install** 选择桌面应用。VM 会在验证隔离出口后，从厂商服务器下载并校验安装包，在桌面终端显示安装进度。应用的自动安装使用厂商的实时版本索引，本仓库的 Release 供手动下载和核对指定版本。

如需在其他 Linux 发行版上安装，请按上面的厂商文档选择对应格式和依赖。Claude 的 Debian 包适用于厂商列出的 Ubuntu / Debian 系统，ChatGPT 的 Arch 包面向 Arch Linux。

## 分发范围

本仓库发布下载清单和校验值。第三方安装包、更新及支持由原厂商提供，软件使用遵循各厂商条款。 [Anthropic 条款](https://www.anthropic.com/legal/consumer-terms) · [OpenAI 条款](https://openai.com/policies/row-terms-of-use/)
