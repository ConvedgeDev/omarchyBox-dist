#!/usr/bin/env python3
"""Parse signed vendor indexes and render release metadata."""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
from email.utils import parsedate_to_datetime
from pathlib import Path
import re
import sys
import tarfile

CLAUDE_NAME = "Claude Desktop"
CHATGPT_NAME = "ChatGPT / Codex App"


def fail(message: str) -> "NoReturn":
    raise SystemExit(message)


def fields(paragraph: str) -> dict[str, str]:
    return dict(
        line.split(": ", 1)
        for line in paragraph.splitlines()
        if ": " in line and not line[0].isspace()
    )


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"Could not read {path}: {exc}")


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def claude_select(stage: Path, index: str, base_url: str, key_url: str, key_fpr: str) -> dict:
    release_path = stage / "Release"
    packages_path = stage / "Packages.gz"
    try:
        release = release_path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"Could not read Anthropic Release file: {exc}")

    release_fields = fields(release)
    if release_fields.get("Suite") != "stable":
        fail("Claude Desktop: signed Release is not for the stable repository.")
    if "arm64" not in release_fields.get("Architectures", "").split():
        fail("Claude Desktop: signed Release does not list arm64.")

    valid_until = release_fields.get("Valid-Until")
    try:
        expiry = parsedate_to_datetime(valid_until)
        if expiry.tzinfo is None or expiry <= dt.datetime.now(dt.timezone.utc):
            raise ValueError
    except (KeyError, TypeError, ValueError, OverflowError):
        fail("Claude Desktop: signed Release has a missing, invalid, or expired Valid-Until.")

    section = re.search(r"(?m)^SHA256:\n((?:[ \t].*\n?)+)", release)
    rows = [line.split() for line in section[1].splitlines()] if section else []
    matches = [row for row in rows if len(row) == 3 and row[2] == index]
    try:
        compressed = packages_path.read_bytes()
    except OSError as exc:
        fail(f"Could not read Anthropic package index: {exc}")
    expected = [hashlib.sha256(compressed).hexdigest(), str(len(compressed))]
    if len(matches) != 1 or matches[0][:2] != expected:
        fail("Claude Desktop: ARM64 Packages.gz failed the signed hash or size check.")

    versions: dict[str, dict[str, str]] = {}
    for paragraph in gzip.decompress(compressed).decode("utf-8").split("\n\n"):
        info = fields(paragraph)
        version = info.get("Version", "")
        if info.get("Package") != "claude-desktop" or info.get("Architecture") != "arm64":
            continue
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", version):
            continue
        expected_path = f"pool/main/c/claude-desktop/claude-desktop_{version}_arm64.deb"
        if (
            version in versions
            or info.get("Filename") != expected_path
            or not re.fullmatch(r"[0-9a-f]{64}", info.get("SHA256", ""))
            or not re.fullmatch(r"[1-9][0-9]*", info.get("Size", ""))
        ):
            fail(f"Claude Desktop: invalid signed package record for {version}.")
        versions[version] = info
    if not versions:
        fail("Claude Desktop: no supported ARM64 releases in the signed index.")

    version = max(versions, key=lambda value: tuple(map(int, value.split("."))))
    info = versions[version]
    package_path = info["Filename"]
    filename = Path(package_path).name
    return {
        "name": CLAUDE_NAME,
        "version": version,
        "filename": filename,
        "url": f"{base_url}/{package_path}",
        "size_bytes": int(info["Size"]),
        "sha256": info["SHA256"],
        "verification": {
            "method": "OpenPGP signed InRelease, SHA-256 of ARM64 Packages.gz, SHA-256 of DEB",
            "metadata": {
                "signing_key": key_url,
                "signed_release": f"{base_url}/dists/stable/InRelease",
                "package_index": f"{base_url}/dists/stable/{index}",
            },
            "release_valid_until_utc": valid_until,
            "signing_key_fingerprint": key_fpr,
        },
    }


def parse_arch_desc(text: str) -> dict[str, str]:
    result: dict[str, list[str]] = {}
    current: str | None = None
    for line in text.splitlines():
        if len(line) > 2 and line.startswith("%") and line.endswith("%"):
            current = line[1:-1]
            result[current] = []
        elif current is not None:
            result[current].append(line)
    return {key: "\n".join(value).strip() for key, value in result.items()}


