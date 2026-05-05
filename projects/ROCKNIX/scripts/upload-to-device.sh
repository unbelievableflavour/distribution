#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Push Heroic + modules files from this tree to a running ROCKNIX handheld:
#   - Tools entries (Install / Uninstall / Scan) in modules are standalone scripts.
#   - MODULES_ROOT_EXTRA (e.g. gamelist.xml) + images/heroic.svg
#   - Merge scripts/data/emulationstation-heroic-system.fragment.xml into
#     /storage/.config/emulationstation/es_systems.cfg if heroic is missing (replaces
#     symlink with a writable copy so ES shows Heroic before you reflash).
#
# Usage:
#   ./projects/ROCKNIX/scripts/upload-to-device.sh
#
# Optional environment:
#   ROCKNIX_HOST               default: root@192.168.1.140
#   ROCKNIX_REMOTE_MODULES     default: /storage/.config/modules
#   ROCKNIX_PASSWORD           default: rocknix
#   DISPLAY                    default: :0 (needed for SSH_ASKPASS on some setups)
#   UPLOAD_HEROIC_ES_SYSTEMS   default: 1 — set to 0 to skip es_systems.cfg merge

set -euo pipefail

ROCKNIX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_EMU="${ROCKNIX_ROOT}/packages/virtual/emulators/sources"
SRC_MOD="${ROCKNIX_ROOT}/packages/misc/modules/sources"
SRC_HEROIC_RUNTIME="${ROCKNIX_ROOT}/packages/emulators/standalone/heroic/scripts"
ROCKNIX_HOST="${ROCKNIX_HOST:-root@192.168.1.140}"
ROCKNIX_REMOTE_MODULES="${ROCKNIX_REMOTE_MODULES:-/storage/.config/modules}"
ROCKNIX_REMOTE_HEROIC_LAUNCHERS="${ROCKNIX_REMOTE_HEROIC_LAUNCHERS:-/storage/.config/heroic-launchers}"
ROCKNIX_PASSWORD="${ROCKNIX_PASSWORD:-rocknix}"
UPLOAD_HEROIC_ES_SYSTEMS="${UPLOAD_HEROIC_ES_SYSTEMS:-1}"

SRC_FRAG="${ROCKNIX_ROOT}/scripts/data/emulationstation-heroic-system.fragment.xml"
REMOTE_FRAG="/tmp/emulationstation-heroic-system.fragment.xml"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o ConnectTimeout=20
)

# Heroic shell modules under SRC_EMU (same names on device).
HEROIC_MODULE_SCRIPTS=(
  "Install Heroic Games Launcher.sh"
  "Uninstall Heroic Games Launcher.sh"
  "Scan Heroic Games.sh"
)

# Flat files in ROCKNIX_REMOTE_MODULES (not under scripts/ or images/).
MODULES_ROOT_EXTRA=(
  "gamelist.xml"
)

# Removed monolithic launcher; delete leftover on device so Tools does not run stale file.
HEROIC_LEGACY_REMOVED_ON_DEVICE="Start Heroic Games Launcher.sh"

ASKPASS_SCRIPT="$(mktemp)"
chmod 700 "${ASKPASS_SCRIPT}"
printf '#!/bin/sh\necho %s\n' "${ROCKNIX_PASSWORD}" > "${ASKPASS_SCRIPT}"
trap 'rm -f "${ASKPASS_SCRIPT}"' EXIT

export DISPLAY="${DISPLAY:-:0}"
export SSH_ASKPASS="${ASKPASS_SCRIPT}"
export SSH_ASKPASS_REQUIRE=force

# Use /dev/null for stdin when attached to a terminal so stray input does not reach ssh.
# When stdin is a heredoc/pipe (e.g. merging es_systems.cfg), forward it so `bash -s` runs.
_ssh() {
  if [[ -t 0 ]]; then
    ssh "${SSH_OPTS[@]}" "$@" < /dev/null
  else
    ssh "${SSH_OPTS[@]}" "$@"
  fi
}
_scp() { scp "${SSH_OPTS[@]}" "$@" < /dev/null; }

heroic_local_paths=()
for name in "${HEROIC_MODULE_SCRIPTS[@]}"; do
  heroic_local_paths+=("${SRC_EMU}/${name}")
  [[ -f "${SRC_EMU}/${name}" ]] || { echo "Missing: ${SRC_EMU}/${name}" >&2; exit 1; }
