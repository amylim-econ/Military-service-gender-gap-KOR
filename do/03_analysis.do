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
* 4. Baseline DiD regressions + Wild Cluster Bootstrap
********************************************************

estimates clear

*---- employed ----
reg employed i.male##i.post_military `controls_basic', vce(cluster cohort)
estimates store did_employed
*Wild cluster bootstrap p-value for the interaction term
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_employed = r(p)
estadd scalar boot_p = boot_p_did_employed : did_employed

*---- monthly_wage ----
reg log_monthly_wage_trim i.male##i.post_military `controls_rich_wage' if wage_worker == 1, vce(cluster cohort)
estimates store did_mwage
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_mwage = r(p)
estadd scalar boot_p = boot_p_did_mwage : did_mwage

*---- entry_age ----
reg entry_age i.male##i.post_military `controls_basic' if wage_worker== 1, vce(cluster cohort)
estimates store did_entry
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_entry = r(p)
estadd scalar boot_p = boot_p_did_entry : did_entry

*---- largefirm ----
reg largefirm i.male##i.post_military `controls_rich_job' if wage_worker == 1, vce(cluster cohort)
estimates store did_largefirm
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_largefirm = r(p)
estadd scalar boot_p = boot_p_did_largefirm : did_largefirm

*---- permanent ----
reg permanent i.male##i.post_military `controls_rich_job' if wage_worker == 1, vce(cluster cohort)
estimates store did_fulltimeperm
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_fulltimeperm = r(p)
estadd scalar boot_p = boot_p_did_fulltimeperm : did_fulltimeperm

*---- log_hourly_wage ----
reg log_hourly_wage_trim i.male##i.post_military `controls_rich_wage' if wage_worker == 1, vce(cluster cohort)
estimates store did_lhw
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_lhw = r(p)
estadd scalar boot_p = boot_p_did_lhw : did_lhw

* Wage with entry-age mediation/control
reg log_hourly_wage_trim i.male##i.post_military c.entry_age `controls_rich_wage' if wage_worker == 1, vce(cluster cohort)
estimates store did_lhw_entry
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_lhw_entry = r(p)
estadd scalar boot_p = boot_p_did_lhw_entry : did_lhw_entry

reg monthly_wage i.male##i.post_military c.entry_age `controls_rich_wage' if wage_worker == 1, vce(cluster cohort)
estimates store did_mwage_entry
boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_did_mwage_entry = r(p)
estadd scalar boot_p = boot_p_did_mwage_entry : did_mwage_entry

* Continuous treatment intensity alternative
reg employed i.male##c.service_months_saved `controls_basic', vce(cluster cohort)
estimates store int_employed
boottest 1.male#c.service_months_saved, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_int_employed = r(p)
estadd scalar boot_p = boot_p_int_employed : int_employed

reg log_monthly_wage_trim i.male##c.service_months_saved `controls_rich_wage' if wage_worker == 1, vce(cluster cohort)
estimates store int_mwage
boottest 1.male#c.service_months_saved, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_int_mwage = r(p)
estadd scalar boot_p = boot_p_int_mwage : int_mwage

reg entry_age i.male##c.service_months_saved `controls_basic' if employed == 1, vce(cluster cohort)
estimates store int_entry
boottest 1.male#c.service_months_saved, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_int_entry = r(p)
estadd scalar boot_p = boot_p_int_entry : int_entry

reg largefirm i.male##c.service_months_saved `controls_rich_job' if employed == 1, vce(cluster cohort)
estimates store int_largefirm
boottest 1.male#c.service_months_saved, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_int_largefirm = r(p)
estadd scalar boot_p = boot_p_int_largefirm : int_largefirm

reg permanent i.male##c.service_months_saved `controls_rich_job' if wage_worker == 1, vce(cluster cohort)
estimates store int_fulltimeperm
boottest 1.male#c.service_months_saved, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_int_fulltimeperm = r(p)
estadd scalar boot_p = boot_p_int_fulltimeperm : int_fulltimeperm

