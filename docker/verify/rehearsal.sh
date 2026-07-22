#!/usr/bin/env bash
# Rejoue le parcours d'un utilisateur qui n'a JAMAIS entendu parler de
# green_ash : bootstrap Phoenix vierge, puis LA VRAIE commande d'installation.
#
# GREEN_ASH_SOURCE choisit CE QUI est installé :
#
#   local (défaut) — la copie de travail montée sur GREEN_ASH_PATH, via la
#                    syntaxe `paquet@path:` d'igniter. C'est le seul mode qui
#                    répète l'installation de ce qu'on s'apprête à publier :
#                    l'installeur n'a aucun test, et les couches "matrice" ne
#                    l'exécutent jamais. Une release qui touche au macro du
#                    router n'est vérifiée que par ici.
#
#   hex            — la version publiée. Répond à une autre question, tout
#                    aussi utile mais différente : la dernière release
#                    s'installe-t-elle encore de zéro ?
#
# set -x : trace chaque commande, pour voir précisément où ça diverge si
# une des hypothèses (nom de fichier généré par un installeur, etc.) est fausse.
set -euxo pipefail

PGHOST="${PGHOST:-postgres}"
GREEN_ASH_SOURCE="${GREEN_ASH_SOURCE:-local}"
GREEN_ASH_PATH="${GREEN_ASH_PATH:-/opt/green_ash}"

case "$GREEN_ASH_SOURCE" in
  local)
    test -f "${GREEN_ASH_PATH}/mix.exs" || {
      echo "ÉCHEC: aucun mix.exs sous ${GREEN_ASH_PATH} — la copie de travail n'est pas montée."
      exit 1
    }
    GREEN_ASH_DEP="green_ash@path:${GREEN_ASH_PATH}"
    ;;
  hex)
    GREEN_ASH_DEP="green_ash"
    ;;
  *)
    echo "ÉCHEC: GREEN_ASH_SOURCE doit valoir 'local' ou 'hex' (reçu: ${GREEN_ASH_SOURCE})"
    exit 1
    ;;
esac

cd /work

echo "### 1. Bootstrap Phoenix vierge (aucune connaissance d'Ash ni de green_ash)"
mix igniter.new demo --with phx.new --yes
cd demo

echo "### 2. Pointer la config DB sur le service Postgres du compose"
sed -i "s/hostname: \"localhost\"/hostname: \"${PGHOST}\"/" config/dev.exs config/test.exs

echo "### 3. LA VRAIE COMMANDE : ash + green_ash en une fois (source: ${GREEN_ASH_SOURCE})"
mix igniter.install "ash,ash_phoenix,ash_postgres,${GREEN_ASH_DEP}" --yes

echo "### 3b. Quelle green_ash a réellement été installée ?"
# Le run qui a motivé ce paramètre affichait "TOUT VERT" en ayant installé la
# version publiée, pas la branche. La réponse doit être lisible dans le log,
# et fausse doit faire échouer le script plutôt que passer inaperçue.
grep -n "green_ash" mix.exs
INSTALLED_VERSION=$(mix run --no-start -e 'IO.puts(Application.spec(:green_ash, :vsn) || "")')
echo "green_ash installée: ${INSTALLED_VERSION} (source demandée: ${GREEN_ASH_SOURCE})"

if [ "$GREEN_ASH_SOURCE" = "local" ]; then
  EXPECTED_VERSION=$(grep -oE '@version "[^"]+"' "${GREEN_ASH_PATH}/mix.exs" | head -1 | grep -oE '[0-9][^"]*')
  if ! grep -q "path:" mix.exs; then
    echo "ÉCHEC: green_ash n'a pas été ajoutée en dépendance path — Hex a été utilisé à la place."
    exit 1
  fi
  if [ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]; then
    echo "ÉCHEC: version installée ${INSTALLED_VERSION}, attendue ${EXPECTED_VERSION} depuis ${GREEN_ASH_PATH}"
    exit 1
  fi
fi

echo "### État après l'installeur (pour diagnostic) ---"
echo "--- mix.exs ---"; cat mix.exs
echo "--- config/config.exs ---"; cat config/config.exs
echo "--- lib/demo_web/router.ex ---"; cat lib/demo_web/router.ex
echo "--- igniter a-t-il été ajouté comme dep (nécessaire à green_ash.install) ? ---"
grep -q '{:igniter,' mix.exs && echo "OK: igniter est une dep du projet" \
  || echo "ATTENTION: igniter absent de mix.exs — le point non vérifié se confirme"

echo "### 4. Resource Ash de démo, ajoutée APRÈS coup (cas réaliste : on"
echo "###    installe green_ash quand on a déjà, ou qu'on ajoute ensuite, du métier)"
mkdir -p lib/demo/catalog
cat > lib/demo/catalog.ex <<'EOF'
defmodule Demo.Catalog do
  use Ash.Domain
  resources do
    resource Demo.Catalog.Widget
  end
end
EOF
cat > lib/demo/catalog/widget.ex <<'EOF'
defmodule Demo.Catalog.Widget do
  use Ash.Resource, domain: Demo.Catalog, data_layer: AshPostgres.DataLayer

  resource do
    description "Widgets"
  end

  postgres do
    table "widgets"
    repo Demo.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name]
    end
  end
end
EOF

echo "### État de ash_domains avant patch ---"
grep -n "ash_domains" config/config.exs || echo "(absent)"

if grep -q "ash_domains" config/config.exs; then
  sed -i 's/ash_domains: \[[^]]*\]/ash_domains: [Demo.Catalog]/' config/config.exs
else
  cat >> config/config.exs <<'EOF'

config :demo, ash_domains: [Demo.Catalog]
EOF
fi
echo "--- ash_domains après patch ---"; grep -n "ash_domains" config/config.exs

echo "### 5. Router : le domaine Demo.Catalog doit apparaître dans le montage green_ash"
grep -n "green_ash" lib/demo_web/router.ex
if ! grep -q "green_ash(\"/cli\"" lib/demo_web/router.ex; then
  echo "ÉCHEC: la route /cli n'a pas été montée par l'installeur"
  exit 1
fi

echo "### 6. Génération migration + setup DB + assets"
mix deps.get
mix ash.codegen initial_catalog
mix ash.setup
mix assets.setup

echo "### 7. Compile strict + tests"
mix compile --warnings-as-errors
mix test

echo "### 8. Démarrage réel du serveur et requête HTTP sur /cli"
mix phx.server &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

for i in $(seq 1 30); do
  if curl -s -o /dev/null http://localhost:4000/cli; then
    break
  fi
  sleep 1
done

STATUS=$(curl -s -o /tmp/cli_response.html -w "%{http_code}" http://localhost:4000/cli)
echo "GET /cli -> $STATUS"

if [ "$STATUS" != "200" ]; then
  echo "ÉCHEC: /cli a répondu $STATUS au lieu de 200"
  exit 1
fi

if ! grep -q "Widgets" /tmp/cli_response.html; then
  echo "ÉCHEC: le menu ne liste pas la resource Widgets (découverte cassée ?)"
  cat /tmp/cli_response.html
  exit 1
fi

echo "### SUCCÈS : bootstrap vierge -> mix igniter.install -> /cli fonctionnel, zéro code d'UI écrit."
echo "###          (green_ash ${INSTALLED_VERSION}, source ${GREEN_ASH_SOURCE})"
