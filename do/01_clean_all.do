****************************************************
* 01. cleaning
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

set varabbrev off

**연도별 파일명 자동생성
capture program drop get_rawfile
program define get_rawfile, rclass
	args y
	
	if inrange(`y', 2001, 2005) {
		return local infile "`y'_8월_근로형태별_20260218_04929.csv"
	}
	else if inrange(`y', 2006, 2010) {
		return local infile "`y'_8월_근로형태별_20260218_07113.csv"
	}
	else if inrange(`y', 2011, 2015) {
		return local infile "`y'_8월_근로형태별_20260218_20485.csv"
	}
	else if inrange(`y', 2016, 2020) {
		return local infile "`y'_8월_근로형태별_20260218_71245.csv"
	}
	else if inrange(`y', 2021, 2025) {
		return local infile "`y'_8월_근로형태별_20260218_26498.csv"
	}
	else {
		di as error "No filename rule defined for year `y'"
		exit 601
	}
end

**연도별 변수 매핑
capture program drop set_source_map
program define set_source_map
	args y
	
	local survey_ym
	local gender
	local birth_year
	local educ
	local educ_attend
	local grad_year
	local marital
	local activity_status
	local worked_lastweek
	local industry_code
	local occupation_code
	local worker_status
	local prev_work
	local firm_size
	local age
	local weight
	local labour_force
	local experience_raw
	local hours_week
	local healthins_raw
	local employins_raw
	local severance
	local bonus		
	local overtime_pay	
	local paid_leave
	local union_raw
	local monthly_wage
	local fivedays_working
	local flexible_work	
	local contract_work
	
**experience_raw 2001/2002 변수 두개임(년/월)
**severance/bonus/overtime_pay 액수인지 여부인지 봐야함
**contract_work 고용계약여부 코드값 달라짐. (정했음/정하지 않았음 확인필요)
	if `y'== 2001 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      
        local marital        v8
        local activity_status v9
        local worked_lastweek v10
		local prev_work		 v28
        local industry_code  v31
        local occupation_code v32
        local worker_status  v33
        local firm_size      v34
        local age            v39
        local weight         v35
		local labour_force	 v40
		local experience_raw v41
        local hours_week     v52
        local pension_raw    v57
        local healthins_raw  v58
        local employins_raw  v59
		local severance		v60
		local bonus			v61
		local overtime_pay	v62
		local paid_leave	
        local union_raw      
        local monthly_wage   v63
		local fivedays_working 
		local flexible_work	
		local contract_work v43
	}
	
	if `y'== 2002 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      
        local marital        v8
        local activity_status v9
        local worked_lastweek v10
		local prev_work		 v28
        local industry_code  v31
        local occupation_code v32
        local worker_status  v33
        local firm_size      v34
        local age            v39
        local weight         v35
		local labour_force	 v40
		local experience_raw v41
        local hours_week     v53
        local pension_raw    v58
        local healthins_raw  v59
        local employins_raw  v60
		local severance		v61
		local bonus			v62
		local overtime_pay	v63
		local paid_leave	
        local union_raw      
        local monthly_wage   v64
		local fivedays_working 
		local flexible_work		
		local contract_work v43
	}

	if `y'== 2003 {
		local survey_ym		v43
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v33
        local industry_code  v36
        local occupation_code v37
        local worker_status  v39
        local firm_size      v38
        local age            v46
        local weight         v47
		local labour_force	
		local experience_raw v40
        local hours_week     v56
        local pension_raw    v61
        local healthins_raw  v62
        local employins_raw  v63
		local severance		v64
		local bonus			v65
		local overtime_pay	v66
		local paid_leave	
        local union_raw      v68
        local monthly_wage   v69
		local fivedays_working 
		local flexible_work		
		local contract_work v41
	}
	
***산업/직업 n차개정 뭐로 할지 정해야함 - 현재 최신 기준
**유급휴가 추가
	if `y'== 2004 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v33
        local industry_code  v48
        local occupation_code v49
        local worker_status  v39
        local firm_size      v38
        local age            v47
        local weight         v43
		local labour_force	v50
		local experience_raw v40
        local hours_week     v59
        local pension_raw    v64
        local healthins_raw  v65
        local employins_raw  v66
		local severance		v67
		local bonus			v68
		local overtime_pay	v69
		local paid_leave	v70
        local union_raw      v72
        local monthly_wage   v74
		local fivedays_working 
		local flexible_work		
		local contract_work v41
	}