done
for name in "${MODULES_ROOT_EXTRA[@]}"; do
  [[ -f "${SRC_MOD}/${name}" ]] || { echo "Missing: ${SRC_MOD}/${name}" >&2; exit 1; }
done
[[ -f "${SRC_MOD}/images/heroic.svg" ]] || { echo "Missing: heroic.svg" >&2; exit 1; }
[[ -f "${SRC_FRAG}" ]] || { echo "Missing: ${SRC_FRAG}" >&2; exit 1; }
for name in start_heroic_authenticate.sh start_heroic_play.sh start_heroic_play_gamescope.sh; do
  [[ -f "${SRC_HEROIC_RUNTIME}/${name}" ]] || { echo "Missing: ${SRC_HEROIC_RUNTIME}/${name}" >&2; exit 1; }
done

# Symlinks on these names make scp overwrite the wrong file; drop symlinks first.
symlink_cleanup=''
for name in "${HEROIC_MODULE_SCRIPTS[@]}"; do
  symlink_cleanup+="[ -L '${ROCKNIX_REMOTE_MODULES}/${name}' ] && rm -f '${ROCKNIX_REMOTE_MODULES}/${name}'; "
done
_ssh "${ROCKNIX_HOST}" "${symlink_cleanup}rm -f '${ROCKNIX_REMOTE_MODULES}/${HEROIC_LEGACY_REMOVED_ON_DEVICE}' '${ROCKNIX_REMOTE_MODULES}/scripts/heroic_common.sh' '${ROCKNIX_REMOTE_MODULES}/scripts/heroic_common.inc'"
_ssh "${ROCKNIX_HOST}" "ROMS_DIR='/storage/roms/heroic'; if [ -d \"\${ROMS_DIR}\" ]; then rm -f \"\${ROMS_DIR}/Configure Heroic.sh\" \"\${ROMS_DIR}/Play Heroic.sh\" \"\${ROMS_DIR}/Play Heroic (Gamescope).sh\" \"\${ROMS_DIR}/000 Heroic (Configure).sh\" \"\${ROMS_DIR}/000 Heroic (Play).sh\" \"\${ROMS_DIR}/000 Heroic (Gamescope).sh\" \"\${ROMS_DIR}/000 Heroic Games Launcher (Authenticate).sh\" \"\${ROMS_DIR}/000 Heroic Games Launcher.sh\" \"\${ROMS_DIR}/000 Heroic Games Launcher (Gamescope).sh\"; fi"
_ssh "${ROCKNIX_HOST}" "rm -f /storage/.config/modules/Start\\ Heroic\\ Authenticate.sh /storage/.config/modules/Start\\ Heroic\\ Play.sh /storage/.config/modules/Start\\ Heroic\\ Play\\ Gamescope.sh"
_ssh "${ROCKNIX_HOST}" "mkdir -p '${ROCKNIX_REMOTE_HEROIC_LAUNCHERS}'"

modules_root_local=()
for name in "${MODULES_ROOT_EXTRA[@]}"; do
  modules_root_local+=("${SRC_MOD}/${name}")
done
_scp "${heroic_local_paths[@]}" "${modules_root_local[@]}" "${ROCKNIX_HOST}:${ROCKNIX_REMOTE_MODULES}/"

_ssh "${ROCKNIX_HOST}" "mkdir -p '${ROCKNIX_REMOTE_MODULES}/images' '${ROCKNIX_REMOTE_MODULES}/scripts'"

_scp "${SRC_MOD}/images/heroic.svg" "${ROCKNIX_HOST}:${ROCKNIX_REMOTE_MODULES}/images/"
_scp "${SRC_HEROIC_RUNTIME}/start_heroic_authenticate.sh" "${ROCKNIX_HOST}:${ROCKNIX_REMOTE_HEROIC_LAUNCHERS}/Start Heroic Authenticate.sh"
_scp "${SRC_HEROIC_RUNTIME}/start_heroic_play.sh" "${ROCKNIX_HOST}:${ROCKNIX_REMOTE_HEROIC_LAUNCHERS}/Start Heroic Play.sh"
_scp "${SRC_HEROIC_RUNTIME}/start_heroic_play_gamescope.sh" "${ROCKNIX_HOST}:${ROCKNIX_REMOTE_HEROIC_LAUNCHERS}/Start Heroic Play Gamescope.sh"
chmod_cmd="chmod 0755"
for name in "${HEROIC_MODULE_SCRIPTS[@]}"; do
  chmod_cmd+=" '${ROCKNIX_REMOTE_MODULES}/${name}'"
