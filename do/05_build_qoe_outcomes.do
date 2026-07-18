****************************************************
* 05. Build Quality of Employment deprivation outcomes
* Dataset: MDIS 8월 근로형태별 부가조사, 2001-2025
*
* Run after:
*   00_globals.do
*   01_clean_all.do
*   02_append.do
*
* This script reads the appended master dataset and creates
* deprivation cutoffs under a Quality of Employment framework:
*   1. Income from labour
*   2. Employment stability
*   3. Employment conditions
*
* It does not modify raw data or overwrite the appended master file.
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
    global OUT "output"
}

capture mkdir "$OUT"

use "$CLEAN/mdis_master_2001_2025.dta", clear

****************************************************
* Required cleaned variables
****************************************************
foreach v in year male birth_year age wage_worker monthly_wage_clean ///
    hours_week permanent can_continue pension healthins employins ///
    employins_raw {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found. Run 01_clean_all.do and 02_append.do first."
        exit 111
    }
}

****************************************************
* Remove previously generated QoE variables if re-running
****************************************************
capture drop monthly_wage_for_median
capture drop monthly_wage_median_year
capture drop monthly_wage_cutoff50_year
capture drop monthly_wage_cutoff667_year
capture drop dep_low_monthly_wage
capture drop dep_low_monthly_wage50
capture drop dep_low_monthly_wage667
capture drop dep_nonpermanent
capture drop dep_no_continuity
capture drop dep_excess_hours
capture drop has_core_ins_pkg
capture drop dep_no_social_insurance_package
capture drop qoe_income_deprivation
capture drop qoe_income_deprivation50
capture drop qoe_income_deprivation667
capture drop qoe_stability_deprivation
capture drop qoe_conditions_deprivation
capture drop qoe_deprivation_score
capture drop qoe_deprivation_score50
capture drop qoe_deprivation_score667
capture drop qoe_multidim_deprived50
capture drop qoe_multidim_deprived667
capture drop qoe_complete

****************************************************
* Dimension 1: Income from labour
* Deprived if monthly wage is below 50% of the same-year
* median monthly wage among all-age wage workers with positive wages.
****************************************************
gen monthly_wage_for_median = monthly_wage_clean ///
    if wage_worker == 1 & monthly_wage_clean > 0

bysort year: egen monthly_wage_median_year = ///
    median(monthly_wage_for_median)
bysort year: egen wage_obs_year = total(!missing(monthly_wage_for_median))

gen monthly_wage_cutoff50_year = 0.5 * monthly_wage_median_year
gen monthly_wage_cutoff667_year = (2/3) * monthly_wage_median_year

gen dep_low_monthly_wage50 = .
replace dep_low_monthly_wage50 = 1 if wage_worker == 1 ///
    & monthly_wage_clean > 0 ///
    & monthly_wage_clean < monthly_wage_cutoff50_year
replace dep_low_monthly_wage50 = 0 if wage_worker == 1 ///
    & monthly_wage_clean >= monthly_wage_cutoff50_year ///
    & monthly_wage_clean < .

gen dep_low_monthly_wage667 = .
replace dep_low_monthly_wage667 = 1 if wage_worker == 1 ///
    & monthly_wage_clean > 0 ///
    & monthly_wage_clean < monthly_wage_cutoff667_year
replace dep_low_monthly_wage667 = 0 if wage_worker == 1 ///
    & monthly_wage_clean >= monthly_wage_cutoff667_year ///
    & monthly_wage_clean < .

label variable monthly_wage_median_year ///
    "Year-specific median monthly wage among wage workers"
label variable wage_obs_year ///
    "Positive monthly-wage observations used for yearly median"
label variable monthly_wage_cutoff50_year ///
    "50% of year-specific median monthly wage among wage workers"
label variable monthly_wage_cutoff667_year ///
    "Two-thirds of year-specific median monthly wage among wage workers"
label variable dep_low_monthly_wage50 ///
    "QoE deprivation: monthly wage below 50% of yearly median"
label variable dep_low_monthly_wage667 ///
    "QoE deprivation: monthly wage below two-thirds of yearly median"

****************************************************
* Export the income-deprivation thresholds used in the analysis period
* Medians are unweighted and calculated among all-age wage workers.
****************************************************
preserve
    keep if inrange(year, 2015, 2025)
    keep year wage_obs_year monthly_wage_median_year ///
        monthly_wage_cutoff50_year monthly_wage_cutoff667_year
    duplicates drop year, force
    sort year
    isid year
    export delimited using "$OUT/qoe_income_cutoffs_2015_2025.csv", replace
restore

drop monthly_wage_for_median

****************************************************
* Dimension 2: Employment stability
* Deprived if non-permanent or current work cannot continue.
****************************************************
gen dep_nonpermanent = .
replace dep_nonpermanent = 1 if wage_worker == 1 & permanent == 0
replace dep_nonpermanent = 0 if wage_worker == 1 & permanent == 1

gen dep_no_continuity = .
replace dep_no_continuity = 1 if wage_worker == 1 & can_continue == 0
replace dep_no_continuity = 0 if wage_worker == 1 & can_continue == 1

