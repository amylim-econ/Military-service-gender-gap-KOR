****************************************************
* 16. Employment-gap mechanism and trajectory analysis
*
* Purpose:
*   1. decompose the Male x cohort employment effect into male and female
*      cohort-specific employment paths;
*   2. compare raw paths with paths standardized to a common education and
*      survey-year distribution; and
*   3. test whether the male-female employment gap shows a post-reform level
*      or slope deviation from its cohort trend.
*
* This is a supplementary diagnostic, not a replacement for the main DiD.
* It reads the existing cleaned master and creates outputs only.
*
* Run after:
*   00_globals.do
*   01_clean_all.do
*   02_append.do
*
* Required packages:
*   ssc install boottest, replace
*   ssc install estout, replace
****************************************************

clear all
set more off
set varabbrev off

capture confirm global CLEAN
if _rc global CLEAN "data_clean"

capture confirm global OUT
if _rc global OUT "`c(pwd)'/output"
else if substr("$OUT",1,1)!="/" & substr("$OUT",2,1)!=":" {
    global OUT "`c(pwd)'/$OUT"
}

capture mkdir "$OUT"

local run_date = subinstr("`c(current_date)'", " ", "", .)
local run_time = subinstr("`c(current_time)'", ":", "", .)
capture log close empgap16
log using "$OUT/16_analysis_employment_gap_`run_date'_`run_time'.log", ///
    text name(empgap16)

capture which boottest
if _rc {
    display as error "boottest is required. Install it with: ssc install boottest"
    exit 199
}

capture confirm file "$CLEAN/mdis_master_2001_2025.dta"
if _rc {
    display as error "Cleaned master not found: $CLEAN/mdis_master_2001_2025.dta"
    display as error "Run 00_globals.do, 01_clean_all.do, and 02_append.do first."
    exit 601
}

use "$CLEAN/mdis_master_2001_2025.dta", clear

* Remove stale internal temporary variables before the first boottest call.
capture drop __000000 __000001

foreach v in year age male birth_year educ_raw employed {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' not found."
        exit 111
    }
}

****************************************************
* 1. Match the main 2018-reform sample
****************************************************

keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year, employed)

gen int cohort = birth_year
gen int rel_cohort = birth_year - 1997
keep if inrange(rel_cohort, -5, 5)
gen byte rel_shift = rel_cohort + 5

gen byte post_military = birth_year >= 1997
gen double post_slope = rel_cohort * post_military

label variable post_slope ///
    "Post-reform cohort trend: zero before k=0, equals k after"

local controls i.educ_raw i.year

****************************************************
* 2. Raw cohort-specific employment rates by gender
****************************************************

tempfile raw_profiles adjusted_profiles combined_profiles

preserve
    collapse (mean) raw_employment=employed ///
        (count) N=employed, by(cohort rel_cohort male)
    isid cohort male
    sort cohort male
    save `raw_profiles', replace
    export delimited using ///
        "$OUT/employment_gender_cohort_raw_profiles.csv", replace
restore

* Export the complete education composition rather than imposing an arbitrary
* high-education cutoff without using an external coding assumption.
preserve
    keep if !missing(educ_raw)
    contract cohort rel_cohort male educ_raw, freq(cell_N)
    bysort cohort male: egen long gender_cohort_N = total(cell_N)
    gen double education_share = cell_N / gender_cohort_N
    sort cohort male educ_raw
    export delimited using ///
        "$OUT/employment_gender_cohort_education_shares.csv", replace
restore

****************************************************
* 3. Education- and year-standardized gender paths
*
* Margins average predictions for each gender-cohort cell over the pooled
* estimation sample's observed education and survey-year distribution.
****************************************************

reg employed i.male##ib4.rel_shift `controls', vce(cluster cohort)
estimates store emp_gap_standardized

tempname adjusted_handle
postfile `adjusted_handle' int cohort rel_cohort byte male ///
    double adjusted_employment adjusted_se adjusted_lb adjusted_ub ///
    using `adjusted_profiles', replace

