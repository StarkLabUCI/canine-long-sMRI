#!/bin/bash
# Setup slurm options
#SBATCH --partition=standard
#SBATCH --job-name=K9proc
#SBATCH -c 2
#SBATCH -o /mnt/hippocampus/starkdata1/head_dog/slurmlog/K9proc_%j.out

# Jessica Noche
# September 27, 2022

# DESCRIPTION: 
# main script for processing a single subject's structural derivatives from the ANTs longitudinal pipeline up to the most recent timepoint
# for ROI statistics for a single subject

# USAGE: proc_singlesub.sh <subj> <sess> <antspath> e.g. sub-2001374 ses-T0 /mnt/hippocampus/starkdata1/head_dog/BIDS/derivatives/ANTS/longCT

umask 002

echo Job ID: $SLURM_JOB_ID
echo Job name: $SLURM_JOB_NAME
echo Submit host: $SLURM_SUBMIT_HOST
echo "Node(s) used": $SLURM_JOB_NODELIST
echo Started at: `date`

echo Using $SLURM_CPUS_PER_TASK slots
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

if [[ ! -v SLURM_CPUS_PER_TASK ]]; then
  echo Defaulting to 8 CPU threads 
  SLURM_CPUS_PER_TASK=8
fi

# Strip off any sub-
subj=`echo $1 | sed s/sub-//`
# session
sess=`echo $2 | sed s/ses-//` # Strip off ses-
sess=`echo $sess | sed s/T//` # Strip off T from sessnum

# output path
outpath=$3
if ((`echo ${#outpath}` < 1)); then
echo invalid outpath - exiting
exit
else echo outpath is $outpath
fi

outsubj_path=$outpath/sub-${subj}
if [ ! -e $outsubj_path ]; then
  mkdir -p $outsubj_path
fi

# Data locations
top_path=/mnt/hippocampus/starkdata1/head_dog
bids_path=$top_path/BIDS
code_path=$bids_path/code
bidssubj_path=$bids_path/sub-${subj}
template_path=$top_path/UCIAtlas

if [ ! -e $outsubj_path/sub-${subj}_ses-T${sess}_T1w_RIP_*/*BrainExtractionBrain.nii.gz ]; then
  echo $outsubj_path/sub-${subj}_ses-T${sess}_T1w_RIP_*/*BrainExtractionBrain.nii.gz not found
  echo ERROR: ANTs Longitudinal Cortical Thickness pipeline needs to be run $code_path/antsLongCT.sh sub-${subj} ses-T${sess} -- exiting
    exit
  else echo Running on subj=$subj sess=ses-T${sess}
  echo ANTs Longitudinal Cortical Thickness outputs exist in $outsubj_path
fi

# 1. Warp atlases on SST and time points
echo 1. ROI stats on SST and Timepoint T${sess}
# Johnson gyrus atlas
$code_path/ROI_stats.sh $subj $sess $outpath $top_path/Johnson_Atlas/Johnson2UCI/Johnson_space/RIP_whole_atlas_cortical_subcortical_gyri_updated.nii.gz JohnsonGyrusAtlas
# Johnson full atlas
$code_path/ROI_stats.sh $subj $sess $outpath $top_path/Johnson_Atlas/Johnson2UCI/Johnson_space/whole_atlas_cortical_subcortical_reoriented_to_poptemplate_LIPtoUCIRSP_0x3mm.nii.gz JohnsonAtlasCorticalSubcorticalLabels

# 2. whole-brain deformation analysis: create CLEAN logJacobian map
echo 2. Create logJacobian of cleaned up timepoint-to-SST warps and SST to-group-template warps
$code_path/make_clean_logJacobian.sh $subj $sess $outpath 

# 3. Make affine for calculating proxy for "ICV"
$code_path/ICV_determinant.sh $subj $sess $outpath

echo +++ DONE processing $subj in proc_singlesub.sh at `date` +++

