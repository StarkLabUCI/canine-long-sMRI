#!/bin/bash
# Setup slurm options
#SBATCH --partition=standard
#SBATCH --job-name=K9segs
#SBATCH -c 2
#SBATCH -o /mnt/hippocampus/starkdata1/head_dog/slurmlog/ROIstats_tissuesegs_%j.out

# DESCRIPTION: putting all subjects' CSF,GM,WM,dGM voxel counts from segmentation maps up to given sessnum onto a textfile
# USAGE: get_segmentations.sh <sess> <antspath>

umask 002

echo Job ID: $SLURM_JOB_ID
echo Job name: $SLURM_JOB_NAME
echo Submit host: $SLURM_SUBMIT_HOST
echo "Node(s) used": $SLURM_JOB_NODELIST
echo Started at: `date`

echo Using $SLURM_CPUS_PER_TASK slots
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

# Data paths
top_path=/mnt/hippocampus/starkdata1/head_dog
bidspath=$top_path/BIDS
code_path=$bidspath/code
cd $antspath

# container locations
SAFNI="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code_path/containers/afni_012821.sif"

sess=$1 # must be single integer - 0, 1, 2, or 3...
antspath=$2

# set up list of timepoints
runs=(0)
seq_runs=`seq $sess`
for value in ${seq_runs[@]}; do runs+=($value); done
# make file

echo GETTING TISSUE VOLUMES FROM THE WHOLE BRAIN
for ses in ${runs[@]}; do
echo $processing tissue from T${ses}
    if [ ! -e $antspath/3dROIstats_T${ses}_CSF-GM-WM-dGM_wholebrain.txt ]; then
        #echo File CSF GM WM dGM > $antspath/3dROIstats_T${ses}_CSF-GM-WM-dGM_wholebrain.txt
        echo ++++++++ sess is $ses ++++++++++
        for i in sub-*; do
            subj=`echo $i | sed s/sub-//`
            echo Running on subj=$subj
            ants_subjpath=$antspath/sub-${subj}
            echo +++ ants_subjpath is $ants_subjpath +++
            ctpath=`echo $ants_subjpath/sub-${subj}_ses-T${ses}_T1w_RIP_*`
            echo $ctpath

            if [ ! -e ${ctpath}/3dROIstats_T${ses}_CSF-GM-WM-dGM_wholebrain.txt ]; then
                echo getting segmentations for $subj ses-T${ses}

                # get the voxel counts for each tissue type and save onto a textfile for each timepoint
                echo Appending $subj ses-T${ses} to 3dROIstats_T${ses}_CSF-GM-WM-dGM.txt

                    $SAFNI 3dROIstats -nzvoxels -nomeanout \
                    -mask ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainSegmentation_MaskedSST.nii.gz \
                    ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainSegmentation_MaskedSST.nii.gz  \
                    > ${ctpath}/3dROIstats_T${ses}_CSF-GM-WM-dGM_wholebrain.txt

            else echo ${ctpath}/3dROIstats_T${ses}_CSF-GM-WM-dGM_wholebrain.txt exists!

            fi
                echo Cleaning up 3dROIstats output
                grep .gz ${ctpath}/3dROIstats_T${ses}_CSF-GM-WM-dGM_wholebrain.txt | \
                cut -f 1,3,4,5,6 >> $antspath/3dROIstats_T${ses}_CSF-GM-WM-dGM_wholebrain.txt
                echo Saved $antspath/3dROIstats_T${ses}_CSF-GM-WM-dGM_wholebrain.txt
        done
    else echo $antspath/3dROIstats_T${ses}_CSF-GM-WM-dGM_wholebrain.txt exists -- skipping
    fi
done

echo FINISHED at `date`