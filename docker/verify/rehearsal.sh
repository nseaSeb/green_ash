#!/usr/bin/env bash
# Rejoue le parcours d'un utilisateur qui n'a JAMAIS entendu parler de
# green_ash : bootstrap Phoenix vierge, puis LA VRAIE commande finale
# (green_ash est publié sur Hex depuis la v0.1.0 — plus besoin du
# contournement Git+sparse utilisé en pré-publication).
#
# set -x : trace chaque commande, pour voir précisément où ça diverge si
# une des hypothèses (nom de fichier généré par un installeur, etc.) est fausse.
set -euxo pipefail

PGHOST="${PGHOST:-postgres}"

cd /work

echo "### 1. Bootstrap Phoenix vierge (aucune connaissance d'Ash ni de green_ash)"
mix igniter.new demo --with phx.new --yes
cd demo

echo "### 2. Pointer la config DB sur le service Postgres du compose"
sed -i "s/hostname: \"localhost\"/hostname: \"${PGHOST}\"/" config/dev.exs config/test.exs

echo "### 3. LA VRAIE COMMANDE : ash + green_ash en une fois, depuis Hex"
mix igniter.install ash,ash_phoenix,ash_postgres,green_ash --yes

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
