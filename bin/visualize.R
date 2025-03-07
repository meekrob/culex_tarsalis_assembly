#!/usr/bin/env Rscript

# This script creates visualizations from the BUSCO and rnaQuast results

# Load required libraries
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(patchwork)  # For combining plots
})

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  stop("Usage: Rscript visualize.R <busco_dir> <rnaquast_dir> <out_dir>")
}

busco_dir <- args[1]
rnaquast_dir <- args[2]
out_dir <- args[3]

cat("BUSCO directory:", busco_dir, "\n")
cat("rnaQuast directory:", rnaquast_dir, "\n")
cat("Output directory:", out_dir, "\n")

# Create output directory if it doesn't exist
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Function to parse BUSCO summary file
parse_busco_summary <- function(busco_dir) {
  # Find the summary file
  summary_file <- list.files(busco_dir, pattern = "short_summary.*txt", full.names = TRUE)
  if (length(summary_file) == 0) {
    stop("No BUSCO summary file found in ", busco_dir)
  }
  
  # Read the file
  lines <- readLines(summary_file[1])
  
  # Extract important metrics
  complete <- as.numeric(sub(".*C:(\\d+\\.\\d+)%.*", "\\1", grep("C:", lines, value = TRUE)))
  single <- as.numeric(sub(".*S:(\\d+\\.\\d+)%.*", "\\1", grep("C:", lines, value = TRUE)))
  duplicated <- as.numeric(sub(".*D:(\\d+\\.\\d+)%.*", "\\1", grep("C:", lines, value = TRUE)))
  fragmented <- as.numeric(sub(".*F:(\\d+\\.\\d+)%.*", "\\1", grep("C:", lines, value = TRUE)))
  missing <- as.numeric(sub(".*M:(\\d+\\.\\d+)%.*", "\\1", grep("C:", lines, value = TRUE)))
  
  total <- as.numeric(sub(".*n:(\\d+).*", "\\1", grep("Total BUSCO groups searched", lines, value = TRUE)))
  
  # Create a data frame
  data.frame(
    Category = c("Complete (single)", "Complete (duplicated)", "Fragmented", "Missing"),
    Percentage = c(single, duplicated, fragmented, missing),
    Count = c(round(single * total / 100), round(duplicated * total / 100), 
              round(fragmented * total / 100), round(missing * total / 100))
  )
}

# Function to create BUSCO visualization
create_busco_plot <- function(busco_data) {
  # Create a pie chart for BUSCO categories
  ggplot(busco_data, aes(x = "", y = Percentage, fill = Category)) +
    geom_bar(stat = "identity", width = 1) +
    coord_polar("y", start = 0) +
    theme_minimal() +
    theme(legend.position = "right") +
    labs(title = "BUSCO Assessment Results",
         subtitle = paste("Total BUSCO groups:", sum(busco_data$Count)),
         x = NULL, y = NULL, fill = "Category") +
    scale_fill_brewer(palette = "Set2") +
    geom_text(aes(label = paste0(round(Percentage, 1), "%")), 
              position = position_stack(vjust = 0.5)) +
    theme(plot.title = element_text(hjust = 0.5),
          plot.subtitle = element_text(hjust = 0.5))
}

# Function to parse rnaQuast report
parse_rnaquast_report <- function(rnaquast_dir) {
  # Find the report file
  report_file <- file.path(rnaquast_dir, "report.txt")
  if (!file.exists(report_file)) {
    stop("rnaQuast report file not found in ", rnaquast_dir)
  }
  
  # Read the file
  lines <- readLines(report_file)
  
  # Extract assembly statistics
  transcripts_line <- grep("^Transcripts", lines, value = TRUE)
  transcripts <- as.numeric(gsub(".*\\s(\\d+)\\s*$", "\\1", transcripts_line))
  
  longest_line <- grep("^Longest transcript length", lines, value = TRUE)
  longest <- as.numeric(gsub(".*\\s(\\d+)\\s*$", "\\1", longest_line))
  
  total_length_line <- grep("^Total length", lines, value = TRUE)
  total_length <- as.numeric(gsub(".*\\s(\\d+)\\s*$", "\\1", total_length_line[1]))
  
  avg_length_line <- grep("^Average transcript length", lines, value = TRUE)
  avg_length <- as.numeric(gsub(".*\\s(\\d+)\\s*$", "\\1", avg_length_line))
  
  n50_line <- grep("^Transcript N50", lines, value = TRUE)
  n50 <- as.numeric(gsub(".*\\s(\\d+)\\s*$", "\\1", n50_line))
  
  # Create a data frame
  data.frame(
    Metric = c("Transcripts", "Longest (bp)", "Total length (bp)", "Average length (bp)", "N50 (bp)"),
    Value = c(transcripts, longest, total_length, avg_length, n50)
  )
}

# Function to create rnaQuast visualization
create_rnaquast_plot <- function(rnaquast_data) {
  # Create a bar plot for key metrics
  ggplot(rnaquast_data, aes(x = Metric, y = Value)) +
    geom_bar(stat = "identity", fill = "steelblue") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    labs(title = "Assembly Statistics from rnaQuast",
         x = NULL, y = "Value") +
    geom_text(aes(label = format(Value, big.mark = ",")), vjust = -0.5) +
    theme(plot.title = element_text(hjust = 0.5))
}

# Main execution
tryCatch({
  # Process BUSCO results
  cat("Processing BUSCO results...\n")
  busco_data <- parse_busco_summary(busco_dir)
  busco_plot <- create_busco_plot(busco_data)
  
  # Process rnaQuast results
  cat("Processing rnaQuast results...\n")
  rnaquast_data <- parse_rnaquast_report(rnaquast_dir)
  rnaquast_plot <- create_rnaquast_plot(rnaquast_data)
  
  # Save individual plots
  ggsave(file.path(out_dir, "busco_plot.pdf"), busco_plot, width = 8, height = 6)
  ggsave(file.path(out_dir, "rnaquast_plot.pdf"), rnaquast_plot, width = 10, height = 6)
  
  # Create and save combined plot
  combined_plot <- busco_plot + rnaquast_plot + plot_layout(ncol = 1)
  ggsave(file.path(out_dir, "combined_plot.pdf"), combined_plot, width = 12, height = 10)
  
  # Save data tables
  write.csv(busco_data, file.path(out_dir, "busco_summary.csv"), row.names = FALSE)
  write.csv(rnaquast_data, file.path(out_dir, "rnaquast_summary.csv"), row.names = FALSE)
  
  cat("Visualization completed successfully!\n")
  cat("Results saved to:", out_dir, "\n")
}, error = function(e) {
  cat("Error in visualization:", conditionMessage(e), "\n")
  quit(status = 1)
})
