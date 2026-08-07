****************************************************
* 08. Mechanism analysis: sorting into occupations with better QoE
* 2018 military-service reduction
*
* Run after:
*   00_globals.do
*   01_clean_all.do
*   02_append.do
*   05_build_qoe_outcomes.do
*
* This supplementary file does not modify the master dataset. It assigns
* workers the QoE deprivation level of their observed occupation, measured
* only in 2015-2017, and tests whether exposed men sort toward occupations
* with better pre-reform QoE. Lower index values mean better job quality.
****************************************************

clear all
set more off
set varabbrev off

capture confirm global CLEAN
if _rc {
    global CLEAN "data_clean"
}

capture confirm global OUT
if _rc {
    global OUT "`c(pwd)'/output"
}
else {
    if substr("$OUT",1,1)!="/" & substr("$OUT",2,1)!=":" {
        global OUT "`c(pwd)'/$OUT"
    }
}

capture mkdir "$OUT"
display as text "Output folder: $OUT"

capture program drop attach_wild_p
program define attach_wild_p
    syntax name(name=model), TERM(string)
    estimates restore `model'
    tempname wild_pvals
    matrix `wild_pvals' = e(b)
    forvalues j = 1/`=colsof(`wild_pvals')' {
        matrix `wild_pvals'[1,`j'] = .
    }
    local target_col = colnumb(`wild_pvals', "`term'")
    if missing(`target_col') {
        display as error "Term `term' not found in stored model `model'."
        exit 111
    }
    matrix `wild_pvals'[1,`target_col'] = e(boot_p)
    estadd matrix wild_pvals = `wild_pvals', replace
    estimates drop `model'
    estimates store `model'
end

capture confirm file "$CLEAN/mdis_master_qoe_2001_2025.dta"
if _rc {
    display as error "QoE master file not found: $CLEAN/mdis_master_qoe_2001_2025.dta"
    display as error "Run 05_build_qoe_outcomes.do before this file."
    exit 601
}

use "$CLEAN/mdis_master_qoe_2001_2025.dta", clear

* 05_build_qoe_outcomes.do currently saves two Stata tempvars (__000000 and
* __000001) in the QoE master. Remove saved internal work variables from the
* in-memory analysis copy before commands such as areg/egen allocate tempvars.
capture drop __*

foreach v in year age male birth_year wage_worker popwt educ_raw ///
    experience_raw survey_ym occupation_code industry_code qoe_complete ///
    qoe_deprivation_score50 qoe_income_deprivation50 ///
    qoe_stability_deprivation qoe_conditions_deprivation {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found."
        exit 111
    }
}

****************************************************
* 1. Current-job tenure for adjusted pre-reform occupation premiums
****************************************************

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
gen job_tenure_years = job_tenure_months/12 if job_tenure_months < .

****************************************************
* 2. Freeze occupation QoE rankings in 2015-2017
*
* Raw index: population-weighted occupation mean.
* Adjusted index: absorbed occupation premium after controlling for
* education, current-job tenure, and year in the pre-reform sample.
* All indices are deprivation measures: lower values mean better QoE.
****************************************************

local qoe_outcomes qoe_deprivation_score50 qoe_income_deprivation50 ///
    qoe_stability_deprivation qoe_conditions_deprivation
local qoe_stems score income stability conditions

tempfile qoe_pre_sample idx_score idx_income idx_stability idx_conditions ///
    occupation_qoe_index

preserve
    keep if inrange(year, 2015, 2017)
    keep if inrange(age, 18, 39)
    keep if wage_worker == 1 & qoe_complete == 1
    keep if !missing(popwt, occupation_code) & popwt > 0
    save `qoe_pre_sample', replace
restore

local i = 1
foreach yvar of local qoe_outcomes {
    local stem : word `i' of `qoe_stems'

    preserve
        use `qoe_pre_sample', clear
        keep if !missing(`yvar')

        areg `yvar' i.educ_raw c.job_tenure_years i.year [pw=popwt], ///
            absorb(occupation_code)
        predict double occupation_qoe_adjusted if e(sample), d

        * areg may leave internal __* work variables that conflict with
        * later data-management commands. Retain only required variables.
        keep occupation_code `yvar' occupation_qoe_adjusted popwt

        * Compute weighted occupation means explicitly. This is equivalent
        * to weighted collapse but avoids Stata's internal __000000 conflict
        * when mean and max statistics are combined after areg.
        bysort occupation_code: gen long occupation_pre_n = _N

        gen double raw_weight = popwt if !missing(`yvar')
        gen double raw_weighted_value = raw_weight * `yvar'
        bysort occupation_code: egen double raw_weight_sum = ///
            total(raw_weight)
        bysort occupation_code: egen double raw_value_sum = ///
            total(raw_weighted_value)
        gen double occ_qoe_`stem'_raw = raw_value_sum / raw_weight_sum

        gen double adjusted_weight = popwt ///
            if !missing(occupation_qoe_adjusted)
        gen double adjusted_weighted_value = ///
            adjusted_weight * occupation_qoe_adjusted
        bysort occupation_code: egen double adjusted_weight_sum = ///
            total(adjusted_weight)
        bysort occupation_code: egen double adjusted_value_sum = ///
            total(adjusted_weighted_value)
        gen double occ_qoe_`stem'_adjusted = ///
            adjusted_value_sum / adjusted_weight_sum

        bysort occupation_code: keep if _n == 1
        rename occupation_pre_n occ_qoe_`stem'_pre_n
        keep occupation_code occ_qoe_`stem'_raw ///
            occ_qoe_`stem'_adjusted occ_qoe_`stem'_pre_n
        isid occupation_code
        save `idx_`stem'', replace
    restore

    local ++i
}

preserve
    use `idx_score', clear
    merge 1:1 occupation_code using `idx_income', assert(3) nogen
    merge 1:1 occupation_code using `idx_stability', assert(3) nogen
    merge 1:1 occupation_code using `idx_conditions', assert(3) nogen
    isid occupation_code
    save `occupation_qoe_index', replace
    export delimited using ///
        "$OUT/qoe_sorting_preperiod_occupation_indices.csv", replace
restore

****************************************************
* 3. Main cohort sample and frozen-index matching
****************************************************

keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year)

gen cohort = birth_year
gen rel_cohort = birth_year - 1997
keep if inrange(rel_cohort, -5, 5)
gen rel_shift = rel_cohort + 5

gen byte post_military = birth_year >= 1997 if !missing(birth_year)
gen double service_months_saved = .
replace service_months_saved = 0 if birth_year <= 1996
replace service_months_saved = 0.75 if birth_year == 1997
replace service_months_saved = 1.50 if birth_year == 1998
replace service_months_saved = 2.25 if birth_year == 1999
replace service_months_saved = 3.00 if birth_year >= 2000

merge m:1 occupation_code using `occupation_qoe_index', ///
    keep(master match) gen(merge_qoe_occupation_index)

* Matching diagnostics use all wage workers. Individual QoE completeness is
* not required because the outcome is the occupation's frozen QoE index.
preserve
    keep if wage_worker == 1
    gen byte qoe_occupation_index_matched = ///
        merge_qoe_occupation_index == 3
    collapse (count) wage_worker_n=wage_worker ///
        (mean) occupation_match_rate=qoe_occupation_index_matched, ///
        by(year male)
    sort year male
    export delimited using ///
        "$OUT/qoe_sorting_index_match_diagnostics.csv", replace
restore

summ occ_qoe_score_raw occ_qoe_score_adjusted ///
    occ_qoe_income_raw occ_qoe_income_adjusted ///
    occ_qoe_stability_raw occ_qoe_stability_adjusted ///
    occ_qoe_conditions_raw occ_qoe_conditions_adjusted ///
    if wage_worker == 1

****************************************************
* 4. DiD and treatment-intensity regressions
*
* Negative Male x Post coefficients mean exposed men moved toward
* occupations with lower pre-reform deprivation and therefore better QoE.
****************************************************

local index_outcomes occ_qoe_score_raw occ_qoe_score_adjusted ///
    occ_qoe_income_raw occ_qoe_income_adjusted ///
    occ_qoe_stability_raw occ_qoe_stability_adjusted ///
    occ_qoe_conditions_raw occ_qoe_conditions_adjusted
local index_stems score_raw score_adj income_raw income_adj ///
    stability_raw stability_adj conditions_raw conditions_adj

* Occupations with fewer than 200 complete pre-reform observations are
* excluded in the small-cell robustness specification. With the current
* data this excludes managers (117) and skilled agriculture (41).
local min_preoccupation_n = 200

estimates clear
local i = 1
foreach yvar of local index_outcomes {
    local stem : word `i' of `index_stems'

    reg `yvar' i.male##i.post_military i.educ_raw i.year ///
        if wage_worker == 1, vce(cluster cohort)
    estimates store qsort_`stem'
    boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_qsort_`stem' = r(p)
    estadd scalar boot_p = boot_p_qsort_`stem' : qsort_`stem'

    reg `yvar' i.male##c.service_months_saved i.educ_raw i.year ///
        if wage_worker == 1, vce(cluster cohort)
    estimates store qsorti_`stem'
    boottest 1.male#c.service_months_saved, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_qsorti_`stem' = r(p)
    estadd scalar boot_p = boot_p_qsorti_`stem' : qsorti_`stem'

    * Small-cell robustness: keep only occupations with sufficiently large
    * 2015-2017 QoE reference samples. The score count is common across all
    * four QoE dimensions because the index uses qoe_complete observations.
    reg `yvar' i.male##i.post_military i.educ_raw i.year ///
        if wage_worker == 1 ///
        & occ_qoe_score_pre_n >= `min_preoccupation_n', ///
        vce(cluster cohort)
    estimates store qsortx_`stem'
    boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_qsortx_`stem' = r(p)
    estadd scalar boot_p = boot_p_qsortx_`stem' : qsortx_`stem'

    reg `yvar' i.male##c.service_months_saved i.educ_raw i.year ///
        if wage_worker == 1 ///
        & occ_qoe_score_pre_n >= `min_preoccupation_n', ///
        vce(cluster cohort)
    estimates store qsortix_`stem'
    boottest 1.male#c.service_months_saved, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_qsortix_`stem' = r(p)
    estadd scalar boot_p = boot_p_qsortix_`stem' : qsortix_`stem'

    local ++i
}

****************************************************
* 5. Individual QoE with sequential post-treatment job controls
*
* These diagnostic specifications separate the total relative QoE change
* from the conditional change within current occupation. Job tenure,
* occupation, and industry may respond to reform exposure, so columns after
* the baseline are mechanism/within-job estimates rather than total effects.
* A common complete sample ensures coefficient changes are not caused by
* changing observations as controls are added.
****************************************************

gen byte qoe_within_common = wage_worker == 1 & qoe_complete == 1 ///
    & !missing(educ_raw, job_tenure_years, occupation_code, industry_code)

local qoe_within_outcomes qoe_deprivation_score50 ///
    qoe_income_deprivation50 qoe_stability_deprivation ///
    qoe_conditions_deprivation
local qoe_within_stems score income stability conditions

local qoe_within_controls_1 i.educ_raw i.year
local qoe_within_controls_2 c.job_tenure_years i.educ_raw i.year
local qoe_within_controls_3 c.job_tenure_years i.educ_raw i.year ///
    i.occupation_code
local qoe_within_controls_4 c.job_tenure_years i.educ_raw i.year ///
    i.occupation_code i.industry_code

local i = 1
foreach yvar of local qoe_within_outcomes {
    local stem : word `i' of `qoe_within_stems'

    forvalues s = 1/4 {
        reg `yvar' i.male##i.post_military `qoe_within_controls_`s'' ///
            if qoe_within_common == 1, vce(cluster cohort)
        estimates store qwithin_`stem'_s`s'
        boottest 1.male#1.post_military, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        scalar boot_p_qwithin_`stem'_s`s' = r(p)
        estadd scalar boot_p = boot_p_qwithin_`stem'_s`s' : ///
            qwithin_`stem'_s`s'
    }

    local ++i
}

****************************************************
* 6. Event studies and wild-bootstrap pre-trend tests
****************************************************

postfile qoe_sorting_pretrend str32 outcome double wild_p_pretrend ///
    using "$OUT/qoe_sorting_eventstudy_pretrend_pvalues.dta", replace

local i = 1
foreach yvar of local index_outcomes {
    local stem : word `i' of `index_stems'

    reg `yvar' i.male##ib4.rel_shift i.educ_raw i.year ///
        if wage_worker == 1, vce(cluster cohort)

    capture noisily boottest 1.male#0.rel_shift 1.male#1.rel_shift ///
        1.male#2.rel_shift 1.male#3.rel_shift, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    if !_rc scalar qoe_sorting_pretrend_p = r(p)
    else scalar qoe_sorting_pretrend_p = .
    post qoe_sorting_pretrend ("`yvar'") (qoe_sorting_pretrend_p)

    tempfile qoe_sorting_coef_`stem'
    postfile qoe_sorting_handle str32 outcome int rel_cohort ///
        double beta cluster_se lb ub ///
        using "`qoe_sorting_coef_`stem''", replace

    forvalues k = -5/5 {
        local s = `k' + 5
        if `k' == -1 {
            post qoe_sorting_handle ("`yvar'") (`k') (0) (0) (0) (0)
        }
        else {
            lincom 1.male#`s'.rel_shift
            scalar qoe_sorting_beta = r(estimate)
            scalar qoe_sorting_se = r(se)
            scalar qoe_sorting_lb = ///
                qoe_sorting_beta - invnormal(.975) * qoe_sorting_se
            scalar qoe_sorting_ub = ///
                qoe_sorting_beta + invnormal(.975) * qoe_sorting_se
            post qoe_sorting_handle ("`yvar'") (`k') ///
                (qoe_sorting_beta) (qoe_sorting_se) ///
                (qoe_sorting_lb) (qoe_sorting_ub)
        }
    }
    postclose qoe_sorting_handle

    preserve
        use "`qoe_sorting_coef_`stem''", clear
        sort rel_cohort
        export delimited using ///
            "$OUT/qoe_sorting_eventstudy_`stem'.csv", replace
    restore

    local ++i
}
postclose qoe_sorting_pretrend

preserve
    use "$OUT/qoe_sorting_eventstudy_pretrend_pvalues.dta", clear
    export delimited using ///
        "$OUT/qoe_sorting_eventstudy_pretrend_pvalues.csv", replace
restore

****************************************************
* 7. Export tables
****************************************************

capture which esttab
if !_rc {

    foreach stem in score_raw score_adj income_raw income_adj ///
        stability_raw stability_adj conditions_raw conditions_adj {
        attach_wild_p qsort_`stem', term("1.male#1.post_military")
        attach_wild_p qsorti_`stem', ///
            term("1.male#c.service_months_saved")
        attach_wild_p qsortx_`stem', term("1.male#1.post_military")
        attach_wild_p qsortix_`stem', ///
            term("1.male#c.service_months_saved")
    }

    foreach stem in score income stability conditions {
        forvalues s = 1/4 {
            attach_wild_p qwithin_`stem'_s`s', ///
                term("1.male#1.post_military")
        }
    }
    esttab qsort_score_raw qsort_score_adj ///
        qsort_income_raw qsort_income_adj ///
        qsort_stability_raw qsort_stability_adj ///
        qsort_conditions_raw qsort_conditions_adj ///
        using "$OUT/qoe_sorting_did_occupation_indices.tex", replace ///
        keep(1.male#1.post_military) ///
        coeflabels(1.male#1.post_military ///
            "Post-reform \$\times\$ Male") ///
        mtitles("Score raw" "Score adjusted" ///
            "Income raw" "Income adjusted" ///
            "Stability raw" "Stability adjusted" ///
            "Conditions raw" "Conditions adjusted") ///
        cells(b(star pvalue(wild_pvals) fmt(a3)) se(par fmt(a3))) ///
        collabels(none) ///
        starlevels(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    esttab qsorti_score_raw qsorti_score_adj ///
        qsorti_income_raw qsorti_income_adj ///
        qsorti_stability_raw qsorti_stability_adj ///
        qsorti_conditions_raw qsorti_conditions_adj ///
        using "$OUT/qoe_sorting_intensity_occupation_indices.tex", replace ///
        keep(1.male#c.service_months_saved) ///
        coeflabels(1.male#c.service_months_saved ///
            "Months saved \$\times\$ Male") ///
        mtitles("Score raw" "Score adjusted" ///
            "Income raw" "Income adjusted" ///
            "Stability raw" "Stability adjusted" ///
            "Conditions raw" "Conditions adjusted") ///
        cells(b(star pvalue(wild_pvals) fmt(a3)) se(par fmt(a3))) ///
        collabels(none) ///
        starlevels(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    * Small-cell robustness: occupations with pre-reform N >= 200.
    esttab qsortx_score_raw qsortx_score_adj ///
        qsortx_income_raw qsortx_income_adj ///
        qsortx_stability_raw qsortx_stability_adj ///
        qsortx_conditions_raw qsortx_conditions_adj ///
        using "$OUT/qoe_sorting_did_exclude_small_occupations.tex", replace ///
        keep(1.male#1.post_military) ///
        coeflabels(1.male#1.post_military ///
            "Post-reform \$\times\$ Male") ///
        mtitles("Score raw" "Score adjusted" ///
            "Income raw" "Income adjusted" ///
            "Stability raw" "Stability adjusted" ///
            "Conditions raw" "Conditions adjusted") ///
        cells(b(star pvalue(wild_pvals) fmt(a3)) se(par fmt(a3))) ///
        collabels(none) ///
        starlevels(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    esttab qsortix_score_raw qsortix_score_adj ///
        qsortix_income_raw qsortix_income_adj ///
        qsortix_stability_raw qsortix_stability_adj ///
        qsortix_conditions_raw qsortix_conditions_adj ///
        using "$OUT/qoe_sorting_intensity_exclude_small_occupations.tex", replace ///
        keep(1.male#c.service_months_saved) ///
        coeflabels(1.male#c.service_months_saved ///
            "Months saved \$\times\$ Male") ///
        mtitles("Score raw" "Score adjusted" ///
            "Income raw" "Income adjusted" ///
            "Stability raw" "Stability adjusted" ///
            "Conditions raw" "Conditions adjusted") ///
        cells(b(star pvalue(wild_pvals) fmt(a3)) se(par fmt(a3))) ///
        collabels(none) ///
        starlevels(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    * Sequential individual-QoE controls, one table per dimension.
    foreach stem in score income stability conditions {
        esttab qwithin_`stem'_s1 qwithin_`stem'_s2 ///
            qwithin_`stem'_s3 qwithin_`stem'_s4 ///
            using "$OUT/qoe_sequential_controls_`stem'.tex", replace ///
            keep(1.male#1.post_military) ///
            coeflabels(1.male#1.post_military ///
                "Post-reform \$\times\$ Male") ///
            mtitles("Education + year" "+ Tenure" ///
                "+ Occupation FE" "+ Industry FE") ///
            cells(b(star pvalue(wild_pvals) fmt(a3)) se(par fmt(a3))) ///
            collabels(none) ///
            starlevels(* 0.10 ** 0.05 *** 0.01) ///
            stats(N r2 boot_p, ///
                labels("Observations" "R-squared" ///
                    "Bootstrap \$p\$-value") ///
                fmt(%9.0fc %9.3f %9.3f)) ///
            booktabs nonumber nonotes fragment
    }
}
else display as error "esttab not installed; regression tables not exported."

display as text ///
    "QoE occupation-sorting analysis completed. Outputs use qoe_sorting_* filenames."
