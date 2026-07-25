****************************************************
* 11. Robustness: alternative representative enlistment ages
* 2018 military-service reduction
*
* Main analysis assumes representative enlistment at age 20.
* This script repeats the employment and entry-age analysis assuming
* representative enlistment at ages 19, 20, and 21.
*
* All specifications use the same 1992-2002 birth-cohort sample.
* Holding the cohort sample fixed ensures that differences across
* specifications reflect the enlistment-age assumption rather than
* changes in sample composition.
*
* Run after:
*   00_globals.do
*   01_clean_all.do
*   02_append.do
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

local analysis_run_date = subinstr("`c(current_date)'", " ", "", .)
local analysis_run_time = subinstr("`c(current_time)'", ":", "", .)
capture log close analysis11
log using "$OUT/11_analysis_enlist_age_robustness_`analysis_run_date'_`analysis_run_time'.log", ///
    text name(analysis11)

capture confirm file "$CLEAN/mdis_master_2001_2025.dta"
if _rc {
    display as error "Master file not found: $CLEAN/mdis_master_2001_2025.dta"
    display as error "Run 00_globals.do, 01_clean_all.do, and 02_append.do first."
    exit 601
}

use "$CLEAN/mdis_master_2001_2025.dta", clear

****************************************************
* 1. Required variables
****************************************************

foreach v in year age male birth_year wage_worker employed ///
    experience_raw survey_ym educ_raw {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found."
        display as error "Run upstream do-files before this robustness script."
        exit 111
    }
}

****************************************************
* 2. Common sample and entry-age outcome
****************************************************

keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year)

gen cohort = birth_year

* Use the main analysis's 1992-2002 cohort window in every specification.
* Do not redefine the estimation sample around each alternative treatment
* threshold, since doing so would confound treatment timing with composition.
keep if inrange(birth_year, 1992, 2002)

gen job_start_year  = floor(experience_raw/100) if experience_raw < .
gen job_start_month = mod(experience_raw,100)  if experience_raw < .
replace job_start_year  = . if job_start_year < 1900 | job_start_year > year
replace job_start_month = . if !inrange(job_start_month,1,12)

gen survey_year_from_ym  = floor(survey_ym/100) if survey_ym < .
gen survey_month_from_ym = mod(survey_ym,100)  if survey_ym < .
replace survey_year_from_ym  = year if missing(survey_year_from_ym)
replace survey_month_from_ym = 8 ///
    if missing(survey_month_from_ym) | !inrange(survey_month_from_ym,1,12)

gen job_start_tm = ym(job_start_year, job_start_month)
gen survey_tm    = ym(survey_year_from_ym, survey_month_from_ym)
format job_start_tm survey_tm %tm

gen job_tenure_months = survey_tm - job_start_tm ///
    if job_start_tm < . & survey_tm < .
replace job_tenure_months = . if job_tenure_months < 0

gen entry_age = age - job_tenure_months/12 ///
    if age < . & job_tenure_months < .
replace entry_age = . if entry_age < 10 | entry_age > age
label variable entry_age "Age at reported job start, inferred from YYYYMM start date"

local controls_basic i.educ_raw i.year
display as text "controls_basic: `controls_basic'"

tempfile base_sample
save "`base_sample'", replace

****************************************************
* 3. Alternative representative enlistment-age analyses
****************************************************

estimates clear

postfile pretrend_results byte enlist_age str20 outcome ///
    double wild_p_pretrend using ///
    "$OUT/enlistage_commoncohort_eventstudy_pretrend_pvalues.dta", replace

