****************************************************
* 13. Robustness: first-job entry age from May Youth Supplement
* Reform: 2018 military-service reduction
* Representative enlistment age: 20
* First affected cohort: born 1997, k = 0
* Outcome is measured in months; birth month is assumed to be 6.5.
*
* Run after 00_globals.do and 12_clean_may_youth.do.
****************************************************

clear all
set more off
set varabbrev off

capture confirm global CLEAN
if _rc global CLEAN "data_clean"

capture confirm global OUT
if _rc global OUT "output"

capture mkdir "$OUT"

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

local run_date = subinstr("`c(current_date)'", " ", "", .)
local run_time = subinstr("`c(current_time)'", ":", "", .)
capture log close analysis13
log using "$OUT/13_analysis_may_entry_age_`run_date'_`run_time'.log", ///
    text name(analysis13)

use "$CLEAN/mdis_may_youth_2015_2025.dta", clear

****************************************************
* 1. Sample and 2018-reform exposure
****************************************************

* Keep the same k=-5,...,5 birth-cohort window as the main specification.
keep if inrange(birth_year,1992,2002)
keep if !missing(male, birth_year)

generate int cohort = birth_year
generate int rel_cohort = birth_year - 1997
generate byte rel_shift = rel_cohort + 5

generate byte post_military = (birth_year >= 1997)

generate double service_months_saved = 0
replace service_months_saved = 0.75 if birth_year == 1997
replace service_months_saved = 1.50 if birth_year == 1998
replace service_months_saved = 2.25 if birth_year == 1999
replace service_months_saved = 3.00 if birth_year >= 2000

label variable rel_cohort ///
    "Birth cohort relative to 1997-born first affected cohort"
label variable post_military ///
    "Born 1997 or later: exposed to 2018 service reduction"
label variable service_months_saved ///
    "Approx. months of military service reduction"

* First-job questions refer to employment after graduation or dropout.
* The main robustness sample further matches the main analysis by retaining
* wage employment at the first job. Every restriction is reported below.
generate byte entry_sample_all = firstjob_experience == 1 & ///
    !missing(entry_age_months, educ_raw)
generate byte entry_sample_wage = entry_sample_all == 1 & ///
    firstjob_wage_worker == 1
generate byte valid_weight = !missing(popwt) & popwt > 0

* Economic activity status: 1 employed, 2 unemployed, 3 inactive.
* Unlike the entry-age sample, this outcome does not condition on graduation,
* dropout, or having entered a first job.
generate byte employed = (activity_status_raw == 1) ///
    if inrange(activity_status_raw,1,3)
generate byte employed_sample = !missing(employed, male, birth_year, educ_raw)

* Decompose first-job entry age into school-exit age and the duration from
* school exit to the first post-school job. Birth month is again assumed to
* be 6.5, so the components add exactly to entry_age_months.
generate int school_exit_year = floor(school_exit_ym_raw/100) ///
    if !missing(school_exit_ym_raw)
generate byte school_exit_month = mod(school_exit_ym_raw,100) ///
    if !missing(school_exit_ym_raw)
generate byte invalid_school_exit_date = ///
    (!inrange(school_exit_month,1,12) | ///
    school_exit_year < birth_year | school_exit_year > year) ///
    if !missing(school_exit_ym_raw, birth_year)
replace school_exit_year = . if invalid_school_exit_date == 1
replace school_exit_month = . if invalid_school_exit_date == 1

generate double school_exit_age_months = ///
    12*(school_exit_year-birth_year) + school_exit_month - 6.5 ///
    if !missing(school_exit_year, school_exit_month, birth_year)
generate byte implausible_school_exit_age = ///
    !inrange(school_exit_age_months,120,420) ///
    if !missing(school_exit_age_months)
replace school_exit_age_months = . ///
    if implausible_school_exit_age == 1

generate double school_to_firstjob_months = ///
    entry_age_months - school_exit_age_months ///
    if !missing(entry_age_months, school_exit_age_months)
generate byte negative_school_to_firstjob = ///
    school_to_firstjob_months < 0 ///
    if !missing(school_to_firstjob_months)

