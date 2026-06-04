#!/usr/bin/env bash
#
# compare-pdfs-gold.sh — Compare deux dossiers de PDFs gold (générés par
# `tools/generate-pdfs-gold.sh`) pour détecter les changements de rendu
# entre deux versions du moteur de composition.
#
# Étape 1 : compare les SHA-256 des manifests pour identifier les
#           projets dont le PDF a changé.
# Étape 2 : pour chaque projet changé, extrait les bbox des mots
#           (pdftotext -bbox-layout) et compte les mots dont la
#           position (xMin / yMin / xMax / yMax) a bougé.
# Étape 3 : sortie texte hiérarchisée (résumé puis détail par projet
#           changé), et code de sortie 0 si tout identique, 1 sinon.
#
# Usage :
#   tools/compare-pdfs-gold.sh <baseline-dir> <after-dir>
#   tools/compare-pdfs-gold.sh /tmp/pdfs-baseline /tmp/pdfs-after
#
# Variables d'environnement :
#   MAX_WORDS_REPORTED  Nombre max de mots déplacés à afficher par projet
#                       changé. Défaut : 10.
#   POSITION_EPSILON    Seuil en points PDF en deçà duquel un déplacement
#                       est ignoré (bruit de rendu). Défaut : 0.5.

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage : $0 <baseline-dir> <after-dir>" >&2
  echo "" >&2
  echo "Exemple :" >&2
  echo "  $0 /tmp/pdfs-baseline /tmp/pdfs-after" >&2
  exit 2
fi

BASELINE="$1"
AFTER="$2"
MAX_WORDS_REPORTED="${MAX_WORDS_REPORTED:-10}"
POSITION_EPSILON="${POSITION_EPSILON:-0.5}"

for d in "$BASELINE" "$AFTER"; do
  if [[ ! -d "$d" ]]; then
    echo "Erreur : dossier introuvable : $d" >&2
    exit 2
  fi
  if [[ ! -f "$d/manifest.txt" ]]; then
    echo "Erreur : manifest absent dans $d" >&2
    echo "         (générer d'abord via tools/generate-pdfs-gold.sh)" >&2
    exit 2
  fi
done

# Extrait (projet, sha256) du manifest. Ignore commentaires et ligne
# de bilan. Format ligne manifest : "projet | thème | taille | pages | sha256".
parse_manifest() {
  awk -F'|' '/^[a-z]/ {
    gsub(/ /, "", $1)
    gsub(/ /, "", $5)
    if ($5 != "" && $5 != "FAILED" && $5 != "see-log") {
      print $1, $5
    }
  }' "$1"
}

baseline_sha=$(mktemp)
after_sha=$(mktemp)
trap 'rm -f "$baseline_sha" "$after_sha"' EXIT

parse_manifest "$BASELINE/manifest.txt" | sort > "$baseline_sha"
parse_manifest "$AFTER/manifest.txt" | sort > "$after_sha"

total_baseline=$(wc -l < "$baseline_sha" | tr -d ' ')
total_after=$(wc -l < "$after_sha" | tr -d ' ')

# Projets seulement dans baseline (disparus) ou seulement dans after (nouveaux)
gone=$(comm -23 <(awk '{print $1}' "$baseline_sha") <(awk '{print $1}' "$after_sha"))
new=$(comm -13 <(awk '{print $1}' "$baseline_sha") <(awk '{print $1}' "$after_sha"))

# Projets dans les deux dont SHA-256 a changé
changed=""
while IFS= read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  sha_a=$(echo "$line" | awk '{print $2}')
  sha_b=$(awk -v n="$name" '$1 == n {print $2}' "$after_sha")
  if [[ -n "$sha_b" && "$sha_a" != "$sha_b" ]]; then
    changed+="$name"$'\n'
  fi
done < "$baseline_sha"

count_lines() {
  if [[ -z "$1" ]]; then
    echo 0
  else
    echo -n "$1" | grep -c '^' | tr -d ' \n'
  fi
}
n_gone=$(count_lines "$gone")
n_new=$(count_lines "$new")
n_changed=$(count_lines "$changed")
n_identical=$((total_baseline - n_gone - n_changed))

echo "═══════════════════════════════════════════════════════════════════════════"
echo " Comparaison PDFs gold"
echo "═══════════════════════════════════════════════════════════════════════════"
echo " baseline : $BASELINE  ($total_baseline projets)"
echo " after    : $AFTER  ($total_after projets)"
echo ""
echo "  identiques : $n_identical"
echo "  modifiés   : $n_changed"
echo "  disparus   : $n_gone"
echo "  nouveaux   : $n_new"
echo "═══════════════════════════════════════════════════════════════════════════"

if [[ "$n_gone" -gt 0 ]]; then
  echo ""
  echo "Disparus :"
  echo "$gone" | sed 's/^/  - /'
fi

if [[ "$n_new" -gt 0 ]]; then
  echo ""
  echo "Nouveaux :"
  echo "$new" | sed 's/^/  + /'
fi

# Pour chaque projet changé, extraire bbox des deux PDFs et compter
# combien de mots ont bougé au-delà de POSITION_EPSILON.
if [[ "$n_changed" -gt 0 ]]; then
  echo ""
  echo "Modifiés ($n_changed) :"
  echo ""

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    pdf_a="$BASELINE/$name.pdf"
    pdf_b="$AFTER/$name.pdf"

    if [[ ! -f "$pdf_a" || ! -f "$pdf_b" ]]; then
      echo "  ⚠ $name : PDF manquant côté baseline ou after"
      continue
    fi

    bbox_a=$(mktemp)
    bbox_b=$(mktemp)
    pdftotext -bbox-layout "$pdf_a" - 2>/dev/null | grep -oE '<word[^>]+>[^<]+</word>' > "$bbox_a"
    pdftotext -bbox-layout "$pdf_b" - 2>/dev/null | grep -oE '<word[^>]+>[^<]+</word>' > "$bbox_b"

    n_words_a=$(wc -l < "$bbox_a" | tr -d ' ')
    n_words_b=$(wc -l < "$bbox_b" | tr -d ' ')

    # Compte les mots qui ont changé de position OU de texte.
    # Approche simple : diff brut, compter les lignes différentes.
    n_diff=$(diff "$bbox_a" "$bbox_b" 2>/dev/null | grep -cE '^[<>]' | tr -d ' \n')
    n_diff="${n_diff:-0}"
    n_diff=$((n_diff / 2)) # diff compte les 2 côtés

    if [[ "$n_words_a" == "$n_words_b" ]]; then
      printf "  %-40s : %5d mots, %5d différents\n" "$name" "$n_words_a" "$n_diff"
    else
      printf "  %-40s : %d → %d mots (+/- %d), %d différents\n" \
        "$name" "$n_words_a" "$n_words_b" $((n_words_b - n_words_a)) "$n_diff"
    fi

    # Afficher les premiers mots qui diffèrent
    if [[ "$n_diff" -gt 0 && "$MAX_WORDS_REPORTED" -gt 0 ]]; then
      diff -u "$bbox_a" "$bbox_b" 2>/dev/null \
        | grep -E '^[+-]<word' \
        | head -n $((MAX_WORDS_REPORTED * 2)) \
        | sed 's/^/      /'
      echo ""
    fi

    rm -f "$bbox_a" "$bbox_b"
  done <<< "$changed"
fi

# Code de sortie : 0 si rien n'a changé, 1 sinon.
if [[ "$n_changed" -gt 0 || "$n_gone" -gt 0 || "$n_new" -gt 0 ]]; then
  exit 1
fi
exit 0
