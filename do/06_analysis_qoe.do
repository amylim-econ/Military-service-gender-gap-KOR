****************************************************
* 06. Analysis: Quality of Employment outcomes
* 2018 military-service reduction
*
* Run after:
*   00_globals.do
*   01_clean_all.do
*   02_append.do
*   05_build_qoe_outcomes.do
*
* Primary income cutoff: 50% of same-year median monthly wage.
* Two-thirds median cutoff is retained as robustness output.
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

capture confirm file "$CLEAN/mdis_master_qoe_2001_2025.dta"
if _rc {
    display as error "QoE master file not found: $CLEAN/mdis_master_qoe_2001_2025.dta"
    display as error "Run 00_globals.do, 01_clean_all.do, 02_append.do, and 05_build_qoe_outcomes.do first."
    exit 601
}

use "$CLEAN/mdis_master_qoe_2001_2025.dta", clear

****************************************************
* 1. Required variables
****************************************************

foreach v in year age male birth_year wage_worker experience_raw survey_ym ///
    educ_raw occupation_code industry_gender_type ///
    qoe_complete qoe_deprivation_score50 qoe_deprivation_score667 ///
    qoe_multidim_deprived50 qoe_multidim_deprived667 ///
    qoe_income_deprivation50 qoe_income_deprivation667 ///
    qoe_stability_deprivation qoe_conditions_deprivation ///
    dep_low_monthly_wage50 dep_low_monthly_wage667 ///
    dep_nonpermanent dep_no_continuity dep_excess_hours ///
    dep_no_social_insurance_package {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found."
        display as error "Run upstream do-files before 06_analysis_qoe.do."
        exit 111
    }
}

****************************************************
* 2. Sample and treatment definition
* Same 2018 reform window as 03_analysis.do.
****************************************************

keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year)

gen cohort = birth_year
gen enlist_year20 = birth_year + 20
gen rel_cohort = birth_year - 1997
label variable rel_cohort "Birth cohort relative to 1997-born first affected cohort"

keep if inrange(rel_cohort, -5, 5)

gen rel_shift = rel_cohort + 5
label variable rel_shift "Shifted event time; base rel_shift=4 means k=-1"

* Policy-based event-time bins reduce reliance on a single birth-cohort
* cluster for each dynamic coefficient. The 1996 cohort (k=-1) is the base.
gen byte qoe_event_bin = .
replace qoe_event_bin = 0 if inrange(rel_cohort, -5, -4)
replace qoe_event_bin = 1 if inrange(rel_cohort, -3, -2)
replace qoe_event_bin = 2 if rel_cohort == -1
replace qoe_event_bin = 3 if inrange(rel_cohort, 0, 2)
replace qoe_event_bin = 4 if inrange(rel_cohort, 3, 5)
assert !missing(qoe_event_bin)

label define qoe_event_bin_lbl ///
    0 "Early pre (k=-5,-4)" ///
    1 "Near pre (k=-3,-2)" ///
    2 "Reference (k=-1)" ///
    3 "Partial reduction (k=0,1,2)" ///
    4 "Full reduction (k=3,4,5)"
label values qoe_event_bin qoe_event_bin_lbl
label variable qoe_event_bin "Policy-based binned cohort event time"

gen post_military = (birth_year >= 1997) if !missing(birth_year)
label variable post_military "Born 1997 or later: exposed to 2018 military-service reduction"

gen full_reduction = (birth_year >= 2000) if !missing(birth_year)
label variable full_reduction "Born 2000 or later: representative age-20 entrant gets full 3-month reduction"

gen service_months_saved = .
replace service_months_saved = 0    if birth_year <= 1996
replace service_months_saved = 0.75 if birth_year == 1997
replace service_months_saved = 1.50 if birth_year == 1998
replace service_months_saved = 2.25 if birth_year == 1999
replace service_months_saved = 3.00 if birth_year >= 2000
label variable service_months_saved "Approx. months of military service reduced, age-20 cohort exposure"

****************************************************
* 3. Job tenure control, matching 03_analysis.do
****************************************************

gen job_start_year  = floor(experience_raw/100) if experience_raw < .
gen job_start_month = mod(experience_raw,100)  if experience_raw < .
replace job_start_year  = . if job_start_year < 1900 | job_start_year > year
replace job_start_month = . if !inrange(job_start_month,1,12)

