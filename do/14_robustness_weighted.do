****************************************************
* 14. Robustness: survey-weighted main results
*
* Compares the main unweighted specifications with otherwise identical
* regressions using the Employment Type Supplement population weights.
*
* Run after:
*   00_globals.do
*   01_clean_all.do
*   02_append.do
*   05_build_qoe_outcomes.do
*
* Required packages:
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
capture log close weighted14
log using "$OUT/14_robustness_weighted_`run_date'_`run_time'.log", ///
    text name(weighted14)

capture which boottest
if _rc {
    display as error "boottest is required. Install it with: ssc install boottest"
    exit 199
}

tempfile weighted_results
tempname results
postfile `results' byte outcome_order str40 outcome byte spec_order ///
    str24 specification double beta se wild_p N using `weighted_results', replace

****************************************************
* 1. Employment and current-job entry age
****************************************************

capture confirm file "$CLEAN/mdis_master_2001_2025.dta"
if _rc {
    display as error "Main analysis dataset not found: $CLEAN/mdis_master_2001_2025.dta"
    display as error "Run the upstream cleaning and append scripts first."
    exit 601
}

use "$CLEAN/mdis_master_2001_2025.dta", clear

foreach v in year age male birth_year educ_raw survey_ym experience_raw ///
    employed wage_worker popwt {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found in the main dataset."
        exit 111
    }
}

* Match the baseline sample and treatment definitions in 03_analysis.do.
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

* Do not allow weighting to change the estimation sample silently.
gen byte valid_weight = !missing(popwt) & popwt > 0
count if !valid_weight
display as text "Invalid population weights in baseline cohort window: " r(N)
assert valid_weight == 1

local controls i.educ_raw i.year

forvalues outcome_index = 1/2 {
    if `outcome_index' == 1 {
        local yvar employed
        local outcome_label "Employed"
        local sample_if "!missing(employed)"
    }
    else {
        local yvar entry_age
        local outcome_label "Current-job entry age"
        local sample_if "wage_worker == 1 & !missing(entry_age)"
    }

    forvalues spec = 1/4 {
        local weight_clause
        local treatment "i.post_military"
        local interaction "1.male#1.post_military"
        local spec_label "DiD unweighted"

        if `spec' == 2 {
            local weight_clause "[pw=popwt]"
            local spec_label "DiD weighted"
        }
        else if `spec' == 3 {
            local treatment "c.service_months_saved"
            local interaction "1.male#c.service_months_saved"
            local spec_label "Intensity unweighted"
        }
        else if `spec' == 4 {
            local weight_clause "[pw=popwt]"
            local treatment "c.service_months_saved"
            local interaction "1.male#c.service_months_saved"
            local spec_label "Intensity weighted"
        }

        regress `yvar' i.male##`treatment' `controls' `weight_clause' ///
            if `sample_if', vce(cluster cohort)
        scalar model_beta = _b[`interaction']
        scalar model_se = _se[`interaction']
        scalar model_n = e(N)

        capture noisily boottest `interaction', cluster(cohort) ///
            reps(9999) seed(12345) nograph
        local boot_rc = _rc
        if `boot_rc' | missing(r(p)) {
            display as error "Wild bootstrap failed for `outcome_label', `spec_label'."
            exit 498
        }
        scalar model_wild_p = r(p)

        post `results' (`outcome_index') ("`outcome_label'") (`spec') ///
            ("`spec_label'") (model_beta) (model_se) ///
            (model_wild_p) (model_n)
    }
}

****************************************************
* 2. Main Quality of Employment outcomes
****************************************************

capture confirm file "$CLEAN/mdis_master_qoe_2001_2025.dta"
if _rc {
    display as error "QoE analysis dataset not found: $CLEAN/mdis_master_qoe_2001_2025.dta"
    display as error "Run 05_build_qoe_outcomes.do first."
    exit 601
}

use "$CLEAN/mdis_master_qoe_2001_2025.dta", clear

local qoe_outcomes qoe_deprivation_score50 qoe_multidim_deprived50 ///
    qoe_income_deprivation50 qoe_stability_deprivation ///
    qoe_conditions_deprivation
local qoe_labels `""QoE deprivation score" "Multidimensional deprivation" "Income deprivation" "Stability deprivation" "Working-conditions deprivation""'

foreach v in year age male birth_year educ_raw wage_worker qoe_complete ///
    popwt `qoe_outcomes' {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found in the QoE dataset."
        exit 111
    }
}

