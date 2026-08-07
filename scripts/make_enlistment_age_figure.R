#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(readxl)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: make_enlistment_age_figure.R INPUT_XLSX OUTPUT_DIR")
input_file <- args[[1]]
output_dir <- args[[2]]
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

raw <- read_excel(input_file, sheet = "데이터", col_names = FALSE)
years <- as.integer(unlist(raw[1, seq(2, ncol(raw), by = 2)]))
age_ko <- c("19세", "20세", "21세", "22세", "23세", "24세", "25세이상")
age_en <- c("19", "20", "21", "22", "23", "24", "25+")
row_labels <- trimws(as.character(raw[[1]]))

records <- list()
k <- 1L
for (j in seq_along(years)) {
  if (years[[j]] < 2019) next
  count_col <- 2L + 2L * (j - 1L)
  total <- as.numeric(raw[[count_col]][match("계", row_labels)])
  for (i in seq_along(age_ko)) {
    count <- as.numeric(raw[[count_col]][match(age_ko[[i]], row_labels)])
    records[[k]] <- data.frame(year = years[[j]], age = age_en[[i]], count = count, total = total)
    k <- k + 1L
  }
}
data <- do.call(rbind, records)
data$age <- factor(data$age, levels = age_en)

pooled <- aggregate(count ~ age, data = data, FUN = sum)
pooled$share <- 100 * pooled$count / sum(pooled$count)
pooled$highlight <- pooled$age == "20"
age20_share <- pooled$share[pooled$age == "20"]
annual20 <- subset(data, age == "20")
annual20$share <- 100 * annual20$count / annual20$total

write.csv(
  pooled[c("age", "count", "share")],
  file.path(output_dir, "enlistment_age_distribution_2019_2024.csv"),
  row.names = FALSE
)

p <- ggplot(pooled, aes(x = age, y = share, fill = highlight)) +
  geom_col(width = 0.72) +
  geom_text(
    data = subset(pooled, age == "20"),
    aes(label = sprintf("%.1f%%", share)),
    vjust = -0.55, size = 3.7, color = "#1A476F"
  ) +
  scale_fill_manual(values = c(`FALSE` = "#B7C3CE", `TRUE` = "#1A476F"), guide = "none") +
  scale_y_continuous(limits = c(0, 70), breaks = seq(0, 70, 10), expand = expansion(mult = c(0, 0))) +
  labs(
    title = "Age distribution of active-duty enlistments, 2019-2024",
    x = "Age at enlistment",
    y = "Share of enlistments (%)"
  ) +
  theme_minimal(base_family = "Helvetica", base_size = 10) +
  theme(
    plot.title = element_text(face = "plain", size = 12, hjust = 0.5, margin = margin(b = 7)),
    axis.title = element_text(size = 10),
    axis.text = element_text(color = "black", size = 9),
    axis.line = element_line(color = "black", linewidth = 0.4),
    axis.ticks = element_line(color = "black", linewidth = 0.4),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_line(color = "#E5E5E5", linewidth = 0.4, linetype = "dashed"),
    plot.margin = margin(8, 10, 8, 8)
  )

stem <- file.path(output_dir, "enlistment_age_distribution_2019_2024")
ggsave(paste0(stem, ".pdf"), p, width = 6.4, height = 3.8, device = "pdf")
ggsave(paste0(stem, ".png"), p, width = 6.4, height = 3.8, dpi = 300, bg = "white")

latex <- paste0(
  "% Requires \\usepackage{graphicx}\n",
  "\\begin{figure}[H]\n",
  "    \\centering\n",
  "    \\includegraphics[width=0.5\\linewidth]{figures/enlistment_age_distribution_2019_2024.pdf}\n",
  "    \\caption{Age distribution of active-duty enlistments, 2019--2024.}\n",
  "    \\label{fig:enlistment_age_distribution}\n",
  "    \\vspace{0.4em}\n",
  "    \\begin{minipage}{0.95\\textwidth}\n",
  "    \\footnotesize\n",
  "    \\textit{Notes:} Shares pool annual counts for 2019--2024, the years for which single-year age categories are available. Age 20 accounts for 62.8\\% of enlistments overall and 60.0--64.1\\% in each year. The 25+ category includes all ages 25 and older. Source: Military Manpower Administration, \\textit{Military Statistics}, KOSIS table TX\\_14401\\_A057.\n",
  "    \\end{minipage}\n",
  "\\end{figure}\n"
)
writeLines(latex, paste0(stem, ".tex"))

print(pooled)
cat(sprintf("Age-20 annual range: %.3f-%.3f%%\n", min(annual20$share), max(annual20$share)))