generate byte school_exit_sample = ///
    !missing(school_exit_age_months, male, birth_year, educ_raw)
generate byte school_to_firstjob_sample = ///
    entry_sample_wage == 1 & ///
    !missing(school_to_firstjob_months) & ///
    negative_school_to_firstjob == 0

label variable school_exit_age_months ///
    "School-exit age (months; birth month assumed 6.5)"
label variable school_to_firstjob_months ///
    "Months from school exit to first post-school job"

tab year entry_sample_all, missing
tab year entry_sample_wage, missing
tab cohort entry_sample_wage, missing
tab male entry_sample_wage, missing
tab year employed if employed_sample == 1, missing
tab cohort employed_sample, missing
tab year school_exit_sample, missing
tab year school_to_firstjob_sample, missing
tab negative_school_to_firstjob, missing

****************************************************
* 2. DiD and treatment-intensity regressions
****************************************************

local controls i.educ_raw i.year
estimates clear

* Preferred estimates: first wage job, survey population weights.
reg entry_age_months i.male##i.post_military `controls' [pw=popwt] ///
    if entry_sample_wage == 1 & valid_weight == 1, vce(cluster cohort)
estimates store may_did_w

scalar boot_p_may_did_w = .
capture noisily boottest 1.male#1.post_military, ///
    cluster(cohort) reps(9999) seed(12345) nograph
if !_rc scalar boot_p_may_did_w = r(p)
capture estadd scalar boot_p = boot_p_may_did_w : may_did_w

reg entry_age_months i.male##c.service_months_saved `controls' ///
    [pw=popwt] if entry_sample_wage == 1 & valid_weight == 1, ///
    vce(cluster cohort)
estimates store may_int_w

scalar boot_p_may_int_w = .
capture noisily boottest 1.male#c.service_months_saved, ///
    cluster(cohort) reps(9999) seed(12345) nograph
if !_rc scalar boot_p_may_int_w = r(p)
capture estadd scalar boot_p = boot_p_may_int_w : may_int_w

* Unweighted estimates diagnose sensitivity to survey weights.
reg entry_age_months i.male##i.post_military `controls' ///
    if entry_sample_wage == 1, vce(cluster cohort)
estimates store may_did_uw

scalar boot_p_may_did_uw = .
capture noisily boottest 1.male#1.post_military, ///
    cluster(cohort) reps(9999) seed(12345) nograph
if !_rc scalar boot_p_may_did_uw = r(p)
capture estadd scalar boot_p = boot_p_may_did_uw : may_did_uw

reg entry_age_months i.male##c.service_months_saved `controls' ///
    if entry_sample_wage == 1, vce(cluster cohort)
estimates store may_int_uw

scalar boot_p_may_int_uw = .
capture noisily boottest 1.male#c.service_months_saved, ///
    cluster(cohort) reps(9999) seed(12345) nograph
if !_rc scalar boot_p_may_int_uw = r(p)
capture estadd scalar boot_p = boot_p_may_int_uw : may_int_uw

****************************************************
* 3. Save compact regression results
****************************************************