gen survey_year_from_ym  = floor(survey_ym/100) if survey_ym < .
gen survey_month_from_ym = mod(survey_ym,100)  if survey_ym < .
replace survey_year_from_ym  = year if missing(survey_year_from_ym)
replace survey_month_from_ym = 8    if missing(survey_month_from_ym) | !inrange(survey_month_from_ym,1,12)

gen job_start_tm = ym(job_start_year, job_start_month)
gen survey_tm    = ym(survey_year_from_ym, survey_month_from_ym)
format job_start_tm survey_tm %tm

gen job_tenure_months = survey_tm - job_start_tm if job_start_tm < . & survey_tm < .
replace job_tenure_months = . if job_tenure_months < 0

gen job_tenure_years = job_tenure_months/12 if job_tenure_months < .
label variable job_tenure_years "Current-job tenure / work experience in years"

****************************************************
* 4. Controls and QoE outcome lists
****************************************************

* Job tenure and occupation are excluded because they may be affected by
* military-service reform exposure and therefore post-treatment controls.
local controls_qoe i.educ_raw i.year
display as text "controls_qoe: `controls_qoe'"

local qoe_main qoe_deprivation_score50 qoe_multidim_deprived50 ///
    qoe_income_deprivation50 qoe_stability_deprivation ///
    qoe_conditions_deprivation

local qoe_main_names score50 multidim50 income50 stability conditions

local qoe_robust qoe_deprivation_score667 qoe_multidim_deprived667 ///
    qoe_income_deprivation667

local qoe_decomp dep_low_monthly_wage50 dep_nonpermanent ///
    dep_no_continuity dep_excess_hours dep_no_social_insurance_package

local qoe_decomp_names lowwage50 nonperm continuity hours socialins

gen double qoe_contrib_income50 = (1/3) * dep_low_monthly_wage50 ///
    if qoe_complete == 1
gen double qoe_contrib_nonperm = (1/6) * dep_nonpermanent ///
    if qoe_complete == 1
gen double qoe_contrib_continuity = (1/6) * dep_no_continuity ///
    if qoe_complete == 1
gen double qoe_contrib_hours = (1/6) * dep_excess_hours ///
    if qoe_complete == 1
gen double qoe_contrib_socialins = (1/6) * dep_no_social_insurance_package ///
    if qoe_complete == 1

label variable qoe_contrib_income50 ///
    "Weighted QoE contribution: low monthly wage, 50% cutoff"
label variable qoe_contrib_nonperm ///
    "Weighted QoE contribution: non-permanent employment"
label variable qoe_contrib_continuity ///
    "Weighted QoE contribution: no continuity"
label variable qoe_contrib_hours ///
    "Weighted QoE contribution: excessive weekly hours"
label variable qoe_contrib_socialins ///
    "Weighted QoE contribution: lacks social insurance package"

assert abs(qoe_deprivation_score50 - ///
    (qoe_contrib_income50 + qoe_contrib_nonperm + ///
     qoe_contrib_continuity + qoe_contrib_hours + ///
     qoe_contrib_socialins)) < 1e-12 if qoe_complete == 1

local qoe_contrib qoe_contrib_income50 qoe_contrib_nonperm ///
    qoe_contrib_continuity qoe_contrib_hours qoe_contrib_socialins

local qoe_event qoe_deprivation_score50 qoe_income_deprivation50 ///
    qoe_stability_deprivation qoe_conditions_deprivation

local qoe_event_names score50 income50 stability conditions

****************************************************
* 5. Main DiD regressions: primary QoE outcomes
****************************************************

estimates clear

local i = 1
foreach yvar of local qoe_main {
    local ystem : word `i' of `qoe_main_names'

    reg `yvar' i.male##i.post_military `controls_qoe' ///
        if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
    estimates store qoe_did_`ystem'
    capture noisily boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    local boot_rc = _rc
    if `boot_rc' {
        display as error "Wild-bootstrap failed for main DiD outcome `yvar' (return code `boot_rc')."
        exit `boot_rc'
    }
    if missing(r(p)) {
        display as text "Wild-bootstrap returned a missing p-value for main DiD outcome `yvar'; retrying once."
        capture noisily boottest 1.male#1.post_military, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        local boot_rc = _rc
        if `boot_rc' {
            display as error "Wild-bootstrap retry failed for main DiD outcome `yvar' (return code `boot_rc')."
            exit `boot_rc'
        }
        if missing(r(p)) {
            display as error "Wild-bootstrap retry returned a missing p-value for main DiD outcome `yvar'."
            exit 498
        }
    }
    scalar boot_p_qoe_did_`ystem' = r(p)
    estadd scalar boot_p = boot_p_qoe_did_`ystem' : qoe_did_`ystem'

    local ++i
}