***주5일제 시작	
	if `y'== 2005 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v33
        local industry_code  v48
        local occupation_code v49
        local worker_status  v39
        local firm_size      v38
        local age            v47
        local weight         v43
		local labour_force	v50
		local experience_raw v40
        local hours_week     v59
        local pension_raw    v64
        local healthins_raw  v65
        local employins_raw  v66
		local severance		v67
		local bonus			v68
		local overtime_pay	v69
		local paid_leave	v70
        local union_raw      v72
        local monthly_wage   v74
		local fivedays_working v75
		local flexible_work	
		local contract_work v41
	}
	
	if `y'== 2006 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v33
        local industry_code  v48
        local occupation_code v49
        local worker_status  v39
        local firm_size      v38
        local age            v44
        local weight         v43
		local labour_force	v50
		local experience_raw v40
        local hours_week     v59
        local pension_raw    v65
        local healthins_raw  v66
        local employins_raw  v67
		local severance		v68
		local bonus			v69
		local overtime_pay	v70
		local paid_leave	v71
        local union_raw      v73
        local monthly_wage   v75
		local fivedays_working v77
		local flexible_work		
		local contract_work v41
	}
	
	if `y'== 2007 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v33
        local industry_code  v48
        local occupation_code v49
        local worker_status  v39
        local firm_size      v38
        local age            v47
        local weight         v43
		local labour_force	v50
		local experience_raw v40
        local hours_week     v59
        local pension_raw    v65
        local healthins_raw  v66
        local employins_raw  v67
		local severance		v68
		local bonus			v69
		local overtime_pay	v70
		local paid_leave	v71
        local union_raw      v73
        local monthly_wage   v75
		local fivedays_working v78
		local flexible_work		
		local contract_work v41
	}
	
	if `y'== 2008 {
		local survey_ym		v43
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v33
        local industry_code  v36
        local occupation_code v37
        local worker_status  v39
        local firm_size      v38
        local age            v46
        local weight         v47
		local labour_force	v48
		local experience_raw v40
        local hours_week     v57
        local pension_raw    v63
        local healthins_raw  v64
        local employins_raw  v65
		local severance		v66
		local bonus			v67
		local overtime_pay	v68
		local paid_leave	v69
        local union_raw      v71
        local monthly_wage   v73
		local fivedays_working v76
		local flexible_work		
		local contract_work v41
	}
	
	if `y'== 2009 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v33
        local industry_code  v36
        local occupation_code v37
        local worker_status  v39
        local firm_size      v38
        local age            v47
        local weight         v43
		local labour_force	v48
		local experience_raw v40
        local hours_week     v57
        local pension_raw    v63
        local healthins_raw  v64
        local employins_raw  v65
		local severance		v66
		local bonus			v67
		local overtime_pay	v68
		local paid_leave	v69
        local union_raw      v71
        local monthly_wage   v73
		local fivedays_working v76
		local flexible_work	
		local contract_work v41
	}
	
	if `y'== 2010 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v33
        local industry_code  v36
        local occupation_code v37
        local worker_status  v39
        local firm_size      v38
        local age            v47
        local weight         v43
		local labour_force	v48
		local experience_raw v40
        local hours_week     v57
        local pension_raw    v63
        local healthins_raw  v64
        local employins_raw  v65
		local severance		v66
		local bonus			v67
		local overtime_pay	v68
		local paid_leave	v69
        local union_raw      v71
        local monthly_wage   v74
		local fivedays_working v77
		local flexible_work		
		local contract_work v41
	}

	if `y'== 2011 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v33
        local industry_code  v36
        local occupation_code v37
        local worker_status  v39
        local firm_size      v38
        local age            v47
        local weight         v43
		local labour_force	v48
		local experience_raw v40
        local hours_week     v57
        local pension_raw    v63
        local healthins_raw  v64
        local employins_raw  v65
		local severance		v66
		local bonus			v67
		local overtime_pay	v68
		local paid_leave	v69
        local union_raw      v71
        local monthly_wage   v74
		local fivedays_working v77
		local flexible_work		
		local contract_work v41
	}
	
	if `y'== 2012 {
		local survey_ym		v1
		local gender		v3
		local birth_year     v4
        local educ           v5
        local educ_attend    v7
        local grad_year      v8
        local marital        v9
        local activity_status v10
        local worked_lastweek v11
		local prev_work		 v35
        local industry_code  v38
        local occupation_code v39
        local worker_status  v41
        local firm_size      v40
        local age            v50
        local weight         v46
		local labour_force	v51
		local experience_raw v41
        local hours_week     v60
        local pension_raw    v66
        local healthins_raw  v67
        local employins_raw  v68
		local severance		v69
		local bonus			v70
		local overtime_pay	v71
		local paid_leave	v72
        local union_raw      v74
        local monthly_wage   v77
		local fivedays_working v80
		local flexible_work		
		local contract_work v43
	}

	if `y'== 2013 {
		local survey_ym		v1
		local gender		v4
		local birth_year     v5
        local educ           v6
        local educ_attend    v8
        local grad_year      v9
        local marital        v10
        local activity_status v12
        local worked_lastweek v11
		local prev_work		 v43
        local industry_code  v54
        local occupation_code v55
        local worker_status  v31
        local firm_size      v27
        local age            v49
        local weight         v51
		local labour_force	v56
		local experience_raw v33
        local hours_week     v66
        local pension_raw    v72
        local healthins_raw  v73
        local employins_raw  v74
		local severance		v75
		local bonus			v76
		local overtime_pay	v77
		local paid_leave	v78
        local union_raw      v80
        local monthly_wage   v84
		local fivedays_working 
		local flexible_work		
		local contract_work v35
	}
	
**주5일제 -> 주40시간근로제로 바뀜
	if `y'== 2014 {
		local survey_ym		v1
		local gender		v4
		local birth_year     v5
        local educ           v6
        local educ_attend    v8
        local grad_year      v9
        local marital        v10
        local activity_status v12
        local worked_lastweek v11
		local prev_work		 v43
        local industry_code  v54
        local occupation_code v55
        local worker_status  v31
        local firm_size      v27
        local age            v49
        local weight         v51
		local labour_force	v56
		local experience_raw v33
        local hours_week     v66
        local pension_raw    v72
        local healthins_raw  v73
        local employins_raw  v74
		local severance		v75
		local bonus			v76
		local overtime_pay	v77
		local paid_leave	v78
        local union_raw      v80
        local monthly_wage   v84
		local fivedays_working v85
		local flexible_work		
		local contract_work v35
	}
	
