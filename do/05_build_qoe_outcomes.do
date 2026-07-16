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

use "$CLEAN/mdis_master_2001_2025.dta", clear

****************************************************
* Required cleaned variables
****************************************************
foreach v in year wage_worker monthly_wage_clean hours_week permanent ///
    can_continue pension healthins employins {
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
capture drop dep_low_monthly_wage
capture drop dep_nonpermanent
capture drop dep_no_continuity
capture drop dep_excess_hours
capture drop has_core_ins_pkg
capture drop dep_no_social_insurance_package
capture drop qoe_income_deprivation
capture drop qoe_stability_deprivation
capture drop qoe_conditions_deprivation
capture drop qoe_deprivation_score

****************************************************
* Dimension 1: Income from labour
* Deprived if monthly wage is below 50% of the same-year
* median monthly wage among all-age wage workers with positive wages.
****************************************************
gen monthly_wage_for_median = monthly_wage_clean ///
    if wage_worker == 1 & monthly_wage_clean > 0

bysort year: egen monthly_wage_median_year = ///
    median(monthly_wage_for_median)

gen monthly_wage_cutoff50_year = 0.5 * monthly_wage_median_year

gen dep_low_monthly_wage = .
replace dep_low_monthly_wage = 1 if wage_worker == 1 ///
    & monthly_wage_clean > 0 ///
    & monthly_wage_clean < monthly_wage_cutoff50_year
replace dep_low_monthly_wage = 0 if wage_worker == 1 ///
    & monthly_wage_clean >= monthly_wage_cutoff50_year ///
    & monthly_wage_clean < .

label variable monthly_wage_median_year ///
    "Year-specific median monthly wage among wage workers"
label variable monthly_wage_cutoff50_year ///
    "50% of year-specific median monthly wage among wage workers"
label variable dep_low_monthly_wage ///
    "QoE deprivation: monthly wage below 50% of yearly median"

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
* Deprived if weekly hours exceed 48 hours, or if any of the
* three core social insurances is missing.
****************************************************
gen dep_excess_hours = .
replace dep_excess_hours = 1 if wage_worker == 1 ///
    & hours_week > 48 & hours_week < .
replace dep_excess_hours = 0 if wage_worker == 1 ///
    & hours_week >= 0 & hours_week <= 48

gen has_core_ins_pkg = .
replace has_core_ins_pkg = 1 if wage_worker == 1 ///
    & pension == 1 & healthins == 1 & employins == 1
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
    "Has pension, health insurance, and employment insurance"
label variable dep_no_social_insurance_package ///
    "QoE deprivation: lacks any core social insurance"

****************************************************
* Dimension scores and overall QoE deprivation score
* Scores are 0-1, with higher values meaning greater deprivation.
****************************************************
egen qoe_income_deprivation = rowmean(dep_low_monthly_wage)
egen qoe_stability_deprivation = rowmean(dep_nonpermanent dep_no_continuity)
egen qoe_conditions_deprivation = rowmean(dep_excess_hours ///
    dep_no_social_insurance_package)

egen qoe_deprivation_score = rowmean(qoe_income_deprivation ///
    qoe_stability_deprivation qoe_conditions_deprivation)

label variable qoe_income_deprivation ///
    "QoE income deprivation score"
label variable qoe_stability_deprivation ///
    "QoE employment stability deprivation score"
label variable qoe_conditions_deprivation ///
    "QoE employment conditions deprivation score"
label variable qoe_deprivation_score ///
    "QoE overall deprivation score"

****************************************************
* Diagnostics
****************************************************
display as text "QoE deprivation indicators by year"
tab year dep_low_monthly_wage, missing
tab year dep_nonpermanent, missing
tab year dep_no_continuity, missing
tab year dep_excess_hours, missing
tab year dep_no_social_insurance_package, missing

summ monthly_wage_cutoff50_year qoe_income_deprivation ///
    qoe_stability_deprivation qoe_conditions_deprivation ///
    qoe_deprivation_score, detail

save "$CLEAN/mdis_master_qoe_2001_2025.dta", replace
