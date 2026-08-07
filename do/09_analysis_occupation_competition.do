****************************************************
* 09. Mechanism analysis: male inflows and within-occupation wages
* 2018 military-service reduction
*
* Run after:
*   00_globals.do
*   01_clean_all.do
*   02_append.do
*
* This supplementary analysis asks whether occupations receiving larger
* relative inflows of exposed men also experienced larger declines in men's
* hourly wages relative to women. The cross-occupation link is descriptive:
* both axes are estimated outcomes and occupation has only nine major groups.
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

capture confirm file "$CLEAN/mdis_master_2001_2025.dta"
if _rc {
    display as error "Master file not found: $CLEAN/mdis_master_2001_2025.dta"
    exit 601
}

use "$CLEAN/mdis_master_2001_2025.dta", clear
capture drop __*

foreach v in year age male birth_year wage_worker hourly_wage popwt ///
    educ_raw experience_raw survey_ym occupation_code occupation_name ///
    industry_code industry_gender_type {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found."
        exit 111
    }
}

****************************************************
* 1. Reproduce the main cohort sample and wage outcome
****************************************************

keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year)

gen cohort = birth_year
gen rel_cohort = birth_year - 1997
keep if inrange(rel_cohort, -5, 5)
gen byte post_military = birth_year >= 1997 if !missing(birth_year)

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

quietly summarize hourly_wage if hourly_wage > 0, detail
scalar p1_hw_comp = r(p1)
scalar p99_hw_comp = r(p99)
gen hourly_wage_trim = hourly_wage ///
    if inrange(hourly_wage, p1_hw_comp, p99_hw_comp)
gen log_hourly_wage_trim = log(hourly_wage_trim) ///
    if hourly_wage_trim > 0

gen byte recent_entrant_6 = wage_worker == 1 ///
    & inrange(job_tenure_months, 0, 6)
gen byte recent_entrant_12 = wage_worker == 1 ///
    & inrange(job_tenure_months, 0, 12)
gen byte recent_entrant_24 = wage_worker == 1 ///
    & inrange(job_tenure_months, 0, 24)

tempfile competition_micro occupation_cells cell_results
save `competition_micro', replace

****************************************************
* 2. Occupation-level inflow and wage estimates
*
* Inflow coefficient: Male x Post in the probability of entering occupation j
* among workers who started their current job within the stated horizon.
* Wage changes are separated into female, male, and male-relative-to-female.
****************************************************

quietly summarize popwt if wage_worker == 1 & inrange(year,2015,2017), meanonly
scalar pre_weight_total = r(sum)

postfile occupation_handle int occupation_code str80 occupation_name ///
    double pre_n pre_share male_n female_n ///
    inflow_6 inflow_6_se inflow_12 inflow_12_se ///
    inflow_24 inflow_24_se stock_sorting stock_sorting_se ///
    female_wage_post female_wage_post_se ///
    male_wage_post male_wage_post_se ///
    relative_wage_did relative_wage_se relative_wage_boot_p ///
    using `occupation_cells', replace