**유연근무제 시작	
		if `y'== 2015 {
		local survey_ym		v1
		local gender		v4
		local birth_year     v5
        local educ           v6
        local educ_attend    v8
        local grad_year      v9
        local marital        v10
        local activity_status v12
        local worked_lastweek v11
		local prev_work		 v44
        local industry_code  v59
        local occupation_code v60
        local worker_status  v33
        local firm_size      v29
        local age            v51
        local weight         v55
		local labour_force	v61
		local experience_raw v35
        local hours_week     v75
        local pension_raw    v81
        local healthins_raw  v82
        local employins_raw  v83
		local severance		v93
		local bonus			v84
		local overtime_pay	v85
		local paid_leave	v86
        local union_raw      v88
        local monthly_wage   v92
		local fivedays_working v94
		local flexible_work		v103
		local contract_work v37
	}
	
if `y'== 2016 {
		local survey_ym		v1
		local gender		v4
		local birth_year     v5
        local educ           v6
        local educ_attend    v8
        local grad_year      v9
        local marital        v10
        local activity_status v45
        local worked_lastweek v11
		local prev_work		 v46
        local industry_code  v61
        local occupation_code v62
        local worker_status  v30
        local firm_size      v27
        local age            v58
        local weight         v60
		local labour_force	v65
		local experience_raw v31
        local hours_week     v75
        local pension_raw    v81
        local healthins_raw  v82
        local employins_raw  v83
		local severance		v84
		local bonus			v85
		local overtime_pay	v86
		local paid_leave	v87
        local union_raw      v88
        local monthly_wage   v92
		local fivedays_working v98
		local flexible_work		v94
		local contract_work v32
	}
	
