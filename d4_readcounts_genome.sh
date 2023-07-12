#!/usr/bin/env bash

# Exit script on first error
set -e

# Default parameters
CPU=4
OUT_DIR=$(pwd)

# Array of required executables
required_executables=("d4tools" "bedtools" "parallel")

# Function to display usage
usage() {
    cat << EOF
Usage: $0 -d D4_FILE -g GENOME [-p CPU] [-o OUT_DIR]

This script takes a D4 and genome files and outputs read counts per 1Mb bin. The fourth column of the resulting file can be used for ichorCNA.

Options:
  -d D4_FILE      Path to the D4 file (mandatory)
  -g GENOME       Path to the genome fai file (mandatory)
  -p CPU          Number of CPUs to be used (optional, default is 4)
  -o OUT_DIR      Output directory (optional, default is current directory)
EOF
}

# Function to check if an executable is available
check_executable() {
  local executable=$1
  if ! command -v "$executable" &> /dev/null; then
    echo "Error: $executable is not installed. Please install $executable and try again."
    exit 1
  fi
}

# Function to check if a file exists
check_file_exists() {
  local file=$1
  if [ ! -f "$file" ]; then
    echo "Error: $file does not exist. Please provide a valid file and try again."
    exit 1
  fi
}

# Check if required executables are available
for executable in "${required_executables[@]}"; do
    check_executable "$executable"
done

# Parse command line options
while getopts "d:g:p:o:" opt; do
    case ${opt} in
        d)
            D4_FILE=${OPTARG}
            ;;
        g)
            GENOME=${OPTARG}
            ;;
        p)
            CPU=${OPTARG}
            ;;
        o)
            OUT_DIR=${OPTARG}
            ;;
        \?)
            usage
            exit 1
            ;;
    esac
done

# Check if mandatory options were provided
if [ -z "${D4_FILE}" ] || [ -z "${GENOME}" ]; then
    usage
    exit 1
fi

# Check if the D4 and genome files exist
check_file_exists "$D4_FILE"
check_file_exists "$GENOME"

# Create output directory if it doesn't exist
mkdir -p ${OUT_DIR}

# Create required file if it doesn't exist
file1Mb="${OUT_DIR}/1Mb.autosomes.bed"
if [ ! -f ${file1Mb} ]; then
    bedtools makewindows -g ${GENOME} -w 1000000 \
    | grep -w '^#\|chr[1-9]\|chr[1-2][0-9]' \
    | sort --parallel=${CPU} -k 1,1 -k2,2n -u -V  > ${file1Mb}
fi

# Extract the file name without extension
filename=$(basename -- "${D4_FILE}")
filename="${filename%.*}"

# Create output file name
outputFile="${OUT_DIR}/${filename}.1Mb.wig"

# Get list of unique chromosomes sorted
chromosomes=$(cut -f1 ${file1Mb} | sort --parallel=${CPU} -u -V)

# Create a temporary directory
tmp_dir=$(mktemp -d -p ${OUT_DIR})

# Define cleanup procedure
cleanup() {
    rm -rf "${tmp_dir}"
}

# Trap the cleanup function to be executed on exit
trap cleanup EXIT

# Use GNU parallel to perform the operation on each chromosome
echo "${chromosomes}" | \
    parallel -j ${CPU} --no-notice "d4tools view -A ${D4_FILE} {} | \
    awk 'NF == 4' |\
    sort --parallel=${CPU} -k 1,1 -k2,2n -u -V | \
    bedtools map -a <(cat ${file1Mb} | grep {}) -b - -c 4 -o sum > \
    ${tmp_dir}/_tmp.${filename}.1Mb.{}.wig"

# Check if outputFile exists, if yes, rename it to .old
if [ -f ${outputFile} ]; then
    mv ${outputFile} ${outputFile}.old
fi

# Concatenate all tmp files into one in the same order as ${chromosomes}
for chrom in ${chromosomes}
do
    cat "${tmp_dir}/_tmp.${filename}.1Mb.${chrom}.wig" >> ${outputFile}
done

# Clean the temporary directory
cleanup
