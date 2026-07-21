****************************************************
* 10. Decompose occupational sorting changes by gender
* 2018 military-service reduction
*
* Run after:
*   00_globals.do
*   05_build_qoe_outcomes.do
*   07_analysis_sorting.do
*   08_analysis_qoe_sorting.do
*
* This supplementary file decomposes the existing Male x Post sorting
* estimates into the cohort change for women and the cohort change for men.
* Women's Post coefficient is a comparison-cohort change, not an effect of
* military-service reform on women.
****************************************************

clear all
set more off
set varabbrev off

capture confirm global CLEAN
if _rc global CLEAN "data_clean"

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

foreach f in mdis_master_qoe_2001_2025.dta {
    capture confirm file "$CLEAN/`f'"
    if _rc {
        display as error "Required file not found: $CLEAN/`f'"
        exit 601
    }
}

foreach f in sorting_preperiod_occupation_wage_index.csv ///
    qoe_sorting_preperiod_occupation_indices.csv {
    capture confirm file "$OUT/`f'"
    if _rc {
        display as error "Required index file not found: $OUT/`f'"
        display as error "Run 07_analysis_sorting.do and 08_analysis_qoe_sorting.do first."
        exit 601
    }
}

****************************************************
* 1. Read frozen pre-reform occupation indices
*
* export delimited writes the occupation value labels to the first column.
* Both upstream files contain one row for each harmonised occupation code,
* sorted from 1 to 9. Reconstruct the numeric key and verify nine unique rows.
****************************************************

tempfile wage_index qoe_index sorting_analysis gender_change_results ///
    robustness_results

import delimited using ///
    "$OUT/sorting_preperiod_occupation_wage_index.csv", clear varnames(1)
assert _N == 9
capture drop occupation_code
gen byte occupation_code = _n
isid occupation_code
keep occupation_code occupation_wage_raw occupation_wage_adjusted
save `wage_index', replace

import delimited using ///
    "$OUT/qoe_sorting_preperiod_occupation_indices.csv", clear varnames(1)
assert _N == 9
capture drop occupation_code
gen byte occupation_code = _n
isid occupation_code
keep occupation_code occ_qoe_score_adjusted ///
    occ_qoe_income_adjusted occ_qoe_stability_adjusted ///
    occ_qoe_conditions_adjusted
save `qoe_index', replace

****************************************************
* 2. Reproduce the main sorting sample
****************************************************

use "$CLEAN/mdis_master_qoe_2001_2025.dta", clear
capture drop __*

foreach v in year age male birth_year wage_worker educ_raw occupation_code ///
    experience_raw survey_ym {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found."
        exit 111
    }
}

keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year)

gen cohort = birth_year
gen rel_cohort = birth_year - 1997
keep if inrange(rel_cohort, -5, 5)
gen byte post_military = birth_year >= 1997 if !missing(birth_year)

merge m:1 occupation_code using `wage_index', keep(master match) ///
    gen(merge_gender_wage_index)
merge m:1 occupation_code using `qoe_index', keep(master match) ///
    gen(merge_gender_qoe_index)

* Current-job tenure is used only in the final mechanism specification.
* It is not included in the baseline total-effect sorting regression because
* current-job tenure may itself respond to military-service reform.
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

save `sorting_analysis', replace

****************************************************
* 3. Gender-specific cohort changes
*
* Female change: Post
* Male change:   Post + Male x Post
* Relative DiD:  Male x Post
*
* All specifications match the education-adjusted sorting regressions in
* 07 and 08. Standard errors are clustered by birth cohort.
****************************************************

local outcomes occupation_wage_adjusted ///
    occ_qoe_score_adjusted occ_qoe_income_adjusted ///
    occ_qoe_stability_adjusted occ_qoe_conditions_adjusted
local label1 "Adjusted occupation wage"
local label2 "Adjusted QoE score"
local label3 "Adjusted QoE income"
local label4 "Adjusted QoE stability"
local label5 "Adjusted QoE conditions"

postfile gender_handle str40 outcome double ///
    female_change female_se female_p ///
    male_change male_se male_p ///
    relative_change relative_se relative_p N ///
    using `gender_change_results', replace

