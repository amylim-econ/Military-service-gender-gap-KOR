****************************************************
* 02. Append
* Data files are stored in a separate directory
* (not shared due to confidentiality restrictions)
* Dataset: MDIS 8월 근로형태별 부가조사, 2001-2025
* Project structure:
*   dissertation/
*       do/
*			00_globals.do
*			01_clean_all.do
*			02_append.do
*			03_analysis.do
*       data_raw/
*       data_clean/
*       output/
*
* Run this do-file from the /do folder.
* Raw files are never modified.
****************************************************

clear
global CLEAN "data_clean"

local first = 1

forvalues y = 2001/2025 {

    if `first' {
        use "$CLEAN/clean_`y'.dta", clear
        local first = 0
    }
    else {
        append using "$CLEAN/clean_`y'.dta"
    }
}

****************************************************
* Safety checks for harmonised industry mapping
****************************************************
tab industry_revision, missing
tab industry_code, missing
tab industry_revision industry_code, missing
assert missing(industry_code) == missing(industry_code_raw)

****************************************************
* Boundary-year diagnostic for industry composition
* Shares are among observations with nonmissing industry.
****************************************************
preserve
	keep if !missing(industry_code)
	contract year industry_code
	bysort year: egen industry_total = total(_freq)
	gen industry_share = 100 * _freq / industry_total
	format industry_share %6.2f

	display as text "Industry shares around KSIC revision boundaries"
	list year industry_code industry_share ///
		if inlist(year, 2003, 2004, 2012, 2013, 2024, 2025), ///
		sepby(year) noobs
restore

****************************************************
* Create fixed industry gender type from pre-reform composition
* Each person is assigned by observed industry_code in each survey year.
****************************************************
tempfile industry_gender_1517
preserve
	keep if !missing(industry_code, male, popwt)
	keep if inrange(year, 2015, 2017)
	gen male_popwt = male * popwt
	collapse (sum) popwt male_popwt, by(industry_code)
	gen industry_male_share_1517 = 100 * male_popwt / popwt
	gen byte industry_gender_type = .
	replace industry_gender_type = 1 if industry_male_share_1517 >= 60
	replace industry_gender_type = 2 if industry_male_share_1517 <= 40
	replace industry_gender_type = 3 if missing(industry_gender_type)
	label define industry_gender_type_lbl ///
	    1 "Male-dominated" ///
	    2 "Female-dominated" ///
	    3 "Mixed", replace
	label values industry_gender_type industry_gender_type_lbl
	label variable industry_male_share_1517 ///
	    "Industry male share in 2015-2017, weighted by popwt (%)"
	label variable industry_gender_type ///
	    "Industry gender type from 2015-2017 weighted male share"
	keep industry_code industry_male_share_1517 industry_gender_type
	isid industry_code
	save `industry_gender_1517', replace
restore

merge m:1 industry_code using `industry_gender_1517', keep(master match) nogen
assert !missing(industry_gender_type) if !missing(industry_code)
tab industry_gender_type, missing
tab industry_code industry_gender_type, missing

****************************************************
* Diagnostic for industry gender composition
* Baseline type is based on weighted 2015-2017 male share:
*   male-dominated   = male share >= 60%
*   female-dominated = male share <= 40%
*   mixed            = otherwise
* The pre-reform 2001-2017 range checks whether this classification
* is stable before the military-service duration reform.
****************************************************
preserve
	keep if !missing(industry_code, male, popwt)
	gen male_popwt = male * popwt

	tempfile male_share_by_year baseline_1517 prereform_range

	collapse (sum) popwt male_popwt, by(year industry_code industry_name)
	gen male_share = 100 * male_popwt / popwt
	format male_share %6.2f
	save `male_share_by_year', replace

	use `male_share_by_year', clear
	keep if inrange(year, 2015, 2017)
	collapse (sum) popwt male_popwt, by(industry_code industry_name)
	gen male_share_1517 = 100 * male_popwt / popwt
	gen byte industry_gender_type = .
	replace industry_gender_type = 1 if male_share_1517 >= 60
	replace industry_gender_type = 2 if male_share_1517 <= 40
	replace industry_gender_type = 3 if missing(industry_gender_type)
	label define industry_gender_type_lbl ///
	    1 "Male-dominated" ///
	    2 "Female-dominated" ///
	    3 "Mixed", replace
	label values industry_gender_type industry_gender_type_lbl
	format male_share_1517 %6.2f
	save `baseline_1517', replace

	use `male_share_by_year', clear
	keep if inrange(year, 2001, 2017)
	collapse (min) male_share_min=male_share ///
	    (max) male_share_max=male_share, by(industry_code)
	gen male_share_range = male_share_max - male_share_min
	format male_share_min male_share_max male_share_range %6.2f
	save `prereform_range', replace

	use `baseline_1517', clear
	merge 1:1 industry_code using `prereform_range', nogen
	gsort industry_gender_type -male_share_1517

	display as text "Industry gender composition diagnostic"
	display as text "Baseline = weighted 2015-2017 male share; range = pre-reform 2001-2017"
	list industry_gender_type industry_code industry_name male_share_1517 ///
	    male_share_min male_share_max male_share_range, ///
	    sepby(industry_gender_type) noobs
restore

save "$CLEAN/mdis_master_2001_2025.dta", replace

**Check after appending
*describe
*tab year

**Sanity check for key variables
*sum hourly_wage
*sum age
*tab male
