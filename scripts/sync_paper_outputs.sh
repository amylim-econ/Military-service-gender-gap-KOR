#!/usr/bin/env bash
set -euo pipefail

analysis_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
paper_root="${1:-"$(dirname "$analysis_root")/military-service-gender-gap-paper"}"
output_root="$analysis_root/output"
files=(
  panel_a_did.tex panel_b_intensity.tex qoe_panel_a_did.tex qoe_panel_b_intensity.tex
  employment_untreated_male_mean.tex
  eventstudy_entry_age.png eventstudy_employed.png qoe_eventstudy_score50.png qoe_eventstudy_income50.png qoe_eventstudy_stability.png qoe_eventstudy_conditions.png
  qoe_binned_eventstudy_score50.png qoe_binned_eventstudy_income50.png qoe_binned_eventstudy_stability.png qoe_binned_eventstudy_conditions.png
  qoe_panel_a_did_robust667.tex qoe_binned_eventstudy_table.tex qoe_decomposition_did.tex qoe_weighted_contribution_did.tex qoe_did_by_industry_gender_type.tex
  qoe_sequential_controls_score.tex qoe_sequential_controls_income.tex qoe_sequential_controls_stability.tex qoe_sequential_controls_conditions.tex
  sorting_did_wage_indices.tex sorting_intensity_wage_indices.tex qoe_sorting_did_occupation_indices.tex qoe_sorting_intensity_occupation_indices.tex
  qoe_sorting_did_exclude_small_occupations.tex qoe_sorting_intensity_exclude_small_occupations.tex
  sorting_gender_age_tenure_robustness.tex sorting_gender_specific_post_changes.tex
  robustness_weighted_table.tex
  few_clusters_webb_comparison.tex leave_one_cohort_out_summary.tex
  leave_one_cohort_out_binary.png leave_one_cohort_out_intensity.png
  employment_gender_gap_decomposition.tex employment_gap_segmented_trend.tex
  employment_gender_cohort_raw_profiles.png employment_gender_gap_raw_standardized.png employment_gap_segmented_fitted_paths.png
  enlistage_commoncohort_did.tex enlistage_commoncohort_intensity.tex enlistage_commoncohort_eventstudy_pretrend_pvalues.csv
  enlistage19_commoncohort_eventstudy_employed.png enlistage19_commoncohort_eventstudy_entry_age.png
  enlistage20_commoncohort_eventstudy_employed.png enlistage20_commoncohort_eventstudy_entry_age.png
  enlistage21_commoncohort_eventstudy_employed.png enlistage21_commoncohort_eventstudy_entry_age.png
  enlistage_qoe_composite_table.tex enlistage_qoe_composite_figure.pdf enlistage_qoe_composite_figure.png
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
  case "$file" in
    *.tex)
      destination="$paper_root/tables"
      ;;
    *.png)
      destination="$paper_root/figures"
      ;;
    *)
      destination="$paper_root"
      ;;
  esac

  mkdir -p "$destination"
  cp "$output_root/$file" "$destination/$file"
  echo "Synced $file to $destination"
done

echo
echo "Paper outputs updated. Review them before committing:"
echo "  git -C \"$paper_root\" status --short"
echo "  git -C \"$paper_root\" diff --stat"
