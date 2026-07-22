#!/usr/bin/env bash
# Vérification "triple" avant publication Hex de green_ash, en Docker (pas de
# CI GitHub) :
#   1/3 — compile + test à froid, salle blanche
#   2/3 — répétition d'installation fidèle (bootstrap vierge + `mix igniter.install`
#         réel) sur LA COPIE DE TRAVAIL, pas sur la version publiée
#   3/3 — la même couche 1, rejouée sur une matrice de versions Elixir/OTP
#
# Usage : ./docker/verify.sh
#         GREEN_ASH_SOURCE=hex ./docker/verify.sh   # vérifie la release publiée
#
# La couche 2 installe par défaut la copie de travail (`green_ash@path:`). Elle
# est le seul endroit où l'installeur tourne — il n'a aucun test, et les couches
# 1/3 ne l'exécutent jamais — donc la faire porter sur la version déjà publiée
# revenait à ne jamais vérifier ce qu'on s'apprête à publier.
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
echo " Couche 2 — répétition d'installation fidèle (source: ${GREEN_ASH_SOURCE:-local})"
echo "=============================================="
# Projet Compose propre à cette exécution. Sans ça, deux répétitions lancées en
# parallèle partagent le même Postgres : la seconde trouve les tables créées par
# la première ("relation widgets already exists"), et le `down -v` de celle qui
# finit d'abord arrache la base de l'autre en pleine migration. Les deux
# échouent, aucune pour une raison qui concerne le code testé.
REHEARSAL_PROJECT="green_ash_rehearsal_$$"
COMPOSE=(docker compose -p "${REHEARSAL_PROJECT}" -f docker/verify/docker-compose.rehearsal.yml)

# Et on nettoie AVANT aussi : une exécution interrompue (Ctrl-C, plantage) laisse
# son volume derrière elle, et la suivante hérite d'une base déjà migrée.
"${COMPOSE[@]}" down -v >/dev/null 2>&1 || true

if "${COMPOSE[@]}" run --build --rm rehearsal; then
  echo "OK   rehearsal"
else
  echo "ÉCHEC rehearsal"
  FAILED+=("rehearsal")
fi
"${COMPOSE[@]}" down -v >/dev/null 2>&1 || true

echo "=============================================="
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "TOUT VERT : ${#MATRIX[@]} versions + répétition d'installation OK."
  exit 0
else
  echo "ÉCHECS : ${FAILED[*]}"
  exit 1
fi
