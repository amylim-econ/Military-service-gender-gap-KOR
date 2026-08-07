****************************************************
* 07. Mechanism analysis: occupational and industry sorting
* 2018 military-service reduction
*
* Run after:
*   00_globals.do
*   01_clean_all.do
*   02_append.do
*
* This supplementary file does not modify the master dataset. It assigns
* workers the wage level of their observed occupation/industry, measured
* only in the pre-reform years 2015-2017, and tests whether exposed men sort
* toward jobs that were higher-paying before the reform.
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

capture confirm file "$CLEAN/mdis_master_2001_2025.dta"
if _rc {
    display as error "Master file not found: $CLEAN/mdis_master_2001_2025.dta"
    display as error "Run the upstream cleaning and append files first."
    exit 601
}

use "$CLEAN/mdis_master_2001_2025.dta", clear

foreach v in year age male birth_year wage_worker hourly_wage popwt ///
    educ_raw experience_raw survey_ym occupation_code industry_code {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found."
        exit 111
    }
}

****************************************************
* 1. Construct current-job tenure for adjusted pre-reform premiums
****************************************************

gen job_start_year  = floor(experience_raw/100) if experience_raw < .
gen job_start_month = mod(experience_raw,100) if experience_raw < .
replace job_start_year = . if job_start_year < 1900 | job_start_year > year
replace job_start_month = . if !inrange(job_start_month,1,12)

gen survey_year_from_ym  = floor(survey_ym/100) if survey_ym < .
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
* 2. Freeze occupation and industry wage rankings in 2015-2017
*
* Raw index: population-weighted mean log hourly wage.
* Adjusted index: absorbed occupation/industry premium after controlling for
* education, current-job tenure, and year in the pre-reform sample.
****************************************************

tempfile preperiod_wage_sample occupation_index industry_index

preserve
    keep if inrange(year, 2015, 2017)
    keep if inrange(age, 18, 39)
    keep if wage_worker == 1
    keep if hourly_wage > 0 & !missing(popwt) & popwt > 0

    quietly summarize hourly_wage [aw=popwt], detail
    scalar pre_hw_p1 = r(p1)
    scalar pre_hw_p99 = r(p99)
    gen double pre_log_hourly_wage = log(hourly_wage) ///
        if inrange(hourly_wage, pre_hw_p1, pre_hw_p99)

    save `preperiod_wage_sample', replace

restore

* Adjusted occupation premium. predict, d returns the absorbed component.
preserve
    use `preperiod_wage_sample', clear
    areg pre_log_hourly_wage i.educ_raw c.job_tenure_years i.year ///
        [pw=popwt] if !missing(occupation_code), absorb(occupation_code)
    predict double occupation_premium_adjusted if e(sample), d

    keep if !missing(occupation_code, pre_log_hourly_wage)
    bysort occupation_code: gen long occupation_pre_n = _N
    collapse (mean) occupation_wage_raw=pre_log_hourly_wage ///
        occupation_wage_adjusted=occupation_premium_adjusted ///
        (max) occupation_pre_n [pw=popwt], by(occupation_code)
    isid occupation_code
    save `occupation_index', replace
    export delimited using ///
        "$OUT/sorting_preperiod_occupation_wage_index.csv", replace
restore

* Adjusted industry premium, estimated separately from occupation.
preserve
    use `preperiod_wage_sample', clear
    areg pre_log_hourly_wage i.educ_raw c.job_tenure_years i.year ///
        [pw=popwt] if !missing(industry_code), absorb(industry_code)
    predict double industry_premium_adjusted if e(sample), d

    keep if !missing(industry_code, pre_log_hourly_wage)
    bysort industry_code: gen long industry_pre_n = _N
    collapse (mean) industry_wage_raw=pre_log_hourly_wage ///
        industry_wage_adjusted=industry_premium_adjusted ///
        (max) industry_pre_n [pw=popwt], by(industry_code)
    isid industry_code
    save `industry_index', replace
    export delimited using ///
        "$OUT/sorting_preperiod_industry_wage_index.csv", replace
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

merge m:1 occupation_code using `occupation_index', keep(master match) ///
    gen(merge_occupation_index)
merge m:1 industry_code using `industry_index', keep(master match) ///
    gen(merge_industry_index)

* Matching diagnostics detect coding changes or occupations/industries absent
* in the 2015-2017 reference period. No unmatched observation is dropped here.
preserve
    keep if wage_worker == 1
    gen byte occupation_index_matched = merge_occupation_index == 3
    gen byte industry_index_matched = merge_industry_index == 3
    collapse (count) wage_worker_n=wage_worker ///
        (mean) occupation_match_rate=occupation_index_matched ///
        industry_match_rate=industry_index_matched, by(year male)
    sort year male
    export delimited using "$OUT/sorting_index_match_diagnostics.csv", replace
restore

summ occupation_wage_raw occupation_wage_adjusted ///
    industry_wage_raw industry_wage_adjusted if wage_worker == 1
pwcorr occupation_wage_raw occupation_wage_adjusted ///
    industry_wage_raw industry_wage_adjusted if wage_worker == 1, sig

****************************************************
* 4. Sorting DiD: year-only and education-adjusted specifications
*
* A positive Male x Post coefficient means exposed men moved toward an
* occupation/industry that paid more in 2015-2017. These are sorting outcomes,
* not contemporaneous individual wages.
****************************************************

local sorting_outcomes occupation_wage_raw occupation_wage_adjusted ///
    industry_wage_raw industry_wage_adjusted
local sorting_stems occ_raw occ_adj ind_raw ind_adj

estimates clear
local i = 1
foreach yvar of local sorting_outcomes {
    local stem : word `i' of `sorting_stems'

    reg `yvar' i.male##i.post_military i.year ///
        if wage_worker == 1, vce(cluster cohort)
    estimates store sort_`stem'_y
    boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_sort_`stem'_y = r(p)
    estadd scalar boot_p = boot_p_sort_`stem'_y : sort_`stem'_y

    reg `yvar' i.male##i.post_military i.educ_raw i.year ///
        if wage_worker == 1, vce(cluster cohort)
    estimates store sort_`stem'_e
    boottest 1.male#1.post_military, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_sort_`stem'_e = r(p)
    estadd scalar boot_p = boot_p_sort_`stem'_e : sort_`stem'_e

    reg `yvar' i.male##c.service_months_saved i.educ_raw i.year ///
        if wage_worker == 1, vce(cluster cohort)
    estimates store sorti_`stem'
    boottest 1.male#c.service_months_saved, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    scalar boot_p_sorti_`stem' = r(p)
    estadd scalar boot_p = boot_p_sorti_`stem' : sorti_`stem'

    local ++i
}

