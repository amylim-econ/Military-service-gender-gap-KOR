# Military-service-gender-gap-KOR
Ongoing research project for MSc Economic Policy for International Development dissertation at LSE. Primary research question is "Does reduction in mandatory military service for male in South Korea decrease time misallocation or increase gender gap in labour market?" 

# Military Service Reform and Gender Gaps in Early Careers
This repository contains Stata code for an ongoing research project
studying the labor market effects of South Korea's mandatory military
service reduction.

## Research Question
How does a reduction in mandatory military service affect:
1. Labor market entry timing
2. Job quality at entry
3. Gender wage gaps in early careers?

## Identification Strategy
I use a cohort-based event study difference-in-differences design,
exploiting differential exposure to the military service reform across
birth cohorts.

## Data
The analysis uses nationally representative microdata (restricted).
Due to data confidentiality, raw data are not included.

## Code Structure
- `01_clean.do`: Data cleaning
- `02_construct_entry_age.do`: Labor market entry age construction
- `03_event_study_entry.do`: Event study on entry age
- `04_event_study_wage.do`: Wage event study
- `05_job_quality_index.do`: Job quality index construction

## Status
This project is ongoing and results are preliminary.
