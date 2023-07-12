# Read Counting alternative to readCounter

It takes a D4 and genome files as input and computes read counts per 1Mb bin.

## Usage

To use the script, you need to pass in command-line arguments:

```bash
bash d4_readcounts_genome.sh -d4 <D4 file> -g <genome file> [-p <number of CPUs>] [-o <output directory>]
