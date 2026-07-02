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
- `00_globals.do`: Global root
- `01_clean_all.do`: Data cleaning for each year
- `02_append.do`: Append cleaned data from 2000-2025
- `03_analysis.do`: Event Study and main Diff-in-Diff regression

## Status
This project is ongoing and results are preliminary.
