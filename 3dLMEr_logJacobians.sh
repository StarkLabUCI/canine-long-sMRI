#!/bin/bash
# Setup slurm options
#SBATCH --partition=large
#SBATCH --job-name=3dLMEr
#SBATCH -c 8
#SBATCH -o /mnt/hippocampus/starkdata1/head_dog/slurmlog/3dLMEr_Jacobians_Treatment_%j.out

# JNL 1/26/23

# DESCRIPTION:
# Runs 3dLMEr to perform linear mixed-effects modeling analysis of the logJacobian images 
# Model: predicting all dogs' logJacobians with baseline age, time in study (continuous), with random effect of subject (intercept)
# Pass in path to textfile of the data table as 1st command line arg

# USAGE: ./3dLMEr_logJacobians.sh datafile.txt 4
# datafile should be full path to datafile, not relative

# open permissions

umask 002 

# Print some useful job scheduling info

if [[ ! -v SLURM_CPUS_PER_TASK ]]; then  # Likely running locally - use more
  echo Defaulting to 8 CPU threads 
  SLURM_CPUS_PER_TASK=8
fi

echo Job ID: $SLURM_JOB_ID
echo Job name: $SLURM_JOB_NAME
echo Submit host: $SLURM_SUBMIT_HOST
echo "Node(s) used": $SLURM_JOB_NODELIST
echo Using $SLURM_CPUS_PER_TASK slots
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK

# PATHS
top_path=/mnt/hippocampus/starkdata1/head_dog
bids_path=$top_path/BIDS
code_path=$bids_path/code
der_path=$bids_path/derivatives
template_path=$top_path/UCIAtlas
antspath=$der_path/ANTS/longCT
datetime=`date +"%Y-%m-%d-%H%M%S"`
base_name=$(basename ${data_file})
test=`echo ${base_name} | sed s/.txt//`
output_path=$antspath/LinearMixedEffects/logJacobians/${test}

# full path to data file
data_file=$1

if [ ! -e $data_file ]; then
	echo data table does not exist!
	exit
else echo Input data file: $data_file
fi

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
slots=${SLURM_CPUS_PER_TASK}

start=$(date +%s)
echo Started at: `date`

# AFNI container with necessary R package for 3dLMEr
SAFNI="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code_path/containers/afni_newR.sif"

if [ ! -e $output_path ]; then
	echo Making $output_path
	mkdir -p $output_path
else echo output path: $output_path
fi

echo Output path: $output_path

# mask is the average brain eroded by 2 voxels 
mask=$template_path/SST_mean_map_x_UCIbrainmask_0x5mm_erode2.nii.gz

if [[ $mask < 1 ]]; then
	echo missing input for mask!
	exit
else echo Mask is $mask
fi

# Change directories to the output dir so we can save the dbgArgs (for debugging)
cd $output_path

full_call="3dLMEr -jobs ${slots} \
-dbgArgs \
-mask ${mask} \
-model 'BLAge+Timepoint*Treatment+(1|Subj)' \
-qVars 'BLAge,Timepoint,Age' \
-qVarCenters 6.47,0,6.47 \
-prefix ${output_path}/3dLMEr_logJacobians_Age \
-gltCode BLAge 'BLAge :' \
-gltCode Timepoint 'Timepoint :' \
-gltCode Place 'Treatment : 1*Place' \
-gltCode Q134R 'Treatment : 1*Q134R' \
-gltCode Tacro 'Treatment : 1*Tacro' \
-gltCode Tac_over_Time 'Treatment : 1*Tacro Timepoint :' \
-gltCode Place_over_Time 'Treatment : 1*Place Timepoint :' \
-gltCode Q134R_over_Time 'Treatment : 1*Q134R Timepoint :' \
-gltCode Tacro-Place_over_Time 'Treatment : 1*Tacro -1*Place Timepoint :' \
-gltCode Q134R-Place_over_Time 'Treatment : 1*Q134R -1*Place Timepoint :' \

-dataTable @${data_file}"

# save call
echo $full_call > $output_path/3dLMEr_command.txt

# execute the call
cd $output_path # changing directories to the output path just to be sure that the tempfiles land here

# pipe the call into the afni container
echo $full_call | $SAFNI bash

end=$(date +%s)

# elapsed time with second resolution
elapsed=$(( end - start ))

echo Finished at: `date`
eval "echo Elapsed time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"

echo copying slurmlog to output dir
cp /mnt/hippocampus/starkdata1/head_dog/slurmlog/3dLMEr_Jacobians_Treatment_${SLURM_JOB_ID}.out $output_path