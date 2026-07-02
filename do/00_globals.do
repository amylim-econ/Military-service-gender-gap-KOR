****************************************************
* 0. set up
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

clear all
set more off

* project root
cd ".."

*folder paths
global RAW   "data_raw"
global CLEAN "data_clean"
global OUT   "output"

