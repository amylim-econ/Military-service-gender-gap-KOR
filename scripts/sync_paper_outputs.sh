#!/usr/bin/env bash

set -euo pipefail

analysis_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
paper_root="${1:-"$(dirname "$analysis_root")/military-service-gender-gap-paper"}"
output_root="$analysis_root/output"

files=(
  "panel_a_did.tex"
  "panel_b_intensity.tex"
  "main_did_by_industry_gender_type.tex"
  "eventstudy_entry_age.png"
  "eventstudy_employed.png"
  "eventstudy_largefirm.png"
  "eventstudy_permanent.png"
  "eventstudy_log_hourly_wage_trim.png"
  "eventstudy_log_monthly_wage_trim.png"
)

if [[ ! -d "$paper_root/.git" ]]; then
  echo "Paper repository not found: $paper_root" >&2
  exit 1
fi

for file in "${files[@]}"; do
  if [[ ! -f "$output_root/$file" ]]; then
    echo "Analysis output not found: $output_root/$file" >&2
    exit 1
  fi
done

for file in "${files[@]}"; do
  cp "$output_root/$file" "$paper_root/$file"
  echo "Synced $file"
done

echo
echo "Paper outputs updated. Review them before committing:"
echo "  git -C \"$paper_root\" status --short"
echo "  git -C \"$paper_root\" diff --stat"