**주5일제 사라짐-법적규제	
	if `y'== 2017 {
		local survey_ym		v1
		local gender		v4
		local birth_year     v5
        local educ           v6
        local educ_attend    v8
        local grad_year      v9
        local marital        v10
        local activity_status v45
        local worked_lastweek v11
		local prev_work		 v46
        local industry_code  v61
        local occupation_code v62
        local worker_status  v30
        local firm_size      v27
        local age            v58
        local weight         v60
		local labour_force	v65
		local experience_raw v31
        local hours_week     v75
        local pension_raw    v81
        local healthins_raw  v82
        local employins_raw  v83
		local severance		v84
		local bonus			v85
		local overtime_pay	v86
		local paid_leave	v87
        local union_raw      v88
        local monthly_wage   v92
		local fivedays_working 
		local flexible_work		v93
		local contract_work v32
	}

	if inrange(`y', 2018, 2020) {
		local survey_ym		v1
		local gender		v4
		local birth_year     v5
        local educ           v6
        local educ_attend    v8
        local grad_year      v9
        local marital        v10
        local activity_status v43
        local worked_lastweek v11
		local prev_work		 v44
        local industry_code  v57
        local occupation_code v58
        local worker_status  v28
        local firm_size      v26
        local age            v54
        local weight         v56
		local labour_force	v61
		local experience_raw v29
        local hours_week     v71
        local pension_raw    v77
        local healthins_raw  v78
        local employins_raw  v79
		local severance		v80
		local bonus			v81
		local overtime_pay	v82
		local paid_leave	v83
        local union_raw      v84
        local monthly_wage   v88
		local fivedays_working 
		local flexible_work		v90
		local contract_work v30
	}

	if inrange(`y', 2021, 2024) {
		local survey_ym		v3
		local gender		v4
		local birth_year     v5
        local educ           v6
        local educ_attend    v8
        local grad_year      v9
        local marital        v10
        local activity_status v45
        local worked_lastweek v11
		local prev_work		 v46
        local industry_code  v27
        local occupation_code v31
        local worker_status  v29
        local firm_size      v26
        local age            v58
        local weight         v60
		local labour_force	v61
		local experience_raw v30
        local hours_week     v71
        local pension_raw    v77
        local healthins_raw  v78
        local employins_raw  v79
		local severance		v80
		local bonus			v81
		local overtime_pay	v82
		local paid_leave	v83
        local union_raw      v84
        local monthly_wage   v88
		local fivedays_working 
		local flexible_work		v90
		local contract_work v32
	}
	
	if `y'== 2025 {
		local survey_ym		v3
		local gender		v4
		local birth_year     v5
        local educ           v6
        local educ_attend    v8
        local grad_year      v9
        local marital        v10
        local activity_status v43
        local worked_lastweek v11
		local prev_work		 v44
        local industry_code  v25
        local occupation_code v27
        local worker_status  v28
        local firm_size      v26
        local age            v54
        local weight         v56
		local labour_force	v57
		local experience_raw v29
        local hours_week     v67
        local pension_raw    v73
        local healthins_raw  v74
        local employins_raw  v75
		local severance		v76
		local bonus			v77
		local overtime_pay	v78
		local paid_leave	v79
        local union_raw      v80
        local monthly_wage   v84
		local fivedays_working 
		local flexible_work		v86
		local contract_work v30
	}
	
	c_local survey_ym      `survey_ym'
    c_local gender         `gender'
    c_local birth_year     `birth_year'
    c_local educ           `educ'
    c_local educ_attend    `educ_attend'
    c_local grad_year      `grad_year'
    c_local marital        `marital'
    c_local activity_status `activity_status'
    c_local worked_lastweek `worked_lastweek'
	c_local prev_work		`prev_work'
    c_local industry_code  `industry_code'
    c_local occupation_code `occupation_code'
    c_local worker_status  `worker_status'
    c_local firm_size      `firm_size'
    c_local age            `age'
    c_local weight         `weight'
	c_local labour_force	`labour_force'
	c_local experience_raw `experience_raw'
    c_local hours_week     `hours_week'
    c_local pension_raw    `pension_raw'
    c_local healthins_raw  `healthins_raw'
    c_local employins_raw  `employins_raw'
	c_local severance		`severance'
	c_local bonus			`bonus'
	c_local overtime_pay	`overtime_pay'
	c_local paid_leave		`paid_leave'
    c_local union_raw      `union_raw'
    c_local monthly_wage   `monthly_wage'
	c_local fivedays_working `fivedays_working'
	c_local flexible_work	`flexible_work'
	c_local contract_work 	`contract_work'
end


** rename helper
capture program drop safe_rename
program define safe_rename
	args old new
	if "`old'" != "" {
        capture confirm variable `old'
        if !_rc rename `old' `new'
        else gen `new' = .
    }
    else {
        gen `new' = .
    }
end


