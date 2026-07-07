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

save "$CLEAN/mdis_master_2001_2025.dta", replace

**Check after appending
*describe
*tab year

**Sanity check for key variables
*sum hourly_wage
*sum age
*tab male
