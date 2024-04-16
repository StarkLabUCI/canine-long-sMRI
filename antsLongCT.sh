#!/bin/bash
# Setup slurm options
#SBATCH --partition=standard
#SBATCH --job-name=ALCT
#SBATCH -c 8
#SBATCH -o /mnt/hippocampus/starkdata1/head_dog/slurmlog/antsLongCT_%j.out

# USAGE: ./antsLongCT.sh <sub-ID> <testdirname> 

# testdirname is optional for debugging

# Description:
# runs the revised ANTs longitudinal thickness pipeline (antsCorticalThickness_k9.sh) up to the most recent session number in BIDS
# This runs antsBrainExtraction_k9.sh 
# Running T4 on the original pipeline

# Notes:
# antsBrainExraction_k9.sh upsamples the extraction template and N4-corrected images to 0.3mm
# ^ Spaces between brackets for ANTS_LINEAR_CONVERGENCE="[ 1000x500x250x100,1e-8,10 ]" matter otherwise it will result in [ 0 1 2 ]

umask 002

echo Job ID: $SLURM_JOB_ID
echo Job name: $SLURM_JOB_NAME
echo Submit host: $SLURM_SUBMIT_HOST
echo "Node(s) used": $SLURM_JOB_NODELIST
echo Started at: `date`

echo Using $SLURM_CPUS_PER_TASK slots
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

if [[ ! -v SLURM_CPUS_PER_TASK ]]; then  # Likely running locally - use more
  echo Defaulting to 8 CPU threads 
  SLURM_CPUS_PER_TASK=8
fi

# subject ID
subj=`echo $1 | sed s/sub-//` # Strip off any sub-

# Data locations
top_path=/mnt/hippocampus/starkdata1/head_dog
bids_path=$top_path/BIDS
bidssubj_path=$bids_path/sub-${subj}
code_path=$bids_path/code

### OPTIONAL TEST/DEBUGGING DIR NAME
test_dirname=$2

outsubj_path=$bids_path/derivatives/ANTS/longCT/$test_dirname/sub-${subj}
if [ ! -e $outsubj_path ]; then
  mkdir -p $outsubj_path
else
echo $outsubj_path exists! Careful not to overwrite existing datasets -- Exiting
exit
fi

# most recent session number
timepoints=($bidssubj_path/ses-T*)
recent=${timepoints[-1]}
sess=`echo "${recent: -1}"` # exclude the ses-T part of the session num

echo Running on subj=$subj up to ses-T${sess}

# container locations
SAFNI="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code_path/containers/afni_012821.sif"
SANTS="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code_path/containers/ants231_bc.sif"

# Must run synquick with 2.3.4 because the spaces were added in the brackets for the convergence steps here
SANTS234="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code_path/containers/ants234_bc.sif"

## longCT parameters 
skull_template=$top_path/UCIAtlas/UCI0x33mm_RSP.nii.gz
brain_prob_mask=$top_path/UCIAtlas/UCI0x33mm_initbrainmask_erode1_blurred.nii.gz
priors_path=$top_path/UCIAtlas/Priors/Prior_%d.nii.gz
control_type=2
template_brain=$top_path/UCIAtlas/UCI0x33mm_brainonly_init.nii.gz
reg_mask=$top_path/UCIAtlas/UCI0x33mm_initbrainmask.nii.gz # - not really ideal to not be dilated but this was the only thing that worked best w/ brain extraction
denoise=1
cpu_cores=$SLURM_CPUS_PER_TASK
SST_as_CT_prior=1
atropos_sst_weight=0.05
atropos_timept_weight=0.1
atropos_iters=40
rigid_align_to_SST=1
keep_tempfiles=1


## PROCESSING ##

# Go through list of timepoint images

for timepoint in ${timepoints[@]}; do
  dir="$(basename $timepoint)"
  echo $timepoint/anat/sub-${subj}_${dir}_T1w_RIP.nii.gz
  if [ ! -e $timepoint/anat/sub-${subj}_${dir}_T1w_RIP.nii.gz ]; then
  cp $timepoint/anat/sub-${subj}_${dir}_T1w.nii.gz $timepoint/anat/sub-${subj}_${dir}_T1w_RIP.nii.gz
  fi
  # Make sure that it's in oriented in RIP
  orient=`$SAFNI @GetAfniOrient $timepoint/anat/sub-${subj}_${dir}_T1w_RIP.nii.gz`
  if [ "$orient" = "RIP" ]; then
    echo $timepoint/anat/sub-${subj}_${dir}_T1w_RIP.nii.gz is in $orient
  else
    echo Reorienting this copy to RIP using 3drefit
    $SAFNI 3drefit -orient RIP -deoblique $timepoint/anat/sub-${subj}_${dir}_T1w_RIP.nii.gz
  fi

done

# Now we should have all of our RIP-oriented images
anats=($bidssubj_path/ses-T*/anat/sub-${subj}_ses-T?_T1w_RIP.nii.gz)

echo Structural T1w images: ${anats[@]}

full_call="$code_path/antsLongitudinalCorticalThickness_k9.sh \
  -d 3 \
  -e $skull_template \
  -m $brain_prob_mask \
  -p $priors_path \
  -f $reg_mask \
  -t $template_brain \
  -r $rigid_align_to_SST \
  -b $keep_tempfiles \
  -c $control_type \
  -j $cpu_cores \
  -n $SST_as_CT_prior \
  -v $atropos_sst_weight \
  -w $atropos_timept_weight \
  -g $denoise \
  -x $atropos_iters \
  -o $outsubj_path/aCT_ \
  -k 1 \
  -q 0 \
  ${anats[@]}"

# save call
echo $full_call > $outsubj_path/antsLongCT_command.txt

# run
echo $full_call | $SANTS bash

echo FINISHED at `date`