** clean by each year
capture program drop clean_one_year
program define clean_one_year
	args y
	
	quietly get_rawfile `y'
	local infile `r(infile)'

	di as text "Cleaning `y' : `infile'"
	
	import delimited using "$RAW/`infile'", ///
	delimiter(",") varnames(nonames) rowrange(2) clear 

	* source map 불러오기
	quietly set_source_map `y'
	
	*필요한 변수만 남기기 전에 source 변수 목록 만들기
	local keep_src
	foreach nm in survey_ym gender birth_year educ educ_attend grad_year marital activity_status worked_lastweek prev_work industry_code occupation_code worker_status firm_size age weight labour_force experience_raw hours_week pension_raw healthins_raw employins_raw severance bonus overtime_pay paid_leave union_raw monthly_wage fivedays_working flexible_work contract_work {
		if "``nm''" != "" local keep_src `keep_src' ``nm''
	}
	keep `keep_src'
	
	 * 공통 이름으로 변환
    safe_rename "`survey_ym'" survey_ym
    safe_rename "`gender'" gender_raw
    safe_rename "`birth_year'" birth_year
    safe_rename "`educ'" educ_raw
    safe_rename "`educ_attend'" educ_attend_raw
    safe_rename "`grad_year'" grad_year
    safe_rename "`marital'" marital_raw
    safe_rename "`activity_status'" activity_status_raw
    safe_rename "`worked_lastweek'" worked_lastweek_raw
	safe_rename "`prev_work'" prev_work
    safe_rename "`industry_code'" industry_code
    safe_rename "`occupation_code'" occupation_code
    safe_rename "`worker_status'" worker_status_raw
    safe_rename "`firm_size'" firm_size_raw
    safe_rename "`age'" age
    safe_rename "`weight'" weight
	safe_rename "`labour_force'" labour_force
	safe_rename "`experience_raw'" experience_raw
    safe_rename "`hours_week'" hours_week
    safe_rename "`pension_raw'" pension_raw
    safe_rename "`healthins_raw'" healthins_raw
    safe_rename "`employins_raw'" employins_raw
	safe_rename "`severance'" severance_raw
	safe_rename "`bonus'" bonus_raw
	safe_rename "`overtime_pay'" overtime_pay_raw
	safe_rename "`paid_leave'" paid_leave
    safe_rename "`union_raw'" union_raw
    safe_rename "`monthly_wage'" monthly_wage
	safe_rename "`fivedays_working'" fivedays_working
	safe_rename "`flexible_work'" flexible_work
	safe_rename "`contract_work'" contract_work
	
	** 공통 변수 생성
    gen year = `y'
	* Survey weight
	* Raw MDIS weight is population weight multiplied by 1,000.
	gen popwt = weight / 1000
	label variable popwt "Population weight = raw MDIS weight / 1,000"

    * gender harmonization
    gen male = .
    replace male = 1 if inlist(gender_raw, 1)
    replace male = 0 if inlist(gender_raw, 2)
	
	* Harmonized age group code
	gen agegrp5 = .
	replace agegrp5 = 1 if inrange(age, 15, 19)
	replace agegrp5 = 2 if inrange(age, 20, 24)
	replace agegrp5 = 3 if inrange(age, 25, 29)
	replace agegrp5 = 4 if inrange(age, 30, 34)
	replace agegrp5 = 5 if inrange(age, 35, 39)
	replace agegrp5 = 6 if inrange(age, 40, 44)
	replace agegrp5 = 7 if inrange(age, 45, 49)
	replace agegrp5 = 8 if inrange(age, 50, 54)
	replace agegrp5 = 9 if inrange(age, 55, 59)
	replace agegrp5 = 10 if inrange(age, 60, 64)
	replace agegrp5 = 11 if inrange(age, 65, 69)
	replace agegrp5 = 12 if inrange(age, 70, 74)
	replace agegrp5 = 13 if age >= 75 & age < .
	
	label define agegrp5_lbl ///
	1 "15-19" ///
	2  "20-24" ///
    3  "25-29" ///
    4  "30-34" ///
    5  "35-39" ///
    6  "40-44" ///
    7  "45-49" ///
    8  "50-54" ///
    9  "55-59" ///
    10 "60-64" ///
    11 "65-69" ///
    12 "70-74" ///
    13 "75+"
	
	label values agegrp5 agegrp5_lbl
	label variable agegrp5 "Harmonized 5-year age group code"
 
    *employed variable
	gen employed = .
	replace employed = 1 if labour_force == 1
	replace employed = 0 if inlist(labour_force, 2, 3)
    
	* worker status harmonization
	gen wage_worker = .
    replace wage_worker = 1 if inlist(worker_status_raw, 1,2,3)	
    replace wage_worker = 0 if inlist(worker_status_raw, 4,5,6)	

	* monthly wage cleaning
	gen monthly_wage_clean = monthly_wage if wage_worker == 1 & monthly_wage > 0
	* year-specific p1 and p99
bysort year: egen p1_mw  = pctile(monthly_wage_clean), p(1)
bysort year: egen p99_mw = pctile(monthly_wage_clean), p(99)

gen monthly_wage_trim = monthly_wage_clean ///
    if monthly_wage_clean >= p1_mw & monthly_wage_clean <= p99_mw

gen log_monthly_wage_trim = log(monthly_wage_trim)

label var monthly_wage_trim "Monthly wage, within-year p1-p99 trimmed"
label var log_monthly_wage_trim "Log monthly wage, within-year p1-p99 trimmed"
	
    * firm size
    gen largefirm = .
    replace largefirm = 1 if firm_size_raw == 6
    replace largefirm = 0 if inrange(firm_size_raw,1,5)

    * insurance
    gen pension = .
    replace pension = 1 if inlist(pension_raw,1,11,21,31)
    replace pension = 0 if inlist(pension_raw,2,12,22,32)

    gen healthins = .
    replace healthins = 1 if inlist(healthins_raw,1,11,21,31)
    replace healthins = 0 if inlist(healthins_raw,2,12,22,32)
	
	gen employins = .
    replace employins = 1 if inlist(employins_raw,1,11,21,31)
    replace employins = 0 if inlist(employins_raw,2,12,22,32)
	
	gen severance = .
    replace severance = 1 if inlist(severance_raw,1,11,21,31)
    replace severance = 0 if inlist(severance_raw,2,12,22,32)
	
	gen bonus = .
    replace bonus = 1 if inlist(bonus_raw,1,11,21,31)
    replace bonus = 0 if inlist(bonus_raw,2,12,22,32)
	
	gen overtime_pay = .
    replace overtime_pay = 1 if inlist(overtime_pay_raw,1,11,21,31)
    replace overtime_pay = 0 if inlist(overtime_pay_raw,2,12,22,32)

	
****************************************************
* Harmonise contract duration variable
* contract_fixed = 1 if fixed-term contract
* contract_fixed = 0 if no fixed contract term
****************************************************

gen contract_fixed = .

* 2001–2002 coding:
* 1 = no fixed term, 2 = fixed term
replace contract_fixed = 0 if inrange(year, 2001, 2002) & contract_work == 1
replace contract_fixed = 1 if inrange(year, 2001, 2002) & contract_work == 2

* 2003 onward coding:
* 1 = fixed term, 2 = no fixed term
replace contract_fixed = 1 if year >= 2003 & contract_work == 1
replace contract_fixed = 0 if year >= 2003 & contract_work == 2

label define contract_fixed_lbl ///
    0 "No fixed contract term" ///
    1 "Fixed-term contract", replace

label values contract_fixed contract_fixed_lbl
label variable contract_fixed "Fixed-term contract indicator, harmonised across years"

	gen permanent = .
	replace permanent = 1 if worker_status_raw == 1 & contract_fixed == 0
	replace permanent = 0 if worker_status_raw == 1 & contract_fixed == 1
	replace permanent = 0 if inlist(worker_status_raw, 2, 3)
	
	label define permanent_lbl 0 "Non-permanent / fixed-term, temporary or daily" ///
                           1 "Permanent / open-ended regular employee", replace
label values permanent permanent_lbl

label variable permanent "Permanent employee: regular worker with no fixed contract term"
	
    * hourly wage
    gen monthly_hours = hours_week * 4.345 if hours_week < .
    gen hourly_wage = monthly_wage / monthly_hours if monthly_wage > 0 & monthly_hours > 0
    gen log_hourly_wage = log(hourly_wage) if hourly_wage > 0

    order year survey_ym male gender_raw birth_year age educ_raw grad_year ///
          marital_raw worker_status_raw wage_worker industry_code occupation_code ///
          firm_size_raw largefirm monthly_wage hours_week hourly_wage ///
          log_hourly_wage pension healthins employins weight popwt, first

    save "$CLEAN/clean_`y'.dta", replace
end

** 전체 연도 자동실행
forvalues y = 2001/2025 {
	clean_one_year `y'
}