label variable dep_nonpermanent ///
    "QoE deprivation: non-permanent employment"
label variable dep_no_continuity ///
    "QoE deprivation: current work cannot continue"

****************************************************
* Dimension 3: Employment conditions
* Deprived if weekly hours exceed 48 hours, or if any applicable
* job-linked social insurance is not covered.
****************************************************
gen dep_excess_hours = .
replace dep_excess_hours = 1 if wage_worker == 1 ///
    & hours_week > 48 & hours_week < .
replace dep_excess_hours = 0 if wage_worker == 1 ///
    & hours_week >= 0 & hours_week <= 48

gen has_core_ins_pkg = .

* Employment-insurance raw code 0 denotes institutional non-applicability,
* concentrated among public administration, education, and related workers
* who have workplace pension and health-insurance coverage. Treat this as
* satisfying all applicable insurance requirements, not as missing coverage.
replace has_core_ins_pkg = 1 if wage_worker == 1 ///
    & pension == 1 & healthins == 1 ///
    & (employins == 1 | employins_raw == 0)

* Explicit non-coverage in any applicable programme implies deprivation.
replace has_core_ins_pkg = 0 if wage_worker == 1 ///
    & (pension == 0 | healthins == 0 | employins == 0)

gen dep_no_social_insurance_package = .
replace dep_no_social_insurance_package = 1 ///
    if has_core_ins_pkg == 0
replace dep_no_social_insurance_package = 0 ///
    if has_core_ins_pkg == 1

label variable dep_excess_hours ///
    "QoE deprivation: usual weekly hours exceed 48"
label variable has_core_ins_pkg ///
    "Has all applicable job-linked social insurances"
label variable dep_no_social_insurance_package ///
    "QoE deprivation: lacks any applicable job-linked social insurance"

****************************************************
* Dimension scores and overall QoE deprivation scores
* Main scores use a common complete-case sample so that missing indicators
* never cause the remaining indicators to receive larger implicit weights.
* Scores are 0-1, with higher values meaning greater deprivation.
****************************************************
gen byte qoe_complete = wage_worker == 1 ///
    & !missing(dep_low_monthly_wage50, dep_nonpermanent, ///
        dep_no_continuity, dep_excess_hours, ///
        dep_no_social_insurance_package)

gen double qoe_income_deprivation50 = dep_low_monthly_wage50 ///
    if qoe_complete == 1
gen double qoe_income_deprivation667 = dep_low_monthly_wage667 ///
    if qoe_complete == 1

gen double qoe_stability_deprivation = ///
    (dep_nonpermanent + dep_no_continuity) / 2 ///
    if qoe_complete == 1
gen double qoe_conditions_deprivation = ///
    (dep_excess_hours + dep_no_social_insurance_package) / 2 ///
    if qoe_complete == 1

gen double qoe_deprivation_score50 = ///
      (1/3) * dep_low_monthly_wage50 ///
    + (1/6) * dep_nonpermanent ///
    + (1/6) * dep_no_continuity ///
    + (1/6) * dep_excess_hours ///
    + (1/6) * dep_no_social_insurance_package ///
    if qoe_complete == 1

gen double qoe_deprivation_score667 = ///
      (1/3) * dep_low_monthly_wage667 ///
    + (1/6) * dep_nonpermanent ///
    + (1/6) * dep_no_continuity ///
    + (1/6) * dep_excess_hours ///
    + (1/6) * dep_no_social_insurance_package ///
    if qoe_complete == 1

gen byte qoe_multidim_deprived50 = ///
    qoe_deprivation_score50 >= 1/3 ///
    if qoe_complete == 1
gen byte qoe_multidim_deprived667 = ///
    qoe_deprivation_score667 >= 1/3 ///
    if qoe_complete == 1

label variable qoe_complete ///
    "All five QoE deprivation indicators observed"
label variable qoe_income_deprivation50 ///
    "QoE income deprivation score: 50% median cutoff"
label variable qoe_income_deprivation667 ///
    "QoE income deprivation score: two-thirds median cutoff"
label variable qoe_stability_deprivation ///
    "QoE employment stability deprivation score"
label variable qoe_conditions_deprivation ///
    "QoE employment conditions deprivation score"
label variable qoe_deprivation_score50 ///
    "QoE overall deprivation score: 50% median cutoff"
label variable qoe_deprivation_score667 ///
    "QoE overall deprivation score: two-thirds median cutoff"
label variable qoe_multidim_deprived50 ///
    "Multidimensionally QoE deprived: score >= 1/3, 50% cutoff"
label variable qoe_multidim_deprived667 ///
    "Multidimensionally QoE deprived: score >= 1/3, two-thirds cutoff"

****************************************************
* Internal consistency checks
****************************************************
assert inrange(qoe_deprivation_score50, 0, 1) ///
    if !missing(qoe_deprivation_score50)
assert inrange(qoe_deprivation_score667, 0, 1) ///
    if !missing(qoe_deprivation_score667)