done
chmod_cmd+=" ; chmod 0755 '${ROCKNIX_REMOTE_HEROIC_LAUNCHERS}/Start Heroic Authenticate.sh' '${ROCKNIX_REMOTE_HEROIC_LAUNCHERS}/Start Heroic Play.sh' '${ROCKNIX_REMOTE_HEROIC_LAUNCHERS}/Start Heroic Play Gamescope.sh'"
_ssh "${ROCKNIX_HOST}" "${chmod_cmd}"

if [[ "${UPLOAD_HEROIC_ES_SYSTEMS}" == "1" ]]; then
  echo "Merging Heroic system into es_systems.cfg on ${ROCKNIX_HOST}..."
  _scp "${SRC_FRAG}" "${ROCKNIX_HOST}:${REMOTE_FRAG}"
  _ssh "${ROCKNIX_HOST}" "bash -s" <<'EOS_MERGE'
set -euo pipefail
CFG=/storage/.config/emulationstation/es_systems.cfg
FRAG=/tmp/emulationstation-heroic-system.fragment.xml

if ! command -v awk >/dev/null 2>&1 || ! command -v xmlstarlet >/dev/null 2>&1; then
  echo "Device missing awk or xmlstarlet; cannot merge heroic into es_systems.cfg" >&2
  rm -f "${FRAG}"
  exit 1
fi

materialize_es_cfg() {
  if [ -L "${CFG}" ]; then
    REAL="$(readlink -f "${CFG}")"
    TMP="${CFG}.copy.$$"
    cp -f "${REAL}" "${TMP}"
    rm -f "${CFG}"
    mv "${TMP}" "${CFG}"
  fi
}

materialize_es_cfg

if grep -q '<name>heroic</name>' "${CFG}" 2>/dev/null; then
  echo "Heroic system already present; setting theme to heroic (own group, not ports)."
  xmlstarlet ed -L -u "//system[name='heroic']/theme" -v heroic "${CFG}"
  if ! xmlstarlet val "${CFG}" >/dev/null 2>&1; then
    echo "es_systems.cfg failed XML validation after theme update." >&2
    exit 1
  fi
  rm -f "${FRAG}"
  echo "Updated heroic theme in ${CFG}. Restart EmulationStation."
  exit 0
fi

BACK="${CFG}.bak.heroic.$(date +%Y%m%d%H%M%S)"
cp -f "${CFG}" "${BACK}"

awk 'FNR==NR { frag = frag $0 ORS; next }
/<\/systemList>/ && !inserted { printf "%s", frag; inserted=1 }
{ print }' "${FRAG}" "${CFG}" > "${CFG}.new.$$"
mv "${CFG}.new.$$" "${CFG}"
rm -f "${FRAG}"

if ! xmlstarlet val "${CFG}" >/dev/null 2>&1; then
  echo "Merged es_systems.cfg failed XML validation; restoring backup." >&2
  cp -f "${BACK}" "${CFG}"
  exit 1
fi

echo "Merged heroic into ${CFG} (backup: ${BACK}). Restart EmulationStation."
EOS_MERGE
else
  echo "Skipping es_systems.cfg merge (UPLOAD_HEROIC_ES_SYSTEMS=${UPLOAD_HEROIC_ES_SYSTEMS})."
fi

echo "Uploaded to ${ROCKNIX_HOST}:${ROCKNIX_REMOTE_MODULES}/"
echo "If Configure/Play still fail, run Tools → Install Heroic once to refresh rom stubs (or Scan Heroic Games)."
ls_cmd="ls -la"
for name in "${HEROIC_MODULE_SCRIPTS[@]}"; do
  ls_cmd+=" '${ROCKNIX_REMOTE_MODULES}/${name}'"
done
for name in "${MODULES_ROOT_EXTRA[@]}"; do
  ls_cmd+=" '${ROCKNIX_REMOTE_MODULES}/${name}'"
done
ls_cmd+=" '${ROCKNIX_REMOTE_MODULES}/images/heroic.svg'"
_ssh "${ROCKNIX_HOST}" "${ls_cmd}"
