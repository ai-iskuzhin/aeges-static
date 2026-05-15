param(
    [string]$Version = $(if ($env:AEGES_VERSION) { $env:AEGES_VERSION } else { "0.1.0-alpha.8" }),
    [string]$PackageSource = $env:AEGES_PACKAGE_SOURCE,
    [string]$DownloadBaseUrl = $env:AEGES_DOWNLOAD_BASE_URL,
    [string]$GithubRepository = $(if ($env:AEGES_GITHUB_REPOSITORY) { $env:AEGES_GITHUB_REPOSITORY } else { "ai-iskuzhin/aeges" }),
    [string]$ToolPackage = $(if ($env:AEGES_TOOL_PACKAGE) { $env:AEGES_TOOL_PACKAGE } else { "Aeges.Cli" }),
    [string]$ToolCommand = $(if ($env:AEGES_TOOL_COMMAND) { $env:AEGES_TOOL_COMMAND } else { "aeges" }),
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Usage {
    @"
Aeges installer

Installs or updates the Aeges CLI as a global .NET tool.

Usage:
  irm https://get.aeges.top/install.ps1 | iex

Versioned release:
  `$env:AEGES_VERSION = "0.1.0-alpha.8"
  irm https://get.aeges.top/install.ps1 | iex

Local checkout:
  dotnet pack src/Aeges.Cli/Aeges.Cli.csproj -c Release
  .\scripts\install.ps1 -PackageSource .\.artifacts\packages -Version 0.1.0-alpha.8

Parameters and environment variables:
  -Version / AEGES_VERSION
  -PackageSource / AEGES_PACKAGE_SOURCE
  -DownloadBaseUrl / AEGES_DOWNLOAD_BASE_URL
  -GithubRepository / AEGES_GITHUB_REPOSITORY
  -ToolPackage / AEGES_TOOL_PACKAGE
  -ToolCommand / AEGES_TOOL_COMMAND
"@
}

if ($Help) {
    Show-Usage
    exit 0
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Error "dotnet was not found on PATH. Install the .NET 10 SDK, then run this installer again. https://dotnet.microsoft.com/download"
}

$toolsDirectory = Join-Path $HOME ".dotnet\tools"
$aegesDirectory = Join-Path $HOME ".aeges"
$downloadDirectory = Join-Path $aegesDirectory "tmp\install"
New-Item -ItemType Directory -Force -Path $downloadDirectory | Out-Null

function Download-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutputPath
}

function Resolve-PackageSource {
    if (-not [string]::IsNullOrWhiteSpace($PackageSource)) {
        return $PackageSource
    }

    if ([string]::IsNullOrWhiteSpace($DownloadBaseUrl)) {
        if ([string]::IsNullOrWhiteSpace($Version)) {
            $DownloadBaseUrl = "https://github.com/$GithubRepository/releases/latest/download"
        } else {
            $DownloadBaseUrl = "https://github.com/$GithubRepository/releases/download/v$Version"
        }
    }

    $checksumsPath = Join-Path $downloadDirectory "SHA256SUMS"

    Download-File -Url "$DownloadBaseUrl/SHA256SUMS" -OutputPath $checksumsPath

    if ([string]::IsNullOrWhiteSpace($Version)) {
        $packagePattern = [Regex]::Escape($ToolPackage) + "\..+\.nupkg"
        $packageLine = Get-Content $checksumsPath |
            Where-Object { $_ -match "\s+($packagePattern)$" } |
            Select-Object -First 1

        if ([string]::IsNullOrWhiteSpace($packageLine)) {
            throw "SHA256SUMS does not contain a $ToolPackage package."
        }

        $packageFile = [Regex]::Match($packageLine, "\s+($packagePattern)$").Groups[1].Value
        $script:Version = $packageFile.Substring($ToolPackage.Length + 1, $packageFile.Length - $ToolPackage.Length - 7)
    } else {
        $packageFile = "$ToolPackage.$Version.nupkg"
    }

    $packagePath = Join-Path $downloadDirectory $packageFile

    Write-Host "Downloading $packageFile..."
    Download-File -Url "$DownloadBaseUrl/$packageFile" -OutputPath $packagePath

    $escapedPackageFile = [Regex]::Escape($packageFile)
    $checksumLine = Get-Content $checksumsPath |
        Where-Object { $_ -match "\s+$escapedPackageFile$" } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($checksumLine)) {
        throw "SHA256SUMS does not contain an entry for $packageFile."
    }

    $expectedHash = ($checksumLine -split "\s+")[0].ToLowerInvariant()
    $actualHash = (Get-FileHash -Algorithm SHA256 -Path $packagePath).Hash.ToLowerInvariant()

    if ($actualHash -ne $expectedHash) {
        throw "Checksum verification failed for $packageFile. Expected $expectedHash but got $actualHash."
    }

    Write-Host "${packageFile}: OK"
    return $downloadDirectory
}

function Invoke-DotnetTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Verb,

        [string]$ResolvedPackageSource
    )

    $arguments = @("tool", $Verb, "--global", $ToolPackage)

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $arguments += @("--version", $Version)
    }

    if (-not [string]::IsNullOrWhiteSpace($ResolvedPackageSource)) {
        $arguments += @("--add-source", $ResolvedPackageSource)
    }

    & dotnet @arguments
    return $LASTEXITCODE
}

$resolvedPackageSource = Resolve-PackageSource

Write-Host "Installing Aeges CLI..."
Write-Host "Package: $ToolPackage"
if (-not [string]::IsNullOrWhiteSpace($Version)) {
    Write-Host "Version: $Version"
}
if (-not [string]::IsNullOrWhiteSpace($resolvedPackageSource)) {
    Write-Host "Source: $resolvedPackageSource"
}

$updateExitCode = Invoke-DotnetTool -Verb "update" -ResolvedPackageSource $resolvedPackageSource
if ($updateExitCode -ne 0) {
    $installExitCode = Invoke-DotnetTool -Verb "install" -ResolvedPackageSource $resolvedPackageSource
    if ($installExitCode -ne 0) {
        exit $installExitCode
    }
}

if (Get-Command $ToolCommand -ErrorAction SilentlyContinue) {
    Write-Host "Aeges installed. Try: $ToolCommand db status"
} else {
    Write-Host "Aeges installed, but '$ToolCommand' is not on PATH yet."
    Write-Host "Add the .NET tools directory to PATH:"
    Write-Host "  $toolsDirectory"
}
