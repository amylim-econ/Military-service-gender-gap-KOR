****************************************************
* 12. Clean May Youth Supplement, 2015-2025
* Purpose: construct directly reported first-job entry age
* Raw files are read only; no file in data_raw is modified.
*
* Run after 00_globals.do from the project root or /do folder.
****************************************************

clear all
set more off
set varabbrev off

capture confirm global RAW
if _rc global RAW "data_raw"

capture confirm global CLEAN
if _rc global CLEAN "data_clean"

capture confirm global OUT
if _rc global OUT "output"

capture mkdir "$CLEAN"
capture mkdir "$OUT"

local run_date = subinstr("`c(current_date)'", " ", "", .)
local run_time = subinstr("`c(current_time)'", ":", "", .)
capture log close clean12
log using "$OUT/12_clean_may_youth_`run_date'_`run_time'.log", ///
    text name(clean12)

tempfile may_master
local first_file = 1

forvalues y = 2015/2025 {

    ****************************************************
    * 1. Resolve the raw filename without modifying it
    ****************************************************

    local download_id
    if `y' == 2015 local download_id "76985"
    if inrange(`y', 2016, 2017) local download_id "06054"
    if inrange(`y', 2018, 2020) local download_id "70355"
    if inrange(`y', 2021, 2025) local download_id "11900"

    * The wildcard avoids dependence on composed/decomposed Korean Unicode.
    local rawfiles : dir "$RAW" files ///
        "`y'_*_20260728_`download_id'.csv"
    local n_rawfiles : word count `rawfiles'

    if `n_rawfiles' != 1 {
        display as error "Expected one May youth CSV for `y'; found `n_rawfiles'."
        display as error "Pattern: `y'_*_20260728_`download_id'.csv"
        exit 601
    }

    local rawfile : word 1 of `rawfiles'
    display as text "Importing `y': $RAW/`rawfile'"

    * Import all columns as strings so YYYYMM fields and leading-zero codes
    * are treated consistently across survey years.
    import delimited using "$RAW/`rawfile'", clear delimiter(",") ///
        varnames(nonames) rowrange(2) stringcols(_all)

    ****************************************************
    * 2. Year-specific source-variable map
    ****************************************************

    local survey_ym       v1
    local gender          v4
    local birth_year      v5
    local educ            v6
    local educ_field      v7
    local educ_status     v8
    local grad_year       v9
    local current_age     v54
    local weight          v56

    if inrange(`y', 2015, 2017) {
        local activity_status v65
        local school_exit_ym  v67
        local firstjob_count  v84
        local firstjob_type   v85
        local firstjob_fulltime v86
        local firstjob_start  v87

        if inrange(`y', 2015, 2016) {
            local firstjob_wage
            local firstjob_exit v88
            local firstjob_exit_reason v89
            local firstjob_industry v90
            local firstjob_occupation v91
        }
        else if `y' == 2017 {
            local firstjob_wage v88
            local firstjob_exit v89
            local firstjob_exit_reason v90
            local firstjob_industry v91
            local firstjob_occupation v92
        }
    }

    if `y' == 2018 {
        local activity_status v61
        local school_exit_ym  v63
        local firstjob_count  v80
        local firstjob_type   v81
        local firstjob_fulltime v82
        local firstjob_wage   v83
        local firstjob_start  v84
        local firstjob_exit   v85
        local firstjob_exit_reason v86
        local firstjob_industry v87
        local firstjob_occupation v88
    }

    if inrange(`y', 2019, 2020) {
        local activity_status v61
        local school_exit_ym  v63
        local firstjob_count  v79
        local firstjob_type   v80
        local firstjob_fulltime v81
        local firstjob_wage   v82
        local firstjob_start  v83
        local firstjob_exit   v84
        local firstjob_exit_reason v85
        local firstjob_industry v86
        local firstjob_occupation v87
    }

    if inrange(`y', 2021, 2024) {
        local current_age     v58
        local weight          v60
        local activity_status v61
        local school_exit_ym  v63
        local firstjob_count  v79
        local firstjob_type   v80
        local firstjob_fulltime v81
        local firstjob_wage   v82
        local firstjob_start  v83
        local firstjob_exit   v84
        local firstjob_exit_reason v85
        local firstjob_industry v86
        local firstjob_occupation v87
    }

    if `y' == 2025 {
        local activity_status v57
        local school_exit_ym  v59
        local firstjob_count  v75
        local firstjob_type   v76
        local firstjob_fulltime v77
        local firstjob_wage   v78
        local firstjob_start  v79
        local firstjob_exit   v80
        local firstjob_exit_reason v81
        local firstjob_industry v82
        local firstjob_occupation v83
    }

    ****************************************************
    * 3. Keep and harmonise selected variables
    ****************************************************

    local source_vars `survey_ym' `gender' `birth_year' `educ' ///
        `educ_field' `educ_status' `grad_year' `current_age' `weight' ///
        `activity_status' `school_exit_ym' `firstjob_count' ///
        `firstjob_type' `firstjob_fulltime' `firstjob_start' ///
        `firstjob_exit' `firstjob_exit_reason' `firstjob_industry' ///
        `firstjob_occupation'
    if "`firstjob_wage'" != "" local source_vars ///
        `source_vars' `firstjob_wage'

    keep `source_vars'

    rename `survey_ym' survey_ym
    rename `gender' gender_raw
    rename `birth_year' birth_year
    rename `educ' educ_raw
    rename `educ_field' educ_field_raw
    rename `educ_status' educ_status_raw
    rename `grad_year' grad_year_raw
    rename `current_age' current_age
    rename `weight' popwt
    rename `activity_status' activity_status_raw
    rename `school_exit_ym' school_exit_ym_raw
    rename `firstjob_count' firstjob_count_raw
    rename `firstjob_type' firstjob_employment_type_raw
    rename `firstjob_fulltime' firstjob_fulltime_raw
    rename `firstjob_start' firstjob_start_ym_raw
    rename `firstjob_exit' firstjob_exit_ym_raw
    rename `firstjob_exit_reason' firstjob_exit_reason_raw
    rename `firstjob_industry' firstjob_industry_raw
    rename `firstjob_occupation' firstjob_occupation_raw

    if "`firstjob_wage'" != "" {
        rename `firstjob_wage' firstjob_monthly_wage_raw
    }
    else {
        generate double firstjob_monthly_wage_raw = .
    }

    * Every retained field is numeric in the public-use codebook. Do not use
    * force: an unexpected nonnumeric value should stop the cleaning script.
    foreach v of varlist _all {
        capture confirm string variable `v'
        if !_rc destring `v', replace ignore(" ,")
    }

    generate int year = `y'
    generate byte male = (gender_raw == 1) if !missing(gender_raw)

    ****************************************************
    * 4. First-job dates and entry age in months
    ****************************************************

    generate int firstjob_year = floor(firstjob_start_ym_raw/100) ///
        if !missing(firstjob_start_ym_raw)
    generate byte firstjob_month = mod(firstjob_start_ym_raw,100) ///
        if !missing(firstjob_start_ym_raw)

    generate byte invalid_firstjob_month = ///
        !inrange(firstjob_month,1,12) if !missing(firstjob_start_ym_raw)
    generate byte invalid_firstjob_year = ///
        (firstjob_year < birth_year | firstjob_year > year) ///
        if !missing(firstjob_year, birth_year)

    replace firstjob_year = . if invalid_firstjob_year == 1
    replace firstjob_month = . if invalid_firstjob_month == 1

    * Assume an unobserved birth month of 6.5 (midyear). This preserves the
    * monthly information in the directly reported first-job start YYYYMM.
    generate double entry_age_months = ///
        12*(firstjob_year-birth_year) + firstjob_month - 6.5 ///
        if !missing(firstjob_year, firstjob_month, birth_year)
    generate double entry_age_years = entry_age_months/12

    * Flags are retained rather than silently dropping observations.
    generate byte implausible_entry_age = ///
        !inrange(entry_age_months,120,420) if !missing(entry_age_months)
    replace entry_age_months = . if implausible_entry_age == 1
    replace entry_age_years  = . if implausible_entry_age == 1

    * Code 1 means no post-school job; codes 2-5 mean at least one job.
    generate byte firstjob_experience = (firstjob_count_raw >= 2) ///
        if !missing(firstjob_count_raw)

    * Employment-type codes 1-6 are wage jobs; 7-9 are self-employment or
    * unpaid family work.
    generate byte firstjob_wage_worker = ///
        inrange(firstjob_employment_type_raw,1,6) ///
        if !missing(firstjob_employment_type_raw)

    label variable entry_age_months ///
        "First-job entry age (months; birth month assumed 6.5)"
    label variable entry_age_years ///
        "First-job entry age (years; birth month assumed 6.5)"
    label variable firstjob_occupation_raw ///
        "First-job occupation code (source label: work-type code)"
    label variable firstjob_wage_worker ///
        "First post-school job was wage employment"

    order year survey_ym gender_raw male birth_year current_age popwt ///
        educ_raw educ_field_raw educ_status_raw grad_year_raw ///
        school_exit_ym_raw activity_status_raw firstjob_count_raw ///
        firstjob_experience firstjob_employment_type_raw ///
        firstjob_wage_worker firstjob_fulltime_raw ///
        firstjob_monthly_wage_raw firstjob_start_ym_raw ///
        firstjob_year firstjob_month entry_age_months entry_age_years

    compress

    quietly count
    display as result "`y' imported observations: " r(N)
    quietly count if !missing(entry_age_months)
    display as result "`y' valid entry-age observations: " r(N)
    quietly count if invalid_firstjob_month == 1 | ///
        invalid_firstjob_year == 1 | implausible_entry_age == 1
    display as result "`y' flagged first-job dates/ages: " r(N)

    if `first_file' == 1 {
        save `may_master', replace
        local first_file = 0
    }
    else {
        append using `may_master'
        save `may_master', replace
    }
}

use `may_master', clear
sort year birth_year male

tab year, missing
tab year firstjob_experience, missing
summarize entry_age_months entry_age_years popwt, detail

save "$CLEAN/mdis_may_youth_2015_2025.dta", replace
display as result ///
    "Created $CLEAN/mdis_may_youth_2015_2025.dta"

log close clean12
