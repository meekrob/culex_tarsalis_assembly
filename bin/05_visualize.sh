#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --job-name=visualize
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main_mosquito.sh
BUSCO_DIR=$1       # BUSCO results directory
RNAQUAST_DIR=$2    # rnaQuast results directory
OUT_DIR=$3         # Output directory for visualizations
DRAFT_BUSCO_DIR=$4 # BUSCO results for draft transcriptome (optional)
DRAFT_RNAQUAST_DIR=$5 # rnaQuast results for draft transcriptome (optional)
LOG_DIR=${6:-"logs/05_visualization"}  # Directory for logs
SUMMARY_FILE=${7:-"logs/pipeline_summary.csv"}  # Summary file path
DEBUG_MODE=${8:-false}  # Debug mode flag

# Create output directory if it doesn't exist
mkdir -p $OUT_DIR
mkdir -p $LOG_DIR

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$OUT_DIR/combined_plot.pdf" ]]; then
    echo "Debug mode: Visualization plot already exists: $OUT_DIR/combined_plot.pdf. Skipping visualization."
    
    # Add entry to summary file
    echo "Visualization,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    echo "Visualization,,Plots Generated,$OUT_DIR/combined_plot.pdf" >> "$SUMMARY_FILE"
    
    exit 0
fi

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting visualization"
echo "BUSCO directory: $BUSCO_DIR"
echo "rnaQuast directory: $RNAQUAST_DIR"
echo "Output directory: $OUT_DIR"
if [[ -n "$DRAFT_BUSCO_DIR" && -d "$DRAFT_BUSCO_DIR" ]]; then
    echo "Draft BUSCO directory: $DRAFT_BUSCO_DIR"
fi
if [[ -n "$DRAFT_RNAQUAST_DIR" && -d "$DRAFT_RNAQUAST_DIR" ]]; then
    echo "Draft rnaQuast directory: $DRAFT_RNAQUAST_DIR"
fi

# Create an R script for visualization
R_SCRIPT="$OUT_DIR/generate_plots.R"

cat > $R_SCRIPT << 'EOF'
# R script to generate visualizations from BUSCO and rnaQuast results

library(ggplot2)
library(dplyr)
library(tidyr)
library(gridExtra)

# Function to read BUSCO summary file
read_busco <- function(file_path, label) {
  if (!file.exists(file_path)) {
    warning(paste("BUSCO file not found:", file_path))
    return(NULL)
  }
  
  lines <- readLines(file_path)
  summary_line <- grep("C:", lines, value = TRUE)[1]
  
  if (is.na(summary_line)) {
    warning(paste("Could not find BUSCO summary line in:", file_path))
    return(NULL)
  }
  
  # Extract percentages
  complete <- as.numeric(sub("C:(\\d+\\.\\d+)%.*", "\\1", summary_line))
  single <- as.numeric(sub(".*\\[S:(\\d+\\.\\d+)%.*", "\\1", summary_line))
  duplicated <- as.numeric(sub(".*D:(\\d+\\.\\d+)%.*", "\\1", summary_line))
  fragmented <- as.numeric(sub(".*F:(\\d+\\.\\d+)%.*", "\\1", summary_line))
  missing <- as.numeric(sub(".*M:(\\d+\\.\\d+)%.*", "\\1", summary_line))
  
  data.frame(
    Category = c("Complete (single)", "Complete (duplicated)", "Fragmented", "Missing"),
    Percentage = c(single, duplicated, fragmented, missing),
    Assembly = label
  )
}

# Function to read rnaQuast report file
read_rnaquast <- function(file_path, label) {
  if (!file.exists(file_path)) {
    warning(paste("rnaQuast file not found:", file_path))
    return(NULL)
  }
  
  lines <- readLines(file_path)
  
  # Extract key metrics
  transcripts <- as.numeric(sub("Transcripts: (\\d+)", "\\1", grep("^Transcripts:", lines, value = TRUE)[1]))
  total_length <- as.numeric(sub("Total length: (\\d+)", "\\1", grep("^Total length", lines, value = TRUE)[1]))
  n50 <- as.numeric(sub("Transcript N50: (\\d+)", "\\1", grep("^Transcript N50:", lines, value = TRUE)[1]))
  
  data.frame(
    Metric = c("Transcripts", "Total Length (Mb)", "N50"),
    Value = c(transcripts, total_length / 1e6, n50),
    Assembly = label
  )
}

# Read BUSCO results
args <- commandArgs(trailingOnly = TRUE)
busco_dir <- args[1]
rnaquast_dir <- args[2]
out_dir <- args[3]
draft_busco_dir <- if (length(args) >= 4 && args[4] != "") args[4] else NULL
draft_rnaquast_dir <- if (length(args) >= 5 && args[5] != "") args[5] else NULL

# Find BUSCO summary files
busco_files <- list.files(busco_dir, pattern = "short_summary.*\\.txt$", full.names = TRUE)
if (length(busco_files) == 0) {
  stop("No BUSCO summary files found in ", busco_dir)
}

# Read assembly BUSCO results
busco_data <- read_busco(busco_files[1], "Assembly")

