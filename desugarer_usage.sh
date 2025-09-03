#!/bin/bash

# Configuration - Update these paths as needed
SEARCH_DIR="$HOME/github.com/vistuleB/wly-composer/vxml_pipeline/src/desugarers"
CHECK_FILE_1="$HOME/github.com/MrChaker/little-bo-peep-solid/renderer/src/renderer.gleam"
CHECK_FILE_2="$HOME/github.com/MrChaker/ti2_html/src/pipeline_html_2_wly.gleam"
CHECK_FILE_3="$HOME/github.com/MrChaker/ti2_html/src/pipeline_wly_2_html.gleam"
CHECK_FILE_4="$HOME/github.com/vistuleB/ti3/src/formatter_pipeline.gleam"
CHECK_FILE_5="$HOME/github.com/vistuleB/ti3/src/main_pipeline.gleam"

# Array of files to check against
CHECK_FILES=("$CHECK_FILE_1" "$CHECK_FILE_2" "$CHECK_FILE_3" "$CHECK_FILE_4" "$CHECK_FILE_5")

# Array to store files that don't appear as substrings
missing_files=()

# Check if search directory exists
if [ ! -d "$SEARCH_DIR" ]; then
    echo "Error: Directory '$SEARCH_DIR' does not exist."
    exit 1
fi

# Check if all check files exist
for file in "${CHECK_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "Warning: File '$file' does not exist or is not readable."
    fi
done

echo "Checking .gleam files in: $SEARCH_DIR"
echo "Against files:"
printf '  %s\n' "${CHECK_FILES[@]}"
echo "----------------------------------------"

# Find all .gleam files and process them
while IFS= read -r -d '' gleam_file; do
    # Extract filename without path and extension
    filename=$(basename "$gleam_file" .gleam)

    # Flag to track if filename was found
    found=false
    
    # Check each of the 5 files for the filename as substring
    for check_file in "${CHECK_FILES[@]}"; do
        if [ -f "$check_file" ] && grep -q "$filename" "$check_file"; then
            found=true
            break
        fi
    done
    
    # If not found in any file, add to missing list
    if [ "$found" = false ]; then
        missing_files+=("$filename")
    fi
    
done < <(find "$SEARCH_DIR" -name "*.gleam" -type f -print0)

# Report results
echo ""
if [ ${#missing_files[@]} -eq 0 ]; then
    echo "All .gleam file names were found as substrings in the checked files."
else
    echo "The following .gleam file names were NOT found as substrings:"
    printf "\n"
    printf '%s\n' "${missing_files[@]}" | sort
fi

echo ""
echo "Summary: ${#missing_files[@]} file(s) not found out of $(find "$SEARCH_DIR" -name "*.gleam" -type f | wc -l) total .gleam files."