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
UNUSED_PARAM=$2    # Placeholder for removed rnaQuast parameter
OUT_DIR=$3         # Output directory for visualizations
DRAFT_BUSCO_DIR=$4 # BUSCO results for draft transcriptome (optional)
UNUSED_PARAM2=$5   # Placeholder for removed rnaQuast parameter
LOG_DIR=${6:-"logs/05_visualization"}  # Directory for logs
SUMMARY_FILE=${7:-"logs/pipeline_summary.csv"}  # Summary file path
DEBUG_MODE=${8:-false}  # Debug mode flag

# Create output directory if it doesn't exist
mkdir -p $OUT_DIR
mkdir -p $LOG_DIR

# Create a log file for this visualization job
VIZ_LOG="$LOG_DIR/visualization_$(date +%Y%m%d_%H%M%S).log"
echo "Starting visualization job at $(date)" > $VIZ_LOG
echo "BUSCO directory: $BUSCO_DIR" >> $VIZ_LOG
echo "Output directory: $OUT_DIR" >> $VIZ_LOG
if [[ -n "$DRAFT_BUSCO_DIR" && -d "$DRAFT_BUSCO_DIR" ]]; then
    echo "Draft BUSCO directory: $DRAFT_BUSCO_DIR" >> $VIZ_LOG
fi

# Get start time for timing
start_time=$(date +%s)

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$OUT_DIR/busco_plot.pdf" ]]; then
    echo "Debug mode: Visualization plot already exists: $OUT_DIR/busco_plot.pdf. Skipping visualization." | tee -a $VIZ_LOG
    
    # Add entry to summary file
    echo "Visualization,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    echo "Visualization,,Plots Generated,$OUT_DIR/busco_plot.pdf" >> "$SUMMARY_FILE"
    
    exit 0
fi

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting visualization" | tee -a $VIZ_LOG

# Create an R script for visualization
R_SCRIPT="$OUT_DIR/generate_plots.R"

cat > $R_SCRIPT << 'EOF'
# R script to generate visualizations from BUSCO results

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

# Read command line arguments
args <- commandArgs(trailingOnly = TRUE)
busco_dir <- args[1]
out_dir <- args[2]
draft_busco_dir <- if (length(args) >= 3 && args[3] != "") args[3] else NULL

# Find BUSCO summary files
busco_files <- list.files(busco_dir, pattern = "short_summary.*\\.txt$", full.names = TRUE, recursive = TRUE)
if (length(busco_files) == 0) {
  stop("No BUSCO summary files found in ", busco_dir)
}

# Read assembly BUSCO results
busco_data <- read_busco(busco_files[1], "Assembly")

# Read draft BUSCO results if available
if (!is.null(draft_busco_dir)) {
  draft_busco_files <- list.files(draft_busco_dir, pattern = "short_summary.*\\.txt$", full.names = TRUE, recursive = TRUE)
  if (length(draft_busco_files) > 0) {
    draft_busco_data <- read_busco(draft_busco_files[1], "Draft")
    if (!is.null(draft_busco_data)) {
      busco_data <- rbind(busco_data, draft_busco_data)
    }
  }
}

# Generate BUSCO plot if data is available
if (!is.null(busco_data)) {
  # Create color palette
  colors <- c("Complete (single)" = "#4DBBD5FF", 
              "Complete (duplicated)" = "#00A087FF",
              "Fragmented" = "#E64B35FF", 
              "Missing" = "#3C5488FF")
  
  # Create BUSCO plot
  busco_plot <- ggplot(busco_data, aes(x = Assembly, y = Percentage, fill = Category)) +
    geom_bar(stat = "identity", width = 0.7) +
    scale_fill_manual(values = colors) +
    theme_minimal() +
    labs(title = "BUSCO Assessment Results",
         y = "Percentage (%)",
         x = NULL) +
    theme(legend.position = "right",
          axis.text.x = element_text(angle = 45, hjust = 1))
  
  # Save BUSCO plot
  pdf(file.path(out_dir, "busco_plot.pdf"), width = 8, height = 6)
  print(busco_plot)
  dev.off()
  
  # Save summary data
  write.csv(busco_data, file.path(out_dir, "busco_summary.csv"), row.names = FALSE)
  
  cat("BUSCO visualization completed successfully!\n")
} else {
  cat("Warning: No BUSCO data available for visualization!\n")
}
EOF

