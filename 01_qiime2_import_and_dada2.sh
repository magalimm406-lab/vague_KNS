#!/usr/bin/env bash

########################
# 0. Activation QIIME2
########################

# On active l'environnement conda qui contient QIIME2.
source /home/vanton/miniconda3/etc/profile.d/conda.sh
conda activate qiime2-amplicon-2026.1

############################
# 1. Définition des chemins
############################

# Dossier racine du projet 
PROJECT_DIR="/home/vanton/magali/vague_magali"

# Dossier contenant les fastq nettoyés (outputs de Trimmomatic)
CLEAN_DIR="${PROJECT_DIR}/03_cleaned_data"

# Dossier où l’on va mettre les fichiers de base de QIIME2 (manifest, metadata)
DB_DIR="${PROJECT_DIR}/98_databasefiles"
MANIFEST_DIR="${DB_DIR}/manifest"
METADATA_DIR="${DB_DIR}/metadata"

# Dossier où l’on va mettre les résultats QIIME2 (artifacts *.qza et visualisations *.qzv)
QIIME_OUT_DIR="${PROJECT_DIR}/99_qiime2_results"

# Création des dossiers si besoin
mkdir -p "${MANIFEST_DIR}"
mkdir -p "${METADATA_DIR}"
mkdir -p "${QIIME_OUT_DIR}"

###############################
# 2. Construction des manifests
###############################
# QIIME2 a besoin de "manifest" pour savoir :
#   - quel est le sample-id
#   - où se trouvent les fichiers R1 et R2
#   - si c’est forward ou reverse
#
# Format PairedEndFastqManifestPhred33V2 (CSV avec en-tête obligatoire) :
#   sample-id,absolute-filepath,direction
#   SAMPLE1,/chemin/complet/SAMPLE1_R1.fastq.gz,forward
#   SAMPLE1,/chemin/complet/SAMPLE1_R2.fastq.gz,reverse
#
# Ici, on va :
#   - créer un manifest pour TOUTS les samples (sauf témoins négatifs "Tneg")
#   - créer un manifest séparé pour les témoins négatifs (pattern "*Tneg*")

# Fichiers manifest
MANIFEST_MAIN="${MANIFEST_DIR}/manifest_paired_main.csv"
MANIFEST_TNEG="${MANIFEST_DIR}/manifest_paired_Tneg.csv"

# On initialise les deux manifest avec l’en-tête QIIME2
echo "sample-id,absolute-filepath,direction" > "${MANIFEST_MAIN}"
echo "sample-id,absolute-filepath,direction" > "${MANIFEST_TNEG}"

