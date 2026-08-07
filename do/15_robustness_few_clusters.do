****************************************************
* 15. Robustness: few birth-cohort clusters
*
* This supplementary analysis does two things:
*   1. compares the baseline Rademacher wild-cluster-bootstrap p-value
*      with a 9,999-replication Webb-weight p-value; and
*   2. re-estimates each main specification after omitting one of the
*      1992-2002 birth cohorts in turn.
*
* The leave-one-cohort-out exercise is an influence diagnostic. Because
* every omitted-cohort regression has only 10 clusters, coefficient signs
* and magnitudes are the primary diagnostic; its Webb p-values are secondary.
*
* Run after:
*   00_globals.do
*   01_clean_all.do
*   02_append.do
*   05_build_qoe_outcomes.do
*
* Required package:
*   ssc install boottest, replace
****************************************************

clear all
set more off
set varabbrev off

capture confirm global CLEAN
if _rc global CLEAN "data_clean"

capture confirm global OUT
if _rc global OUT "`c(pwd)'/output"
else if substr("$OUT",1,1)!="/" & substr("$OUT",2,1)!=":" {
    global OUT "`c(pwd)'/$OUT"
}

capture mkdir "$OUT"

local run_date = subinstr("`c(current_date)'", " ", "", .)
local run_time = subinstr("`c(current_time)'", ":", "", .)
capture log close fewclusters15
log using "$OUT/15_robustness_few_clusters_`run_date'_`run_time'.log", ///
    text name(fewclusters15)

capture which boottest
if _rc {
    display as error "boottest is required. Install it with: ssc install boottest"
    exit 199
}

capture confirm file "$CLEAN/mdis_master_2001_2025.dta"
if _rc {
    display as error "Main analysis dataset not found: $CLEAN/mdis_master_2001_2025.dta"
    exit 601
}

capture confirm file "$CLEAN/mdis_master_qoe_2001_2025.dta"
if _rc {
    display as error "QoE analysis dataset not found: $CLEAN/mdis_master_qoe_2001_2025.dta"
    exit 601
}

tempfile full_results loo_results
tempname full_handle loo_handle

postfile `full_handle' byte outcome_order str12 outcome_group ///
    str40 outcome str44 outcome_label byte spec_order ///
    str16 specification double beta cluster_se rademacher_p webb_p ///
    long N byte N_clusters using `full_results', replace

postfile `loo_handle' byte outcome_order str12 outcome_group ///
    str40 outcome str44 outcome_label byte spec_order ///
    str16 specification int omitted_cohort double full_beta beta ///
    cluster_se webb_p delta pct_change byte sign_flip long N ///
    byte N_clusters using `loo_results', replace

****************************************************
* 1. Employment and current-job entry age
****************************************************

use "$CLEAN/mdis_master_2001_2025.dta", clear

foreach v in year age male birth_year educ_raw survey_ym experience_raw ///
    employed wage_worker {
    capture confirm variable `v'
    if _rc {
        display as error "Required main-analysis variable `v' not found."
        exit 111
    }
}

* Match the sample and cohort exposure definitions in 03_analysis.do.
keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year)

gen cohort = birth_year
gen rel_cohort = birth_year - 1997
keep if inrange(rel_cohort, -5, 5)

gen byte post_military = birth_year >= 1997
gen double service_months_saved = 0 if birth_year <= 1996
replace service_months_saved = 0.75 if birth_year == 1997
replace service_months_saved = 1.50 if birth_year == 1998
replace service_months_saved = 2.25 if birth_year == 1999
replace service_months_saved = 3.00 if birth_year >= 2000

* Reconstruct current-job entry age exactly as in 03_analysis.do.
gen job_start_year = floor(experience_raw/100) if experience_raw < .
gen job_start_month = mod(experience_raw,100) if experience_raw < .
replace job_start_year = . if job_start_year < 1900 | job_start_year > year
replace job_start_month = . if !inrange(job_start_month,1,12)

gen survey_year_from_ym = floor(survey_ym/100) if survey_ym < .
gen survey_month_from_ym = mod(survey_ym,100) if survey_ym < .
replace survey_year_from_ym = year if missing(survey_year_from_ym)
replace survey_month_from_ym = 8 if missing(survey_month_from_ym) ///
    | !inrange(survey_month_from_ym,1,12)