# Run the R script
cmd="Rscript $R_SCRIPT $BUSCO_DIR $OUT_DIR $DRAFT_BUSCO_DIR"
echo "Executing command: $cmd" | tee -a $VIZ_LOG
time eval $cmd 2>> $VIZ_LOG

# Check if visualization was successful
if [[ $? -ne 0 ]]; then
    echo "Error: Visualization failed!" | tee -a $VIZ_LOG
    echo "Visualization,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# Check if output files were created
if [[ ! -s "$OUT_DIR/busco_plot.pdf" ]]; then
    echo "Error: No visualization plots were generated!" | tee -a $VIZ_LOG
    echo "Visualization,,Status,Failed (missing output)" >> "$SUMMARY_FILE"
    exit 1
fi

echo "Visualization completed successfully!" | tee -a $VIZ_LOG

# Add visualization information to summary file
echo "Visualization,,Status,Completed" >> "$SUMMARY_FILE"
echo "Visualization,,Plots Generated,$OUT_DIR/busco_plot.pdf" >> "$SUMMARY_FILE"

# Add HTML summary
cat > "$OUT_DIR/assembly_summary.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Assembly Summary</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            color: #333;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
        }
        h1 {
            color: #2c3e50;
            border-bottom: 2px solid #3498db;
            padding-bottom: 10px;
        }
        h2 {
            color: #2980b9;
            margin-top: 30px;
        }
        .section {
            background: #f9f9f9;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        img {
            max-width: 100%;
            height: auto;
            display: block;
            margin: 20px auto;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            padding: 12px 15px;
            border-bottom: 1px solid #ddd;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
        }
        .metric {
            font-weight: bold;
        }
        .value {
            font-family: monospace;
        }
        a {
            color: #3498db;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Assembly Summary</h1>
        
        <div class="section">
            <h2>BUSCO Assessment</h2>
EOF

# Extract BUSCO results
if [[ -f "$OUT_DIR/busco_plot.pdf" ]]; then
    cp "$OUT_DIR/busco_plot.pdf" "$OUT_DIR/busco_plot.pdf"
    echo '<p><a href="busco_plot.pdf" target="_blank">View BUSCO results (PDF)</a></p>' >> "$OUT_DIR/assembly_summary.html"
    
    # If there's a BUSCO summary CSV, read some data from it
    if [[ -f "$OUT_DIR/busco_summary.csv" ]]; then
        complete_single=$(grep "Complete (single)" "$OUT_DIR/busco_summary.csv" | cut -d, -f3)
        complete_dupl=$(grep "Complete (duplicated)" "$OUT_DIR/busco_summary.csv" | cut -d, -f3)
        fragmented=$(grep "Fragmented" "$OUT_DIR/busco_summary.csv" | cut -d, -f3)
        missing=$(grep "Missing" "$OUT_DIR/busco_summary.csv" | cut -d, -f3)
        
        cat >> "$OUT_DIR/assembly_summary.html" << EOF
            <table>
                <tr><th>Metric</th><th>Value</th></tr>
                <tr><td class="metric">Complete (single-copy)</td><td class="value">${complete_single}%</td></tr>
                <tr><td class="metric">Complete (duplicated)</td><td class="value">${complete_dupl}%</td></tr>
                <tr><td class="metric">Fragmented</td><td class="value">${fragmented}%</td></tr>
                <tr><td class="metric">Missing</td><td class="value">${missing}%</td></tr>
            </table>
EOF
    fi
else
    echo "<p>BUSCO results not found.</p>" >> "$OUT_DIR/assembly_summary.html"
fi

# Close HTML
cat >> "$OUT_DIR/assembly_summary.html" << EOF
        </div>
    </div>
</body>
</html>
EOF

# Check if visualization completed successfully
if [[ $? -eq 0 && -f "$OUT_DIR/assembly_summary.html" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "Visualization completed successfully in $runtime seconds" | tee -a $VIZ_LOG
    echo "Output HTML: $OUT_DIR/assembly_summary.html" | tee -a $VIZ_LOG
    echo "Visualization,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
else
    echo "Error: Visualization failed!" | tee -a $VIZ_LOG
    exit 1
fi