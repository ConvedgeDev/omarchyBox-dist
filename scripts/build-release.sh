#!/usr/bin/env bash
# Download the official ARM64 desktop packages, verify them, refresh the release
# index and README, then tag and publish the GitHub Release.
set -euo pipefail
export LC_ALL=C

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

CLAUDE_BASE=https://downloads.claude.ai/claude-desktop
CLAUDE_APT=$CLAUDE_BASE/apt/stable
CLAUDE_INDEX=main/binary-arm64/Packages.gz
CLAUDE_KEY_URL=$CLAUDE_BASE/key.asc
CLAUDE_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

OPENAI_BASE=https://persistent.oaistatic.com/codex-app-prod/linux
OPENAI_FPR=3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4

RELEASE=
REPO=
REPLACE=0
PUBLISH=1
KEEP=0
STAGE=

usage() {
    cat <<'USAGE'
Usage: bash scripts/build-release.sh [options]

Download the official Claude Desktop and ChatGPT / Codex Desktop ARM64 packages,
verify the vendors' signed indexes and package signatures, refresh
desktop-arm64.json, SHA256SUMS and README.md, then commit, tag and publish the
GitHub Release assets.

Options:
  --release TAG       Release tag, for example v0.1.13. Defaults to the next
                      patch after the latest GitHub Release.
  --replace-existing  Allow refreshing an existing tag/release. The existing git
                      tag is not moved; only release files and notes are updated.
  --repo OWNER/REPO   GitHub repository. Defaults to the current checkout.
  --no-publish        Only refresh files in the worktree; do not commit, tag or
                      upload.
  --keep-downloads    Keep the verified staging directory for inspection.
  -h, --help          Show this help.

Requirements: Bash, curl, gpg, python3, git, gh (authenticated for publishing),
and sha256sum or shasum.
USAGE
}

die() { printf 'build-release: %s\n' "$*" >&2; exit 1; }
note() { printf 'build-release: %s\n' "$*" >&2; }

while (($#)); do
    case "$1" in
        --release)
            (($# >= 2)) || die '--release requires a tag.'
            RELEASE=$2
            shift 2
            ;;
        --repo)
            (($# >= 2)) || die '--repo requires OWNER/REPO.'
            REPO=$2
            shift 2
            ;;
        --replace-existing)
            REPLACE=1
            shift
            ;;
        --no-publish)
            PUBLISH=0
            shift
            ;;
        --keep-downloads)
            KEEP=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1 (use --help)."
            ;;
    esac
done

need() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}
for tool in curl gpg python3 git; do need "$tool"; done
if [[ $PUBLISH -eq 1 ]]; then need gh; fi
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    die 'Required command not found: sha256sum or shasum'
fi

[[ -f scripts/release_files.py && -f README.md.in ]] || die 'Run this script from the project checkout.'
[[ -z $(git status --porcelain) ]] || die 'The git worktree must be clean before building a release.'

if [[ -z $REPO ]]; then
    REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) ||
        die 'Could not determine the repository; pass --repo OWNER/REPO.'