****************************************************
* 6. Main DiD regressions: two-thirds income cutoff robustness
****************************************************

reg qoe_deprivation_score667 i.male##i.post_military `controls_qoe' ///
    if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
estimates store qoe_did_score667
capture noisily boottest 1.male#1.post_military, ///
    cluster(cohort) reps(9999) seed(12345) nograph
local boot_rc = _rc
if `boot_rc' {
    display as error "Wild-bootstrap failed for robustness outcome qoe_deprivation_score667 (return code `boot_rc')."
    exit `boot_rc'
}
scalar boot_p_qoe_did_score667 = r(p)
estadd scalar boot_p = boot_p_qoe_did_score667 : qoe_did_score667

reg qoe_multidim_deprived667 i.male##i.post_military `controls_qoe' ///
    if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
estimates store qoe_did_multidim667
capture noisily boottest 1.male#1.post_military, ///
    cluster(cohort) reps(9999) seed(12345) nograph
local boot_rc = _rc
if `boot_rc' {
    display as error "Wild-bootstrap failed for robustness outcome qoe_multidim_deprived667 (return code `boot_rc')."
    exit `boot_rc'
}
scalar boot_p_qoe_did_multidim667 = r(p)
estadd scalar boot_p = boot_p_qoe_did_multidim667 : qoe_did_multidim667

reg qoe_income_deprivation667 i.male##i.post_military `controls_qoe' ///
    if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
estimates store qoe_did_income667
capture noisily boottest 1.male#1.post_military, ///
    cluster(cohort) reps(9999) seed(12345) nograph
local boot_rc = _rc
if `boot_rc' {
    display as error "Wild-bootstrap failed for robustness outcome qoe_income_deprivation667 (return code `boot_rc')."
    exit `boot_rc'
}
scalar boot_p_qoe_did_income667 = r(p)
estadd scalar boot_p = boot_p_qoe_did_income667 : qoe_did_income667

****************************************************
* 7. Decomposition DiD regressions
* Raw components show which deprivation indicators move.
* Weighted contributions show each component's contribution to the
* overall QoE score, using the score's exact weights.
****************************************************

local i = 1
foreach yvar of local qoe_decomp {
    local ystem : word `i' of `qoe_decomp_names'

    reg `yvar' i.male##i.post_military `controls_qoe' ///
        if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
    estimates store qoe_decomp_`ystem'
    capture noisily boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    local boot_rc = _rc
    if `boot_rc' {
        display as error "Wild-bootstrap failed for decomposition outcome `yvar' (return code `boot_rc')."
        exit `boot_rc'
    }
    scalar boot_p_qoe_decomp_`ystem' = r(p)
    estadd scalar boot_p = boot_p_qoe_decomp_`ystem' : qoe_decomp_`ystem'

    local ++i
}

foreach yvar of local qoe_contrib {
    local ystem = subinstr("`yvar'", "qoe_contrib_", "", .)

    reg `yvar' i.male##i.post_military `controls_qoe' ///
        if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
    estimates store qoe_contrib_`ystem'
    capture noisily boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    local boot_rc = _rc
    if `boot_rc' {
        display as error "Wild-bootstrap failed for weighted contribution `yvar' (return code `boot_rc')."
        exit `boot_rc'
    }
    scalar boot_p_qoe_contrib_`ystem' = r(p)
    estadd scalar boot_p = boot_p_qoe_contrib_`ystem' : qoe_contrib_`ystem'
}

****************************************************
* 8. Continuous treatment intensity regressions
****************************************************

local i = 1
foreach yvar of local qoe_main {
    local ystem : word `i' of `qoe_main_names'

    reg `yvar' i.male##c.service_months_saved `controls_qoe' ///
        if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
    estimates store qoe_int_`ystem'
    capture noisily boottest 1.male#c.service_months_saved, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    local boot_rc = _rc
    if `boot_rc' {
        display as error "Wild-bootstrap failed for intensity outcome `yvar' (return code `boot_rc')."
        exit `boot_rc'
    }
    scalar boot_p_qoe_int_`ystem' = r(p)
    estadd scalar boot_p = boot_p_qoe_int_`ystem' : qoe_int_`ystem'

    local ++i
}

****************************************************
* 9. DiD by 2015-2017 industry gender type
* Industry gender type is fixed in 02_append.do.
* Subgroup regressions exclude industry fixed effects.
****************************************************