forvalues j = 1/9 {
    local jname : label occupation_code_lbl `j'
    local occname`j' "`jname'"

    quietly count if wage_worker == 1 & occupation_code == `j' ///
        & inrange(year,2015,2017)
    scalar pre_n_j = r(N)
    quietly summarize popwt if wage_worker == 1 & occupation_code == `j' ///
        & inrange(year,2015,2017), meanonly
    scalar pre_share_j = r(sum) / pre_weight_total

    quietly count if wage_worker == 1 & occupation_code == `j' ///
        & !missing(log_hourly_wage_trim) & male == 1
    scalar male_n_j = r(N)
    quietly count if wage_worker == 1 & occupation_code == `j' ///
        & !missing(log_hourly_wage_trim) & male == 0
    scalar female_n_j = r(N)

    foreach h in 6 12 24 {
        capture drop in_occupation
        gen byte in_occupation = occupation_code == `j' ///
            if recent_entrant_`h' == 1 & !missing(occupation_code)
        capture quietly reg in_occupation i.male##i.post_military ///
            i.educ_raw i.year if recent_entrant_`h' == 1, ///
            vce(cluster cohort)
        if !_rc {
            capture quietly lincom 1.male#1.post_military
            if !_rc {
                scalar inflow_`h'_j = r(estimate)
                scalar inflow_`h'_se_j = r(se)
            }
            else {
                scalar inflow_`h'_j = .
                scalar inflow_`h'_se_j = .
            }
        }
        else {
            scalar inflow_`h'_j = .
            scalar inflow_`h'_se_j = .
        }
    }

    capture drop in_occupation
    gen byte in_occupation = occupation_code == `j' ///
        if wage_worker == 1 & !missing(occupation_code)
    capture quietly reg in_occupation i.male##i.post_military ///
        i.educ_raw i.year if wage_worker == 1, vce(cluster cohort)
    if !_rc {
        capture quietly lincom 1.male#1.post_military
        if !_rc {
            scalar stock_j = r(estimate)
            scalar stock_se_j = r(se)
        }
        else {
            scalar stock_j = .
            scalar stock_se_j = .
        }
    }
    else {
        scalar stock_j = .
        scalar stock_se_j = .
    }

    capture quietly reg log_hourly_wage_trim ///
        i.male##i.post_military c.job_tenure_years ///
        i.educ_raw i.year i.industry_code ///
        if wage_worker == 1 & occupation_code == `j', ///
        vce(cluster cohort)
    if !_rc {
        capture quietly lincom 1.post_military
        if !_rc {
            scalar female_wage_j = r(estimate)
            scalar female_wage_se_j = r(se)
        }
        else {
            scalar female_wage_j = .
            scalar female_wage_se_j = .
        }

        capture quietly lincom 1.post_military + 1.male#1.post_military
        if !_rc {
            scalar male_wage_j = r(estimate)
            scalar male_wage_se_j = r(se)
        }
        else {
            scalar male_wage_j = .
            scalar male_wage_se_j = .
        }

        capture quietly lincom 1.male#1.post_military
        if !_rc {
            scalar relative_wage_j = r(estimate)
            scalar relative_wage_se_j = r(se)

            capture quietly boottest 1.male#1.post_military, ///
                cluster(cohort) reps(9999) seed(12345) nograph
            if !_rc scalar relative_wage_boot_j = r(p)
            else scalar relative_wage_boot_j = .
        }
        else {
            scalar relative_wage_j = .
            scalar relative_wage_se_j = .
            scalar relative_wage_boot_j = .
        }
    }
    else {
        scalar female_wage_j = .
        scalar female_wage_se_j = .
        scalar male_wage_j = .
        scalar male_wage_se_j = .
        scalar relative_wage_j = .
        scalar relative_wage_se_j = .
        scalar relative_wage_boot_j = .
    }

    post occupation_handle (`j') ("`jname'") ///
        (pre_n_j) (pre_share_j) (male_n_j) (female_n_j) ///
        (inflow_6_j) (inflow_6_se_j) ///
        (inflow_12_j) (inflow_12_se_j) ///
        (inflow_24_j) (inflow_24_se_j) ///
        (stock_j) (stock_se_j) ///
        (female_wage_j) (female_wage_se_j) ///
        (male_wage_j) (male_wage_se_j) ///
        (relative_wage_j) (relative_wage_se_j) ///
        (relative_wage_boot_j)
}
postclose occupation_handle

use `occupation_cells', clear
sort occupation_code
isid occupation_code
save "$CLEAN/occupation_competition_cells.dta", replace
export delimited using "$OUT/occupation_competition_cells.csv", replace

****************************************************
* 3. Cross-occupation link and robustness
*
* A negative slope is consistent with stronger male inflows being associated
* with larger within-occupation relative wage declines. With only nine major
* groups these are descriptive relationships, not causal second-stage tests.
****************************************************

estimates clear
reg relative_wage_did inflow_12, vce(robust)
estimates store competition_ols

reg relative_wage_did inflow_12 [aw=pre_share], vce(robust)
estimates store competition_wls

reg relative_wage_did inflow_12 [aw=pre_share] ///
    if pre_n >= 200 & male_n >= 50 & female_n >= 50, vce(robust)
estimates store competition_wls_large

spearman relative_wage_did inflow_12
scalar competition_spearman = r(rho)
scalar competition_spearman_p = r(p)

postfile loo_handle int omitted_occupation str80 omitted_name ///
    double slope slope_se using "$OUT/occupation_competition_loo.dta", replace
forvalues j = 1/9 {
    local jname "`occname`j''"
    capture quietly reg relative_wage_did inflow_12 [aw=pre_share] ///
        if occupation_code != `j', vce(robust)
    if !_rc {
        scalar loo_slope = _b[inflow_12]
        scalar loo_se = _se[inflow_12]
    }
    else {
        scalar loo_slope = .
        scalar loo_se = .
    }
    post loo_handle (`j') ("`jname'") (loo_slope) (loo_se)
}
postclose loo_handle

preserve
    use "$OUT/occupation_competition_loo.dta", clear
    export delimited using "$OUT/occupation_competition_loo.csv", replace
restore

twoway ///
    (scatter relative_wage_did inflow_12 [aw=pre_share], ///
        msymbol(O) mcolor(navy) mlabel(occupation_name) ///
        mlabsize(vsmall) mlabposition(12)) ///
    (lfit relative_wage_did inflow_12 [aw=pre_share], lcolor(maroon)), ///
    xline(0, lpattern(dash) lcolor(gs10)) ///
    yline(0, lpattern(dash) lcolor(gs10)) ///
    xtitle("Male relative inflow: current-job starters <=12 months") ///
    ytitle("Within-occupation Male x Post: log hourly wage") ///
    title("Male inflows and relative hourly wages by occupation") ///
    legend(order(1 "Occupation" 2 "Weighted fit"))
graph export "$OUT/occupation_competition_scatter.png", replace

****************************************************
* 4. Occupation x industry-gender-type cell analysis
****************************************************

use `competition_micro', clear
keep if wage_worker == 1 & !missing(occupation_code, industry_gender_type)
gen int occupation_industry_cell = ///
    10 * occupation_code + industry_gender_type
levelsof occupation_industry_cell, local(cells)

quietly summarize popwt if inrange(year,2015,2017), meanonly
scalar pre_cell_weight_total = r(sum)

postfile cell_handle int cell_id occupation_code industry_gender_type ///
    str80 cell_name double pre_n pre_share male_n female_n ///
    inflow_12 inflow_12_se relative_wage_did relative_wage_se ///
    using `cell_results', replace

foreach c of local cells {
    local j = floor(`c'/10)
    local g = mod(`c',10)
    local jname : label occupation_code_lbl `j'
    if `g' == 1 local gname "Male-dominated"
    if `g' == 2 local gname "Female-dominated"
    if `g' == 3 local gname "Mixed"
    local cname "`jname' - `gname'"

    quietly count if occupation_industry_cell == `c' ///
        & inrange(year,2015,2017)
    scalar cell_pre_n = r(N)
    quietly summarize popwt if occupation_industry_cell == `c' ///
        & inrange(year,2015,2017), meanonly
    scalar cell_pre_share = r(sum) / pre_cell_weight_total
    quietly count if occupation_industry_cell == `c' ///
        & !missing(log_hourly_wage_trim) & male == 1
    scalar cell_male_n = r(N)
    quietly count if occupation_industry_cell == `c' ///
        & !missing(log_hourly_wage_trim) & male == 0
    scalar cell_female_n = r(N)

    capture drop in_cell
    gen byte in_cell = occupation_industry_cell == `c' ///
        if recent_entrant_12 == 1
    capture quietly reg in_cell i.male##i.post_military ///
        i.educ_raw i.year if recent_entrant_12 == 1, ///
        vce(cluster cohort)
    if !_rc {
        capture quietly lincom 1.male#1.post_military
        if !_rc {
            scalar cell_inflow = r(estimate)
            scalar cell_inflow_se = r(se)
        }
        else {
            scalar cell_inflow = .
            scalar cell_inflow_se = .
        }
    }
    else {
        scalar cell_inflow = .
        scalar cell_inflow_se = .
    }

    capture quietly reg log_hourly_wage_trim ///
        i.male##i.post_military c.job_tenure_years i.educ_raw i.year ///
        if occupation_industry_cell == `c', vce(cluster cohort)
    if !_rc {
        capture quietly lincom 1.male#1.post_military
        if !_rc {
            scalar cell_wage = r(estimate)
            scalar cell_wage_se = r(se)
        }
        else {
            scalar cell_wage = .
            scalar cell_wage_se = .
        }
    }
    else {
        scalar cell_wage = .
        scalar cell_wage_se = .
    }

    post cell_handle (`c') (`j') (`g') ("`cname'") ///
        (cell_pre_n) (cell_pre_share) (cell_male_n) (cell_female_n) ///
        (cell_inflow) (cell_inflow_se) (cell_wage) (cell_wage_se)
}
postclose cell_handle

use `cell_results', clear
sort occupation_code industry_gender_type
save "$CLEAN/occupation_industry_competition_cells.dta", replace
export delimited using ///
    "$OUT/occupation_industry_competition_cells.csv", replace

count if pre_n >= 200 & male_n >= 50 & female_n >= 50 ///
    & !missing(inflow_12, relative_wage_did)
if r(N) >= 5 {
    reg relative_wage_did inflow_12 [aw=pre_share] ///
        if pre_n >= 200 & male_n >= 50 & female_n >= 50, vce(robust)
    estimates store competition_cell_wls

    twoway ///
        (scatter relative_wage_did inflow_12 [aw=pre_share] ///
            if pre_n >= 200 & male_n >= 50 & female_n >= 50, ///
            msymbol(O) mcolor(navy) mlabel(cell_name) mlabsize(tiny)) ///
        (lfit relative_wage_did inflow_12 [aw=pre_share] ///
            if pre_n >= 200 & male_n >= 50 & female_n >= 50, ///
            lcolor(maroon)), ///
        xline(0, lpattern(dash) lcolor(gs10)) ///
        yline(0, lpattern(dash) lcolor(gs10)) ///
        xtitle("Male relative inflow: current-job starters <=12 months") ///
        ytitle("Cell-specific Male x Post: log hourly wage") ///
        title("Male inflows and wages: occupation x industry type") ///
        legend(order(1 "Cell" 2 "Weighted fit"))
    graph export "$OUT/occupation_industry_competition_scatter.png", replace
}

****************************************************
* 5. Export regression-link tables
****************************************************

capture which esttab
if !_rc {
    capture estimates restore competition_cell_wls
    local has_cell = !_rc

    if `has_cell' {
        esttab competition_ols competition_wls competition_wls_large ///
            competition_cell_wls ///
            using "$OUT/occupation_competition_link.tex", replace ///
            keep(inflow_12) ///
            coeflabels(inflow_12 "Male relative inflow") ///
            mtitles("Occupation OLS" "Occupation weighted" ///
                "Occupation large cells" "Occupation x industry type") ///
            se star(* 0.10 ** 0.05 *** 0.01) ///
            stats(N r2, labels("Cells" "R-squared") ///
                fmt(%9.0fc %9.3f)) ///
            booktabs nonumber nonotes fragment
    }
    else {
        esttab competition_ols competition_wls competition_wls_large ///
            using "$OUT/occupation_competition_link.tex", replace ///
            keep(inflow_12) ///
            coeflabels(inflow_12 "Male relative inflow") ///
            mtitles("Occupation OLS" "Occupation weighted" ///
                "Occupation large cells") ///
            se star(* 0.10 ** 0.05 *** 0.01) ///
            stats(N r2, labels("Cells" "R-squared") ///
                fmt(%9.0fc %9.3f)) ///
            booktabs nonumber nonotes fragment
    }
}

display as text "Occupation competition analysis completed."
display as text "Spearman rho (occupation level): " ///
    %9.3f competition_spearman "  p-value: " %9.3f competition_spearman_p