foreach enlist_age in 19 20 21 {
    use "`base_sample'", clear

    * First affected cohort is defined by representative enlistment in 2017:
    *   birth_year + representative enlistment age = 2017.
    local first_affected = 2017 - `enlist_age'
    local full_reduction = `first_affected' + 3
    local min_rel = 1992 - `first_affected'
    local max_rel = 2002 - `first_affected'

    gen representative_enlist_age = `enlist_age'
    gen enlist_year_rep = birth_year + representative_enlist_age
    gen rel_cohort = birth_year - `first_affected'
    label variable rel_cohort ///
        "Birth cohort relative to first affected cohort under enlist-age assumption"

    * Shift all possible event times to positive factor-variable values.
    * With the common cohort sample, k ranges from -6 to 6 across assumptions.
    gen rel_shift = rel_cohort + 7
    label variable rel_shift "Shifted event time; base rel_shift=6 means k=-1"

    gen post_military = (birth_year >= `first_affected') ///
        if !missing(birth_year)
    label variable post_military ///
        "Exposed to 2018 military-service reduction under enlist-age assumption"

    gen full_reduction = (birth_year >= `full_reduction') ///
        if !missing(birth_year)
    label variable full_reduction ///
        "Full 3-month reduction under enlist-age assumption"

    gen service_months_saved = .
    replace service_months_saved = 0    if birth_year <= `first_affected' - 1
    replace service_months_saved = 0.75 if birth_year == `first_affected'
    replace service_months_saved = 1.50 if birth_year == `first_affected' + 1
    replace service_months_saved = 2.25 if birth_year == `first_affected' + 2
    replace service_months_saved = 3.00 if birth_year >= `first_affected' + 3
    label variable service_months_saved ///
        "Approx. months saved under alternative enlist-age assumption"

    display as text "Representative enlistment age: `enlist_age'"
    display as text "First affected cohort: `first_affected'"
    display as text "Full reduction cohort: `full_reduction' and later"
    tab rel_cohort, missing

    ****************************************************
    * 3A. DiD and intensity regressions
    ****************************************************

    reg employed i.male##i.post_military `controls_basic', ///
        vce(cluster cohort)
    estimates store ea`enlist_age'_did_emp
    boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_ea`enlist_age'_did_emp = r(p)
    estadd scalar boot_p = boot_p_ea`enlist_age'_did_emp : ///
        ea`enlist_age'_did_emp

    reg entry_age i.male##i.post_military `controls_basic' ///
        if wage_worker == 1, vce(cluster cohort)
    estimates store ea`enlist_age'_did_entry
    boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_ea`enlist_age'_did_entry = r(p)
    estadd scalar boot_p = boot_p_ea`enlist_age'_did_entry : ///
        ea`enlist_age'_did_entry

    reg employed i.male##c.service_months_saved `controls_basic', ///
        vce(cluster cohort)
    estimates store ea`enlist_age'_int_emp
    boottest 1.male#c.service_months_saved, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_ea`enlist_age'_int_emp = r(p)
    estadd scalar boot_p = boot_p_ea`enlist_age'_int_emp : ///
        ea`enlist_age'_int_emp

    reg entry_age i.male##c.service_months_saved `controls_basic' ///
        if wage_worker == 1, vce(cluster cohort)
    estimates store ea`enlist_age'_int_entry
    boottest 1.male#c.service_months_saved, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_ea`enlist_age'_int_entry = r(p)
    estadd scalar boot_p = boot_p_ea`enlist_age'_int_entry : ///
        ea`enlist_age'_int_entry

    ****************************************************
    * 3B. Event-study regressions and plots
    ****************************************************

    foreach yvar in employed entry_age {
        local sample_if ""
        if "`yvar'" == "entry_age" local sample_if "if wage_worker == 1"

        reg `yvar' i.male##ib6.rel_shift `controls_basic' `sample_if', ///
            vce(cluster cohort)
        estimates store ea`enlist_age'_es_`yvar'

        * Jointly test every available pre-treatment interaction except k=-1.
        local pretrend_terms ""
        forvalues k = `min_rel'/-2 {
            local s = `k' + 7
            local pretrend_terms ///
                "`pretrend_terms' 1.male#`s'.rel_shift"
        }
        capture boottest `pretrend_terms', ///
            cluster(cohort) reps(9999) seed(12345) nograph
        if !_rc scalar pretrend_p = r(p)
        else scalar pretrend_p = .
        post pretrend_results (`enlist_age') ("`yvar'") (pretrend_p)

        tempfile coef_ea`enlist_age'_`yvar'
        postfile handle str20 outcome byte enlist_age int rel_cohort ///
            double beta se lb ub using ///
            "`coef_ea`enlist_age'_`yvar''", replace

        forvalues k = `min_rel'/`max_rel' {
            local s = `k' + 7
            if `k' == -1 {
                post handle ("`yvar'") (`enlist_age') (`k') ///
                    (0) (0) (0) (0)
            }
            else {
                capture lincom 1.male#`s'.rel_shift
                if !_rc {
                    post handle ("`yvar'") (`enlist_age') (`k') ///
                        (r(estimate)) (r(se)) ///
                        (r(estimate) - invnormal(.975)*r(se)) ///
                        (r(estimate) + invnormal(.975)*r(se))
                }
            }
        }
        postclose handle

        preserve
            use "`coef_ea`enlist_age'_`yvar''", clear
            sort rel_cohort
            export delimited using ///
                "$OUT/enlistage`enlist_age'_commoncohort_eventstudy_`yvar'.csv", replace

            twoway ///
                (rcap lb ub rel_cohort, lcolor(gs8)) ///
                (connected beta rel_cohort, msymbol(O) msize(medium) ///
                    lcolor(navy) mcolor(navy)), ///
                xline(-0.5, lpattern(dash) lcolor(red)) ///
                yline(0, lpattern(dash) lcolor(gs10)) ///
                xtitle("Relative birth cohort (k)") ///
                ytitle("Male × cohort coefficient (ref: k=-1)") ///
                title("Event study: `yvar', enlist age `enlist_age'") ///
                note("Common 1992-2002 cohorts; vce(cluster cohort).") ///
                legend(off)

            graph export ///
                "$OUT/enlistage`enlist_age'_commoncohort_eventstudy_`yvar'.png", replace
        restore
    }
}