* Match the baseline sample and treatment definitions in 06_analysis_qoe.do.
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

gen byte valid_weight = !missing(popwt) & popwt > 0
count if !valid_weight
display as text "Invalid population weights in QoE cohort window: " r(N)
assert valid_weight == 1

local qoe_index = 0
foreach yvar of local qoe_outcomes {
    local ++qoe_index
    local outcome_order = `qoe_index' + 2
    local outcome_label : word `qoe_index' of `qoe_labels'

    forvalues spec = 1/4 {
        local weight_clause
        local treatment "i.post_military"
        local interaction "1.male#1.post_military"
        local spec_label "DiD unweighted"

        if `spec' == 2 {
            local weight_clause "[pw=popwt]"
            local spec_label "DiD weighted"
        }
        else if `spec' == 3 {
            local treatment "c.service_months_saved"
            local interaction "1.male#c.service_months_saved"
            local spec_label "Intensity unweighted"
        }
        else if `spec' == 4 {
            local weight_clause "[pw=popwt]"
            local treatment "c.service_months_saved"
            local interaction "1.male#c.service_months_saved"
            local spec_label "Intensity weighted"
        }

        regress `yvar' i.male##`treatment' i.educ_raw i.year ///
            `weight_clause' if wage_worker == 1 & qoe_complete == 1, ///
            vce(cluster cohort)
        scalar model_beta = _b[`interaction']
        scalar model_se = _se[`interaction']
        scalar model_n = e(N)

        capture noisily boottest `interaction', cluster(cohort) ///
            reps(9999) seed(12345) nograph
        local boot_rc = _rc
        if `boot_rc' | missing(r(p)) {
            display as error "Wild bootstrap failed for `outcome_label', `spec_label'."
            exit 498
        }
        scalar model_wild_p = r(p)

        post `results' (`outcome_order') ("`outcome_label'") (`spec') ///
            ("`spec_label'") (model_beta) (model_se) ///
            (model_wild_p) (model_n)
    }
}

postclose `results'

****************************************************
* 3. Export audit-friendly CSV and compact LaTeX table
****************************************************

use `weighted_results', clear
sort outcome_order spec_order
export delimited using "$OUT/robustness_weighted_results.csv", replace

* Stars use wild-cluster-bootstrap p-values, matching the main tables.
gen str3 stars = cond(wild_p < .01, "***", ///
    cond(wild_p < .05, "**", cond(wild_p < .10, "*", "")))
gen str20 beta_text = string(beta, "%9.4f") + stars
gen str20 se_text = "(" + string(se, "%9.4f") + ")"
gen str20 p_text = "[" + string(wild_p, "%9.3f") + "]"
gen str20 n_text = string(N, "%12.0fc")

tempname table
file open `table' using "$OUT/robustness_weighted_table.tex", ///
    write replace text
file write `table' "            & DiD unweighted & DiD weighted & Intensity unweighted & Intensity weighted \\" _n
file write `table' "\midrule" _n

forvalues outcome_index = 1/7 {
    quietly levelsof outcome if outcome_order == `outcome_index', ///
        local(row_label) clean

    forvalues spec = 1/4 {
        quietly levelsof beta_text if outcome_order == `outcome_index' ///
            & spec_order == `spec', local(b`spec') clean
        quietly levelsof se_text if outcome_order == `outcome_index' ///
            & spec_order == `spec', local(s`spec') clean
        quietly levelsof p_text if outcome_order == `outcome_index' ///
            & spec_order == `spec', local(p`spec') clean
        quietly levelsof n_text if outcome_order == `outcome_index' ///
            & spec_order == `spec', local(n`spec') clean
    }

    file write `table' "`row_label' & `b1' & `b2' & `b3' & `b4' \\" _n
    file write `table' "            & `s1' & `s2' & `s3' & `s4' \\" _n
    file write `table' "Wild-bootstrap p-value & `p1' & `p2' & `p3' & `p4' \\" _n
    file write `table' "Observations & `n1' & `n2' & `n3' & `n4' \\" _n
    if `outcome_index' < 7 file write `table' "\addlinespace" _n
}

file write `table' "\midrule" _n
file write `table' "Education controls & Yes & Yes & Yes & Yes \\" _n
file write `table' "Survey-year fixed effects & Yes & Yes & Yes & Yes \\" _n
file close `table'

display as result "Weighted robustness analysis completed."
display as result "Created: $OUT/robustness_weighted_results.csv"
display as result "Created: $OUT/robustness_weighted_table.tex"

log close weighted14
