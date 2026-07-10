# Military-service-gender-gap-KOR
Ongoing research project for MSc Economic Policy for International Development dissertation at LSE. Primary research question is "Does a one-sided shift in labour supply reshape gender gaps in early-career labour markets?"

# Military Service Reform and Gender Gaps in Early Careers
This repository contains Stata code for an ongoing research project
studying the labor market effects of South Korea's mandatory military
service reduction.

## Research Question
How does a reduction in mandatory military service affect men relative to women in the same birth cohorts:
1. Labor market entry timing
2. Job quality at entry


## Identification Strategy
I estimate cohort-based event study and difference-in-differences specifications, with a treatment-intensity check based on months of service saved, exploiting differential exposure to the military service reform across
birth cohorts.

## Data
The analysis uses nationally representative microdata (restricted).
Due to data confidentiality, raw data are not included.

## Code Structure
- `00_globals.do`: Global root
- `01_clean_all.do`: Data cleaning for each year
- `02_append.do`: Append cleaned data from 2001-2025
- `03_analysis.do`: Event Study and main DiD regressions

## Status
This project is ongoing and results are preliminary.
