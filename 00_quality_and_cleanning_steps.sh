#!/usr/bin/env bash

RAW_DIR=/home/vanton/magali/vague_magali/01_raw_data_KNS/

cd /home/vanton/magali/vague_magali

mkdir –p 02_raw_data_quality
RAW_QC_DIR=/home/vanton/magali/vague_magali/02_raw_data_quality/

mkdir –p 03_cleaned_data
CLEAN_DIR=/home/vanton/magali/vague_magali/03_cleaned_data/

mkdir –p 04_cleaned_data_quality

ADAPTERFILE=/home/vanton/magali/vague_magali/smallRNA_adapters.fa

THREADS=8

ml load Py10/Bio_info_env/3.10 #ou conda activate bioinfo

################################## 1. QC des données brutes

mkdir -p "$RAW_QC_DIR"

fastqc -t "$THREADS" \
   -o "$RAW_QC_DIR" \
   "$RAW_DIR"/*fastq.gz

multiqc "$RAW_QC_DIR" -o "$RAW_QC_DIR"

################################## 2. Trimmomatic

mkdir -p "$CLEAN_DIR"
for R1 in "$RAW_DIR"/*_R1_001.fastq.gz; do
    SAMPLE=$(basename "$R1" _R1_001.fastq.gz)
    R2="$RAW_DIR/${SAMPLE}_R2_001.fastq.gz"
    trimmomatic PE -threads "$THREADS" -phred33 \
        "$R1" \
        "$R2" \
        "$CLEAN_DIR/${SAMPLE}_R1_001.paired.fastq.gz" \
        "$CLEAN_DIR/${SAMPLE}_R1_001.unpaired.fastq.gz" \
        "$CLEAN_DIR/${SAMPLE}_R2_001.paired.fastq.gz" \
        "$CLEAN_DIR/${SAMPLE}_R2_001.unpaired.fastq.gz" \
        ILLUMINACLIP:"$ADAPTERFILE":2:30:10 \
        LEADING:5 TRAILING:5 SLIDINGWINDOW:4:20 MINLEN:36 AVGQUAL:20
done


################################## 3. QC des données nettoyées

CLEAN_DIR=/home/vanton/magali/vague_magali/03_cleaned_data
CLEAN_QC_DIR=/home/vanton/magali/vague_magali/04_cleaned_data_quality

mkdir -p "$CLEAN_QC_DIR"

fastqc -t "$THREADS" \
   -o "$CLEAN_QC_DIR" \
   "$CLEAN_DIR"/*fastq.gz

multiqc "$CLEAN_QC_DIR" -o "$CLEAN_QC_DIR"

########### 
cd /home/vanton/magali/vague_magali/04_cleaned_data_quality
mkdir -p unpaired #il faut commencer par les unpaired
mv *.unpaired* unpaired/
cd unpaired
conda activate bioinfo 
multiqc .

cd ..
mkdir -p paired
mv *.paired* paired/
cd paired
multiqc .