reg log_hourly_wage_trim i.male##c.service_months_saved `controls_rich_wage' if wage_worker == 1, vce(cluster cohort)
estimates store int_lhw
boottest 1.male#c.service_months_saved, cluster(cohort) reps(9999) seed(12345) nograph
scalar boot_p_int_lhw = r(p)
estadd scalar boot_p = boot_p_int_lhw : int_lhw

****************************************************
* 4A. Baseline DiD by 2015-2017 industry gender type
* Industry gender type is fixed at the industry level in 02_append.do.
* Subgroup regressions do not include industry fixed effects.
* The employed outcome is not estimated by current industry type because
* industry is observed for jobs/workers; splitting by current industry would
* condition on employment.
****************************************************

tab industry_gender_type, missing

foreach g in 1 2 3 {
	if `g' == 1 local gname maleind
	if `g' == 2 local gname femaleind
	if `g' == 3 local gname mixedind

	display as text "Subgroup DiD: industry_gender_type == `g' (`gname')"

	reg log_monthly_wage_trim i.male##i.post_military `controls_sub_wage' ///
	    if wage_worker == 1 & industry_gender_type == `g', vce(cluster cohort)
	estimates store did_mwage_`gname'
	capture boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
	if !_rc scalar boot_p_sub = r(p)
	else scalar boot_p_sub = .
	estadd scalar boot_p = boot_p_sub : did_mwage_`gname'

	reg entry_age i.male##i.post_military `controls_basic' ///
	    if wage_worker == 1 & industry_gender_type == `g', vce(cluster cohort)
	estimates store did_entry_`gname'
	capture boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
	if !_rc scalar boot_p_sub = r(p)
	else scalar boot_p_sub = .
	estadd scalar boot_p = boot_p_sub : did_entry_`gname'

	reg largefirm i.male##i.post_military `controls_sub_job' ///
	    if wage_worker == 1 & industry_gender_type == `g', vce(cluster cohort)
	estimates store did_largefirm_`gname'
	capture boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
	if !_rc scalar boot_p_sub = r(p)
	else scalar boot_p_sub = .
	estadd scalar boot_p = boot_p_sub : did_largefirm_`gname'

	reg permanent i.male##i.post_military `controls_sub_job' ///
	    if wage_worker == 1 & industry_gender_type == `g', vce(cluster cohort)
	estimates store did_fulltimeperm_`gname'
	capture boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
	if !_rc scalar boot_p_sub = r(p)
	else scalar boot_p_sub = .
	estadd scalar boot_p = boot_p_sub : did_fulltimeperm_`gname'

	reg log_hourly_wage_trim i.male##i.post_military `controls_sub_wage' ///
	    if wage_worker == 1 & industry_gender_type == `g', vce(cluster cohort)
	estimates store did_lhw_`gname'
	capture boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
	if !_rc scalar boot_p_sub = r(p)
	else scalar boot_p_sub = .
	estadd scalar boot_p = boot_p_sub : did_lhw_`gname'
}

****************************************************
* 4B. Comparable main specification table
* Full sample and industry-gender subgroups use the same controls.
* No industry fixed effects are included in this section.
* The employed outcome is excluded because industry type is assigned
* from observed current industry.
****************************************************

foreach yvar in entry_age largefirm permanent log_hourly_wage_trim log_monthly_wage_trim {

	if "`yvar'" == "entry_age" {
		local ctrls `controls_basic'
		local sample_base "wage_worker == 1"
		local ystem entry
	}
	else if "`yvar'" == "largefirm" {
		local ctrls `controls_sub_job'
		local sample_base "wage_worker == 1"
		local ystem large
	}
	else if "`yvar'" == "permanent" {
		local ctrls `controls_sub_job'
		local sample_base "wage_worker == 1"
		local ystem perm
	}
	else if "`yvar'" == "log_hourly_wage_trim" {
		local ctrls `controls_sub_wage'
		local sample_base "wage_worker == 1"
		local ystem lhw
	}
	else {
		local ctrls `controls_sub_wage'
		local sample_base "wage_worker == 1"
		local ystem mwage
	}

	reg `yvar' i.male##i.post_military `ctrls' ///
	    if `sample_base' & !missing(industry_gender_type), vce(cluster cohort)
	estimates store main_`ystem'_full
	capture boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
	if !_rc scalar boot_p_main = r(p)
	else scalar boot_p_main = .
	estadd scalar boot_p = boot_p_main : main_`ystem'_full

	foreach g in 1 2 3 {
		if `g' == 1 local gname maleind
		if `g' == 2 local gname femaleind
		if `g' == 3 local gname mixedind

		reg `yvar' i.male##i.post_military `ctrls' ///
		    if `sample_base' & industry_gender_type == `g', vce(cluster cohort)
		estimates store main_`ystem'_`gname'
		capture boottest 1.male#1.post_military, cluster(cohort) reps(9999) seed(12345) nograph
		if !_rc scalar boot_p_main = r(p)
		else scalar boot_p_main = .
		estadd scalar boot_p = boot_p_main : main_`ystem'_`gname'
	}
}