****************************************************
* 5. Event studies and pre-trend tests
****************************************************

postfile sorting_pretrend str32 outcome double wild_p_pretrend ///
    using "$OUT/sorting_eventstudy_pretrend_pvalues.dta", replace

local i = 1
foreach yvar of local sorting_outcomes {
    local stem : word `i' of `sorting_stems'

    reg `yvar' i.male##ib4.rel_shift i.educ_raw i.year ///
        if wage_worker == 1, vce(cluster cohort)

    capture noisily boottest 1.male#0.rel_shift 1.male#1.rel_shift ///
        1.male#2.rel_shift 1.male#3.rel_shift, ///
        cluster(cohort) reps(9999) seed(12345) nograph
    if !_rc scalar sorting_pretrend_p = r(p)
    else scalar sorting_pretrend_p = .
    post sorting_pretrend ("`yvar'") (sorting_pretrend_p)

    tempfile sorting_coef_`stem'
    postfile sorting_handle str32 outcome int rel_cohort ///
        double beta cluster_se lb ub using "`sorting_coef_`stem''", replace

    forvalues k = -5/5 {
        local s = `k' + 5
        if `k' == -1 {
            post sorting_handle ("`yvar'") (`k') (0) (0) (0) (0)
        }
        else {
            lincom 1.male#`s'.rel_shift
            scalar sorting_beta = r(estimate)
            scalar sorting_se = r(se)
            scalar sorting_lb = sorting_beta - invnormal(.975) * sorting_se
            scalar sorting_ub = sorting_beta + invnormal(.975) * sorting_se
            post sorting_handle ("`yvar'") (`k') (sorting_beta) ///
                (sorting_se) (sorting_lb) (sorting_ub)
        }
    }
    postclose sorting_handle

    preserve
        use "`sorting_coef_`stem''", clear
        sort rel_cohort
        export delimited using ///
            "$OUT/sorting_eventstudy_`stem'.csv", replace
    restore

    local ++i
}
postclose sorting_pretrend

preserve
    use "$OUT/sorting_eventstudy_pretrend_pvalues.dta", clear
    export delimited using ///
        "$OUT/sorting_eventstudy_pretrend_pvalues.csv", replace
restore

****************************************************
* 6. Export regression tables
****************************************************

capture which esttab
if !_rc {

    foreach stem in occ_raw occ_adj ind_raw ind_adj {
        foreach suffix in y e {
            attach_wild_p sort_`stem'_`suffix', ///
                term("1.male#1.post_military")
        }
        attach_wild_p sorti_`stem', ///
            term("1.male#c.service_months_saved")
    }
    esttab sort_occ_raw_y sort_occ_raw_e sort_occ_adj_y sort_occ_adj_e ///
        sort_ind_raw_y sort_ind_raw_e sort_ind_adj_y sort_ind_adj_e ///
        using "$OUT/sorting_did_wage_indices.tex", replace ///
        keep(1.male#1.post_military) ///
        coeflabels(1.male#1.post_military "Post-reform \$\times\$ Male") ///
        mtitles("Occ. raw" "Occ. raw + educ." ///
            "Occ. adjusted" "Occ. adjusted + educ." ///
            "Ind. raw" "Ind. raw + educ." ///
            "Ind. adjusted" "Ind. adjusted + educ.") ///
        cells(b(star pvalue(wild_pvals) fmt(a3)) se(par fmt(a3))) ///
        collabels(none) ///
        starlevels(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment

    esttab sorti_occ_raw sorti_occ_adj sorti_ind_raw sorti_ind_adj ///
        using "$OUT/sorting_intensity_wage_indices.tex", replace ///
        keep(1.male#c.service_months_saved) ///
        coeflabels(1.male#c.service_months_saved ///
            "Months saved \$\times\$ Male") ///
        mtitles("Occupation raw" "Occupation adjusted" ///
            "Industry raw" "Industry adjusted") ///
        cells(b(star pvalue(wild_pvals) fmt(a3)) se(par fmt(a3))) ///
        collabels(none) ///
        starlevels(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2 boot_p, ///
            labels("Observations" "R-squared" "Bootstrap \$p\$-value") ///
            fmt(%9.0fc %9.3f %9.3f)) ///
        booktabs nonumber nonotes fragment
}
else display as error "esttab not installed; regression tables not exported."

display as text "Sorting analysis completed. New outputs use sorting_* filenames."