def chatgpt_select(stage: Path, db_path: Path, version: str, base_url: str, key_fpr: str) -> dict:
    package = f"chatgpt-bin-{version}-1-aarch64.pkg.tar.zst"
    member = f"chatgpt-bin-{version}-1/desc"
    try:
        with tarfile.open(db_path, "r:*") as archive:
            extracted = archive.extractfile(member)
            if extracted is None:
                fail("OpenAI repository index did not contain the expected desc entry.")
            desc = parse_arch_desc(extracted.read().decode("utf-8"))
    except (OSError, tarfile.TarError, KeyError) as exc:
        fail(f"Could not inspect the OpenAI repository index: {exc}")

    required = {
        "NAME": "chatgpt-bin",
        "VERSION": f"{version}-1",
        "ARCH": "aarch64",
        "FILENAME": package,
    }
    for key, expected in required.items():
        if desc.get(key) != expected:
            fail(f"OpenAI signed metadata has an unexpected {key.lower()}.")
    if not re.fullmatch(r"[1-9][0-9]*", desc.get("CSIZE", "")):
        fail("OpenAI signed metadata has an invalid package size.")
    if not re.fullmatch(r"[0-9a-f]{64}", desc.get("SHA256SUM", "")):
        fail("OpenAI signed metadata has an invalid package SHA-256.")

    version_url = base_url
    arch_url = f"{version_url}/aarch64"
    return {
        "name": CHATGPT_NAME,
        "version": f"{version}-1",
        "filename": package,
        "url": f"{arch_url}/{package}",
        "size_bytes": int(desc["CSIZE"]),
        "sha256": desc["SHA256SUM"],
        "verification": {
            "method": "OpenPGP signed Arch package index and detached package signature",
            "metadata": {
                "signing_key": f"{version_url}/repository-signing-key.gpg",
                "package_index": f"{arch_url}/openai-chatgpt.db",
                "package_index_signature": f"{arch_url}/openai-chatgpt.db.sig",
                "package_signature": f"{arch_url}/{package}.sig",
            },
            "signing_key_fingerprint": key_fpr,
        },
    }


def human_size(size: int) -> str:
    mib = size / (1024 * 1024)
    return f"{mib:.0f} MiB"


def write_release(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    claude = read_json(Path(args.claude_json))
    chatgpt = read_json(Path(args.chatgpt_json))
    packages = []
    for item in (claude, chatgpt):
        package = dict(item)
        package["release_url"] = (
            f"https://github.com/{args.repo}/releases/download/{args.release}/{item['filename']}"
        )
        packages.append(package)

    manifest = {
        "schema_version": 1,
        "release": args.release,
        "architecture": "Linux ARM64",
        "verified_on": args.verified_on,
        "repository": f"https://github.com/{args.repo}",
        "packages": packages,
    }
    write_json(root / "desktop-arm64.json", manifest)
    (root / "SHA256SUMS").write_text(
        "".join(f"{item['sha256']}  {item['filename']}\n" for item in packages),
        encoding="utf-8",
    )

    template_path = root / "README.md.in"
    try:
        template = template_path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"Could not read {template_path}: {exc}")
    substitutions = {
        "@@RELEASE@@": args.release,
        "@@REPO@@": args.repo,
        "@@VERIFIED_ON@@": args.verified_on,
        "@@CLAUDE_VERSION@@": claude["version"],
        "@@CLAUDE_FILE@@": claude["filename"],
        "@@CLAUDE_SIZE@@": human_size(int(claude["size_bytes"])),
        "@@CHATGPT_VERSION@@": chatgpt["version"],
        "@@CHATGPT_FILE@@": chatgpt["filename"],
        "@@CHATGPT_SIZE@@": human_size(int(chatgpt["size_bytes"])),
    }
    for token, value in substitutions.items():
        template = template.replace(token, value)
    if "@@" in template:
        fail("README.md.in contains an unknown placeholder.")
    (root / "README.md").write_text(template, encoding="utf-8")