tempname results
postfile `results' str20 specification double beta se boot_p N r2 ///
    using "$OUT/may_youth_entry_age_results.dta", replace

estimates restore may_did_w
post `results' ("DiD weighted") ///
    (_b[1.male#1.post_military]) (_se[1.male#1.post_military]) ///
    (boot_p_may_did_w) (e(N)) (e(r2))

estimates restore may_int_w
post `results' ("Intensity weighted") ///
    (_b[1.male#c.service_months_saved]) ///
    (_se[1.male#c.service_months_saved]) ///
    (boot_p_may_int_w) (e(N)) (e(r2))

estimates restore may_did_uw
post `results' ("DiD unweighted") ///
    (_b[1.male#1.post_military]) (_se[1.male#1.post_military]) ///
    (boot_p_may_did_uw) (e(N)) (e(r2))

estimates restore may_int_uw
post `results' ("Intensity unweighted") ///
    (_b[1.male#c.service_months_saved]) ///
    (_se[1.male#c.service_months_saved]) ///
    (boot_p_may_int_uw) (e(N)) (e(r2))

postclose `results'

preserve
    use "$OUT/may_youth_entry_age_results.dta", clear
    export delimited using "$OUT/may_youth_entry_age_results.csv", replace
restore

****************************************************
* 4. Event studies
* Reference cohort: 1996-born, k=-1, rel_shift=4.
* The unweighted specification matches the main analysis. The weighted
* specification is retained as a separate survey-weight robustness check.
****************************************************

foreach es_spec in unweighted weighted {

    local weight_clause
    local sample_if "if entry_sample_wage == 1"
    local estimates_name "may_es_uw"
    local graph_note ///
        "Unweighted; matches main specification; reference cohort k=-1."

    if "`es_spec'" == "weighted" {
        local weight_clause "[pw=popwt]"
        local sample_if ///
            "if entry_sample_wage == 1 & valid_weight == 1"
        local estimates_name "may_es_w"
        local graph_note ///
            "Survey weighted; reference cohort k=-1."
    }

    reg entry_age_months i.male##ib4.rel_shift `controls' ///
        `weight_clause' `sample_if', vce(cluster cohort)
    estimates store `estimates_name'

    scalar may_pretrend_p_`es_spec' = .
    capture noisily boottest 1.male#0.rel_shift 1.male#1.rel_shift ///
        1.male#2.rel_shift 1.male#3.rel_shift, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    if !_rc scalar may_pretrend_p_`es_spec' = r(p)

    tempfile es_coefs
    tempname es_handle
    postfile `es_handle' int rel_cohort double beta se lb ub ///
        using `es_coefs', replace

    forvalues k = -5/5 {
        local s = `k' + 5
        if `k' == -1 {
            post `es_handle' (`k') (0) (0) (0) (0)
        }
        else {
            capture lincom 1.male#`s'.rel_shift
            if !_rc {
                post `es_handle' (`k') ///
                    (r(estimate)) (r(se)) ///
                    (r(estimate)-1.96*r(se)) ///
                    (r(estimate)+1.96*r(se))
            }
        }
    }
    postclose `es_handle'

    preserve
        use `es_coefs', clear
        generate double wild_pretrend_p = ///
            may_pretrend_p_`es_spec'
        export delimited using ///
            "$OUT/may_youth_entry_age_eventstudy_`es_spec'.csv", ///
            replace

        twoway ///
            (rcap lb ub rel_cohort, lcolor(gs8)) ///
            (connected beta rel_cohort, msymbol(O) msize(medium) ///
                lcolor(navy) mcolor(navy)), ///
            xline(-0.5, lpattern(dash) lcolor(red)) ///
            yline(0, lpattern(dash) lcolor(gs10)) ///
            xtitle("Relative birth cohort (k)") ///
            ytitle("Male x cohort effect on entry age (months)") ///
            title("First-job entry age: May Youth Supplement") ///
            note("`graph_note' 95% confidence intervals.") ///
            legend(off)

        graph export ///
            "$OUT/may_youth_entry_age_eventstudy_`es_spec'.png", ///
            replace
    restore
}

****************************************************
* 5. Employment event studies
* This sample does not condition on observed first-job entry. Comparing its
* pre-trends with entry age helps diagnose first-job censoring and selection.
****************************************************

foreach es_spec in unweighted weighted {

    local weight_clause
    local sample_if "if employed_sample == 1"
    local estimates_name "may_emp_es_uw"
    local graph_note ///
        "Unweighted; matches main specification; reference cohort k=-1."

    if "`es_spec'" == "weighted" {
        local weight_clause "[pw=popwt]"
        local sample_if ///
            "if employed_sample == 1 & valid_weight == 1"
        local estimates_name "may_emp_es_w"
        local graph_note ///
            "Survey weighted; reference cohort k=-1."
    }

    reg employed i.male##ib4.rel_shift `controls' ///
        `weight_clause' `sample_if', vce(cluster cohort)
    estimates store `estimates_name'

    scalar may_emp_pretrend_p_`es_spec' = .
    capture noisily boottest 1.male#0.rel_shift 1.male#1.rel_shift ///
        1.male#2.rel_shift 1.male#3.rel_shift, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    if !_rc scalar may_emp_pretrend_p_`es_spec' = r(p)

    tempfile emp_es_coefs
    tempname emp_es_handle
    postfile `emp_es_handle' int rel_cohort double beta se lb ub ///
        using `emp_es_coefs', replace

    forvalues k = -5/5 {
        local s = `k' + 5
        if `k' == -1 {
            post `emp_es_handle' (`k') (0) (0) (0) (0)
        }
        else {
            capture lincom 1.male#`s'.rel_shift
            if !_rc {
                post `emp_es_handle' (`k') ///
                    (r(estimate)) (r(se)) ///
                    (r(estimate)-1.96*r(se)) ///
                    (r(estimate)+1.96*r(se))
            }
        }
    }
    postclose `emp_es_handle'

    preserve
        use `emp_es_coefs', clear
        generate double wild_pretrend_p = ///
            may_emp_pretrend_p_`es_spec'
        export delimited using ///
            "$OUT/may_youth_employed_eventstudy_`es_spec'.csv", ///
            replace

        twoway ///
            (rcap lb ub rel_cohort, lcolor(gs8)) ///
            (connected beta rel_cohort, msymbol(O) msize(medium) ///
                lcolor(navy) mcolor(navy)), ///
            xline(-0.5, lpattern(dash) lcolor(red)) ///
            yline(0, lpattern(dash) lcolor(gs10)) ///
            xtitle("Relative birth cohort (k)") ///
            ytitle("Male x cohort effect on employment") ///
            title("Employment: May Youth Supplement") ///
            note("`graph_note' 95% confidence intervals.") ///
            legend(off)

        graph export ///
            "$OUT/may_youth_employed_eventstudy_`es_spec'.png", ///
            replace
    restore
}

****************************************************
* 6. Decomposition event studies
* First-job entry age = school-exit age + school-to-first-job duration.
* Both components use the same valid first-wage-job transition sample so
* their regression coefficients are additively comparable.
****************************************************

foreach yvar in school_exit_age_months school_to_firstjob_months {

    local outcome_name "school_exit_age"
    local outcome_tag "exit"
    local outcome_title "School-exit age"
    local y_axis_title ///
        "Male x cohort effect on school-exit age (months)"
    local base_sample "school_to_firstjob_sample == 1"

    if "`yvar'" == "school_to_firstjob_months" {
        local outcome_name "school_to_firstjob"
        local outcome_tag "transition"
        local outcome_title "School-to-first-job duration"
        local y_axis_title ///
            "Male x cohort effect on transition duration (months)"
        local base_sample "school_to_firstjob_sample == 1"
    }

    foreach es_spec in unweighted weighted {

        local spec_tag "uw"
        local weight_clause
        local sample_if "if `base_sample'"
        local estimates_name ///
            "may_`outcome_tag'_es_uw"
        local graph_note ///
            "Unweighted; reference cohort k=-1."

        if "`es_spec'" == "weighted" {
            local spec_tag "w"
            local weight_clause "[pw=popwt]"
            local sample_if ///
                "if `base_sample' & valid_weight == 1"
            local estimates_name ///
                "may_`outcome_tag'_es_w"
            local graph_note ///
                "Survey weighted; reference cohort k=-1."
        }

        reg `yvar' i.male##ib4.rel_shift `controls' ///
            `weight_clause' `sample_if', vce(cluster cohort)
        estimates store `estimates_name'

        scalar may_dec_p_`outcome_tag'_`spec_tag' = .
        capture noisily boottest ///
            1.male#0.rel_shift 1.male#1.rel_shift ///
            1.male#2.rel_shift 1.male#3.rel_shift, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        if !_rc scalar may_dec_p_`outcome_tag'_`spec_tag' = r(p)

        tempfile decomposition_es_coefs
        tempname decomposition_es_handle
        postfile `decomposition_es_handle' int rel_cohort ///
            double beta se lb ub using `decomposition_es_coefs', replace

        forvalues k = -5/5 {
            local s = `k' + 5
            if `k' == -1 {
                post `decomposition_es_handle' (`k') (0) (0) (0) (0)
            }
            else {
                capture lincom 1.male#`s'.rel_shift
                if !_rc {
                    post `decomposition_es_handle' (`k') ///
                        (r(estimate)) (r(se)) ///
                        (r(estimate)-1.96*r(se)) ///
                        (r(estimate)+1.96*r(se))
                }
            }
        }
        postclose `decomposition_es_handle'

        preserve
            use `decomposition_es_coefs', clear
            generate double wild_pretrend_p = ///
                may_dec_p_`outcome_tag'_`spec_tag'
            export delimited using ///
                "$OUT/may_youth_`outcome_name'_eventstudy_`es_spec'.csv", ///
                replace

            twoway ///
                (rcap lb ub rel_cohort, lcolor(gs8)) ///
                (connected beta rel_cohort, msymbol(O) msize(medium) ///
                    lcolor(navy) mcolor(navy)), ///
                xline(-0.5, lpattern(dash) lcolor(red)) ///
                yline(0, lpattern(dash) lcolor(gs10)) ///
                xtitle("Relative birth cohort (k)") ///
                ytitle("`y_axis_title'") ///
                title("`outcome_title': May Youth Supplement") ///
                note("`graph_note' 95% confidence intervals.") ///
                legend(off)

            graph export ///
                "$OUT/may_youth_`outcome_name'_eventstudy_`es_spec'.png", ///
                replace
        restore
    }
}

****************************************************
* 7. Common-year-support event studies, 2017-2021
* Every 1992-2002 cohort is within ages 15-29 in every survey year in this
* window. These specifications diagnose changing cohort-by-year support in
* the full 2015-2025 repeated cross-section.
****************************************************

foreach yvar in employed entry_age_months {

    local outcome_name "employed"
    local outcome_tag "emp"
    local outcome_title "Employment"
    local y_axis_title "Male x cohort effect on employment"
    local base_sample ///
        "employed_sample == 1 & inrange(year,2017,2021)"

    if "`yvar'" == "entry_age_months" {
        local outcome_name "entry_age"
        local outcome_tag "entry"
        local outcome_title "First-job entry age"
        local y_axis_title ///
            "Male x cohort effect on entry age (months)"
        local base_sample ///
            "entry_sample_wage == 1 & inrange(year,2017,2021)"
    }

    foreach es_spec in unweighted weighted {

        local spec_tag "uw"
        local weight_clause
        local sample_if "if `base_sample'"
        local estimates_name ///
            "may_common_`outcome_name'_es_uw"
        local graph_note ///
            "Unweighted; common survey years 2017-2021; reference k=-1."

        if "`es_spec'" == "weighted" {
            local spec_tag "w"
            local weight_clause "[pw=popwt]"
            local sample_if ///
                "if `base_sample' & valid_weight == 1"
            local estimates_name ///
                "may_common_`outcome_name'_es_w"
            local graph_note ///
                "Survey weighted; common years 2017-2021; reference k=-1."
        }

        reg `yvar' i.male##ib4.rel_shift `controls' ///
            `weight_clause' `sample_if', vce(cluster cohort)
        estimates store `estimates_name'

        scalar mc_p_`outcome_tag'_`spec_tag' = .
        capture noisily boottest ///
            1.male#0.rel_shift 1.male#1.rel_shift ///
            1.male#2.rel_shift 1.male#3.rel_shift, ///
            cluster(cohort) reps(9999) seed(12345) nograph
        if !_rc scalar mc_p_`outcome_tag'_`spec_tag' = r(p)

        tempfile common_es_coefs
        tempname common_es_handle
        postfile `common_es_handle' int rel_cohort ///
            double beta se lb ub using `common_es_coefs', replace

        forvalues k = -5/5 {
            local s = `k' + 5
            if `k' == -1 {
                post `common_es_handle' (`k') (0) (0) (0) (0)
            }
            else {
                capture lincom 1.male#`s'.rel_shift
                if !_rc {
                    post `common_es_handle' (`k') ///
                        (r(estimate)) (r(se)) ///
                        (r(estimate)-1.96*r(se)) ///
                        (r(estimate)+1.96*r(se))
                }
            }
        }
        postclose `common_es_handle'

        preserve
            use `common_es_coefs', clear
            generate double wild_pretrend_p = ///
                mc_p_`outcome_tag'_`spec_tag'
            export delimited using ///
                "$OUT/may_youth_`outcome_name'_eventstudy_commonyears_`es_spec'.csv", ///
                replace

            twoway ///
                (rcap lb ub rel_cohort, lcolor(gs8)) ///
                (connected beta rel_cohort, msymbol(O) msize(medium) ///
                    lcolor(navy) mcolor(navy)), ///
                xline(-0.5, lpattern(dash) lcolor(red)) ///
                yline(0, lpattern(dash) lcolor(gs10)) ///
                xtitle("Relative birth cohort (k)") ///
                ytitle("`y_axis_title'") ///
                title("`outcome_title': common-year support") ///
                note("`graph_note' 95% confidence intervals.") ///
                legend(off)

            graph export ///
                "$OUT/may_youth_`outcome_name'_eventstudy_commonyears_`es_spec'.png", ///
                replace
        restore
    }
}