tab industry_gender_type if wage_worker == 1 & qoe_complete == 1, missing

local i = 1
foreach yvar of local qoe_main {
    local ystem : word `i' of `qoe_main_names'
    if "`ystem'" == "score50" local shorty sc50
    if "`ystem'" == "multidim50" local shorty md50
    if "`ystem'" == "income50" local shorty inc50
    if "`ystem'" == "stability" local shorty stab
    if "`ystem'" == "conditions" local shorty cond

    reg `yvar' i.male##i.post_military `controls_qoe' ///
        if wage_worker == 1 & qoe_complete == 1 ///
        & !missing(industry_gender_type), vce(cluster cohort)
    estimates store qm_`shorty'_all
    capture noisily boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    local boot_rc = _rc
    if `boot_rc' {
        display as error "Wild-bootstrap failed for full industry sample, outcome `yvar' (return code `boot_rc')."
        exit `boot_rc'
    }
    scalar boot_p_qoe_main = r(p)
    estadd scalar boot_p = boot_p_qoe_main : qm_`shorty'_all

    foreach g in 1 2 3 {
        if `g' == 1 local gname maleind
        if `g' == 2 local gname femaleind
        if `g' == 3 local gname mixedind
        if `g' == 1 local shortg male
        if `g' == 2 local shortg fem
        if `g' == 3 local shortg mix

        reg `yvar' i.male##i.post_military `controls_qoe' ///
            if wage_worker == 1 & qoe_complete == 1 ///
            & industry_gender_type == `g', vce(cluster cohort)
        estimates store qm_`shorty'_`shortg'
        capture noisily boottest 1.male#1.post_military, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        local boot_rc = _rc
        if `boot_rc' {
            display as error "Wild-bootstrap failed for outcome `yvar', industry group `g' (return code `boot_rc')."
            exit `boot_rc'
        }
        scalar boot_p_qoe_main = r(p)
        estadd scalar boot_p = boot_p_qoe_main : qm_`shorty'_`shortg'
    }

    local ++i
}

****************************************************
* 10. Event-study regressions and wild-bootstrap
* joint pre-trend tests
* Reference cohort: k=-1, birth cohort 1996, rel_shift=4.
* Event-study regressions use vce(cluster cohort), matching DiD.
****************************************************

postfile pretrend_results str40 outcome double wild_p_pretrend ///
    using "$OUT/qoe_eventstudy_pretrend_pvalues.dta", replace

