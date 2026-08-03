#!/usr/bin/env bash
set -euo pipefail

analysis_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
paper_root="${1:-"$(dirname "$analysis_root")/military-service-gender-gap-paper"}"
output_root="$analysis_root/output"
files=(
  panel_a_did.tex panel_b_intensity.tex qoe_panel_a_did.tex qoe_panel_b_intensity.tex
  eventstudy_entry_age.png eventstudy_employed.png qoe_eventstudy_score50.png qoe_eventstudy_income50.png qoe_eventstudy_stability.png qoe_eventstudy_conditions.png
  qoe_binned_eventstudy_score50.png qoe_binned_eventstudy_income50.png qoe_binned_eventstudy_stability.png qoe_binned_eventstudy_conditions.png
  qoe_panel_a_did_robust667.tex qoe_decomposition_did.tex qoe_weighted_contribution_did.tex qoe_did_by_industry_gender_type.tex
  qoe_sequential_controls_score.tex qoe_sequential_controls_income.tex qoe_sequential_controls_stability.tex qoe_sequential_controls_conditions.tex
  sorting_did_wage_indices.tex sorting_intensity_wage_indices.tex qoe_sorting_did_occupation_indices.tex qoe_sorting_intensity_occupation_indices.tex
  qoe_sorting_did_exclude_small_occupations.tex qoe_sorting_intensity_exclude_small_occupations.tex occupation_competition_link.tex
  occupation_competition_scatter.png occupation_industry_competition_scatter.png sorting_gender_age_tenure_robustness.tex sorting_gender_specific_post_changes.tex
  enlistage_commoncohort_did.tex enlistage_commoncohort_intensity.tex enlistage_commoncohort_eventstudy_pretrend_pvalues.csv
  enlistage19_commoncohort_eventstudy_employed.png enlistage19_commoncohort_eventstudy_entry_age.png
  enlistage20_commoncohort_eventstudy_employed.png enlistage20_commoncohort_eventstudy_entry_age.png
  enlistage21_commoncohort_eventstudy_employed.png enlistage21_commoncohort_eventstudy_entry_age.png
  may_youth_entry_age_table.tex may_youth_entry_age_results.csv
  may_youth_entry_age_eventstudy_unweighted.png may_youth_entry_age_eventstudy_weighted.png
  may_youth_entry_age_eventstudy_commonyears_unweighted.png may_youth_entry_age_eventstudy_commonyears_weighted.png
  may_youth_employed_eventstudy_unweighted.png may_youth_employed_eventstudy_weighted.png
  may_youth_employed_eventstudy_commonyears_unweighted.png may_youth_employed_eventstudy_commonyears_weighted.png
  may_youth_school_exit_age_eventstudy_unweighted.png may_youth_school_exit_age_eventstudy_weighted.png
  may_youth_school_to_firstjob_eventstudy_unweighted.png may_youth_school_to_firstjob_eventstudy_weighted.png
)

if [[ ! -d "$paper_root/.git" ]]; then
  echo "Paper repository not found: $paper_root" >&2
  exit 1
fi

for file in "${files[@]}"; do
  [[ -f "$output_root/$file" ]] || { echo "Analysis output not found: $output_root/$file" >&2; exit 1; }
done

for file in "${files[@]}"; do
  cp "$output_root/$file" "$paper_root/$file"
  echo "Synced $file"
done

echo
echo "Paper outputs updated. Review them before committing:"
echo "  git -C \"$paper_root\" status --short"
echo "  git -C \"$paper_root\" diff --stat"
