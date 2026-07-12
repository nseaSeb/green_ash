#!/usr/bin/env bash
# Vérification "triple" avant publication Hex de green_ash, en Docker (pas de
# CI GitHub) :
#   1/3 — compile + test à froid, salle blanche
#   2/3 — répétition d'installation fidèle (bootstrap vierge + `mix igniter.install`
#         réel, via GitHub)
#   3/3 — la même couche 1, rejouée sur une matrice de versions Elixir/OTP
#
# Usage : ./docker/verify.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MATRIX=("1.15-otp-25" "1.17-otp-26" "1.19-otp-28")
FAILED=()

echo "=============================================="
echo " Couches 1 et 3 — matrice de compile/test"
echo "=============================================="
for tag in "${MATRIX[@]}"; do
  echo "--- elixir:${tag} ---"
  if docker build \
      -f docker/verify/Dockerfile.matrix \
      --build-arg "ELIXIR_TAG=${tag}" \
      -t "green_ash-verify:${tag}" \
      green_ash; then
    echo "OK   elixir:${tag}"
  else
    echo "ÉCHEC elixir:${tag}"
    FAILED+=("matrix:${tag}")
  fi
done

echo "=============================================="
echo " Couche 2 — répétition d'installation fidèle"
echo "=============================================="
if docker compose -f docker/verify/docker-compose.rehearsal.yml run --build --rm rehearsal; then
  echo "OK   rehearsal"
else
  echo "ÉCHEC rehearsal"
  FAILED+=("rehearsal")
fi
docker compose -f docker/verify/docker-compose.rehearsal.yml down -v 2>/dev/null || true

echo "=============================================="
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "TOUT VERT : ${#MATRIX[@]} versions + répétition d'installation OK."
  exit 0
else
  echo "ÉCHECS : ${FAILED[*]}"
  exit 1
fi