# Read draft BUSCO results if available
if (!is.null(draft_busco_dir)) {
  draft_busco_files <- list.files(draft_busco_dir, pattern = "short_summary.*\\.txt$", full.names = TRUE)
  if (length(draft_busco_files) > 0) {
    draft_busco_data <- read_busco(draft_busco_files[1], "Draft")
    if (!is.null(draft_busco_data)) {
      busco_data <- rbind(busco_data, draft_busco_data)
    }
  }
}

# Read rnaQuast results
rnaquast_file <- file.path(rnaquast_dir, "report.txt")
rnaquast_data <- read_rnaquast(rnaquast_file, "Assembly")

# Read draft rnaQuast results if available
if (!is.null(draft_rnaquast_dir)) {
  draft_rnaquast_file <- file.path(draft_rnaquast_dir, "report.txt")
  draft_rnaquast_data <- read_rnaquast(draft_rnaquast_file, "Draft")
  if (!is.null(draft_rnaquast_data)) {
    rnaquast_data <- rbind(rnaquast_data, draft_rnaquast_data)
  }
}

# Create BUSCO plot
if (!is.null(busco_data)) {
  busco_plot <- ggplot(busco_data, aes(x = Assembly, y = Percentage, fill = Category)) +
    geom_bar(stat = "identity") +
    scale_fill_manual(values = c("Complete (single)" = "#44AA99", 
                                "Complete (duplicated)" = "#88CCEE", 
                                "Fragmented" = "#DDCC77", 
                                "Missing" = "#CC6677")) +
    labs(title = "BUSCO Assessment", y = "Percentage", x = "") +
    theme_minimal() +
    theme(legend.position = "bottom")
  
  ggsave(file.path(out_dir, "busco_plot.pdf"), busco_plot, width = 8, height = 6)
}

# Create rnaQuast plots
if (!is.null(rnaquast_data)) {
  # Reshape data for plotting
  rnaquast_long <- rnaquast_data %>%
    pivot_wider(names_from = Metric, values_from = Value) %>%
    pivot_longer(cols = c("Transcripts", "Total Length (Mb)", "N50"), 
                 names_to = "Metric", values_to = "Value")
  
  # Create separate plots for each metric
  rnaquast_plots <- rnaquast_long %>%
    group_by(Metric) %>%
    do(plot = ggplot(., aes(x = Assembly, y = Value, fill = Assembly)) +
         geom_bar(stat = "identity") +
         labs(title = unique(.$Metric), y = "", x = "") +
         theme_minimal() +
         theme(legend.position = "none"))
  
  # Arrange plots in a grid
  pdf(file.path(out_dir, "rnaquast_plots.pdf"), width = 10, height = 8)
  grid.arrange(grobs = rnaquast_plots$plot, ncol = 2)
  dev.off()
}

# Create combined plot if both datasets are available
if (!is.null(busco_data) && !is.null(rnaquast_data)) {
  pdf(file.path(out_dir, "combined_plot.pdf"), width = 12, height = 8)
  grid.arrange(
    busco_plot,
    arrangeGrob(grobs = rnaquast_plots$plot, ncol = 2),
    ncol = 1,
    heights = c(1, 1.5)
  )
  dev.off()
}

# Save summary data
if (!is.null(busco_data)) {
  write.csv(busco_data, file.path(out_dir, "busco_summary.csv"), row.names = FALSE)
}
if (!is.null(rnaquast_data)) {
  write.csv(rnaquast_data, file.path(out_dir, "rnaquast_summary.csv"), row.names = FALSE)
}

cat("Visualization completed successfully!\n")
EOF

# Run the R script
cmd="Rscript $R_SCRIPT $BUSCO_DIR $RNAQUAST_DIR $OUT_DIR $DRAFT_BUSCO_DIR $DRAFT_RNAQUAST_DIR"
echo "Executing command: $cmd"
time eval $cmd

# Check if visualization was successful
if [[ $? -ne 0 ]]; then
    echo "Error: Visualization failed!" >&2
    echo "Visualization,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# Check if output files were created
if [[ ! -s "$OUT_DIR/combined_plot.pdf" && ! -s "$OUT_DIR/busco_plot.pdf" && ! -s "$OUT_DIR/rnaquast_plots.pdf" ]]; then
    echo "Error: No visualization plots were generated!" >&2
    echo "Visualization,,Status,Failed (missing output)" >> "$SUMMARY_FILE"
    exit 1
fi

echo "Visualization completed successfully!"

# Add visualization information to summary file
echo "Visualization,,Status,Completed" >> "$SUMMARY_FILE"
if [[ -s "$OUT_DIR/combined_plot.pdf" ]]; then
    echo "Visualization,,Plots Generated,$OUT_DIR/combined_plot.pdf" >> "$SUMMARY_FILE"
elif [[ -s "$OUT_DIR/busco_plot.pdf" ]]; then
    echo "Visualization,,Plots Generated,$OUT_DIR/busco_plot.pdf" >> "$SUMMARY_FILE"
elif [[ -s "$OUT_DIR/rnaquast_plots.pdf" ]]; then
    echo "Visualization,,Plots Generated,$OUT_DIR/rnaquast_plots.pdf" >> "$SUMMARY_FILE"
fi

echo "Visualization results saved to $OUT_DIR"