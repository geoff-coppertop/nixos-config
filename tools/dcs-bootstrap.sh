#!/usr/bin/env bash
# dcs-bootstrap.sh — stand up a DCS World (standalone, Eagle Dynamics build)
# Wine/Proton prefix on stargazer and launch the ED updater. Run ON THE MACHINE
# after NixOS is installed; DCS is a proprietary interactive download and cannot
# be provisioned declaratively (there is no pkgs.dcs).
#
# What this does NOT do: log into your ED account, accept the EULA, or pick
# modules — those are interactive and yours. It gets you to the updater with a
# correct prefix + runner so the rest is "log in and wait".
#
# Prereqs (from custom.wineGaming.enable): umu-launcher, protonup-qt.
# Pick up DCS_Updater.exe from https://www.digitalcombatsimulator.com/ first.
set -euo pipefail

PREFIX="${DCS_PREFIX:-$HOME/Games/dcs/prefix}"
UPDATER="${1:-$HOME/Downloads/DCS_Updater.exe}"
# Point at the official Proton 11 build (Wine 11 base — improves DCS). Override
# PROTONPATH to a GE-Proton if you prefer; umu resolves "GE-Proton" specially.
PROTONPATH="${PROTONPATH:-GE-Proton}"

if [ ! -f "$UPDATER" ]; then
  echo "DCS_Updater.exe not found at: $UPDATER" >&2
  echo "Download it from Eagle Dynamics and pass its path, e.g.:" >&2
  echo "  tools/dcs-bootstrap.sh ~/Downloads/DCS_Updater.exe" >&2
  exit 1
fi

mkdir -p "$PREFIX"

echo "DCS prefix : $PREFIX"
echo "Runner     : $PROTONPATH"
echo "Updater    : $UPDATER"
echo

# umu-run runs the updater under Proton in an explicit, isolated prefix. The DCS
# updater then downloads the game into that prefix's drive_c. VoiceAttack stays
# in its own Steam prefix — VAICOM/SimHaptic reach DCS over UDP localhost, so a
# single shared prefix is unnecessary. Symlink the export path afterwards:
#   ln -s "$PREFIX/drive_c/users/steamuser/Saved Games/DCS" ~/dcs-saved-games
WINEPREFIX="$PREFIX" GAMEID="umu-dcs" PROTONPATH="$PROTONPATH" \
  umu-run "$UPDATER"

echo
echo "Updater launched. Log into Eagle Dynamics, accept the EULA, choose modules."
echo "Next: VR via ALVR->SteamVR->OpenXR; VAICOM/SimHaptic/SimHub per README."
