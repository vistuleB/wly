#!/bin/bash

# Script to replace "desugarer_blame(X)" where X is any integer with "desugarer_blame(line_number)"
# Usage: ./renumber_desugarer_blame.sh [directory_path]

# Set default directory to current directory if no argument provided
TARGET_DIR=src/desugarers/

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

echo "Processing files in directory: $TARGET_DIR"
echo "Renumbering 'desugarer_blame(X)' patterns with correct line numbers..."
echo

# Counter for processed files
processed_files=0

# Process all files in the directory (not subdirectories)
find "$TARGET_DIR" -maxdepth 1 -type f | while read -r file; do
    # Skip binary files using the file command
    if ! file -b --mime-type "$file" | grep -q '^text/'; then
        echo "Skipping non-text file: $(basename "$file")"
        continue
    fi
    
    # Create a temporary file
    temp_file=$(mktemp)
    
    # Track if any replacements were made
    replacements_made=false
    
    # Process the file line by line
    line_number=1
    while IFS= read -r line || [ -n "$line" ]; do
        # Check if line contains "desugarer_blame(" followed by digits and ")"
        if [[ "$line" =~ desugarer_blame\([0-9]+\) ]]; then
            # Replace all occurrences of "desugarer_blame(digits)" with "desugarer_blame(line_number)" on this line
            # Using sed to handle multiple occurrences on the same line
            modified_line=$(echo "$line" | sed -E 's/desugarer_blame\([0-9]+\)/desugarer_blame('"$line_number"')/g')
            echo "$modified_line" >> "$temp_file"
            replacements_made=true
        else
            echo "$line" >> "$temp_file"
        fi
        ((line_number++))
    done < "$file"
    
    # If replacements were made, replace the original file
    if [ "$replacements_made" = true ]; then
        mv "$temp_file" "$file"
        echo "Processed: $(basename "$file")"
        ((processed_files++))
    else
        # No replacements needed, remove temp file
        rm "$temp_file"
    fi
done

# Count files that were actually modified
final_count=$(find "$TARGET_DIR" -maxdepth 1 -type f -exec grep -l "desugarer_blame([0-9]\+)" {} \; 2>/dev/null | wc -l)

echo
echo "Script completed!"
echo "Files with renumbered desugarer_blame patterns: $final_count"