gen job_start_tm = ym(job_start_year, job_start_month)
gen survey_tm = ym(survey_year_from_ym, survey_month_from_ym)
gen job_tenure_months = survey_tm - job_start_tm ///
    if !missing(job_start_tm, survey_tm)
replace job_tenure_months = . if job_tenure_months < 0
gen entry_age = age - job_tenure_months/12 ///
    if !missing(age, job_tenure_months)
replace entry_age = . if entry_age < 10 | entry_age > age

local controls i.educ_raw i.year

forvalues outcome_index = 1/2 {
    if `outcome_index' == 1 {
        local outcome_order 1
        local yvar entry_age
        local outcome_label "Current-job entry age"
        local sample_if "wage_worker == 1"
    }
    else {
        local outcome_order 2
        local yvar employed
        local outcome_label "Employed"
        local sample_if "1"
    }

    forvalues spec = 1/2 {
        if `spec' == 1 {
            local specification "Binary DiD"
            local treatment "i.post_military"
            local interaction "1.male#1.post_military"
        }
        else {
            local specification "Intensity"
            local treatment "c.service_months_saved"
            local interaction "1.male#c.service_months_saved"
        }

        quietly reg `yvar' i.male##`treatment' `controls' ///
            if `sample_if', vce(cluster cohort)
        scalar full_beta = _b[`interaction']
        scalar full_se = _se[`interaction']
        scalar full_N = e(N)
        quietly levelsof cohort if e(sample), local(full_clusters)
        local full_G : word count `full_clusters'

        capture noisily boottest `interaction', cluster(cohort) ///
            reps(9999) seed(12345) nograph noci
        scalar p_rademacher = .
        if !_rc scalar p_rademacher = r(p)

        capture noisily boottest `interaction', cluster(cohort) ///
            weight(webb) reps(9999) seed(12345) nograph noci
        scalar p_webb = .
        if !_rc scalar p_webb = r(p)

        post `full_handle' (`outcome_order') ("Entry") ("`yvar'") ///
            ("`outcome_label'") (`spec') ("`specification'") ///
            (full_beta) (full_se) (p_rademacher) (p_webb) ///
            (full_N) (`full_G')

        forvalues omitted = 1992/2002 {
            quietly reg `yvar' i.male##`treatment' `controls' ///
                if `sample_if' & cohort != `omitted', vce(cluster cohort)
            scalar loo_beta = _b[`interaction']
            scalar loo_se = _se[`interaction']
            scalar loo_N = e(N)
            quietly levelsof cohort if e(sample), local(loo_clusters)
            local loo_G : word count `loo_clusters'

            capture noisily boottest `interaction', cluster(cohort) ///
                weight(webb) reps(9999) seed(12345) nograph noci
            scalar loo_webb_p = .
            if !_rc scalar loo_webb_p = r(p)
            scalar loo_delta = loo_beta - full_beta
            scalar loo_pct = cond(full_beta == 0, ., ///
                100 * loo_delta / abs(full_beta))
            scalar loo_flip = sign(loo_beta) != sign(full_beta)

            post `loo_handle' (`outcome_order') ("Entry") ("`yvar'") ///
                ("`outcome_label'") (`spec') ("`specification'") ///
                (`omitted') (full_beta) (loo_beta) (loo_se) ///
                (loo_webb_p) (loo_delta) (loo_pct) (loo_flip) ///
                (loo_N) (`loo_G')
        }
    }
}

****************************************************
* 2. Primary QoE outcomes
****************************************************

use "$CLEAN/mdis_master_qoe_2001_2025.dta", clear

foreach v in year age male birth_year educ_raw wage_worker qoe_complete ///
    qoe_deprivation_score50 qoe_multidim_deprived50 ///
    qoe_income_deprivation50 qoe_stability_deprivation ///
    qoe_conditions_deprivation {
    capture confirm variable `v'
    if _rc {
        display as error "Required QoE variable `v' not found."
        exit 111
    }
}

* Match the sample, treatment, and controls in 06_analysis_qoe.do.
keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year)

gen cohort = birth_year
gen rel_cohort = birth_year - 1997
keep if inrange(rel_cohort, -5, 5)

gen byte post_military = birth_year >= 1997
gen double service_months_saved = 0 if birth_year <= 1996
replace service_months_saved = 0.75 if birth_year == 1997
replace service_months_saved = 1.50 if birth_year == 1998
replace service_months_saved = 2.25 if birth_year == 1999
replace service_months_saved = 3.00 if birth_year >= 2000

local controls_qoe i.educ_raw i.year
local qoe_outcomes qoe_deprivation_score50 qoe_multidim_deprived50 ///
    qoe_income_deprivation50 qoe_stability_deprivation ///
    qoe_conditions_deprivation
local qoe_labels `""QoE deprivation score" "Multidimensional deprivation" "Income deprivation" "Stability deprivation" "Conditions deprivation""'

local qoe_index = 1
foreach yvar of local qoe_outcomes {
    local outcome_order = `qoe_index' + 2
    local outcome_label : word `qoe_index' of `qoe_labels'

    forvalues spec = 1/2 {
        if `spec' == 1 {
            local specification "Binary DiD"
            local treatment "i.post_military"
            local interaction "1.male#1.post_military"
        }
        else {
            local specification "Intensity"
            local treatment "c.service_months_saved"
            local interaction "1.male#c.service_months_saved"
        }

        quietly reg `yvar' i.male##`treatment' `controls_qoe' ///
            if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
        scalar full_beta = _b[`interaction']
        scalar full_se = _se[`interaction']
        scalar full_N = e(N)
        quietly levelsof cohort if e(sample), local(full_clusters)
        local full_G : word count `full_clusters'

        capture noisily boottest `interaction', cluster(cohort) ///
            reps(9999) seed(12345) nograph noci
        scalar p_rademacher = .
        if !_rc scalar p_rademacher = r(p)

        capture noisily boottest `interaction', cluster(cohort) ///
            weight(webb) reps(9999) seed(12345) nograph noci
        scalar p_webb = .
        if !_rc scalar p_webb = r(p)

        post `full_handle' (`outcome_order') ("QoE") ("`yvar'") ///
            ("`outcome_label'") (`spec') ("`specification'") ///
            (full_beta) (full_se) (p_rademacher) (p_webb) ///
            (full_N) (`full_G')

        forvalues omitted = 1992/2002 {
            quietly reg `yvar' i.male##`treatment' `controls_qoe' ///
                if wage_worker == 1 & qoe_complete == 1 ///
                & cohort != `omitted', vce(cluster cohort)
            scalar loo_beta = _b[`interaction']
            scalar loo_se = _se[`interaction']
            scalar loo_N = e(N)
            quietly levelsof cohort if e(sample), local(loo_clusters)
            local loo_G : word count `loo_clusters'

            capture noisily boottest `interaction', cluster(cohort) ///
                weight(webb) reps(9999) seed(12345) nograph noci
            scalar loo_webb_p = .
            if !_rc scalar loo_webb_p = r(p)
            scalar loo_delta = loo_beta - full_beta
            scalar loo_pct = cond(full_beta == 0, ., ///
                100 * loo_delta / abs(full_beta))
            scalar loo_flip = sign(loo_beta) != sign(full_beta)

            post `loo_handle' (`outcome_order') ("QoE") ("`yvar'") ///
                ("`outcome_label'") (`spec') ("`specification'") ///
                (`omitted') (full_beta) (loo_beta) (loo_se) ///
                (loo_webb_p) (loo_delta) (loo_pct) (loo_flip) ///
                (loo_N) (`loo_G')
        }
    }
    local ++qoe_index
}

postclose `full_handle'
postclose `loo_handle'

****************************************************
* 3. Export full-sample bootstrap comparison
****************************************************

use `full_results', clear
sort outcome_order spec_order
order outcome_group outcome outcome_label specification beta cluster_se ///
    rademacher_p webb_p N N_clusters
export delimited using "$OUT/few_clusters_webb_comparison.csv", replace
save "$OUT/few_clusters_webb_comparison.dta", replace

* Compact appendix table: coefficient and bootstrap p-values under the two
* treatment specifications. The coefficient is unchanged across bootstrap
* weight choices; only the p-value columns differ.
matrix webb_comparison_table = J(7, 6, .)
forvalues o = 1/7 {
    quietly summarize beta if outcome_order == `o' & spec_order == 1, meanonly
    matrix webb_comparison_table[`o',1] = r(mean)
    quietly summarize rademacher_p if outcome_order == `o' & spec_order == 1, meanonly
    matrix webb_comparison_table[`o',2] = r(mean)
    quietly summarize webb_p if outcome_order == `o' & spec_order == 1, meanonly
    matrix webb_comparison_table[`o',3] = r(mean)
    quietly summarize beta if outcome_order == `o' & spec_order == 2, meanonly
    matrix webb_comparison_table[`o',4] = r(mean)
    quietly summarize rademacher_p if outcome_order == `o' & spec_order == 2, meanonly
    matrix webb_comparison_table[`o',5] = r(mean)
    quietly summarize webb_p if outcome_order == `o' & spec_order == 2, meanonly
    matrix webb_comparison_table[`o',6] = r(mean)
}
matrix rownames webb_comparison_table = entry_age employed qoe_score ///
    multidimensional income stability conditions
matrix colnames webb_comparison_table = did_beta did_rademacher_p ///
    did_webb_p intensity_beta intensity_rademacher_p intensity_webb_p

capture which esttab
if !_rc {
    esttab matrix(webb_comparison_table, ///
        fmt(%9.4f %9.3f %9.3f %9.4f %9.3f %9.3f)) ///
        using "$OUT/few_clusters_webb_comparison.tex", replace ///
        coeflabels(entry_age "Entry age" employed "Employed" ///
            qoe_score "QoE score" multidimensional "Multidimensional" ///
            income "Income" stability "Stability" ///
            conditions "Conditions") ///
        collabels("DiD coefficient" "Rademacher p" "Webb p" ///
            "Intensity coefficient" "Rademacher p" "Webb p") ///
        mlabels(none) ///
        booktabs nonumber noobs fragment ///
        addnotes("All specifications use 11 birth-cohort clusters." ///
            "Rademacher p-values enumerate all 2,048 assignments; Webb p-values use 9,999 replications with seed 12345.")
}

****************************************************
* 4. Export leave-one-cohort-out results and summary
****************************************************

use `loo_results', clear
sort outcome_order spec_order omitted_cohort
order outcome_group outcome outcome_label specification omitted_cohort ///
    full_beta beta cluster_se webb_p delta pct_change sign_flip N N_clusters
export delimited using "$OUT/leave_one_cohort_out_results.csv", replace
save "$OUT/leave_one_cohort_out_results.dta", replace

* Identify the omitted cohort producing the largest absolute coefficient
* change, then construct one summary row per outcome and specification.
gen double abs_delta = abs(delta)
gen double abs_pct_change = abs(pct_change)
bysort outcome_order spec_order (abs_delta): gen int most_influential_cohort = ///
    omitted_cohort[_N]

collapse (firstnm) outcome_group outcome outcome_label specification ///
    full_beta most_influential_cohort ///
    (min) min_beta=beta min_webb_p=webb_p ///
    (max) max_beta=beta max_abs_pct_change=abs_pct_change ///
        max_webb_p=webb_p ///
    (sum) sign_flips=sign_flip, by(outcome_order spec_order)

sort outcome_order spec_order
order outcome_group outcome outcome_label specification full_beta ///
    min_beta max_beta max_abs_pct_change sign_flips ///
    most_influential_cohort min_webb_p max_webb_p
export delimited using "$OUT/leave_one_cohort_out_summary.csv", replace
save "$OUT/leave_one_cohort_out_summary.dta", replace

* Appendix summary table with one row per outcome and treatment specification.
matrix loo_summary_table = J(14, 8, .)
forvalues r = 1/14 {
    matrix loo_summary_table[`r',1] = full_beta[`r']
    matrix loo_summary_table[`r',2] = min_beta[`r']
    matrix loo_summary_table[`r',3] = max_beta[`r']
    matrix loo_summary_table[`r',4] = max_abs_pct_change[`r']
    matrix loo_summary_table[`r',5] = sign_flips[`r']
    matrix loo_summary_table[`r',6] = most_influential_cohort[`r']
    matrix loo_summary_table[`r',7] = min_webb_p[`r']
    matrix loo_summary_table[`r',8] = max_webb_p[`r']
}
matrix rownames loo_summary_table = entry_did entry_intensity ///
    employed_did employed_intensity score_did score_intensity ///
    multidim_did multidim_intensity income_did income_intensity ///
    stability_did stability_intensity conditions_did conditions_intensity
matrix colnames loo_summary_table = full_beta min_beta max_beta ///
    max_abs_pct_change sign_flips influential_cohort min_webb_p max_webb_p

capture which esttab
if !_rc {
    esttab matrix(loo_summary_table, ///
        fmt(%9.4f %9.4f %9.4f %9.1f %9.0f %9.0f %9.3f %9.3f)) ///
        using "$OUT/leave_one_cohort_out_summary.tex", replace ///
        coeflabels(entry_did "Entry age: DiD" ///
            entry_intensity "Entry age: intensity" ///
            employed_did "Employed: DiD" ///
            employed_intensity "Employed: intensity" ///
            score_did "QoE score: DiD" ///
            score_intensity "QoE score: intensity" ///
            multidim_did "Multidimensional: DiD" ///
            multidim_intensity "Multidimensional: intensity" ///
            income_did "Income: DiD" income_intensity "Income: intensity" ///
            stability_did "Stability: DiD" ///
            stability_intensity "Stability: intensity" ///
            conditions_did "Conditions: DiD" ///
            conditions_intensity "Conditions: intensity") ///
        collabels("Full" "LOO min." "LOO max." "Max. change (pct.)" ///
            "Sign flips" "Most influential cohort" ///
            "Min. Webb p" "Max. Webb p") ///
        mlabels(none) ///
        booktabs nonumber noobs fragment ///
        addnotes("Each leave-one-out estimate omits one 1992--2002 birth cohort and uses the remaining 10 clusters." ///
            "Webb p-values use 9,999 replications with seed 12345; coefficient stability is the primary diagnostic.")
}

****************************************************
* 5. Normalized influence plots
*
* beta_ratio = 1 means the leave-one-out coefficient equals the full-sample
* estimate. Ratios preserve comparability across outcomes with different units.
****************************************************

use "$OUT/leave_one_cohort_out_results.dta", clear
gen double beta_ratio = beta / full_beta

forvalues spec = 1/2 {
    if `spec' == 1 local plot_stem binary
    if `spec' == 1 local plot_title "Leave-one-cohort-out: binary DiD"
    if `spec' == 2 local plot_stem intensity
    if `spec' == 2 local plot_title "Leave-one-cohort-out: intensity"

    twoway ///
        (connected beta_ratio omitted_cohort if outcome_order == 1 ///
            & spec_order == `spec', msymbol(O)) ///
        (connected beta_ratio omitted_cohort if outcome_order == 2 ///
            & spec_order == `spec', msymbol(T)) ///
        (connected beta_ratio omitted_cohort if outcome_order == 3 ///
            & spec_order == `spec', msymbol(S)) ///
        (connected beta_ratio omitted_cohort if outcome_order == 4 ///
            & spec_order == `spec', msymbol(D)) ///
        (connected beta_ratio omitted_cohort if outcome_order == 5 ///
            & spec_order == `spec', msymbol(+)) ///
        (connected beta_ratio omitted_cohort if outcome_order == 6 ///
            & spec_order == `spec', msymbol(X)) ///
        (connected beta_ratio omitted_cohort if outcome_order == 7 ///
            & spec_order == `spec', msymbol(Oh)), ///
        yline(1, lpattern(dash) lcolor(gs8)) ///
        yline(0, lpattern(shortdash) lcolor(red)) ///
        xlabel(1992(1)2002, angle(45)) ///
        xtitle("Omitted birth cohort") ///
        ytitle("Leave-one-out coefficient / full-sample coefficient") ///
        title("`plot_title'") ///
        legend(order(1 "Entry age" 2 "Employed" 3 "QoE score" ///
            4 "Multidimensional" 5 "Income" 6 "Stability" ///
            7 "Conditions") position(6) cols(4) size(small))

    graph export "$OUT/leave_one_cohort_out_`plot_stem'.png", replace
}

display as text "Few-cluster robustness analysis completed."
display as text "Full-sample comparison: $OUT/few_clusters_webb_comparison.csv"
display as text "Full-sample LaTeX table: $OUT/few_clusters_webb_comparison.tex"
display as text "Leave-one-out results: $OUT/leave_one_cohort_out_results.csv"
display as text "Leave-one-out summary: $OUT/leave_one_cohort_out_summary.csv"
display as text "Leave-one-out LaTeX table: $OUT/leave_one_cohort_out_summary.tex"

log close fewclusters15
****************************************************
* End
****************************************************
