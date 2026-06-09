#Requires -Version 5.1
<#
.SYNOPSIS
  Bootstrap NixOS WSL (holodeck-01) from scratch on Windows.

.PARAMETER AgeIdentityPath
  Path to the holodeck-01 age private key file. If not supplied the script
  will ask interactively. Providing it skips the prompt. Pass an empty string
  or answer "skip" at the prompt to install without an identity (secrets and
  backups will not be active until enrolled post-boot).

.PARAMETER FlakeBranch
  Branch of geoff-coppertop/nixos-config to build from (e.g. 'main').
  Defaults to the repository's default branch. Useful when testing a
  feature branch before it is merged.

.DESCRIPTION
  1. Downloads the NixOS-WSL pre-built tarball from GitHub releases.
  2. Imports it as a WSL distro named 'NixOS'.
  3. Installs the age identity key if one is provided.
  4. Applies the holodeck-01 flake config from inside the new NixOS distro.

  Prerequisites: WSL2 must be enabled (run: wsl --install; reboot once if
  first time). Run from Windows Terminal (PowerShell) — no Nix or Linux
  tooling required on the Windows side.
#>

param(
  [string]$AgeIdentityPath = $null,
  [string]$FlakeBranch     = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DistroName  = 'NixOS'
$InstallDir  = "$env:LOCALAPPDATA\$DistroName"
$FlakeTarget = 'holodeck-01'
$FlakeRepo   = if ($FlakeBranch -ne "") {
    "github:geoff-coppertop/nixos-config/$FlakeBranch"
} else {
    "github:geoff-coppertop/nixos-config"
}
$TmpImage    = "$env:TEMP\nixos-wsl-installer.wsl"

Write-Host "=== NixOS WSL Bootstrap ==="
Write-Host ""

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Error "wsl.exe not found. Enable WSL2 first: wsl --install (then reboot)"
    exit 1
}

# ── Age identity ──────────────────────────────────────────────────────────────

if ($null -eq $AgeIdentityPath) {
    Write-Host "Age identity key source:"
    Write-Host "  1) File path"
    Write-Host "  2) Skip (enroll post-boot)"
    Write-Host ""
    $choice = Read-Host "Choice [1/2]"

    switch ($choice) {
        "1" {
            $AgeIdentityPath = Read-Host "Path to age identity file"
        }
        "2" {
            $AgeIdentityPath = ""
        }
        default {
            Write-Error "Invalid choice."
            exit 1
        }
    }
}

if ($AgeIdentityPath -ne "" -and -not (Test-Path $AgeIdentityPath)) {
    Write-Error "Age identity file not found: $AgeIdentityPath"
    exit 1
}

# ── Download and import ───────────────────────────────────────────────────────

Write-Host ""
Write-Host "Fetching latest NixOS-WSL release..."
$release = Invoke-RestMethod 'https://api.github.com/repos/nix-community/NixOS-WSL/releases/latest'
$asset   = $release.assets | Where-Object { $_.name -like '*.wsl' -and $_.name -notlike '*.sha256' } | Select-Object -First 1
if (-not $asset) { throw "No .wsl asset found in NixOS-WSL latest release. Assets: $($release.assets.name -join ', ')" }

Write-Host "Downloading $($asset.name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $TmpImage -UseBasicParsing

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

Write-Host "Importing as WSL distro '$DistroName'..."
wsl.exe --import $DistroName $InstallDir $TmpImage
if ($LASTEXITCODE -ne 0) { throw "wsl --import failed (exit $LASTEXITCODE)" }

Remove-Item $TmpImage

# ── Install age identity ──────────────────────────────────────────────────────

if ($AgeIdentityPath -ne "") {
    Write-Host ""
    Write-Host "Installing age identity..."
    $absPath = (Resolve-Path $AgeIdentityPath).Path
    $drive   = $absPath.Substring(0, 1).ToLower()
    $rest    = $absPath.Substring(2) -replace '\\', '/'
    $wslPath = "/mnt/$drive$rest"
    wsl.exe -d $DistroName -- bash -c "sudo mkdir -p -m 700 /var/lib/agenix && sudo cp '$wslPath' /var/lib/agenix/identity && sudo chmod 400 /var/lib/agenix/identity"
    if ($LASTEXITCODE -ne 0) { throw "Failed to install age identity (exit $LASTEXITCODE)" }
    Write-Host "Age identity installed."
    Write-Host "Remember to securely delete $AgeIdentityPath from Windows after provisioning."
}

# ── Apply flake config ────────────────────────────────────────────────────────

if ($AgeIdentityPath -eq "") {
    Write-Host ""
    Write-Host "=== Distro imported. Age identity not provided — skipping nixos-rebuild. ==="
    Write-Host ""
    Write-Host "The holodeck-01 config declares agenix secrets, so nixos-rebuild requires"
    Write-Host "the age private key at /var/lib/agenix/identity before it can succeed."
    Write-Host ""
    Write-Host "To complete setup, find the holodeck-01 age identity (generated on enterprise-d"
    Write-Host "at ~/.config/agenix/holodeck-01.age), then run from PowerShell:"
    Write-Host ""
    Write-Host '  # Copy from enterprise-d (adjust host if needed):'
    Write-Host '  scp thomasga@enterprise-d:~/.config/agenix/holodeck-01.age "$env:TEMP\holodeck-01.age"'
    Write-Host ""
    Write-Host "  # Then rerun the bootstrap script with the identity path:"
    Write-Host "  & ([scriptblock]::Create((irm '$($MyInvocation.ScriptName -replace '.*tools[/\\]','...tools/')' ))) ``"
    Write-Host "      -AgeIdentityPath `"`$env:TEMP\holodeck-01.age`" -FlakeBranch '$FlakeBranch'"
    Write-Host ""
    Write-Host "Or if the distro was already imported, install the identity and rebuild manually:"
    Write-Host "  (see README > WSL Setup > Option B)"
    exit 0
}

Write-Host ""
Write-Host "Applying holodeck-01 configuration (this may take several minutes)..."
wsl.exe -d $DistroName -- bash -c "sudo nixos-rebuild switch --flake '${FlakeRepo}#${FlakeTarget}'"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Error "nixos-rebuild failed (exit $LASTEXITCODE). The distro was imported and the age identity was installed."
    Write-Host "To retry:"
    Write-Host "  wsl -d $DistroName -- bash -c `"sudo nixos-rebuild switch --flake '${FlakeRepo}#${FlakeTarget}'`""
    exit 1
}

Write-Host ""
Write-Host "=== Setup complete. Launch NixOS WSL with: wsl -d $DistroName ==="