postclose pretrend_results

preserve
    use "$OUT/enlistage_commoncohort_eventstudy_pretrend_pvalues.dta", clear
    export delimited using ///
        "$OUT/enlistage_commoncohort_eventstudy_pretrend_pvalues.csv", replace
restore

****************************************************
* 4. Export tables
****************************************************

capture which esttab
if !_rc {
    esttab ea19_did_emp ea19_did_entry ea20_did_emp ea20_did_entry ///
        ea21_did_emp ea21_did_entry ///
        using "$OUT/enlistage_commoncohort_did.tex", replace ///
        keep(1.male#1.post_military) ///
        coeflabels(1.male#1.post_military ///
            "Post-reform \$\times\$ Male") ///
        mtitles("Emp., age 19" "Entry age, age 19" ///
            "Emp., age 20" "Entry age, age 20" ///
            "Emp., age 21" "Entry age, age 21") ///
        se star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    esttab ea19_int_emp ea19_int_entry ea20_int_emp ea20_int_entry ///
        ea21_int_emp ea21_int_entry ///
        using "$OUT/enlistage_commoncohort_intensity.tex", replace ///
        keep(1.male#c.service_months_saved) ///
        coeflabels(1.male#c.service_months_saved ///
            "Months saved \$\times\$ Male") ///
        mtitles("Emp., age 19" "Entry age, age 19" ///
            "Emp., age 20" "Entry age, age 20" ///
            "Emp., age 21" "Entry age, age 21") ///
        se star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment
}
else display as error "esttab not installed; regression tables not exported."

****************************************************
* 5. QoE outcomes under alternative enlistment ages
*
* Use the QoE master separately so that adding QoE outcomes does not
* alter the employment and entry-age samples estimated above.
****************************************************

capture confirm file "$CLEAN/mdis_master_qoe_2001_2025.dta"
if _rc {
    display as error ///
        "QoE master file not found: $CLEAN/mdis_master_qoe_2001_2025.dta"
    display as error ///
        "Run 00_globals.do, 01_clean_all.do, 02_append.do, and 05_build_qoe_outcomes.do first."
    exit 601
}

use "$CLEAN/mdis_master_qoe_2001_2025.dta", clear

* Remove stale internal temporary variables carried in the QoE master.
* boottest also uses these reserved names; retaining them corrupts the first
* bootstrap call after each reload of the common QoE sample.
capture drop __000000 __000001

foreach v in year age male birth_year wage_worker educ_raw qoe_complete ///
    qoe_deprivation_score50 qoe_multidim_deprived50 ///
    qoe_income_deprivation50 qoe_stability_deprivation ///
    qoe_conditions_deprivation {
    capture confirm variable `v'
    if _rc {
        display as error "Required QoE variable `v' not found."
        display as error "Run 05_build_qoe_outcomes.do before this script."
        exit 111
    }
}

keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year)

