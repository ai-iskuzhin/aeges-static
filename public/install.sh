#!/bin/sh
set -eu

TOOL_PACKAGE="${AEGES_TOOL_PACKAGE:-Aeges.Cli}"
TOOL_COMMAND="${AEGES_TOOL_COMMAND:-aeges}"
VERSION="${AEGES_VERSION:-}"
PACKAGE_SOURCE="${AEGES_PACKAGE_SOURCE:-}"
GITHUB_REPOSITORY="${AEGES_GITHUB_REPOSITORY:-ai-iskuzhin/aeges}"
DOWNLOAD_BASE_URL="${AEGES_DOWNLOAD_BASE_URL:-}"

usage() {
    cat <<'EOF'
Aeges installer

Installs or updates the Aeges CLI as a global .NET tool.

Usage:
  curl -fsSL https://get.aeges.top/install.sh | sh
  wget -qO- https://get.aeges.top/install.sh | sh

Options via environment variables:
  AEGES_VERSION=0.1.0-alpha.5
  AEGES_PACKAGE_SOURCE=/path/to/packages
  AEGES_DOWNLOAD_BASE_URL=https://github.com/ai-iskuzhin/aeges/releases/latest/download
  AEGES_GITHUB_REPOSITORY=ai-iskuzhin/aeges
  AEGES_TOOL_PACKAGE=Aeges.Cli
  AEGES_TOOL_COMMAND=aeges

Local checkout example:
  dotnet pack src/Aeges.Cli/Aeges.Cli.csproj -c Release
  AEGES_PACKAGE_SOURCE="$PWD/.artifacts/packages" AEGES_VERSION=0.1.0-alpha.5 sh scripts/install.sh

Release example:
  curl -fsSL https://get.aeges.top/install.sh | sh
  curl -fsSL https://get.aeges.top/install.sh | AEGES_VERSION=0.1.0-alpha.5 sh
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if ! command -v dotnet >/dev/null 2>&1; then
    echo "dotnet was not found on PATH." >&2
    echo "Install the .NET 10 SDK, then run this installer again." >&2
    echo "https://dotnet.microsoft.com/download" >&2
    exit 1
fi

TOOLS_DIR="${HOME}/.dotnet/tools"
DOWNLOAD_DIR="${HOME}/.aeges/tmp/install"
mkdir -p "${HOME}/.aeges" "${DOWNLOAD_DIR}"

fetch() {
    url="$1"
    output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
        return
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output"
        return
    fi

    echo "Neither curl nor wget was found on PATH." >&2
    exit 1
}

resolve_package_source() {
    if [ -n "${PACKAGE_SOURCE}" ]; then
        return
    fi

    if [ -z "${DOWNLOAD_BASE_URL}" ]; then
        if [ -n "${VERSION}" ]; then
            DOWNLOAD_BASE_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/v${VERSION}"
        else
            DOWNLOAD_BASE_URL="https://github.com/${GITHUB_REPOSITORY}/releases/latest/download"
        fi
    fi

    sums_path="${DOWNLOAD_DIR}/SHA256SUMS"

    fetch "${DOWNLOAD_BASE_URL}/SHA256SUMS" "${sums_path}"

    if [ -n "${VERSION}" ]; then
        package_file="${TOOL_PACKAGE}.${VERSION}.nupkg"
    else
        package_file="$(awk '{print $2}' "${sums_path}" | grep "^${TOOL_PACKAGE}\\..*\\.nupkg$" | head -n 1 || true)"
        if [ -z "${package_file}" ]; then
            echo "SHA256SUMS does not contain a ${TOOL_PACKAGE} package." >&2
            exit 1
        fi
        VERSION="${package_file#${TOOL_PACKAGE}.}"
        VERSION="${VERSION%.nupkg}"
    fi

    package_path="${DOWNLOAD_DIR}/${package_file}"

    echo "Downloading ${package_file}..."
    fetch "${DOWNLOAD_BASE_URL}/${package_file}" "${package_path}"

    if command -v sha256sum >/dev/null 2>&1; then
        (cd "${DOWNLOAD_DIR}" && grep "  ${package_file}\$" SHA256SUMS | sha256sum -c -)
    elif command -v shasum >/dev/null 2>&1; then
        (cd "${DOWNLOAD_DIR}" && grep "  ${package_file}\$" SHA256SUMS | shasum -a 256 -c -)
    else
        echo "Checksum file downloaded, but neither sha256sum nor shasum was found." >&2
        exit 1
    fi

    PACKAGE_SOURCE="${DOWNLOAD_DIR}"
}

resolve_package_source

tool_update() {
    if [ -n "${VERSION}" ] && [ -n "${PACKAGE_SOURCE}" ]; then
        dotnet tool update --global "${TOOL_PACKAGE}" --version "${VERSION}" --add-source "${PACKAGE_SOURCE}"
    elif [ -n "${VERSION}" ]; then
        dotnet tool update --global "${TOOL_PACKAGE}" --version "${VERSION}"
    elif [ -n "${PACKAGE_SOURCE}" ]; then
        dotnet tool update --global "${TOOL_PACKAGE}" --add-source "${PACKAGE_SOURCE}"
    else
        dotnet tool update --global "${TOOL_PACKAGE}"
    fi
}

tool_install() {
    if [ -n "${VERSION}" ] && [ -n "${PACKAGE_SOURCE}" ]; then
        dotnet tool install --global "${TOOL_PACKAGE}" --version "${VERSION}" --add-source "${PACKAGE_SOURCE}"
    elif [ -n "${VERSION}" ]; then
        dotnet tool install --global "${TOOL_PACKAGE}" --version "${VERSION}"
    elif [ -n "${PACKAGE_SOURCE}" ]; then
        dotnet tool install --global "${TOOL_PACKAGE}" --add-source "${PACKAGE_SOURCE}"
    else
        dotnet tool install --global "${TOOL_PACKAGE}"
    fi
}

echo "Installing Aeges CLI..."
echo "Package: ${TOOL_PACKAGE}"
if [ -n "${VERSION}" ]; then
    echo "Version: ${VERSION}"
fi
if [ -n "${PACKAGE_SOURCE}" ]; then
    echo "Source: ${PACKAGE_SOURCE}"
fi

# Use update first because it is idempotent when the tool is already installed.
# Fall back to install for first-time setup.
if tool_update; then
    :
else
    tool_install
fi

if command -v "${TOOL_COMMAND}" >/dev/null 2>&1; then
    echo "Aeges installed. Try: ${TOOL_COMMAND} db status"
else
    echo "Aeges installed, but '${TOOL_COMMAND}' is not on PATH yet."
    echo "Add the .NET tools directory to PATH:"
    echo "  export PATH=\"\$PATH:${TOOLS_DIR}\""
fi