fi
[[ $REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "Invalid repository: $REPO"
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null) || die 'The checkout must be on a branch.'

if [[ -z $RELEASE ]]; then
    latest=$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName // ""' 2>/dev/null || true)
    RELEASE=$(python3 scripts/release_files.py bump --latest "$latest")
    note "No --release given; using next patch $RELEASE."
fi
[[ $RELEASE =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Release tag must look like vX.Y.Z: $RELEASE"

if git rev-parse -q --verify "refs/tags/$RELEASE" >/dev/null; then
    [[ $REPLACE -eq 1 ]] || die "Tag $RELEASE already exists; use --replace-existing to refresh it."
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/desktop-release.XXXXXX")
cleanup() {
    if [[ $KEEP -eq 0 ]]; then rm -rf -- "$STAGE"; else note "Kept downloads in $STAGE"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}
file_size() { wc -c < "$1" | tr -d '[:space:]'; }

fetch() {
    curl --disable --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --fail --silent --show-error --location --retry 3 --retry-delay 2 \
        --connect-timeout 20 --max-time 1800 -o "$2" "$1"
}

gpg_fingerprint() {
    local home=$2
    [[ -d $home ]] || die "GnuPG home does not exist: $home"
    gpg --no-options --homedir "$home" --batch --no-autostart --with-colons --show-keys "$1" |
        awk -F: '$1 == "pub" { primary=1; next }
                 $1 == "sub" { primary=0; next }
                 $1 == "fpr" && primary { print $10; primary=0 }'
}

gpg_verify_detached() {
    local home=$1 signature=$2 signed_file=$3 status
    status=$(gpg --no-options --homedir "$home" --batch --no-autostart \
        --no-auto-key-retrieve --no-auto-key-import --trust-model always \
        --status-fd 1 --verify "$signature" "$signed_file") || return 1
    grep -q '^\[GNUPG:\] VALIDSIG ' <<<"$status" &&
        ! grep -Eq '^\[GNUPG:\] (BADSIG|ERRSIG|REVKEYSIG|EXPSIG|EXPKEYSIG|KEYEXPIRED|SIGEXPIRED)( |$)' <<<"$status"
}

# ---------------------------------------------------------------------------
# Claude Desktop: verify Anthropic's signed APT Release, then select the latest
# ARM64 package from the verified Packages.gz index.
# ---------------------------------------------------------------------------
mkdir -p "$STAGE/claude"
claude_stage=$STAGE/claude
note 'Fetching Anthropic signing key and APT metadata...'
fetch "$CLAUDE_KEY_URL" "$claude_stage/key.asc"
claude_gpg=$(mktemp -d "${TMPDIR:-/tmp}/desktop-gpg.XXXXXX")
trap 'rm -rf -- "$claude_gpg"; cleanup' EXIT
chmod 700 "$claude_gpg"
claude_key_fpr=$(gpg_fingerprint "$claude_stage/key.asc" "$claude_gpg")
[[ $claude_key_fpr == "$CLAUDE_FPR" ]] || die 'Anthropic signing-key fingerprint mismatch.'
gpg --no-options --homedir "$claude_gpg" --batch --no-autostart --import "$claude_stage/key.asc" >/dev/null 2>&1 ||
    die 'Could not import the Anthropic signing key.'
fetch "$CLAUDE_APT/dists/stable/InRelease" "$claude_stage/InRelease"
claude_status=$(gpg --no-options --homedir "$claude_gpg" --batch --no-autostart \
    --no-auto-key-retrieve --no-auto-key-import --trust-model always \
    --status-fd 1 --output "$claude_stage/Release" --decrypt "$claude_stage/InRelease") ||
    die 'Anthropic InRelease signature verification failed.'
grep -q '^\[GNUPG:\] VALIDSIG ' <<<"$claude_status" || die 'Anthropic InRelease has no valid signature.'
if grep -Eq '^\[GNUPG:\] (BADSIG|ERRSIG|REVKEYSIG|EXPSIG|EXPKEYSIG|KEYEXPIRED|SIGEXPIRED)( |$)' <<<"$claude_status"; then
    die 'Anthropic InRelease signature is expired or invalid.'
fi
fetch "$CLAUDE_APT/dists/stable/$CLAUDE_INDEX" "$claude_stage/Packages.gz"
python3 scripts/release_files.py claude-select \
    "$claude_stage" "$CLAUDE_INDEX" "$CLAUDE_APT" "$CLAUDE_KEY_URL" "$CLAUDE_FPR" \
    > "$STAGE/claude.json"
claude_file=$(python3 scripts/release_files.py field "$STAGE/claude.json" filename)
claude_url=$(python3 scripts/release_files.py field "$STAGE/claude.json" url)
claude_size=$(python3 scripts/release_files.py field "$STAGE/claude.json" size_bytes)
claude_sha=$(python3 scripts/release_files.py field "$STAGE/claude.json" sha256)
[[ $claude_file != */* && $claude_file != .* ]] || die 'Unexpected Claude package filename.'
note "Downloading $claude_file..."
fetch "$claude_url" "$STAGE/$claude_file"
[[ $(file_size "$STAGE/$claude_file") == "$claude_size" ]] || die 'Claude package size mismatch.'
[[ $(sha256_file "$STAGE/$claude_file") == "$claude_sha" ]] || die 'Claude package SHA-256 mismatch.'
note "Claude Desktop $(python3 scripts/release_files.py field "$STAGE/claude.json" version) verified."

# ---------------------------------------------------------------------------
# ChatGPT / Codex: read the versions array from OpenAI's official installer,
# verify the signed Arch index and the detached package signature.
# ---------------------------------------------------------------------------
mkdir -p "$STAGE/chatgpt"
chatgpt_stage=$STAGE/chatgpt
note 'Fetching OpenAI installer release list...'
fetch "$OPENAI_BASE/install-arch.sh" "$chatgpt_stage/install-arch.sh"
release_line=$(grep -Ex 'versions=\([0-9]+(\.[0-9]+)+( +[0-9]+(\.[0-9]+)+)*\)' "$chatgpt_stage/install-arch.sh") ||
    die 'The OpenAI release list format changed.'
[[ $release_line != *$'\n'* ]] || die 'Found more than one OpenAI release list.'
release_line=${release_line#versions=\(}
read -r -a openai_versions <<< "${release_line%\)}"

chatgpt_selected=0
for version in "${openai_versions[@]}"; do
    candidate=$chatgpt_stage/$version
    mkdir -p "$candidate"
    version_url=$OPENAI_BASE/arch/$version
    arch_url=$version_url/aarch64
    note "Checking OpenAI release $version..."
    if ! fetch "$version_url/repository-signing-key.gpg" "$candidate/key.gpg" ||
       ! fetch "$arch_url/openai-chatgpt.db" "$candidate/openai-chatgpt.db" ||
       ! fetch "$arch_url/openai-chatgpt.db.sig" "$candidate/openai-chatgpt.db.sig"; then
        note "OpenAI release $version metadata is unavailable; trying the next one."
        continue
    fi
    openai_gpg=$candidate/.gnupg
    mkdir -m 700 "$openai_gpg"
    key_fpr=$(gpg_fingerprint "$candidate/key.gpg" "$openai_gpg")
    if [[ $key_fpr != "$OPENAI_FPR" ]]; then
        die "OpenAI signing-key fingerprint mismatch for $version."
    fi
    gpg --no-options --homedir "$openai_gpg" --batch --no-autostart --import "$candidate/key.gpg" >/dev/null 2>&1 ||
        die 'Could not import the OpenAI signing key.'
    gpg_verify_detached "$openai_gpg" "$candidate/openai-chatgpt.db.sig" "$candidate/openai-chatgpt.db" ||
        die "OpenAI repository index signature failed for $version."

    if ! python3 scripts/release_files.py chatgpt-select \
        "$candidate" "$candidate/openai-chatgpt.db" "$version" "$version_url" "$OPENAI_FPR" \
        > "$candidate/meta.json"; then
        note "OpenAI release $version does not contain the expected package; trying the next one."
        continue
    fi
    file=$(python3 scripts/release_files.py field "$candidate/meta.json" filename)
    package_url=$(python3 scripts/release_files.py field "$candidate/meta.json" url)
    package_size=$(python3 scripts/release_files.py field "$candidate/meta.json" size_bytes)
    package_sha=$(python3 scripts/release_files.py field "$candidate/meta.json" sha256)
    if ! fetch "$arch_url/$file.sig" "$candidate/$file.sig" ||
       ! fetch "$package_url" "$candidate/$file"; then
        note "OpenAI release $version package is unavailable; trying the next one."
        continue
    fi
    [[ $(file_size "$candidate/$file") == "$package_size" ]] || die 'ChatGPT package size mismatch.'
    [[ $(sha256_file "$candidate/$file") == "$package_sha" ]] || die 'ChatGPT package SHA-256 mismatch.'
    gpg_verify_detached "$openai_gpg" "$candidate/$file.sig" "$candidate/$file" ||
        die 'OpenAI package signature verification failed.'
    cp -- "$candidate/$file" "$STAGE/$file"
    cp -- "$candidate/meta.json" "$STAGE/chatgpt.json"
    chatgpt_file=$file
    chatgpt_selected=1
    note "ChatGPT / Codex $(python3 scripts/release_files.py field "$STAGE/chatgpt.json" version) verified."
    break
done
[[ $chatgpt_selected -eq 1 ]] || die 'No published OpenAI ARM64 release could be verified.'

# ---------------------------------------------------------------------------
# Render and validate the repository files, then optionally commit and publish.
# ---------------------------------------------------------------------------
verified_on=$(date -u +%F)
python3 scripts/release_files.py write \
    --root "$ROOT" --repo "$REPO" --release "$RELEASE" --verified-on "$verified_on" \
    --claude-json "$STAGE/claude.json" --chatgpt-json "$STAGE/chatgpt.json"
python3 scripts/release_files.py notes \
    --repo "$REPO" --release "$RELEASE" \
    --claude-json "$STAGE/claude.json" --chatgpt-json "$STAGE/chatgpt.json" \
    > "$STAGE/release-notes.md"

python3 - "$ROOT/desktop-arm64.json" "$ROOT/SHA256SUMS" "$STAGE/claude.json" "$STAGE/chatgpt.json" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text())
expected = [json.loads(Path(path).read_text()) for path in sys.argv[3:]]
for package, source in zip(manifest["packages"], expected, strict=True):
    if (package["filename"], package["version"], package["sha256"], package["size_bytes"]) != (
        source["filename"], source["version"], source["sha256"], source["size_bytes"]
    ):
        raise SystemExit("Generated manifest does not match verified metadata.")
lines = Path(sys.argv[2]).read_text().splitlines()
if len(lines) != 2:
    raise SystemExit("SHA256SUMS must contain exactly two entries.")
for line, package in zip(lines, expected, strict=True):
    if line != f"{package['sha256']}  {package['filename']}":
        raise SystemExit("SHA256SUMS does not match verified metadata.")
PY

note "Release files rendered for $RELEASE."
if [[ $PUBLISH -eq 0 ]]; then
    note '--no-publish: files were updated, but nothing was committed or uploaded.'
    [[ $KEEP -eq 1 ]] || true
    exit 0
fi

git add -- README.md README.md.in desktop-arm64.json SHA256SUMS scripts/build-release.sh scripts/release_files.py
if ! git diff --cached --quiet; then
    git commit -m "Release $RELEASE Linux ARM64 desktop installers"
fi

if git rev-parse -q --verify "refs/tags/$RELEASE" >/dev/null; then
    note "Tag $RELEASE already exists; keeping its commit unchanged."
else
    git tag -a "$RELEASE" -m "Linux ARM64 desktop apps $RELEASE"
fi
git push origin "$BRANCH"
git push origin "refs/tags/$RELEASE"

assets=("$STAGE/$claude_file" "$STAGE/$chatgpt_file" "$ROOT/SHA256SUMS" "$ROOT/desktop-arm64.json")
for asset in "${assets[@]}"; do [[ -f $asset ]] || die "Missing release asset: $asset"; done
if gh release view "$RELEASE" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$RELEASE" "${assets[@]}" --repo "$REPO" --clobber
    gh release edit "$RELEASE" --repo "$REPO" \
        --title "Linux ARM64 desktop apps $RELEASE" \
        --notes-file "$STAGE/release-notes.md"
else
    gh release create "$RELEASE" "${assets[@]}" --repo "$REPO" \
        --title "Linux ARM64 desktop apps $RELEASE" \
        --notes-file "$STAGE/release-notes.md"
fi

gh release view "$RELEASE" --repo "$REPO" --json assets > "$STAGE/remote-assets.json"
python3 - "$STAGE/remote-assets.json" "${assets[@]}" <<'PY'
import json
from pathlib import Path
import sys

remote = {item["name"]: item["size"] for item in json.loads(Path(sys.argv[1]).read_text())["assets"]}
for path in sys.argv[2:]:
    file = Path(path)
    if remote.get(file.name) != file.stat().st_size:
        raise SystemExit(f"Release asset is missing or has the wrong size: {file.name}")
PY
note "Published $RELEASE with both installers, SHA256SUMS and desktop-arm64.json."
