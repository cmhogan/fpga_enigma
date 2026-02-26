#!/bin/bash
# Copyright (c) 2026, Chad Hogan
# All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.
# coverage_summary.sh — Generate coverage summary from VCD files
# Analyzes VCD files in build/ directory to report which RTL modules were
# exercised and provide basic signal toggle coverage metrics.

set -e

BUILD_DIR="build"
VCD_FILES=("$BUILD_DIR"/*.vcd)

# Check if any VCD files exist
if [ ! -e "${VCD_FILES[0]}" ]; then
    echo "ERROR: No VCD files found in $BUILD_DIR/"
    echo "Run 'make coverage' first to generate VCD files."
    exit 1
fi

echo "=== Coverage Summary ==="
echo ""

# Summary counters
total_testbenches=0
total_modules_seen=0
declare -A all_modules_map

# Process each VCD file
for vcd_file in "${VCD_FILES[@]}"; do
    if [ ! -f "$vcd_file" ]; then
        continue
    fi

    testbench_name=$(basename "$vcd_file" .vcd)
    total_testbenches=$((total_testbenches + 1))

    echo "--- $testbench_name ---"

    # Extract module hierarchy from VCD $scope lines
    # VCD format: $scope module <name> $end
    # We want to find all RTL module instances (not testbench itself)

    # Count signals (look for $var lines before first timestamp)
    signal_count=$(awk '
        /^\$var/ { count++ }
        /^#[0-9]/ { exit }
        END { print count }
    ' "$vcd_file")

    # Extract unique module scopes (hierarchical paths)
    # Skip the top-level testbench module and focus on DUT hierarchy
    modules=$(awk '
        BEGIN { indent=0; path=""; }
        /^\$scope module/ {
            name = $3;
            if (indent > 0) {
                if (path == "") path = name;
                else path = path "." name;
            }
            indent++;
            if (indent > 1) print path;
        }
        /^\$upscope/ {
            indent--;
            # Remove last component from path
            n = split(path, parts, ".");
            path = "";
            for (i = 1; i < n; i++) {
                if (path == "") path = parts[i];
                else path = path "." parts[i];
            }
        }
        /^#[0-9]/ { exit }
    ' "$vcd_file" | sort -u)

    if [ -z "$modules" ]; then
        echo "  Modules exercised: (none detected - check VCD format)"
    else
        echo "  Modules exercised:"
        module_count=0
        while IFS= read -r module; do
            echo "    - $module"
            all_modules_map["$module"]=1
            module_count=$((module_count + 1))
        done <<< "$modules"
        total_modules_seen=$((total_modules_seen + module_count))
    fi

    echo "  Signal count: $signal_count"

    # For toggle coverage, we'd need to parse all signal changes throughout
    # the VCD, which is expensive for large files. Instead, provide a simpler
    # metric: percentage of signals that had at least one transition.
    # This requires scanning the entire VCD, so we'll do a lightweight check.

    # Count unique signal identifiers that appear in value change lines
    # VCD value changes are in format: b<value> <id> or 0<id> or 1<id>
    toggled_signals=$(awk '
        /^\$var/ {
            # VCD format: $var <type> <size> <id> <name> [bits] $end
            # Identifier is field 4
            id = $4;
            all_sigs[id] = 1;
        }
        /^#[0-9]/ { in_data = 1; next; }
        in_data {
            # Value change line
            if ($0 ~ /^[01]/) {
                # Single bit: format is "0<id>" or "1<id>"
                # The id is everything after the first character
                id = substr($0, 2);
                if (id != "" && id in all_sigs) {
                    toggled[id] = 1;
                }
            } else if ($0 ~ /^b/) {
                # Multi-bit: format is "b<value> <id>"
                id = $2;
                if (id != "" && id in all_sigs) {
                    toggled[id] = 1;
                }
            }
        }
        END {
            total = 0;
            toggle_count = 0;
            for (sig in all_sigs) {
                total++;
                if (sig in toggled) toggle_count++;
            }
            if (total > 0) {
                pct = int(toggle_count * 100 / total);
                print toggle_count "/" total " (" pct "%)";
            } else {
                print "0/0 (N/A)";
            }
        }
    ' "$vcd_file")

    echo "  Signals toggled: $toggled_signals"
    echo ""
done

# Summary
echo "==================================="
echo "Total testbenches analyzed: $total_testbenches"
echo "Unique modules exercised: ${#all_modules_map[@]}"
if [ ${#all_modules_map[@]} -gt 0 ]; then
    echo ""
    echo "All modules seen across testbenches:"
    for module in "${!all_modules_map[@]}"; do
        echo "  - $module"
    done | sort
fi
echo "==================================="
