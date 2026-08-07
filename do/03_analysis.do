****************************************************
* 03. Analysis: 2018 military-service reduction
* Representative enlistment age: 20
* First affected cohort: born 1997, k = 0
* Full 3-month reduction cohort: born 2000+, k >= 3
* Required packages (install once via command window)
*	ssc install boottest, replace
*	ssc install estout, replace
****************************************************

clear all
set more off
set varabbrev off

* Run after 00_globals.do and 02_append.do.
* Make output path robust: Stata writes CSV/PNG/RTF to an absolute folder.
* If your master data path differs, keep the CLEAN global from 00_globals.do.
capture confirm global CLEAN
if _rc {
    * If globals were not loaded, assume this file is run from the project root.
    global CLEAN "data_clean"
}

capture confirm global OUT
if _rc {
    global OUT "`c(pwd)'/output"
}
else {
    * Convert relative OUT paths such as "output" into absolute paths.
    if substr("$OUT",1,1)!="/" & substr("$OUT",2,1)!=":" {
        global OUT "`c(pwd)'/$OUT"
    }
}

capture mkdir "$OUT"
display as text "Output folder: $OUT"

* Keep a timestamped text log so warnings, omitted terms, cluster counts,
* and regression sample sizes can be audited without overwriting prior runs.
local analysis_run_date = subinstr("`c(current_date)'", " ", "", .)
local analysis_run_time = subinstr("`c(current_time)'", ":", "", .)
capture log close analysis03
log using "$OUT/03_analysis_`analysis_run_date'_`analysis_run_time'.log", ///
    text name(analysis03)

use "$CLEAN/mdis_master_2001_2025.dta", clear

****************************************************
* 1. Sample
****************************************************

* Main sample: post-reform window matching the dissertation setup
keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year)

* Cohort definition based on representative enlistment at age 20
* 1997-born: age-20 enlistment year 2017, first affected cohort
* 2000-born: age-20 enlistment year 2020, full 3-month reduction cohort

gen cohort = birth_year
gen enlist_year20 = birth_year + 20
gen rel_cohort = birth_year - 1997
label variable rel_cohort "Birth cohort relative to 1997-born first affected cohort"

* Event window: adjust if needed
keep if inrange(rel_cohort, -5, 5)

* Stata factor variables cannot always handle negative bases cleanly,
* so shift event time: rel_shift = 0 corresponds k=-5, ..., 4 corresponds k=-1.
gen rel_shift = rel_cohort + 5
label variable rel_shift "Shifted event time; base rel_shift=4 means k=-1"

* Treatment indicators

gen post_military = (birth_year >= 1997) if !missing(birth_year)
label variable post_military "Born 1997 or later: exposed to 2018 military-service reduction"

gen full_reduction = (birth_year >= 2000) if !missing(birth_year)
label variable full_reduction "Born 2000 or later: representative age-20 entrant gets full 3-month reduction"

* Simple cohort-level intensity, in months, under representative-age assumption.
* This is intentionally conservative and transparent, not an individual enlistment record.
gen service_months_saved = .
replace service_months_saved = 0    if birth_year <= 1996
replace service_months_saved = 0.75 if birth_year == 1997
replace service_months_saved = 1.50 if birth_year == 1998
replace service_months_saved = 2.25 if birth_year == 1999
replace service_months_saved = 3.00 if birth_year >= 2000
label variable service_months_saved "Approx. months of military service reduced, age-20 cohort exposure"

****************************************************
* 2. Outcomes
****************************************************

* Job-start timing variable: experience_raw is coded as YYYYMM, e.g. 200808.
* Convert YYYYMM into monthly Stata dates, then infer age at job start as:
* current survey age - elapsed months between job start and survey month / 12.
* Note: this is age at the start of the reported job spell. Confirm from codebook
* whether this is first-job start date or current-job start date.


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

****기존 변수설계
gen entry_age = age - job_tenure_months/12 if age < . & job_tenure_months < .
replace entry_age = . if entry_age < 10 | entry_age > age
label variable entry_age "Age at reported job start, inferred from YYYYMM start date"
label variable job_tenure_months "Months between reported job start and survey month"

gen job_tenure_years = job_tenure_months/12 if job_tenure_months < .
label variable job_tenure_years "Current-job tenure / work experience in years"