def release_notes(args: argparse.Namespace) -> None:
    claude = read_json(Path(args.claude_json))
    chatgpt = read_json(Path(args.chatgpt_json))
    base = f"https://github.com/{args.repo}/releases/download/{args.release}"
    print(
        f"Linux ARM64 desktop installer mirrors for {args.release}.\n\n"
        "The files below are the official Anthropic and OpenAI packages, verified against "
        "the vendors' signed indexes before upload.\n\n"
        "### Download\n\n"
        f"- [Claude Desktop {claude['version']}]({base}/{claude['filename']}) "
        f"(Debian ARM64, {human_size(int(claude['size_bytes']))})\n"
        f"- [ChatGPT / Codex App {chatgpt['version']}]({base}/{chatgpt['filename']}) "
        f"(Arch Linux AArch64, {human_size(int(chatgpt['size_bytes']))})\n"
        f"- [SHA256SUMS]({base}/SHA256SUMS)\n"
        f"- [desktop-arm64.json]({base}/desktop-arm64.json)\n\n"
        "### Verify\n\n"
        "```sh\n"
        "sha256sum --ignore-missing --check SHA256SUMS\n"
        "```\n\n"
        "### 中文说明\n\n"
        f"本版本包含两个 Linux ARM64 桌面应用的官方安装包："
        f"Claude Desktop {claude['version']} 与 ChatGPT / Codex App {chatgpt['version']}。"
        "发布前已核对厂商签名索引、安装包大小和 SHA-256。\n\n"
        "将安装包与 `SHA256SUMS` 放在同一目录，运行：\n\n"
        "```sh\n"
        "sha256sum --ignore-missing --check SHA256SUMS\n"
        "```\n\n"
        f"完整说明：[README](https://github.com/{args.repo}#readme)。"
    )


def meta_field(args: argparse.Namespace) -> None:
    info = read_json(Path(args.path))
    value = info
    for part in args.field.split("."):
        if not isinstance(value, dict) or part not in value:
            fail(f"No {args.field} field in {args.path}.")
        value = value[part]
    if isinstance(value, (dict, list)):
        print(json.dumps(value, ensure_ascii=False))
    else:
        print(value)


def unchanged(args: argparse.Namespace) -> None:
    try:
        manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
        expected = [json.loads(Path(path).read_text(encoding="utf-8")) for path in (
            args.claude_json, args.chatgpt_json
        )]
        packages = manifest["packages"]
        if len(packages) != 2 or len(expected) != 2:
            raise ValueError
        for package, source in zip(packages, expected, strict=True):
            if (
                package["version"],
                package["filename"],
                package["sha256"],
                package["size_bytes"],
            ) != (
                source["version"],
                source["filename"],
                source["sha256"],
                source["size_bytes"],
            ):
                raise ValueError
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
        raise SystemExit(1)


def bump(args: argparse.Namespace) -> None:
    match = re.fullmatch(r"v([0-9]+)\.([0-9]+)\.([0-9]+)", args.latest or "")
    if not match:
        print("v0.1.0")
        return
    major, minor, patch = map(int, match.groups())
    print(f"v{major}.{minor}.{patch + 1}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    sub = result.add_subparsers(dest="command", required=True)

    item = sub.add_parser("claude-select")
    item.add_argument("stage")
    item.add_argument("index")
    item.add_argument("base_url")
    item.add_argument("key_url")
    item.add_argument("key_fpr")
    item.set_defaults(func=lambda a: print(json.dumps(claude_select(
        Path(a.stage), a.index, a.base_url, a.key_url, a.key_fpr
    ), indent=2, ensure_ascii=False) + "\n", end=""))

    item = sub.add_parser("chatgpt-select")
    item.add_argument("stage")
    item.add_argument("db")
    item.add_argument("version")
    item.add_argument("base_url")
    item.add_argument("key_fpr")
    item.set_defaults(func=lambda a: print(json.dumps(chatgpt_select(
        Path(a.stage), Path(a.db), a.version, a.base_url, a.key_fpr
    ), indent=2, ensure_ascii=False) + "\n", end=""))

    item = sub.add_parser("write")
    item.add_argument("--root", required=True)
    item.add_argument("--repo", required=True)
    item.add_argument("--release", required=True)
    item.add_argument("--verified-on", required=True)
    item.add_argument("--claude-json", required=True)
    item.add_argument("--chatgpt-json", required=True)
    item.set_defaults(func=write_release)

    item = sub.add_parser("notes")
    item.add_argument("--repo", required=True)
    item.add_argument("--release", required=True)
    item.add_argument("--claude-json", required=True)
    item.add_argument("--chatgpt-json", required=True)
    item.set_defaults(func=release_notes)

    item = sub.add_parser("field")
    item.add_argument("path")
    item.add_argument("field")
    item.set_defaults(func=meta_field)

    item = sub.add_parser("unchanged")
    item.add_argument("--manifest", required=True)
    item.add_argument("--claude-json", required=True)
    item.add_argument("--chatgpt-json", required=True)
    item.set_defaults(func=unchanged)

    item = sub.add_parser("bump")
    item.add_argument("--latest", default="")
    item.set_defaults(func=bump)
    return result


def main() -> None:
    args = parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