local i = 1
foreach yvar of local outcomes {
    local outcome_label "`label`i''"

    quietly reg `yvar' i.male##i.post_military i.educ_raw i.year ///
        if wage_worker == 1, vce(cluster cohort)
    scalar result_n = e(N)

    quietly lincom 1.post_military
    scalar female_b = r(estimate)
    scalar female_se = r(se)
    scalar female_p = r(p)

    quietly lincom 1.post_military + 1.male#1.post_military
    scalar male_b = r(estimate)
    scalar male_se = r(se)
    scalar male_p = r(p)

    quietly lincom 1.male#1.post_military
    scalar relative_b = r(estimate)
    scalar relative_se = r(se)
    scalar relative_p = r(p)

    post gender_handle ("`outcome_label'") ///
        (female_b) (female_se) (female_p) ///
        (male_b) (male_se) (male_p) ///
        (relative_b) (relative_se) (relative_p) (result_n)

    local ++i
}
postclose gender_handle

use `gender_change_results', clear
export delimited using ///
    "$OUT/sorting_gender_specific_post_changes.csv", replace

****************************************************
* 4. Display and export one compact LaTeX table
****************************************************

format female_change male_change relative_change %9.4f
format female_se male_se relative_se %9.4f
format female_p male_p relative_p %9.3f
list outcome female_change female_se female_p male_change male_se male_p ///
    relative_change relative_se relative_p N, noobs abbreviate(32)

file open gender_table using ///
    "$OUT/sorting_gender_specific_post_changes.tex", write replace text
file write gender_table ///
    "Outcome & Women: Post & Men: Post & Male relative change \\" _n
file write gender_table "\midrule" _n

forvalues r = 1/`=_N' {
    local row_label = outcome[`r']
    local fb : display %9.4f female_change[`r']
    local fs : display %9.4f female_se[`r']
    local fp : display %9.3f female_p[`r']
    local mb : display %9.4f male_change[`r']
    local ms : display %9.4f male_se[`r']
    local mp : display %9.3f male_p[`r']
    local rb : display %9.4f relative_change[`r']
    local rs : display %9.4f relative_se[`r']
    local rp : display %9.3f relative_p[`r']

    file write gender_table "`row_label'" ///
        " & `fb' (`fs') [p=`fp']" ///
        " & `mb' (`ms') [p=`mp']" ///
        " & `rb' (`rs') [p=`rp'] \\" _n
}

file write gender_table "\midrule" _n
file write gender_table ///
    "\multicolumn{4}{l}{\footnotesize Clustered standard errors in parentheses; p-values in brackets.} \\" _n
file write gender_table ///
    "\multicolumn{4}{l}{\footnotesize Lower QoE indices indicate better job quality.} \\" _n
file write gender_table ///
    "\multicolumn{4}{l}{\footnotesize Women's Post coefficient is a cohort change, not a policy effect on women.} \\" _n
file close gender_table

****************************************************
* 5. Age-composition and current-job-tenure diagnostics
*
* Exact common age support across the 1992-2002 birth cohorts is ages 22-23.
* Specifications 3 and 4 use the same tenure-complete sample, so their
* difference reflects tenure conditioning rather than changing observations.
* The tenure specification is a mechanism/conditional estimate, not a total
* reform effect, because tenure may respond to reform exposure.
****************************************************

use `sorting_analysis', clear

gen byte common_age_22_23 = inrange(age,22,23)
gen byte common_age_tenure_sample = wage_worker == 1 ///
    & common_age_22_23 == 1 ///
    & !missing(educ_raw, job_tenure_years)

local spec_label1 "Baseline: education and year FE"
local spec_label2 "Add age FE"
local spec_label3 "Ages 22-23: common tenure sample"
local spec_label4 "Ages 22-23: add current-job tenure"

postfile robustness_handle str40 outcome byte specification ///
    str50 specification_label double ///
    female_change female_se female_p female_wild_p ///
    male_change male_se male_p male_wild_p ///
    relative_change relative_se relative_p relative_wild_p N ///
    using `robustness_results', replace

local i = 1
foreach yvar of local outcomes {
    local outcome_label "`label`i''"

    forvalues s = 1/4 {
        if `s' == 1 {
            quietly reg `yvar' i.male##i.post_military ///
                i.educ_raw i.year if wage_worker == 1, ///
                vce(cluster cohort)
        }
        else if `s' == 2 {
            quietly reg `yvar' i.male##i.post_military ///
                i.educ_raw i.age i.year if wage_worker == 1, ///
                vce(cluster cohort)
        }
        else if `s' == 3 {
            quietly reg `yvar' i.male##i.post_military ///
                i.educ_raw i.age i.year ///
                if common_age_tenure_sample == 1, vce(cluster cohort)
        }
        else if `s' == 4 {
            quietly reg `yvar' i.male##i.post_military ///
                i.educ_raw i.age i.year c.job_tenure_years ///
                if common_age_tenure_sample == 1, vce(cluster cohort)
        }

        scalar robust_n = e(N)

        quietly lincom 1.post_military
        scalar robust_female_b = r(estimate)
        scalar robust_female_se = r(se)
        scalar robust_female_p = r(p)

        quietly lincom 1.post_military + 1.male#1.post_military
        scalar robust_male_b = r(estimate)
        scalar robust_male_se = r(se)
        scalar robust_male_p = r(p)

        quietly lincom 1.male#1.post_military
        scalar robust_relative_b = r(estimate)
        scalar robust_relative_se = r(se)
        scalar robust_relative_p = r(p)

        * Wild-cluster bootstrap inference is reported because treatment is
        * assigned across only 11 birth cohorts. Keep asymptotic clustered
        * p-values above as diagnostics in the CSV output.
        capture quietly boottest 1.post_military, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        if !_rc scalar robust_female_wild_p = r(p)
        else scalar robust_female_wild_p = .

        capture quietly boottest ///
            1.post_military + 1.male#1.post_military = 0, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        if !_rc scalar robust_male_wild_p = r(p)
        else scalar robust_male_wild_p = .

        capture quietly boottest 1.male#1.post_military, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        if !_rc scalar robust_relative_wild_p = r(p)
        else scalar robust_relative_wild_p = .

        local current_spec_label "`spec_label`s''"
        post robustness_handle ("`outcome_label'") (`s') ///
            ("`current_spec_label'") ///
            (robust_female_b) (robust_female_se) (robust_female_p) ///
            (robust_female_wild_p) ///
            (robust_male_b) (robust_male_se) (robust_male_p) ///
            (robust_male_wild_p) ///
            (robust_relative_b) (robust_relative_se) ///
            (robust_relative_p) (robust_relative_wild_p) (robust_n)
    }

    local ++i
}
postclose robustness_handle

use `robustness_results', clear
sort outcome specification
export delimited using ///
    "$OUT/sorting_gender_age_tenure_robustness.csv", replace

format female_change male_change relative_change %9.4f
format female_se male_se relative_se %9.4f
format female_p male_p relative_p %9.3f
format female_wild_p male_wild_p relative_wild_p %9.3f
list outcome specification_label female_change female_se female_wild_p ///
    male_change male_se male_wild_p relative_change relative_se ///
    relative_wild_p N, ///
    noobs abbreviate(32) sepby(outcome)

file open robustness_table using ///
    "$OUT/sorting_gender_age_tenure_robustness.tex", write replace text
file write robustness_table ///
    "Outcome / specification & Women: Post & Men: Post & Male relative change \\" _n
file write robustness_table "\midrule" _n

forvalues r = 1/`=_N' {
    local row_outcome = outcome[`r']
    local row_spec = specification_label[`r']
    local fb : display %9.4f female_change[`r']
    local fs : display %9.4f female_se[`r']
    local fp : display %9.3f female_wild_p[`r']
    local mb : display %9.4f male_change[`r']
    local ms : display %9.4f male_se[`r']
    local mp : display %9.3f male_wild_p[`r']
    local rb : display %9.4f relative_change[`r']
    local rs : display %9.4f relative_se[`r']
    local rp : display %9.3f relative_wild_p[`r']

    file write robustness_table "`row_outcome': `row_spec'" ///
        " & `fb' (`fs') [wild p=`fp']" ///
        " & `mb' (`ms') [wild p=`mp']" ///
        " & `rb' (`rs') [wild p=`rp'] \\" _n
}

file write robustness_table "\midrule" _n
file write robustness_table ///
    "\multicolumn{4}{l}{\footnotesize Clustered standard errors in parentheses; wild-bootstrap p-values in brackets.} \\" _n
file write robustness_table ///
    "\multicolumn{4}{l}{\footnotesize Lower QoE indices indicate better job quality.} \\" _n
file write robustness_table ///
    "\multicolumn{4}{l}{\footnotesize Tenure is a post-reform mechanism control, not a baseline control.} \\" _n
file close robustness_table

display as text "Gender-specific sorting decomposition completed."