* Wage outcome: trim raw hourly wage at p1/p99, then log
summ hourly_wage if hourly_wage > 0, detail
scalar p1_hw  = r(p1)
scalar p99_hw = r(p99)

gen hourly_wage_trim = hourly_wage if hourly_wage >= p1_hw & hourly_wage <= p99_hw
gen log_hourly_wage_trim = log(hourly_wage_trim) if hourly_wage_trim > 0
label variable hourly_wage_trim "Hourly wage, p1-p99 trimmed"
label variable log_hourly_wage_trim "Log hourly wage, p1-p99 trimmed"

* Large-firm outcome already created in 01_clean_all.do
label variable largefirm "Employed in large firm, firm size code == 6"

* Full-time / permanent role outcome
* worker_status_raw: 1=regular/permanent employee, 2=temporary, 3=daily worker
* hours_week >= 36 is used as a transparent full-time proxy.
*gen fulltime = .
*replace fulltime = 1 if hours_week >= 36 & hours_week < .
*replace fulltime = 0 if hours_week < 36 & hours_week >= 0
*label variable fulltime "Full-time proxy: usual weekly hours >= 36"


****************************************************
* 3. Controls
****************************************************

* Baseline controls: do not control for age in entry_age regressions mechanically
local controls_basic i.educ_raw i.year
local controls_wage  c.job_tenure_years i.educ_raw i.year 
local controls_job   c.job_tenure_years i.educ_raw i.year 

clonevar industry_fe = industry_code

* Rich controls: use only where categories are not missing
* For wage regressions, prefer job tenure/experience over age because military service
* creates gender differences in work experience at the same age.
local controls_rich_wage c.job_tenure_years i.educ_raw i.year i.industry_fe i.occupation_code
local controls_rich_job  c.job_tenure_years i.educ_raw i.year i.industry_fe i.occupation_code
local controls_sub_wage  c.job_tenure_years i.educ_raw i.year i.occupation_code
local controls_sub_job   c.job_tenure_years i.educ_raw i.year i.occupation_code

* Diagnostic: confirm that tenure, not age, is used in wage/job controls
display as text "controls_wage: `controls_wage'"
display as text "controls_job:   `controls_job'"
display as text "controls_rich_job: `controls_rich_job'"
display as text "controls_rich_wage: `controls_rich_wage'"
display as text "controls_sub_job: `controls_sub_job'"
display as text "controls_sub_wage: `controls_sub_wage'"

********************************************************
* 4. Labour-market entry DiD + Wild Cluster Bootstrap
* Job-quality outcomes are analysed in 05_build_qoe_outcomes.do and
* 06_analysis_qoe.do; this file focuses on employment and entry timing.
********************************************************

estimates clear

*---- employed ----
reg employed i.male##i.post_military `controls_basic', vce(cluster cohort)

