# AGENTS.md

## Project overview
This repository contains Stata code for an MSc dissertation project at LSE on the labour market effects of South Korea's mandatory military service reduction.

The main research question is whether reductions in mandatory military service affected men relative to women in the same birth cohorts:
- labour market entry timing
- job quality at entry

The empirical strategy is a cohort-based event-study and difference-in-differences design exploiting differential exposure to military service reform across birth cohorts, assuming the typical timing of military service around age 20 (Military Manpower Administration, 2000-2024).

This is an empirical economics research project, not a software application. Prioritise reproducibility, data safety, and preservation of the identification strategy.

## Operating mode for Codex / coding agents
Work in planning mode by default.

Before modifying any existing `.do` file, first explain:
1. which file(s) you propose to modify,
2. why the change is needed,
3. the exact logic of the proposed change,
4. whether the change affects data cleaning, sample construction, treatment definition, regression specification, tables, or figures.

Do not implement the change until the user confirms.

Small non-substantive edits, such as fixing comments or formatting, should still be described briefly before editing if they touch existing analysis files.

## Data safety rules
The `data_raw/` folder contains restricted raw data.
Never modify, overwrite, rename, delete, move, or re-save any files inside `data_raw/`.

Treat `data_raw/` as read-only.

Code may read from `data_raw/`, but all cleaned, appended, intermediate, or analysis-ready datasets must be written outside `data_raw/`, for example to a `data_clean/` folder defined in `00_globals.do`.

Do not commit raw data, copies of raw data, or temporary files derived from raw data.

If a task appears to require changing anything inside `data_raw/`, stop and ask the user for explicit confirmation before proceeding.

## Code structure
The main workflow is:
1. `00_globals.do`  
   Defines root paths and global settings.

2. `01_clean_all.do`  
   Cleans year-specific raw data.

3. `02_append.do`  
   Appends cleaned data from 2001-2025.
   Creates fixed industry gender type from pre-reform composition and diagnostic for industry gender composition.

4. `03_analysis.do`  
   Runs the event-study and main difference-in-differences analysis.
   Export tables and figures.

Do not run downstream scripts before the required upstream scripts have been checked or run.

When adding new code, prefer creating a clearly named supplementary `.do` file rather than inserting large blocks into existing scripts, unless the user asks for direct integration.

## Stata coding conventions
Use Stata syntax that is readable and explicit.

Comment any non-obvious data cleaning, variable construction, sample restriction, or regression choice.

Avoid hard-coded absolute paths except in `00_globals.do`.

Use globals or locals defined in `00_globals.do` for paths and shared settings.

Preserve existing variable names unless there is a clear reason to change them.

Do not silently drop observations. Any `drop`, `keep`, or sample restriction must be clearly commented.

Use logs when running major scripts, and save logs to an appropriate output/log folder if one is defined.

## Empirical design safeguards
Do not change the core identification strategy without explicit user approval.

In particular, do not alter the following without first explaining the implications:
- treatment definition,
- cohort exposure definition,
- event-time construction,
- omitted/reference period,
- sample period,
- control group,
- gender sample restrictions,
- wage or job-quality outcome definitions,
- fixed effects,
- clustering level,
- regression weights,
- binning of event-study endpoints.

If you notice a possible problem with the empirical design, explain it as a concern and propose options. Do not automatically rewrite the specification.

## Outputs, tables, and figures
Do not overwrite existing tables, figures, or regression output unless explicitly instructed.

When creating new outputs, use informative filenames that indicate the date, specification, or purpose.

After running analysis code, report:
- which script was run,
- whether it completed successfully,
- which outputs were created or changed,
- any warnings, errors, or unexpected sample-size changes.

## Version control
Before editing, inspect the current file and make the smallest change necessary.

After editing, summarise the changes clearly.

Do not make broad refactors unless the user explicitly asks.

Do not commit changes automatically unless the user asks for a commit.

Suggested commit message style:
- `clean: clarify cohort construction`
- `analysis: add robustness check for event-study window`
- `docs: add AGENTS.md`
- `output: update main regression table`

## When uncertain
If instructions conflict, prioritise:
1. user instructions in the current chat,
2. this AGENTS.md,
3. README.md,
4. existing code conventions.

If the requested task could affect the research design, data confidentiality, or reproducibility, stop and ask before editing.