local i = 1
foreach yvar of local qoe_event {
    local ystem : word `i' of `qoe_event_names'

    reg `yvar' i.male##ib4.rel_shift `controls_qoe' ///
        if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
    estimates store qoe_es_`ystem'

    capture boottest 1.male#0.rel_shift 1.male#1.rel_shift ///
        1.male#2.rel_shift 1.male#3.rel_shift, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    if !_rc scalar pretrend_p = r(p)
    else scalar pretrend_p = .
    post pretrend_results ("`yvar'") (pretrend_p)

    tempfile coef_`ystem'
    postfile handle str40 outcome int rel_cohort double beta se lb ub ///
        wild_p using "`coef_`ystem''", replace

    forvalues k = -5/5 {
        local s = `k' + 5
        if `k' == -1 {
            post handle ("`yvar'") (`k') (0) (0) (0) (0) (.)
        }
        else {
            capture lincom 1.male#`s'.rel_shift
            if !_rc {
                scalar es_beta = r(estimate)
                scalar es_se = r(se)
                scalar es_lb = r(estimate) - 1.96*r(se)
                scalar es_ub = r(estimate) + 1.96*r(se)

                capture boottest 1.male#`s'.rel_shift, ///
                    cluster(cohort) reps(9999) seed(12345) nograph
                if !_rc scalar es_wild_p = r(p)
                else scalar es_wild_p = .

                post handle ("`yvar'") (`k') (es_beta) (es_se) ///
                    (es_lb) (es_ub) (es_wild_p)
            }
        }
    }
    postclose handle

    preserve
        quietly use "`coef_`ystem''", clear
        export delimited using "$OUT/qoe_eventstudy_`ystem'.csv", replace
    restore

    local ++i
}

postclose pretrend_results

preserve
    use "$OUT/qoe_eventstudy_pretrend_pvalues.dta", clear
    export delimited using "$OUT/qoe_eventstudy_pretrend_pvalues.csv", replace
restore

****************************************************
* 11. Event-study plots
* Confidence intervals are clustered-regression CIs.
* Wild-bootstrap coefficient p-values are saved in the CSVs.
****************************************************

local i = 1
foreach yvar of local qoe_event {
    local ystem : word `i' of `qoe_event_names'

    preserve
        import delimited using "$OUT/qoe_eventstudy_`ystem'.csv", clear
        sort rel_cohort

        quietly summarize beta if rel_cohort == -5
        local pretitle ""

        twoway ///
            (rcap lb ub rel_cohort, lcolor(gs8)) ///
            (connected beta rel_cohort, msymbol(O) msize(medium) ///
                lcolor(navy) mcolor(navy)), ///
            xline(-0.5, lpattern(dash) lcolor(red)) ///
            yline(0, lpattern(dash) lcolor(gs10)) ///
            xtitle("Relative birth cohort (k)") ///
            ytitle("Male × cohort coefficient (ref: k=-1)") ///
            title("QoE event study: `yvar'") ///
            note("Regression uses vce(cluster cohort). Wild-bootstrap p-values saved in CSV.") ///
            legend(off)

        graph export "$OUT/qoe_eventstudy_`ystem'.png", replace
    restore

    local ++i
}

****************************************************
* 12. Binned event study
* Bins follow policy exposure: two pre-reform bins, the k=-1 base,
* partial reduction (k=0 to 2), and full reduction (k=3 to 5).
* Graphs show point estimates only. Clustered SEs and wild-bootstrap
* p-values are saved in CSVs; conventional CIs are intentionally omitted.
****************************************************

postfile binned_pretrend_results str40 outcome double wild_p_pretrend ///
    using "$OUT/qoe_binned_eventstudy_pretrend_pvalues.dta", replace

local i = 1
foreach yvar of local qoe_event {
    local ystem : word `i' of `qoe_event_names'

    reg `yvar' i.male##ib2.qoe_event_bin `controls_qoe' ///
        if wage_worker == 1 & qoe_complete == 1, vce(cluster cohort)
    estimates store qoe_bes_`ystem'

    capture noisily boottest 1.male#0.qoe_event_bin ///
        1.male#1.qoe_event_bin, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    local boot_rc = _rc
    if `boot_rc' {
        display as error "Wild-bootstrap binned pretrend test failed for `yvar' (return code `boot_rc')."
        exit `boot_rc'
    }
    if missing(r(p)) {
        display as error "Wild-bootstrap binned pretrend test returned a missing p-value for `yvar'."
        exit 498
    }
    scalar binned_pretrend_p = r(p)
    post binned_pretrend_results ("`yvar'") (binned_pretrend_p)

    tempfile binned_coef_`ystem'
    postfile binned_handle str40 outcome byte event_bin str32 bin_label ///
        double beta cluster_se wild_p using "`binned_coef_`ystem''", replace

    forvalues b = 0/4 {
        if `b' == 2 {
            post binned_handle ("`yvar'") (`b') ("Reference (k=-1)") ///
                (0) (0) (.)
        }
        else {
            lincom 1.male#`b'.qoe_event_bin
            scalar binned_beta = r(estimate)
            scalar binned_se = r(se)

            capture noisily boottest 1.male#`b'.qoe_event_bin, ///
                cluster(cohort) reps(9999) seed(12345) nograph
            local boot_rc = _rc
            if `boot_rc' {
                display as error "Wild-bootstrap failed for `yvar', event bin `b' (return code `boot_rc')."
                exit `boot_rc'
            }
            if missing(r(p)) {
                display as error "Wild-bootstrap returned a missing p-value for `yvar', event bin `b'."
                exit 498
            }
            scalar binned_wild_p = r(p)

            local blabel : label qoe_event_bin_lbl `b'
            post binned_handle ("`yvar'") (`b') ("`blabel'") ///
                (binned_beta) (binned_se) (binned_wild_p)
        }
    }
    postclose binned_handle

    preserve
        quietly use "`binned_coef_`ystem''", clear
        export delimited using ///
            "$OUT/qoe_binned_eventstudy_`ystem'.csv", replace

        twoway ///
            (connected beta event_bin, msymbol(O) msize(medium) ///
                lcolor(navy) mcolor(navy)), ///
            xline(2.5, lpattern(dash) lcolor(red)) ///
            yline(0, lpattern(dash) lcolor(gs10)) ///
            xlabel(0 "Early pre" 1 "Near pre" 2 "Reference" ///
                3 "Partial" 4 "Full", angle(30)) ///
            xtitle("Birth-cohort exposure bin") ///
            ytitle("Male × bin coefficient (ref: k=-1)") ///
            title("Binned QoE event study: `yvar'") ///
            note("Points are estimates; cohort wild-bootstrap p-values are saved in CSV.") ///
            legend(off)

        graph export "$OUT/qoe_binned_eventstudy_`ystem'.png", replace
    restore

    local ++i
}

