#!/usr/bin/env bash
#
# generate-pdfs-gold.sh — Génère des PDFs de référence pour tous les README
# du dossier prod-crystal, afin de servir de baseline pour la détection de
# régressions visuelles lors des modifications du moteur de composition de
# asciicrystal-pdf.
#
# Pour chaque dossier projet (sous PROD_DIR) qui contient un README :
#   - Privilégie README.fr.adoc avec le thème `fr` (typographie française).
#   - Tombe sur README.adoc avec le thème par défaut sinon.
#   - Génère le PDF dans GOLD_DIR/<nom-projet>.pdf
#   - Enregistre le log STDOUT/STDERR dans GOLD_DIR/<nom-projet>.log
#   - Calcule taille, nombre de pages (via pdfinfo si dispo), SHA-256.
#
# Le manifest final (GOLD_DIR/manifest.txt) liste tous les projets avec
# leurs métadonnées. Il sera comparé après chaque modification du moteur
# pour détecter les régressions (changement de SHA-256 = changement de
# rendu visuel ; à investiguer si non intentionnel).
#
# Variables d'environnement (avec valeurs par défaut) :
#   CRYSTAL_PDF_BIN  Binaire à utiliser pour la génération.
#                    Défaut : ./bin/asciicrystal-pdf
#   GOLD_DIR         Dossier de sortie des PDFs.
#                    Défaut : /tmp/pdfs-gold
#   PROD_DIR         Racine des projets Crystal à parcourir.
#                    Défaut : /Users/philippe/prod-crystal
#
# Usage :
#   tools/generate-pdfs-gold.sh
#   GOLD_DIR=/tmp/pdfs-baseline tools/generate-pdfs-gold.sh
#
# Pour la comparaison après modification :
#   diff <(awk '{print $1, $5}' baseline/manifest.txt) \
#        <(awk '{print $1, $5}' after/manifest.txt)
# (les SHA-256 qui changent pointent les projets dont le rendu a évolué).

set -uo pipefail

CRYSTAL_PDF_BIN="${CRYSTAL_PDF_BIN:-$(cd "$(dirname "$0")/.." && pwd)/bin/asciicrystal-pdf}"
GOLD_DIR="${GOLD_DIR:-/tmp/pdfs-gold}"
PROD_DIR="${PROD_DIR:-/Users/philippe/prod-crystal}"

if [[ ! -x "$CRYSTAL_PDF_BIN" ]]; then
  echo "Erreur : binaire introuvable ou non exécutable : $CRYSTAL_PDF_BIN" >&2
  echo "Lancez d'abord : (cd asciicrystal-pdf && shards build)" >&2
  exit 1
fi

mkdir -p "$GOLD_DIR"

manifest="$GOLD_DIR/manifest.txt"
echo "# PDFs gold — $(date -u '+%Y-%m-%d %H:%M:%S UTC')" > "$manifest"
echo "# binaire : $CRYSTAL_PDF_BIN" >> "$manifest"
echo "# binaire mtime : $(stat -f '%Sm' "$CRYSTAL_PDF_BIN" 2>/dev/null || stat -c '%y' "$CRYSTAL_PDF_BIN" 2>/dev/null)" >> "$manifest"
echo "" >> "$manifest"
printf "# %-44s | %-7s | %12s | %5s | %s\n" "projet" "thème" "taille (o)" "pages" "sha256" >> "$manifest"
printf "# %s\n" "$(printf '%0.s-' {1..130})" >> "$manifest"

total=0
ok=0
failed=0
warnings=0
skipped=0

for dir in "$PROD_DIR"/*/; do
  [[ -d "$dir" ]] || continue
  name=$(basename "$dir")

  # Ne traiter que les dossiers qui sont des repos git (= vrais projets).
  [[ -d "$dir/.git" ]] || { skipped=$((skipped + 1)); continue; }

  fr="$dir/README.fr.adoc"
  en="$dir/README.adoc"

  if [[ -f "$fr" ]]; then
    src="$fr"
    theme="fr"
  elif [[ -f "$en" ]]; then
    src="$en"
    theme="default"
  else
    skipped=$((skipped + 1))
    continue
  fi

  total=$((total + 1))
  out="$GOLD_DIR/$name.pdf"
  log="$GOLD_DIR/$name.log"

  printf "  %-40s  [%s] ... " "$name" "$theme"

  if "$CRYSTAL_PDF_BIN" -T "$theme" "$src" -o "$out" > "$log" 2>&1; then
    size=$(wc -c < "$out" | tr -d ' ')
    pages=$(pdfinfo "$out" 2>/dev/null | awk '/^Pages:/ {print $2}')
    [[ -z "$pages" ]] && pages="?"
    sha=$(shasum -a 256 "$out" | cut -d' ' -f1)
    n_warn=$(grep -c "WARNING\|asciidoctor: WARNING" "$log" 2>/dev/null | tr -d ' \n' || echo 0)
    n_warn="${n_warn:-0}"

    if [[ "$n_warn" -gt 0 ]] 2>/dev/null; then
      echo "OK ($pages pages, $size o, ⚠ $n_warn warnings)"
      warnings=$((warnings + 1))
    else
      echo "OK ($pages pages, $size o)"
    fi

    printf "%-46s | %-7s | %12s | %5s | %s\n" "$name" "$theme" "$size" "$pages" "$sha" >> "$manifest"
    ok=$((ok + 1))
  else
    echo "FAILED (voir $log)"
    printf "%-46s | %-7s | %12s | %5s | %s\n" "$name" "$theme" "FAILED" "-" "see-log" >> "$manifest"
    failed=$((failed + 1))
  fi
done

echo "" >> "$manifest"
echo "# Bilan : $total projets traités — OK $ok | Failed $failed | Warnings $warnings | Skipped $skipped" >> "$manifest"

echo ""
echo "──────────────────────────────────────────────────────────────"
echo "Bilan : $total projets — OK: $ok | Failed: $failed | Warnings: $warnings | Skipped: $skipped"
echo "Manifest : $manifest"
echo ""
if [[ "$failed" -gt 0 ]]; then
  echo "Projets échoués :"
  awk '/FAILED/ {print "  - " $1}' "$manifest"
fi