****************************************************
* 8. Optional LaTeX table
****************************************************

capture which esttab
if !_rc {
    attach_wild_p may_did_w, term("1.male#1.post_military")
    attach_wild_p may_int_w, term("1.male#c.service_months_saved")
    attach_wild_p may_did_uw, term("1.male#1.post_military")
    attach_wild_p may_int_uw, term("1.male#c.service_months_saved")

    esttab may_did_w may_int_w may_did_uw may_int_uw ///
        using "$OUT/may_youth_entry_age_table.tex", replace ///
        keep(1.male#1.post_military ///
            1.male#c.service_months_saved) ///
        coeflabels(1.male#1.post_military ///
            "Post-reform \$\times\$ Male" ///
            1.male#c.service_months_saved ///
            "Months saved \$\times\$ Male") ///
        mtitles("DiD weighted" "Intensity weighted" ///
            "DiD unweighted" "Intensity unweighted") ///
        cells(b(star pvalue(wild_pvals) fmt(a3)) se(par fmt(a3))) ///
        collabels(none) ///
        starlevels(* 0.10 ** 0.05 *** 0.01) ///
        stats(N boot_p, labels("Observations" ///
            "Wild-bootstrap \$p\$-value") fmt(%9.0fc %9.3f)) ///
        addnotes("Outcome is first-job entry age in months." ///
            "Birth month is assumed to be 6.5." ///
            "Standard errors are clustered by birth cohort.") ///
        booktabs nonumber fragment
}

display as result "May Youth entry-age robustness completed."
display as result "Unweighted event-study pretrend p-value: " ///
    may_pretrend_p_unweighted
display as result "Weighted event-study pretrend p-value: " ///
    may_pretrend_p_weighted
display as result "Unweighted employment pretrend p-value: " ///
    may_emp_pretrend_p_unweighted
display as result "Weighted employment pretrend p-value: " ///
    may_emp_pretrend_p_weighted
display as result ///
    "Common-years unweighted employment pretrend p-value: " ///
    mc_p_emp_uw
display as result ///
    "Common-years weighted employment pretrend p-value: " ///
    mc_p_emp_w
display as result ///
    "Common-years unweighted entry-age pretrend p-value: " ///
    mc_p_entry_uw
display as result ///
    "Common-years weighted entry-age pretrend p-value: " ///
    mc_p_entry_w
display as result ///
    "Unweighted school-exit-age pretrend p-value: " ///
    may_dec_p_exit_uw
display as result ///
    "Weighted school-exit-age pretrend p-value: " ///
    may_dec_p_exit_w
display as result ///
    "Unweighted school-to-first-job pretrend p-value: " ///
    may_dec_p_transition_uw
display as result ///
    "Weighted school-to-first-job pretrend p-value: " ///
    may_dec_p_transition_w

log close analysis13
