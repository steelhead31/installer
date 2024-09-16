# ********************************************************************************
# Copyright (c) 2024 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made
# available under the terms of the Apache Software License 2.0
# which is available at https://www.apache.org/licenses/LICENSE-2.0.
#
# SPDX-License-Identifier: Apache-2.0
# ********************************************************************************

# This is the main driving script to generate linux packages

set -e

## Define constants
valid_versions=("8" "11" "17" "21" "22" "23")
valid_dists=("alpine" "debian" "rhel" "suse")
valid_types=("jdk" "jre")
valid_archs=("aarch64" "x86_64" "s390x" "ppc64le" "riscv")

[ $# -lt 4 ] && echo "Usage: $0 DISTRIBUTION PACKAGE_TYPE VERSION ARCH" && exit 1
DIST_PARAM=$1
TYPE_PARAM=$2
VERS_PARAM=$3
ARCH_PARAM=$4

# Function to convert input to lowercase
to_lowercase() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Function to parse version number 
parse_version_number() {
    local release_number=$1  # First argument: release number

    # Use IFS to split the release number based on '.' and '+'
    IFS='.' read -r MAJOR_VERSION MINOR_VERSION rest <<< "$release_number"
    IFS='+' read -r PATCH_VERSION BUILD_VERSION <<< "$rest"
}

# function to validate input parameters 

validate_params() {
    # Input parameters from command line
    input_dist=$(to_lowercase "$DIST_PARAM")
    input_version="$VERS_PARAM"
    input_package_type=$(to_lowercase "$TYPE_PARAM")
    input_arch=$(to_lowercase "$ARCH_PARAM")

    # Check if input OS is valid
    if [[ ! " ${valid_dists[@]} " =~ " ${input_dist} " ]]; then
        echo "Invalid Distribution: $input_dist"
        exit 1
    fi

    # Parse Version Number
    parse_version_number "$input_version"

    # Check if input version is valid
    if [[ ! " ${valid_versions[@]} " =~ " ${MAJOR_VERSION} " ]]; then
        echo "Invalid version: $input_version"
        exit 1
    fi

    # Check if input package type is valid
    if [[ ! " ${valid_types[@]} " =~ " ${input_package_type} " ]]; then
        echo "Invalid package type: $input_package_type"
        exit 1
    fi

    # Check if input architecture is valid
    if [[ ! " ${valid_archs[@]} " =~ " ${input_arch} " ]]; then
        echo "Invalid Architecture : $input_arch"
        exit 1
    fi

    # Distribution Specific Validation Rules Go Here
    # Maybe breakout into seperate function ?
    # ------------------------------------------------------------------------
    
    # Alpine Only Allows x86_64 and aarch64 for versions > 21
    if [ "$input_dist" = "alpine" ] && [ "$MAJOR_VERSION" -ge 21 ]; then
      ## Allowed x64 & aarch64
      if [ "$input_arch" != "x86_64" ] && [ "$input_arch" != "aarch64" ]; then 
        echo "Error - Unsupported Arch For Alpine >= 21 Detected"
        exit 99;
      fi
    fi
    
    if [ "$input_dist" = "alpine" ] && [ "$MAJOR_VERSION" -lt 21 ]; then
      ## Only allowed x64
      if [ "$input_arch" != "x86_64" ]; then 
        echo "Error - Unsupported Arch For Alpine < 21 Detected"
        exit 99;
      fi
    fi

    # ------------------------------------------------------------------------

    # Store the converted values in global variables
    GLOBAL_DIST="$input_dist"
    GLOBAL_VERSION="$input_version"
    GLOBAL_PACKAGE_TYPE="$input_package_type"
    GLOBAL_ARCH="$input_arch"
}
# general function to update a template spec file

update_template() {
    local source_type="$1"
    local package_type="$2"
    local major_version_to_replace="$3"
    local release_version="$4"
    local release_arch="$5"
    local source_file="./templates/$source_type.$package_type.template"
    local destination_file="./build_prep/$source_type.$package_type.output"

    if [ -d "./build_prep" ]; then
      echo "Warning - Output Directory Exists. Removing It..."
      rm -rf "./build_prep"
    fi

    mkdir "./build_prep"
    
    # llllllllll echo "Source File = $source_file"
    # llllllllll echo "Target Vers = $major_version_to_replace"
    # llllllllll echo "Target File = $destination_file"
    # llllllllll echo "Release Version = $release_version"
   
    if [[ ! -f "$source_file" ]]; then
        echo "ERROR - Template File for this distribution does not exist."
        return 1
    fi

    # Copy the file and replace "zzzzzzzzzz" with the relevant version in the new copy
    # Also replace "yyyyyyyyy" with the full release version
    sed -e "s/zzzzzzzzzz/$major_version_to_replace/g" \
        -e "s/yyyyyyyyyy/$release_version/g" \
        -e "s/xxxxxxxxxx/$release_arch/g" \
        "$source_file" > "$destination_file"

    if [[ $? -eq 0 ]]; then
        echo "Template file copied and strings replaced successfully."
    else
        echo "An error occurred during the copy and replace process."
    fi
}

generate_spec_file() {
    update_template "$GLOBAL_DIST" "$GLOBAL_PACKAGE_TYPE" "$MAJOR_VERSION" "$GLOBAL_VERSION" "$GLOBAL_ARCH"
}

cleanup_files() {
    if [ -d "./build_prep" ]; then
      echo "Warning - Output Directory Exists. Removing It..."
      rm -rf "./build_prep"
    fi
}

## Main Program Starts Here

# Validate Input Parameters
validate_params
# Generate Spec File For The Selected Distribution
generate_spec_file
# Housekeep
#cleanup_files

## Debugging Outputs
echo "Debugging.........."
echo "-------------------------------------------------"
echo "Dist_Param : $DIST_PARAM"
echo "Type Param : $TYPE_PARAM"
echo "Vers Param : $VERS_PARAM"
echo "Major: $MAJOR_VERSION"
echo "Minor: $MINOR_VERSION"
echo "Patch: $PATCH_VERSION"
echo "Build: $BUILD_VERSION"

# If all checks passed
echo "All inputs are valid: OS=$GLOBAL_DIST, Version=$GLOBAL_VERSION, Package Type=$GLOBAL_PACKAGE_TYPE, Arch = $GLOBAL_ARCH"