* Descriptive denominator used to express the employment DiD estimate as a
* percentage of untreated men's mean employment. Restrict to the exact
* employment-regression sample so missing controls cannot alter the denominator.
scalar employed_did_beta = _b[1.male#1.post_military]
quietly summarize employed if e(sample) & male == 1 & post_military == 0
scalar untreated_male_employment_mean = r(mean)
scalar untreated_male_employment_N = r(N)
quietly levelsof cohort if e(sample) & male == 1 & post_military == 0, ///
    local(untreated_male_cohorts)
local untreated_male_cluster_count : word count `untreated_male_cohorts'
scalar untreated_male_cluster_N = ///
    `untreated_male_cluster_count'
scalar employed_relative_magnitude_pct = ///
    100 * abs(employed_did_beta) / untreated_male_employment_mean

tempfile untreated_male_mean_data
tempname untreated_male_mean_handle
postfile `untreated_male_mean_handle' ///
    double employment_mean employment_percent did_coefficient ///
    relative_magnitude_percent untreated_male_N untreated_male_cohorts ///
    using `untreated_male_mean_data', replace
post `untreated_male_mean_handle' ///
    (untreated_male_employment_mean) ///
    (100 * untreated_male_employment_mean) ///
    (employed_did_beta) (employed_relative_magnitude_pct) ///
    (untreated_male_employment_N) (untreated_male_cluster_N)
postclose `untreated_male_mean_handle'

preserve
    use `untreated_male_mean_data', clear
    export delimited using ///
        "$OUT/employment_untreated_male_mean.csv", replace
    save "$OUT/employment_untreated_male_mean.dta", replace
restore

matrix untreated_male_mean_table = ///
    (untreated_male_employment_mean, ///
     100 * untreated_male_employment_mean, ///
     employed_did_beta, employed_relative_magnitude_pct, ///
     untreated_male_employment_N, untreated_male_cluster_N)
matrix rownames untreated_male_mean_table = employment
matrix colnames untreated_male_mean_table = ///
    mean proportion_percent did_coefficient relative_percent N cohorts

capture which esttab
if !_rc {
    esttab matrix(untreated_male_mean_table, ///
        fmt(%9.4f %9.2f %9.4f %9.2f %9.0f %9.0f)) ///
        using "$OUT/employment_untreated_male_mean.tex", replace ///
        coeflabels(employment "Employment") ///
        collabels("Untreated-male mean" "Mean (percent)" ///
            "DiD coefficient" "Relative magnitude (percent)" ///
            "Observations" "Cohorts") ///
        mlabels(none) booktabs nonumber noobs fragment ///
        addnotes("Untreated men are men born before 1997 in the exact estimation sample of the main employment DiD regression." ///
            "Relative magnitude is 100 times the absolute DiD coefficient divided by the untreated-male employment mean.")
}

estimates store did_employed
*Wild cluster bootstrap p-value for the interaction term
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_employed = r(p)
estadd scalar boot_p = boot_p_did_employed : did_employed

*---- entry_age: timing among wage workers ----
reg entry_age i.male##i.post_military `controls_basic' ///
    if wage_worker == 1, vce(cluster cohort)
estimates store did_entry
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_entry = r(p)
estadd scalar boot_p = boot_p_did_entry : did_entry

* Continuous treatment intensity alternative
reg employed i.male##c.service_months_saved `controls_basic', vce(cluster cohort)
estimates store int_employed
boottest 1.male#c.service_months_saved, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_int_employed = r(p)
estadd scalar boot_p = boot_p_int_employed : int_employed

reg entry_age i.male##c.service_months_saved `controls_basic' ///
    if wage_worker == 1, vce(cluster cohort)
estimates store int_entry
boottest 1.male#c.service_months_saved, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_int_entry = r(p)
estadd scalar boot_p = boot_p_int_entry : int_entry

* esttab normally derives stars from the conventional regression p-values.
* Attach a coefficient-aligned p-value matrix to each stored model so that
* stars on the treatment interaction instead use the wild-bootstrap p-value.
foreach model in did_employed did_entry int_employed int_entry {
    estimates restore `model'
    matrix wild_pvals = e(b)
    forvalues j = 1/`=colsof(wild_pvals)' {
        matrix wild_pvals[1,`j'] = .
    }

    if inlist("`model'", "did_employed", "did_entry") {
        local target_term "1.male#1.post_military"
    }
    else {
        local target_term "1.male#c.service_months_saved"
    }
    matrix wild_pvals[1,colnumb(wild_pvals,"`target_term'")] = ///
        boot_p_`model'
    estadd matrix wild_pvals = wild_pvals, replace
    estimates drop `model'
    estimates store `model'
}

****************************************************
* Bootstrap p-values print & save
****************************************************

* print
foreach outcome in did_employed did_entry int_employed int_entry {
    display "`outcome': boot p = " boot_p_`outcome'
}

* CSV saving
postfile boot_results str30 spec double boot_p using "$OUT/bootstrap_pvalues.dta", replace

foreach outcome in did_employed did_entry int_employed int_entry {
    post boot_results ("`outcome'") (boot_p_`outcome')
}

postclose boot_results

*Do not touch original data and save seperately
preserve
	use "$OUT/bootstrap_pvalues.dta", clear
	export delimited using "$OUT/bootstrap_pvalues.csv", replace
restore

****************************************************
* 5. Event-study regressions
* Reference cohort: k=-1, birth cohort 1996, rel_shift=4
* Plotted pointwise 95% confidence intervals use cohort-clustered standard
* errors and a t critical value with G-1 cluster degrees of freedom.
* Formal inference continues to use wild-cluster-bootstrap tests.
* Wild-bootstrap joint pre-trend p-values test k=-5 to k=-2.
****************************************************

postfile pretrend_results str40 outcome double wild_p_pretrend ///
    using "$OUT/eventstudy_pretrend_pvalues.dta", replace

foreach yvar in employed entry_age {

    local sample_if ""

    if "`yvar'" == "employed" {
        local ctrls `controls_basic'
    }
    else if "`yvar'" == "entry_age" {
        local ctrls `controls_basic'
        local sample_if "if wage_worker == 1"
    }

    reg `yvar' i.male##ib4.rel_shift `ctrls' `sample_if', vce(cluster cohort)
    estimates store es_`yvar'
    scalar es_tcrit = invttail(e(df_r), .025)

    capture boottest 1.male#0.rel_shift 1.male#1.rel_shift ///
        1.male#2.rel_shift 1.male#3.rel_shift, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    if !_rc scalar pretrend_p = r(p)
    else scalar pretrend_p = .
    post pretrend_results ("`yvar'") (pretrend_p)

    * Export event-study coefficients for plotting elsewhere if desired
    tempfile coef_`yvar'
    postfile handle str30 outcome int rel_cohort double beta se lb ub ///
        using "`coef_`yvar''", replace

    forvalues k = -5/5 {
        local s = `k' + 5
        if `k' == -1 {
            post handle ("`yvar'") (`k') (0) (0) (0) (0)
        }
        else {
            capture lincom 1.male#`s'.rel_shift
            if !_rc {
                post handle ("`yvar'") (`k') (r(estimate)) (r(se)) ///
                    (r(estimate) - es_tcrit*r(se)) ///
                    (r(estimate) + es_tcrit*r(se))
            }
        }
    }
    postclose handle

    preserve
        quietly use "`coef_`yvar''", clear
        export delimited using "$OUT/eventstudy_`yvar'.csv", replace
    restore
}

postclose pretrend_results

preserve
    use "$OUT/eventstudy_pretrend_pvalues.dta", clear
    export delimited using "$OUT/eventstudy_pretrend_pvalues.csv", replace
restore

****************************************************
* 6. Quick built-in plots from exported coefficients
****************************************************

foreach yvar in employed entry_age {
    preserve
        import delimited using "$OUT/eventstudy_`yvar'.csv", clear
        sort rel_cohort

        twoway ///
    (rcap lb ub rel_cohort, lcolor(gs8)) ///
    (connected beta rel_cohort, msymbol(O) msize(medium) lcolor(navy) mcolor(navy)), ///
    xline(-0.5, lpattern(dash) lcolor(red)) ///
    yline(0, lpattern(dash) lcolor(gs10)) ///
    xtitle("Relative birth cohort (k)") ///
    ytitle("Male × cohort coefficient (ref: k=-1)") ///
    title("Event study: `yvar'") ///
    legend(off)

        graph export "$OUT/eventstudy_`yvar'.png", replace
    restore
}

****************************************************
* 7. Export proposal table
****************************************************

estimates dir

capture which esttab
if !_rc {

* ---- Panel A: Baseline DiD ----
esttab did_entry did_employed ///
    using "$OUT/panel_a_did.tex", replace ///
    keep(1.male#1.post_military) ///
    coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
    mtitles("Entry age" "Employed") ///
    cells(b(star pvalue(wild_pvals) fmt(3)) se(par fmt(3))) ///
    starlevels(* 0.10 ** 0.05 *** 0.01) ///
    stats(N boot_p, labels("Observations" "Wild-bootstrap \$p\$-value") ///
        fmt(%9.0fc %9.3f)) ///
    addnotes("Standard errors clustered by birth cohort (11 clusters)." ///
        "Inference uses wild-cluster-bootstrap p-values; 0.000 denotes p<0.001.") ///
    booktabs nonumber fragment

* ---- Panel B ----
esttab int_entry int_employed ///
    using "$OUT/panel_b_intensity.tex", replace ///
    keep(1.male#c.service_months_saved) ///
    coeflabels(1.male#c.service_months_saved "Months saved \$\times\$ Male") ///
    mtitles("Entry age" "Employed") ///
    cells(b(star pvalue(wild_pvals) fmt(3)) se(par fmt(3))) ///
    starlevels(* 0.10 ** 0.05 *** 0.01) ///
    stats(N boot_p, labels("Observations" "Wild-bootstrap \$p\$-value") ///
        fmt(%9.0fc %9.3f)) ///
    addnotes("Standard errors clustered by birth cohort (11 clusters)." ///
        "Inference uses wild-cluster-bootstrap p-values; 0.000 denotes p<0.001.") ///
    booktabs nonumber fragment

}
* End
****************************************************

log close analysis03