postclose binned_pretrend_results

preserve
    use "$OUT/qoe_binned_eventstudy_pretrend_pvalues.dta", clear
    export delimited using ///
        "$OUT/qoe_binned_eventstudy_pretrend_pvalues.csv", replace
restore

****************************************************
* 13. Export tables
****************************************************

estimates dir

capture which esttab
if !_rc {

    * ---- Main QoE DiD outcomes, primary 50% income cutoff ----
    esttab qoe_did_score50 qoe_did_multidim50 qoe_did_income50 ///
        qoe_did_stability qoe_did_conditions ///
        using "$OUT/qoe_panel_a_did.tex", replace ///
        keep(1.male#1.post_military) ///
        coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
        mtitles("QoE score" "Multidim. deprived" "Income" ///
            "Stability" "Conditions") ///
        se star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    * ---- Two-thirds income cutoff robustness ----
    esttab qoe_did_score667 qoe_did_multidim667 qoe_did_income667 ///
        using "$OUT/qoe_panel_a_did_robust667.tex", replace ///
        keep(1.male#1.post_military) ///
        coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
        mtitles("QoE score" "Multidim. deprived" "Income") ///
        se star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    * ---- QoE intensity specification ----
    esttab qoe_int_score50 qoe_int_multidim50 qoe_int_income50 ///
        qoe_int_stability qoe_int_conditions ///
        using "$OUT/qoe_panel_b_intensity.tex", replace ///
        keep(1.male#c.service_months_saved) ///
        coeflabels(1.male#c.service_months_saved "Months saved \$\times\$ Male") ///
        mtitles("QoE score" "Multidim. deprived" "Income" ///
            "Stability" "Conditions") ///
        se star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    * ---- Decomposition: raw deprivation indicators ----
    esttab qoe_decomp_lowwage50 qoe_decomp_nonperm ///
        qoe_decomp_continuity qoe_decomp_hours qoe_decomp_socialins ///
        using "$OUT/qoe_decomposition_did.tex", replace ///
        keep(1.male#1.post_military) ///
        coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
        mtitles("Low wage" "Non-permanent" "No continuity" ///
            "Hours >48" "Lacks insurance") ///
        se star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    * ---- Decomposition: weighted contribution to overall score ----
    esttab qoe_contrib_income50 qoe_contrib_nonperm ///
        qoe_contrib_continuity qoe_contrib_hours qoe_contrib_socialins ///
        using "$OUT/qoe_weighted_contribution_did.tex", replace ///
        keep(1.male#1.post_military) ///
        coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
        mtitles("Income contrib." "Nonperm. contrib." ///
            "Continuity contrib." "Hours contrib." "Insurance contrib.") ///
        se star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    * ---- Main QoE DiD table by industry gender type ----
    esttab qm_sc50_all qm_sc50_male qm_sc50_fem qm_sc50_mix ///
        qm_md50_all qm_md50_male qm_md50_fem qm_md50_mix ///
        qm_inc50_all qm_inc50_male qm_inc50_fem qm_inc50_mix ///
        qm_stab_all qm_stab_male qm_stab_fem qm_stab_mix ///
        qm_cond_all qm_cond_male qm_cond_fem qm_cond_mix ///
        using "$OUT/qoe_did_by_industry_gender_type.tex", replace ///
        keep(1.male#1.post_military) ///
        coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
        mtitles("Full" "Male-dom." "Female-dom." "Mixed" ///
            "Full" "Male-dom." "Female-dom." "Mixed" ///
            "Full" "Male-dom." "Female-dom." "Mixed" ///
            "Full" "Male-dom." "Female-dom." "Mixed" ///
            "Full" "Male-dom." "Female-dom." "Mixed") ///
        mgroups("QoE score" "Multidim. deprived" "Income" ///
            "Stability" "Conditions", ///
            pattern(1 0 0 0 1 0 0 0 1 0 0 0 1 0 0 0 1 0 0 0) ///
            prefix("\multicolumn{@span}{c}{") suffix("}") span) ///
        se star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment
}

****************************************************
* End
****************************************************