forvalues s = 0/10 {
    local k = `s' - 5
    local birth_cohort = 1997 + `k'
    forvalues g = 0/1 {
        quietly margins, at(male=`g' rel_shift=`s') noestimcheck
        matrix margin_table = r(table)
        post `adjusted_handle' (`birth_cohort') (`k') (`g') ///
            (margin_table[1,1]) (margin_table[2,1]) ///
            (margin_table[5,1]) (margin_table[6,1])
    }
}
postclose `adjusted_handle'

preserve
    use `adjusted_profiles', clear
    sort cohort male
    export delimited using ///
        "$OUT/employment_gender_cohort_standardized_profiles.csv", replace
restore

****************************************************
* 4. Decompose the raw and standardized employment gaps
****************************************************

use `raw_profiles', clear
reshape wide raw_employment N, i(cohort rel_cohort) j(male)
rename raw_employment0 raw_female
rename raw_employment1 raw_male
rename N0 N_female
rename N1 N_male
gen double raw_gap = raw_male - raw_female
save `combined_profiles', replace

use `adjusted_profiles', clear
reshape wide adjusted_employment adjusted_se adjusted_lb adjusted_ub, ///
    i(cohort rel_cohort) j(male)
rename adjusted_employment0 standardized_female
rename adjusted_employment1 standardized_male
rename adjusted_se0 standardized_female_se
rename adjusted_se1 standardized_male_se
rename adjusted_lb0 standardized_female_lb
rename adjusted_lb1 standardized_male_lb
rename adjusted_ub0 standardized_female_ub
rename adjusted_ub1 standardized_male_ub

merge 1:1 cohort rel_cohort using `combined_profiles', assert(3) nogen
gen double standardized_gap = standardized_male - standardized_female
gen double composition_gap = ///
    raw_gap - standardized_gap
sort cohort
order cohort rel_cohort raw_female raw_male raw_gap ///
    standardized_female standardized_male standardized_gap ///
    composition_gap N_female N_male
export delimited using ///
    "$OUT/employment_gender_gap_decomposition.csv", replace
save "$OUT/employment_gender_gap_decomposition.dta", replace

* Paper-ready cohort decomposition table. The composition column is the raw
* gap minus the education/year-standardized gap.
capture which esttab
if !_rc {
    mkmat raw_gap standardized_gap composition_gap, matrix(gap_decomposition)
    matrix rownames gap_decomposition = ///
        k_m5 k_m4 k_m3 k_m2 k_m1 k_0 k_1 k_2 k_3 k_4 k_5
    matrix colnames gap_decomposition = ///
        raw_gap standardized_gap composition_gap
    esttab matrix(gap_decomposition, fmt(%9.3f %9.3f %9.3f)) ///
        using "$OUT/employment_gender_gap_decomposition.tex", replace ///
        coeflabels(k_m5 "\$k=-5\$" k_m4 "\$k=-4\$" k_m3 "\$k=-3\$" ///
            k_m2 "\$k=-2\$" k_m1 "\$k=-1\$" k_0 "\$k=0\$" ///
            k_1 "\$k=1\$" k_2 "\$k=2\$" k_3 "\$k=3\$" ///
            k_4 "\$k=4\$" k_5 "\$k=5\$") ///
        collabels("Raw gap" "Standardized gap" "Composition difference") ///
        mlabels(none) booktabs nonumber noobs fragment ///
        addnotes("Each gap is the male employment rate minus the female employment rate." ///
            "Standardized gaps use a common pooled education and survey-year distribution; composition difference equals raw minus standardized gap.")
}

* Gender-specific raw employment trajectories.
twoway ///
    (connected raw_male rel_cohort, msymbol(O) lcolor(navy) mcolor(navy)) ///
    (connected raw_female rel_cohort, msymbol(T) lcolor(maroon) mcolor(maroon)), ///
    xline(-0.5, lpattern(dash) lcolor(red)) ///
    xtitle("Relative birth cohort (k)") ///
    ytitle("Employment rate") ///
    title("Employment trajectories by gender and birth cohort") ///
    legend(order(1 "Men" 2 "Women") position(6) rows(1)) ///
    note("Raw unweighted employment rates; main 1992-2002 cohort sample.")
graph export "$OUT/employment_gender_cohort_raw_profiles.png", replace

* Raw and standardized male-female employment gaps.
twoway ///
    (connected raw_gap rel_cohort, msymbol(O) lcolor(navy) mcolor(navy)) ///
    (connected standardized_gap rel_cohort, msymbol(T) ///
        lcolor(forest_green) mcolor(forest_green)), ///
    xline(-0.5, lpattern(dash) lcolor(red)) ///
    yline(0, lpattern(shortdash) lcolor(gs10)) ///
    xtitle("Relative birth cohort (k)") ///
    ytitle("Male - female employment rate") ///
    title("Raw and standardized gender employment gaps") ///
    legend(order(1 "Raw gap" 2 "Education/year standardized gap") ///
        position(6) rows(1)) ///
    note("Standardized predictions use a common pooled education and survey-year distribution.")
graph export "$OUT/employment_gender_gap_raw_standardized.png", replace

****************************************************
* 5. Segmented cohort-trend diagnostic
*
* Male x Post is the relative level deviation at k=0.
* Male x post_slope is the relative change in slope after k=0.
****************************************************

use "$CLEAN/mdis_master_2001_2025.dta", clear
capture drop __000000 __000001
keep if inrange(year, 2015, 2025)
keep if inrange(age, 18, 39)
keep if !missing(male, birth_year, employed)

gen int cohort = birth_year
gen int rel_cohort = birth_year - 1997
keep if inrange(rel_cohort, -5, 5)
gen byte post_military = birth_year >= 1997
gen double post_slope = rel_cohort * post_military

reg employed i.male##c.rel_cohort ///
    i.male##i.post_military i.male##c.post_slope ///
    i.educ_raw i.year, vce(cluster cohort)
estimates store emp_gap_segmented

scalar level_beta = _b[1.male#1.post_military]
scalar level_se = _se[1.male#1.post_military]
scalar slope_beta = _b[1.male#c.post_slope]
scalar slope_se = _se[1.male#c.post_slope]

capture noisily boottest 1.male#1.post_military, ///
    cluster(cohort) reps(9999) seed(12345) nograph noci
scalar level_rademacher_p = .
if !_rc scalar level_rademacher_p = r(p)

capture noisily boottest 1.male#1.post_military, ///
    cluster(cohort) weight(webb) reps(9999) seed(12345) nograph noci
scalar level_webb_p = .
if !_rc scalar level_webb_p = r(p)

capture noisily boottest 1.male#c.post_slope, ///
    cluster(cohort) reps(9999) seed(12345) nograph noci
scalar slope_rademacher_p = .
if !_rc scalar slope_rademacher_p = r(p)

capture noisily boottest 1.male#c.post_slope, ///
    cluster(cohort) weight(webb) reps(9999) seed(12345) nograph noci
scalar slope_webb_p = .
if !_rc scalar slope_webb_p = r(p)

capture noisily boottest 1.male#1.post_military ///
    1.male#c.post_slope, ///
    cluster(cohort) reps(9999) seed(12345) nograph
scalar joint_rademacher_p = .
if !_rc scalar joint_rademacher_p = r(p)

tempfile segmented_results
tempname segmented_handle
postfile `segmented_handle' str28 parameter double beta cluster_se ///
    rademacher_p webb_p using `segmented_results', replace
post `segmented_handle' ("Male relative level break") ///
    (level_beta) (level_se) (level_rademacher_p) (level_webb_p)
post `segmented_handle' ("Male relative slope change") ///
    (slope_beta) (slope_se) (slope_rademacher_p) (slope_webb_p)
postclose `segmented_handle'

preserve
    use `segmented_results', clear
    gen double joint_rademacher_p = scalar(joint_rademacher_p)
    export delimited using ///
        "$OUT/employment_gap_segmented_trend_results.csv", replace
    save "$OUT/employment_gap_segmented_trend_results.dta", replace
restore

matrix segmented_table = ///
    (level_beta, level_se, level_rademacher_p, level_webb_p \ ///
     slope_beta, slope_se, slope_rademacher_p, slope_webb_p)
matrix rownames segmented_table = level_break slope_change
matrix colnames segmented_table = beta cluster_se rademacher_p webb_p

capture which esttab
if !_rc {
    esttab matrix(segmented_table, fmt(%9.4f %9.4f %9.3f %9.3f)) ///
        using "$OUT/employment_gap_segmented_trend.tex", replace ///
        coeflabels(level_break "Male relative level break" ///
            slope_change "Male relative slope change") ///
        collabels("Coefficient" "Clustered SE" "Rademacher p" "Webb p") ///
        mlabels(none) booktabs nonumber noobs fragment ///
        addnotes("The model includes a common cohort trend, Male x cohort trend, post level and slope terms, education controls, and survey-year fixed effects." ///
            "Inference clusters by 11 birth cohorts; the joint Rademacher p-value for the male-relative level and slope changes is reported in the accompanying CSV.")
}

****************************************************
* 6. Plot fitted segmented gap and pre-reform trend extrapolation
****************************************************

scalar gap_intercept = _b[1.male]
scalar gap_pre_slope = _b[1.male#c.rel_cohort]

tempfile fitted_gap
tempname fitted_handle
postfile `fitted_handle' int rel_cohort double pretrend_extrapolation ///
    segmented_fitted_gap using `fitted_gap', replace

forvalues k = -5/5 {
    scalar gap_cf = gap_intercept + gap_pre_slope * `k'
    scalar gap_fit = gap_cf
    if `k' >= 0 {
        scalar gap_fit = gap_fit + level_beta + slope_beta * `k'
    }
    post `fitted_handle' (`k') (gap_cf) (gap_fit)
}
postclose `fitted_handle'

use `fitted_gap', clear
export delimited using ///
    "$OUT/employment_gap_segmented_fitted_paths.csv", replace

twoway ///
    (connected segmented_fitted_gap rel_cohort, msymbol(O) ///
        lcolor(navy) mcolor(navy)) ///
    (line pretrend_extrapolation rel_cohort, lpattern(dash) lcolor(maroon)), ///
    xline(-0.5, lpattern(dash) lcolor(red)) ///
    yline(0, lpattern(shortdash) lcolor(gs10)) ///
    xtitle("Relative birth cohort (k)") ///
    ytitle("Adjusted male - female employment rate") ///
    title("Gender employment gap: segmented fit and pre-trend extrapolation") ///
    legend(order(1 "Segmented fitted gap" 2 "Pre-reform trend extrapolation") ///
        position(6) rows(1)) ///
    note("Diagnostic linear-trend specification; formal inference is reported in the accompanying table.")
graph export "$OUT/employment_gap_segmented_fitted_paths.png", replace

display as text "Employment-gap mechanism analysis completed."
display as text "Gender profiles: $OUT/employment_gender_gap_decomposition.csv"
display as text "Segmented results: $OUT/employment_gap_segmented_trend_results.csv"

log close empgap16
****************************************************
* End
****************************************************