# Boucle sur les fichiers R1 "paired"
# les fichiers ont le pattern *_R1_001.paired.fastq.gz et idem pour R2.
for R1 in "${CLEAN_DIR}"/*_R1_001.paired.fastq.gz; do
    # On récupère le nom de base (sans chemin)
    BASENAME_R1=$(basename "${R1}")

    # On dérive le chemin R2 correspondant en remplaçant R1 par R2
    R2="${CLEAN_DIR}/${BASENAME_R1/_R1_001.paired.fastq.gz/_R2_001.paired.fastq.gz}"

    # Sécurité : si le R2 n’existe pas, on saute cette sample
    if [[ ! -f "${R2}" ]]; then
        echo "ATTENTION: R2 manquant pour ${BASENAME_R1}, on ignore cette sample."
        continue
    fi

    # On définit un sample-id en supprimant la partie suffixe (_R1_001.paired.fastq.gz)
    SAMPLE_ID="${BASENAME_R1%_R1_001.paired.fastq.gz}"

    # Pour simplifier : sample-id = nom de fichier sans suffixe.
    # Si tu veux un sample-id plus court (ex: CS25-IC1_S149), il faudra adapter
    # en jouant avec des découpes (cut, sed, etc.).

    # On teste si c’est un témoin négatif via le pattern "Tneg" dans le nom
    if [[ "${SAMPLE_ID}" == *"Tneg"* ]]; then
        # Écriture dans le manifest Tneg
        echo "${SAMPLE_ID},${R1},forward" >> "${MANIFEST_TNEG}"
        echo "${SAMPLE_ID},${R2},reverse" >> "${MANIFEST_TNEG}"
    else
        # Écriture dans le manifest principal
        echo "${SAMPLE_ID},${R1},forward" >> "${MANIFEST_MAIN}"
        echo "${SAMPLE_ID},${R2},reverse" >> "${MANIFEST_MAIN}"
    fi
done

###################################
# 3. Création d’un fichier metadata
###################################
# QIIME2 a besoin d’un "metadata" (tableau tabulé ou CSV) pour l’annotation
# des samples (ex : type d’échantillon, site, condition, etc.).
# Ici on va créer un squelette minimal que Magali devra compléter.
#
# Format classique TSV (tabulé) :
#   sample-id\tcolumn1\tcolumn2
#   SAMPLE1\tval1\tval2
#
# On crée un metadata pour les samples "main" (sans les témoins négatifs).
# On pourrait en faire un autre pour les Tneg si on veut les analyser à part.

METADATA_MAIN="${METADATA_DIR}/metadata_main.tsv"

# En-tête : sample-id + colonnes example
{
    echo -e "sample-id\tgroup\tcomment"
} > "${METADATA_MAIN}"

# On remplit la colonne sample-id à partir du manifest principal
# On ignore la première ligne (en-tête) et on ne prend que la colonne "sample-id".
tail -n +2 "${MANIFEST_MAIN}" | cut -d',' -f1 | sort | uniq | while read -r SID; do
    # group et comment sont juste des placeholders à éditer manuellement
    echo -e "${SID}\tTODO_group\tTODO_comment"
done >> "${METADATA_MAIN}"

echo "Metadata principal créé : ${METADATA_MAIN}"
echo "IMPORTANT : Magali doit éditer ce fichier (group, comment, etc.)."

###################################
# 4. Import des données dans QIIME2
###################################
# On va importer les données en tant que :
#   --type 'SampleData[PairedEndSequencesWithQuality]'
#   --input-format PairedEndFastqManifestPhred33V2 [web:35][web:39]
#
# On fait deux imports :
#   1) pour les samples "main"
#   2) pour les témoins négatifs "Tneg"

# Artifacts de sortie (demultiplexed sequences)
DEMUX_MAIN_QZA="${QIIME_OUT_DIR}/demux_paired_main.qza"
DEMUX_TNEG_QZA="${QIIME_OUT_DIR}/demux_paired_Tneg.qza"

# Import principal
qiime tools import \
  --type 'SampleData[PairedEndSequencesWithQuality]' \
  --input-path "${MANIFEST_MAIN}" \
  --output-path "${DEMUX_MAIN_QZA}" \
  --input-format PairedEndFastqManifestPhred33

# Import témoins négatifs
qiime tools import \
  --type 'SampleData[PairedEndSequencesWithQuality]' \
  --input-path "${MANIFEST_TNEG}" \
  --output-path "${DEMUX_TNEG_QZA}" \
  --input-format PairedEndFastqManifestPhred33

##nano metadata_main.tsv
#modifier les TODO_group et les TODO_comment 
#Dans nano :
#Ctrl + O → Entrée (sauvegarder)
#Ctrl + X → quitter

#####################################################
# 5. Résumé du demultiplexage (qiime demux summarize)
#####################################################
# Cette étape permet d’obtenir des visualisations (fichiers .qzv)
# pour inspecter la distribution des tailles, des qualités, etc.

DEMUX_MAIN_QZV="${QIIME_OUT_DIR}/demux_paired_main.qzv"
DEMUX_TNEG_QZV="${QIIME_OUT_DIR}/demux_paired_Tneg.qzv"

qiime demux summarize \
  --i-data "${DEMUX_MAIN_QZA}" \
  --o-visualization "${DEMUX_MAIN_QZV}"

qiime demux summarize \
  --i-data "${DEMUX_TNEG_QZA}" \
  --o-visualization "${DEMUX_TNEG_QZV}"

############################
# 6. DADA2 denoise-paired
############################
# On applique DADA2 sur les reads paired-end :
#   - denoise-paired : débruitage, fusion des R1/R2, détection/filtre de chimères [web:37][web:40]
#   - on doit choisir des paramètres de trimming/truncation adaptés
#     (à ajuster après avoir regardé les courbes de qualité dans demux.qzv).
#
# Ici je mets des valeurs "placeholder" :
#   --p-trim-left-f 0
#   --p-trim-left-r 0
#   --p-trunc-len-f 0
#   --p-trunc-len-r 0
# "0" = pas de truncation (déconseillé en pratique, à adapter !)
#
# Magali, tu devras donc :
#   - ouvrir les demux_paired_main.qzv dans QIIME2 View
#   - choisir des positions de cut raisonnables pour forward/reverse
#   - modifier les paramètres ci-dessous dans SON script.

# Fichiers de sortie pour les données principales
TABLE_MAIN_QZA="${QIIME_OUT_DIR}/table_main.qza"
REP_SEQS_MAIN_QZA="${QIIME_OUT_DIR}/rep_seqs_main.qza"
STATS_MAIN_QZA="${QIIME_OUT_DIR}/dada2_stats_main.qza"
BASETRANS_MAIN_QZA="${QIIME_OUT_DIR}/dada2_basetrans_main.qza"   

qiime dada2 denoise-paired \
  --i-demultiplexed-seqs "${DEMUX_MAIN_QZA}" \
  --p-trim-left-f 0 \
  --p-trim-left-r 0 \
  --p-trunc-len-f 290 \
  --p-trunc-len-r 280 \
  --p-n-threads 0 \
  --o-table "${TABLE_MAIN_QZA}" \
  --o-representative-sequences "${REP_SEQS_MAIN_QZA}" \
  --o-denoising-stats "${STATS_MAIN_QZA}" \
  --o-base-transition-stats "${BASETRANS_MAIN_QZA}"

# Fichiers de sortie pour les témoins négatifs
TABLE_TNEG_QZA="${QIIME_OUT_DIR}/table_Tneg.qza"
REP_SEQS_TNEG_QZA="${QIIME_OUT_DIR}/rep_seqs_Tneg.qza"
STATS_TNEG_QZA="${QIIME_OUT_DIR}/dada2_stats_Tneg.qza"
BASETRANS_TNEG_QZA="${QIIME_OUT_DIR}/dada2_basetrans_Tneg.qza" 

qiime dada2 denoise-paired \
  --i-demultiplexed-seqs "${DEMUX_TNEG_QZA}" \
  --p-trim-left-f 0 \
  --p-trim-left-r 0 \
  --p-trunc-len-f 290 \
  --p-trunc-len-r 280 \
  --p-n-threads 0 \
  --o-table "${TABLE_TNEG_QZA}" \
  --o-representative-sequences "${REP_SEQS_TNEG_QZA}" \
  --o-denoising-stats "${STATS_TNEG_QZA}" \
  --o-base-transition-stats "${BASETRANS_TNEG_QZA}"

#####################################
# 7. Visualisations des outputs DADA2
#####################################
# On génère les .qzv associés à la table, aux séquences représentatives
# et aux stats de denoising pour pouvoir les explorer dans QIIME2 View.

# Fichiers pour le résumé de la table principale
FEATURE_FREQ_MAIN_QZA="${QIIME_OUT_DIR}/feature_freq_main.qza"
SAMPLE_FREQ_MAIN_QZA="${QIIME_OUT_DIR}/sample_freq_main.qza"
TABLE_MAIN_QZV="${QIIME_OUT_DIR}/table_main.qzv"

qiime feature-table summarize \
  --i-table "${TABLE_MAIN_QZA}" \
  --m-metadata-file "${METADATA_MAIN}" \
  --o-feature-frequencies "${FEATURE_FREQ_MAIN_QZA}" \
  --o-sample-frequencies "${SAMPLE_FREQ_MAIN_QZA}" \
  --o-summary "${TABLE_MAIN_QZV}"

# Fichiers pour le résumé de la table Tneg
FEATURE_FREQ_TNEG_QZA="${QIIME_OUT_DIR}/feature_freq_Tneg.qza"
SAMPLE_FREQ_TNEG_QZA="${QIIME_OUT_DIR}/sample_freq_Tneg.qza"
TABLE_TNEG_QZV="${QIIME_OUT_DIR}/table_Tneg.qzv"

qiime feature-table summarize \
  --i-table "${TABLE_TNEG_QZA}" \
  --m-metadata-file "${METADATA_MAIN}" \
  --o-feature-frequencies "${FEATURE_FREQ_TNEG_QZA}" \
  --o-sample-frequencies "${SAMPLE_FREQ_TNEG_QZA}" \
  --o-summary "${TABLE_TNEG_QZV}"


TABLE_MAIN_QZV="${QIIME_OUT_DIR}/table_main.qzv"
REP_SEQS_MAIN_QZV="${QIIME_OUT_DIR}/rep_seqs_main.qzv"
STATS_MAIN_QZV="${QIIME_OUT_DIR}/dada2_stats_main.qzv"
REP_SEQS_TNEG_QZV="${QIIME_OUT_DIR}/rep_seqs_Tneg.qzv"

qiime feature-table summarize \
  --i-table "${TABLE_MAIN_QZA}" \
  --o-visualization "${TABLE_MAIN_QZV}" \
  --m-sample-metadata-file "${METADATA_MAIN}"

qiime feature-table tabulate-seqs \
  --i-data "${REP_SEQS_MAIN_QZA}" \
  --o-visualization "${REP_SEQS_MAIN_QZV}"

qiime feature-table tabulate-seqs \
  --i-data "${REP_SEQS_TNEG_QZA}" \
  --o-visualization "${REP_SEQS_TNEG_QZV}"

qiime metadata tabulate \
  --m-input-file "${STATS_MAIN_QZA}" \
  --o-visualization "${STATS_MAIN_QZV}"

########################################
# 8. Retrait des ASV des témoins
########################################
#On enlève dans la table principale "main" les ASV des Tneg
#
# On utilise directement :
# - la table Tneg pour filtrer les séquences (.qza)
# - les rep_seqs_Tneg comme liste d'IDs d'ASV (.qza)

TABLE_MAIN_NOTNEG_QZA="${QIIME_OUT_DIR}/table_main_noTneg.qza"
REP_SEQS_MAIN_NOTNEG_QZA="${QIIME_OUT_DIR}/rep_seqs_main_noTneg.qza"

qiime feature-table filter-seqs \
--i-data "${REP_SEQS_MAIN_QZA}" \
--i-table "${TABLE_TNEG_QZA}" \
--p-exclude-ids \
--o-filtered-data "${REP_SEQS_MAIN_NOTNEG_QZA}"

qiime feature-table filter-features \
--i-table "${TABLE_MAIN_QZA}" \
--m-metadata-file "${REP_SEQS_TNEG_QZA}" \
--p-exclude-ids \
--o-filtered-table "${TABLE_MAIN_NOTNEG_QZA}"

########################################
# 9. Visualisation du main sans Tneg
########################################

TABLE_MAIN_NOTNEG_QZV="${QIIME_OUT_DIR}/table_main_noTneg.qzv"
REP_SEQS_MAIN_NOTNEG_QZV="${QIIME_OUT_DIR}/rep_seqs_main_noTneg.qzv"

qiime feature-table summarize \
--i-table "${TABLE_MAIN_NOTNEG_QZA}" \
--o-visualization "${TABLE_MAIN_NOTNEG_QZV}" \
--m-sample-metadata-file "${METADATA_MAIN}"

qiime feature-table tabulate-seqs \
--i-data "${REP_SEQS_MAIN_NOTNEG_QZA}" \
--o-visualization "${REP_SEQS_MAIN_NOTNEG_QZV}"


echo "Pipeline QIIME2 terminé."
echo "Résultats dans : ${QIIME_OUT_DIR}"
echo "Manifest dans : ${MANIFEST_DIR}"
echo "Metadata dans : ${METADATA_DIR}"