****************************************************
* Bootstrap p-values print & save
****************************************************

* print
foreach outcome in did_employed did_mwage did_entry did_largefirm did_fulltimeperm did_lhw did_lhw_entry did_mwage_entry int_employed int_entry int_fulltimeperm int_largefirm int_lhw int_mwage {
    display "`outcome': boot p = " boot_p_`outcome'
}

* CSV saving
postfile boot_results str30 spec double boot_p using "$OUT/bootstrap_pvalues.dta", replace

foreach outcome in did_employed did_mwage did_entry did_largefirm did_fulltimeperm did_lhw did_lhw_entry did_mwage_entry {
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
****************************************************

foreach yvar in employed log_monthly_wage_trim entry_age largefirm permanent log_hourly_wage_trim {

    local sample_if ""

    if "`yvar'" == "employed" {
        local ctrls `controls_basic'
    }
	else if "`yvar'" == "log_monthly_wage_trim" {
		local ctrls `controls_rich_wage'
		local sample_if "if wage_worker == 1"
	}
    else if "`yvar'" == "entry_age" {
        local ctrls `controls_basic'
        local sample_if "if wage_worker == 1"
    }
	else if "`yvar'" == "largefirm" {
        local ctrls `controls_rich_job'
        local sample_if "if wage_worker == 1"
    }
    else if "`yvar'" == "permanent" {
        local ctrls `controls_rich_job'
        local sample_if "if wage_worker == 1"
    }
    else {
        local ctrls `controls_rich_wage'
        local sample_if "if wage_worker == 1"
    }

    reg `yvar' i.male##ib4.rel_shift `ctrls' `sample_if', vce(robust)
    estimates store es_`yvar'

    * Export event-study coefficients for plotting elsewhere if desired
    tempfile coef_`yvar'
    postfile handle str30 outcome int rel_cohort double beta se lb ub using "`coef_`yvar''", replace

    forvalues k = -5/5 {
        local s = `k' + 5
        if `k' == -1 {
            post handle ("`yvar'") (`k') (0) (0) (0) (0)
        }
        else {
            capture lincom 1.male#`s'.rel_shift
            if !_rc {
                post handle ("`yvar'") (`k') (r(estimate)) (r(se)) ///
                    (r(estimate) - 1.96*r(se)) (r(estimate) + 1.96*r(se))
            }
        }
    }
    postclose handle

    preserve
        quietly use "`coef_`yvar''", clear
        capture erase "$OUT/eventstudy_`yvar'.csv"
        export delimited using "$OUT/eventstudy_`yvar'.csv", replace
    restore
}

****************************************************
* 6. Quick built-in plots from exported coefficients
****************************************************

foreach yvar in employed log_monthly_wage_trim entry_age largefirm permanent log_hourly_wage_trim {
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
* 6A. Event-study plots by industry gender type
* Side-by-side graphs compare male-dominated and female-dominated industries.
* Mixed industries are omitted from these figures.
****************************************************

foreach yvar in entry_age largefirm permanent log_hourly_wage_trim {

	if "`yvar'" == "entry_age" {
		local ctrls `controls_basic'
		local sample_base "wage_worker == 1"
		local ytitle "Entry age"
		local ystem entry
	}
	else if "`yvar'" == "largefirm" {
		local ctrls `controls_sub_job'
		local sample_base "wage_worker == 1"
		local ytitle "Large firm"
		local ystem large
	}
	else if "`yvar'" == "permanent" {
		local ctrls `controls_sub_job'
		local sample_base "wage_worker == 1"
		local ytitle "Permanent"
		local ystem perm
	}
	else {
		local ctrls `controls_sub_wage'
		local sample_base "wage_worker == 1"
		local ytitle "Log hourly wage"
		local ystem lhw
	}

	foreach g in 1 2 {
		if `g' == 1 local gname maleind
		if `g' == 2 local gname femaleind

		reg `yvar' i.male##ib4.rel_shift `ctrls' ///
		    if `sample_base' & industry_gender_type == `g', vce(robust)
		estimates store es_`ystem'_`gname'

		tempfile coef_`ystem'_`gname'
		postfile handle str30 outcome str12 industry_type int rel_cohort ///
		    double beta se lb ub using "`coef_`ystem'_`gname''", replace

		forvalues k = -5/5 {
			local s = `k' + 5
			if `k' == -1 {
				post handle ("`yvar'") ("`gname'") (`k') (0) (0) (0) (0)
			}
			else {
				capture lincom 1.male#`s'.rel_shift
				if !_rc {
					post handle ("`yvar'") ("`gname'") (`k') ///
					    (r(estimate)) (r(se)) ///
					    (r(estimate) - 1.96*r(se)) ///
					    (r(estimate) + 1.96*r(se))
				}
			}
		}
		postclose handle

		preserve
			quietly use "`coef_`ystem'_`gname''", clear
			export delimited using "$OUT/eventstudy_`ystem'_`gname'.csv", replace
		restore
	}

	preserve
		quietly use "`coef_`ystem'_maleind'", clear
		append using "`coef_`ystem'_femaleind'"
		summarize lb, meanonly
		local ymin = floor(r(min) * 10) / 10
		summarize ub, meanonly
		local ymax = ceil(r(max) * 10) / 10
		if `ymin' > 0 local ymin = 0
		if `ymax' < 0 local ymax = 0
		local ystep = (`ymax' - `ymin') / 4
		local ystep = ceil(`ystep' * 100) / 100
	restore

	foreach g in 1 2 {
		if `g' == 1 local gname maleind
		if `g' == 2 local gname femaleind
		preserve
			quietly use "`coef_`ystem'_`gname''", clear
			sort rel_cohort

			if "`gname'" == "maleind" local gtitle "Male-dominated industries"
			if "`gname'" == "femaleind" local gtitle "Female-dominated industries"

			twoway ///
			    (rcap lb ub rel_cohort, lcolor(gs8)) ///
			    (connected beta rel_cohort, msymbol(O) msize(medium) ///
			        lcolor(navy) mcolor(navy)), ///
			    xline(-0.5, lpattern(dash) lcolor(red)) ///
			    yline(0, lpattern(dash) lcolor(gs10)) ///
			    xtitle("Relative birth cohort (k)") ///
			    ytitle("Male × cohort coefficient") ///
			    yscale(range(`ymin' `ymax')) ///
			    ylabel(`ymin'(`ystep')`ymax') ///
			    title("`gtitle'") ///
			    legend(off) ///
			    name(es_`ystem'_`gname', replace)
		restore
	}

	graph combine es_`ystem'_maleind es_`ystem'_femaleind, ///
	    cols(2) ///
	    title("Event study by industry gender type: `ytitle'") ///
	    note("Reference cohort: k = -1. Controls exclude industry fixed effects.")
	graph export "$OUT/eventstudy_`ystem'_gender_type.png", replace
	graph drop es_`ystem'_maleind es_`ystem'_femaleind
}


****************************************************
* 7. Export proposal table
****************************************************

estimates dir

capture which esttab
if !_rc {

* ---- Panel A: Baseline DiD ----
esttab did_entry did_employed did_largefirm did_fulltimeperm did_lhw ///
    using "$OUT/panel_a_did.tex", replace ///
    keep(1.male#1.post_military) ///
    coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    scalars("boot_p Bootstrap \$p\$-value") ///
    sfmt(%9.3f) ///
    booktabs nonumber nomtitles noobs nonotes fragment

* ---- Panel B ----
esttab int_entry int_employed int_largefirm int_fulltimeperm int_lhw ///
    using "$OUT/panel_b_intensity.tex", replace ///
    keep(1.male#c.service_months_saved) ///
    coeflabels(1.male#c.service_months_saved "Months saved \$\times\$ Male") ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    scalars("boot_p Bootstrap \$p\$-value") ///
    sfmt(%9.3f) ///
    booktabs nonumber nomtitles noobs nonotes fragment

* ---- Subgroup DiD by industry gender type ----
foreach outcome in entry largefirm fulltimeperm lhw mwage {
	esttab did_`outcome'_maleind did_`outcome'_femaleind did_`outcome'_mixedind ///
	    using "$OUT/subgroup_did_`outcome'.tex", replace ///
	    keep(1.male#1.post_military) ///
	    coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
	    mtitles("Male-dominated" "Female-dominated" "Mixed") ///
	    se star(* 0.10 ** 0.05 *** 0.01) ///
	    scalars("boot_p Bootstrap \$p\$-value") ///
	    sfmt(%9.3f) ///
	    booktabs nonumber noobs nonotes fragment
}

* ---- Combined subgroup DiD table: compare industry gender types across outcomes ----
esttab did_entry_maleind did_entry_femaleind did_entry_mixedind ///
    did_largefirm_maleind did_largefirm_femaleind did_largefirm_mixedind ///
    did_fulltimeperm_maleind did_fulltimeperm_femaleind did_fulltimeperm_mixedind ///
    did_lhw_maleind did_lhw_femaleind did_lhw_mixedind ///
    did_mwage_maleind did_mwage_femaleind did_mwage_mixedind ///
    using "$OUT/subgroup_did_combined.tex", replace ///
    keep(1.male#1.post_military) ///
    coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
    mtitles("Male-dom." "Female-dom." "Mixed" ///
        "Male-dom." "Female-dom." "Mixed" ///
        "Male-dom." "Female-dom." "Mixed" ///
        "Male-dom." "Female-dom." "Mixed" ///
        "Male-dom." "Female-dom." "Mixed") ///
	    mgroups("Entry age" "Large firm" "Permanent" ///
	        "Log hourly wage" "Log monthly wage", pattern(1 0 0 1 0 0 1 0 0 1 0 0 1 0 0) ///
	        prefix("\multicolumn{@span}{c}{") suffix("}") span) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    scalars("boot_p Bootstrap \$p\$-value") ///
    sfmt(%9.3f) ///
    booktabs nonumber noobs nonotes fragment

* ---- Main specification table: comparable full sample and subgroups ----
esttab main_entry_full main_entry_maleind main_entry_femaleind main_entry_mixedind ///
    main_large_full main_large_maleind main_large_femaleind main_large_mixedind ///
    main_perm_full main_perm_maleind main_perm_femaleind main_perm_mixedind ///
    main_lhw_full main_lhw_maleind main_lhw_femaleind main_lhw_mixedind ///
    main_mwage_full main_mwage_maleind main_mwage_femaleind main_mwage_mixedind ///
    using "$OUT/main_did_by_industry_gender_type.tex", replace ///
    keep(1.male#1.post_military) ///
    coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
    mtitles("Full" "Male-dom." "Female-dom." "Mixed" ///
        "Full" "Male-dom." "Female-dom." "Mixed" ///
        "Full" "Male-dom." "Female-dom." "Mixed" ///
        "Full" "Male-dom." "Female-dom." "Mixed" ///
        "Full" "Male-dom." "Female-dom." "Mixed") ///
	    mgroups("Entry age" "Large firm" "Permanent" ///
	        "Log hourly wage" "Log monthly wage", ///
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