assert !missing(qoe_deprivation_score50, qoe_deprivation_score667) ///
    if qoe_complete == 1
assert missing(qoe_deprivation_score50, qoe_deprivation_score667) ///
    if qoe_complete == 0

* Anyone below 50% of the median must also be below two-thirds.
assert dep_low_monthly_wage50 <= dep_low_monthly_wage667 ///
    if !missing(dep_low_monthly_wage50, dep_low_monthly_wage667)

tempvar qoe_score_check50 qoe_score_check667
gen double `qoe_score_check50' = ///
      (1/3) * dep_low_monthly_wage50 ///
    + (1/6) * dep_nonpermanent ///
    + (1/6) * dep_no_continuity ///
    + (1/6) * dep_excess_hours ///
    + (1/6) * dep_no_social_insurance_package ///
    if qoe_complete == 1
gen double `qoe_score_check667' = ///
      (1/3) * dep_low_monthly_wage667 ///
    + (1/6) * dep_nonpermanent ///
    + (1/6) * dep_no_continuity ///
    + (1/6) * dep_excess_hours ///
    + (1/6) * dep_no_social_insurance_package ///
    if qoe_complete == 1
assert abs(qoe_deprivation_score50 - `qoe_score_check50') < 1e-12 ///
    if qoe_complete == 1
assert abs(qoe_deprivation_score667 - `qoe_score_check667') < 1e-12 ///
    if qoe_complete == 1

****************************************************
* Diagnostics
****************************************************
display as text "QoE deprivation indicators by year"
tab year dep_low_monthly_wage50, missing
tab year dep_low_monthly_wage667, missing
tab year dep_nonpermanent, missing
tab year dep_no_continuity, missing
tab year dep_excess_hours, missing
tab year dep_no_social_insurance_package, missing
tab year qoe_complete, missing

summ monthly_wage_cutoff50_year monthly_wage_cutoff667_year ///
    qoe_income_deprivation50 qoe_income_deprivation667 ///
    qoe_stability_deprivation qoe_conditions_deprivation ///
    qoe_deprivation_score50 qoe_deprivation_score667 ///
    qoe_multidim_deprived50 qoe_multidim_deprived667, detail

****************************************************
* Export unweighted QoE means and missingness by year and gender
* Sample matches the dissertation analysis window and event-study cohorts.
* QoE means use the common complete-case sample; missingness rates use all
* wage workers in the analysis sample as the denominator.
****************************************************
preserve
    keep if inrange(year, 2015, 2025)
    keep if inrange(age, 18, 39)
    keep if !missing(male, birth_year)
    keep if inrange(birth_year - 1997, -5, 5)
    keep if wage_worker == 1

    gen long summary_obs = 1

    gen byte miss_income50  = missing(dep_low_monthly_wage50)
    gen byte miss_nonperm   = missing(dep_nonpermanent)
    gen byte miss_continuity = missing(dep_no_continuity)
    gen byte miss_hours     = missing(dep_excess_hours)
    gen byte miss_social    = missing(dep_no_social_insurance_package)

    * Complete-case copies ensure identical denominators across QoE means.
    gen double cc_income50   = dep_low_monthly_wage50 if qoe_complete == 1
    gen double cc_nonperm    = dep_nonpermanent if qoe_complete == 1
    gen double cc_continuity = dep_no_continuity if qoe_complete == 1
    gen double cc_hours      = dep_excess_hours if qoe_complete == 1
    gen double cc_social     = dep_no_social_insurance_package ///
        if qoe_complete == 1

    collapse ///
        (sum) wage_worker_n=summary_obs complete_n=qoe_complete ///
        (mean) complete_rate=qoe_complete ///
            missing_income50=miss_income50 ///
            missing_nonperm=miss_nonperm ///
            missing_continuity=miss_continuity ///
            missing_hours=miss_hours ///
            missing_social=miss_social ///
            mean_income50=cc_income50 ///
            mean_nonperm=cc_nonperm ///
            mean_no_continuity=cc_continuity ///
            mean_excess_hours=cc_hours ///
            mean_no_social_insurance=cc_social ///
            mean_income_dimension50=qoe_income_deprivation50 ///
            mean_stability_dimension=qoe_stability_deprivation ///
            mean_conditions_dimension=qoe_conditions_deprivation ///
            mean_qoe_score50=qoe_deprivation_score50 ///
            mean_multidim_deprived50=qoe_multidim_deprived50 ///
            mean_qoe_score667=qoe_deprivation_score667 ///
            mean_multidim_deprived667=qoe_multidim_deprived667, ///
        by(year male)

    sort year male
    isid year male
    assert _N == 22
    assert inrange(complete_rate, 0, 1)

    order year male wage_worker_n complete_n complete_rate ///
        missing_income50 missing_nonperm missing_continuity ///
        missing_hours missing_social

    export delimited using ///
        "$OUT/qoe_summary_by_year_gender_2015_2025.csv", replace
restore

save "$CLEAN/mdis_master_qoe_2001_2025.dta", replace