gen cohort = birth_year

* Hold the main 1992-2002 birth-cohort sample fixed across all assumptions.
keep if inrange(birth_year, 1992, 2002)

local controls_qoe i.educ_raw i.year
local qoe_main qoe_deprivation_score50 qoe_multidim_deprived50 ///
    qoe_income_deprivation50 qoe_stability_deprivation ///
    qoe_conditions_deprivation
local qoe_main_names score50 multidim50 income50 stability conditions

* Match the unbinned event-study outcomes in 06_analysis_qoe.do.
local qoe_event qoe_deprivation_score50 qoe_income_deprivation50 ///
    qoe_stability_deprivation qoe_conditions_deprivation
local qoe_event_names score50 income50 stability conditions

tempfile qoe_base_sample
save "`qoe_base_sample'", replace

postfile qoe_results str12 specification byte enlist_age str40 outcome ///
    double beta se wild_p N r2 using ///
    "$OUT/enlistage_qoe_commoncohort_results.dta", replace

foreach enlist_age in 19 20 21 {
    use "`qoe_base_sample'", clear

    local first_affected = 2017 - `enlist_age'
    local min_rel = 1992 - `first_affected'
    local max_rel = 2002 - `first_affected'

    gen representative_enlist_age = `enlist_age'
    gen enlist_year_rep = birth_year + representative_enlist_age
    gen rel_cohort = birth_year - `first_affected'
    gen rel_shift = rel_cohort + 7

    gen post_military = (birth_year >= `first_affected') ///
        if !missing(birth_year)

    gen service_months_saved = .
    replace service_months_saved = 0 ///
        if birth_year <= `first_affected' - 1
    replace service_months_saved = 0.75 ///
        if birth_year == `first_affected'
    replace service_months_saved = 1.50 ///
        if birth_year == `first_affected' + 1
    replace service_months_saved = 2.25 ///
        if birth_year == `first_affected' + 2
    replace service_months_saved = 3.00 ///
        if birth_year >= `first_affected' + 3

    ****************************************************
    * 5A. QoE DiD and treatment-intensity regressions
    ****************************************************

    local i = 1
    foreach yvar of local qoe_main {
        local ystem : word `i' of `qoe_main_names'

        reg `yvar' i.male##i.post_military `controls_qoe' ///
            if wage_worker == 1 & qoe_complete == 1, ///
            vce(cluster cohort)
        estimates store qea`enlist_age'_did_`ystem'

        capture noisily boottest 1.male#1.post_military, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        local boot_rc = _rc
        if `boot_rc' {
            display as error ///
                "QoE DiD wild-bootstrap failed: age `enlist_age', outcome `yvar' (return code `boot_rc')."
            exit `boot_rc'
        }
        if missing(r(p)) {
            display as text ///
                "QoE DiD wild-bootstrap returned a missing p-value; retrying once."
            capture noisily boottest 1.male#1.post_military, ///
                cluster(cohort) reps(9999) seed(12345) nograph
            local boot_rc = _rc
            if `boot_rc' | missing(r(p)) {
                display as error ///
                    "QoE DiD wild-bootstrap retry failed: age `enlist_age', outcome `yvar'."
                exit 498
            }
        }
        scalar qoe_boot_p = r(p)
        estadd scalar boot_p = qoe_boot_p : ///
            qea`enlist_age'_did_`ystem'
        post qoe_results ("DiD") (`enlist_age') ("`yvar'") ///
            (_b[1.male#1.post_military]) ///
            (_se[1.male#1.post_military]) (qoe_boot_p) (e(N)) (e(r2))

        reg `yvar' i.male##c.service_months_saved `controls_qoe' ///
            if wage_worker == 1 & qoe_complete == 1, ///
            vce(cluster cohort)
        estimates store qea`enlist_age'_int_`ystem'

        capture noisily boottest 1.male#c.service_months_saved, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        local boot_rc = _rc
        if `boot_rc' {
            display as error ///
                "QoE intensity wild-bootstrap failed: age `enlist_age', outcome `yvar' (return code `boot_rc')."
            exit `boot_rc'
        }
        if missing(r(p)) {
            display as text ///
                "QoE intensity wild-bootstrap returned a missing p-value; retrying once."
            capture noisily boottest 1.male#c.service_months_saved, ///
                cluster(cohort) reps(9999) seed(12345) nograph
            local boot_rc = _rc
            if `boot_rc' | missing(r(p)) {
                display as error ///
                    "QoE intensity wild-bootstrap retry failed: age `enlist_age', outcome `yvar'."
                exit 498
            }
        }
        scalar qoe_boot_p = r(p)
        estadd scalar boot_p = qoe_boot_p : ///
            qea`enlist_age'_int_`ystem'
        post qoe_results ("Intensity") (`enlist_age') ("`yvar'") ///
            (_b[1.male#c.service_months_saved]) ///
            (_se[1.male#c.service_months_saved]) ///
            (qoe_boot_p) (e(N)) (e(r2))

        local ++i
    }
}

postclose qoe_results

* Open the event-study postfile only after closing the DiD/intensity
* postfile. Keeping both postfiles open while boottest runs can cause
* internal temporary-variable collisions and invalid bootstrap p-values.
postfile qoe_pretrend_results byte enlist_age str40 outcome ///
    double wild_p_pretrend using ///
    "$OUT/enlistage_qoe_commoncohort_eventstudy_pretrend_pvalues.dta", replace

foreach enlist_age in 19 20 21 {
    use "`qoe_base_sample'", clear

    local first_affected = 2017 - `enlist_age'
    local min_rel = 1992 - `first_affected'
    local max_rel = 2002 - `first_affected'

    gen representative_enlist_age = `enlist_age'
    gen enlist_year_rep = birth_year + representative_enlist_age
    gen rel_cohort = birth_year - `first_affected'
    gen rel_shift = rel_cohort + 7

    gen post_military = (birth_year >= `first_affected') ///
        if !missing(birth_year)

    ****************************************************
    * 5B. QoE event-study regressions and plots
    ****************************************************

    local i = 1
    foreach yvar of local qoe_event {
        local ystem : word `i' of `qoe_event_names'

        reg `yvar' i.male##ib6.rel_shift `controls_qoe' ///
            if wage_worker == 1 & qoe_complete == 1, ///
            vce(cluster cohort)
        estimates store qea`enlist_age'_es_`ystem'

        local pretrend_terms ""
        forvalues k = `min_rel'/-2 {
            local s = `k' + 7
            local pretrend_terms ///
                "`pretrend_terms' 1.male#`s'.rel_shift"
        }
        capture noisily boottest `pretrend_terms', ///
            cluster(cohort) reps(9999) seed(12345) nograph
        if !_rc scalar qoe_pretrend_p = r(p)
        else scalar qoe_pretrend_p = .
        post qoe_pretrend_results (`enlist_age') ("`yvar'") ///
            (qoe_pretrend_p)

        tempfile qoe_coef_ea`enlist_age'_`ystem'
        postfile qoe_handle str40 outcome byte enlist_age int rel_cohort ///
            double beta se lb ub using ///
            "`qoe_coef_ea`enlist_age'_`ystem''", replace

        forvalues k = `min_rel'/`max_rel' {
            local s = `k' + 7
            if `k' == -1 {
                post qoe_handle ("`yvar'") (`enlist_age') (`k') ///
                    (0) (0) (0) (0)
            }
            else {
                capture lincom 1.male#`s'.rel_shift
                if !_rc {
                    post qoe_handle ("`yvar'") (`enlist_age') (`k') ///
                        (r(estimate)) (r(se)) ///
                        (r(estimate) - invnormal(.975)*r(se)) ///
                        (r(estimate) + invnormal(.975)*r(se))
                }
            }
        }
        postclose qoe_handle

        preserve
            use "`qoe_coef_ea`enlist_age'_`ystem''", clear
            sort rel_cohort
            export delimited using ///
                "$OUT/enlistage_qoe`enlist_age'_commoncohort_eventstudy_`ystem'.csv", replace

            twoway ///
                (rcap lb ub rel_cohort, lcolor(gs8)) ///
                (connected beta rel_cohort, msymbol(O) msize(medium) ///
                    lcolor(navy) mcolor(navy)), ///
                xline(-0.5, lpattern(dash) lcolor(red)) ///
                yline(0, lpattern(dash) lcolor(gs10)) ///
                xtitle("Relative birth cohort (k)") ///
                ytitle("Male × cohort coefficient (ref: k=-1)") ///
                title("QoE event study: `ystem', enlist age `enlist_age'") ///
                note("Common 1992-2002 cohorts; vce(cluster cohort).") ///
                legend(off)

            graph export ///
                "$OUT/enlistage_qoe`enlist_age'_commoncohort_eventstudy_`ystem'.png", replace
        restore

        local ++i
    }
}

postclose qoe_pretrend_results

preserve
    use "$OUT/enlistage_qoe_commoncohort_results.dta", clear
    sort specification outcome enlist_age
    export delimited using ///
        "$OUT/enlistage_qoe_commoncohort_results.csv", replace
restore

preserve
    use ///
        "$OUT/enlistage_qoe_commoncohort_eventstudy_pretrend_pvalues.dta", ///
        clear
    sort outcome enlist_age
    export delimited using ///
        "$OUT/enlistage_qoe_commoncohort_eventstudy_pretrend_pvalues.csv", ///
        replace
restore

****************************************************
* 6. Export compact QoE tables by outcome
****************************************************

capture which esttab
if !_rc {
    local i = 1
    foreach yvar of local qoe_main {
        local ystem : word `i' of `qoe_main_names'

        esttab qea19_did_`ystem' qea20_did_`ystem' qea21_did_`ystem' ///
            using "$OUT/enlistage_qoe_commoncohort_did_`ystem'.tex", ///
            replace keep(1.male#1.post_military) ///
            coeflabels(1.male#1.post_military ///
                "Post-reform \$\times\$ Male") ///
            mtitles("Age 19" "Age 20" "Age 21") ///
            se star(* 0.10 ** 0.05 *** 0.01) ///
            stats(N r2 boot_p, ///
                labels("Observations" "R-squared" ///
                    "Bootstrap \$p\$-value") ///
                fmt(%9.0fc %9.3f %9.3f)) ///
            booktabs nonumber nonotes fragment

        esttab qea19_int_`ystem' qea20_int_`ystem' qea21_int_`ystem' ///
            using ///
                "$OUT/enlistage_qoe_commoncohort_intensity_`ystem'.tex", ///
            replace keep(1.male#c.service_months_saved) ///
            coeflabels(1.male#c.service_months_saved ///
                "Months saved \$\times\$ Male") ///
            mtitles("Age 19" "Age 20" "Age 21") ///
            se star(* 0.10 ** 0.05 *** 0.01) ///
            stats(N r2 boot_p, ///
                labels("Observations" "R-squared" ///
                    "Bootstrap \$p\$-value") ///
                fmt(%9.0fc %9.3f %9.3f)) ///
            booktabs nonumber nonotes fragment

        local ++i
    }
}
else display as error "esttab not installed; QoE tables not exported."

capture log close analysis11

****************************************************
* End
****************************************************
