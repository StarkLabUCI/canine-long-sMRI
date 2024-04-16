#!/bin/bash
# Setup slurm options
#SBATCH --partition=standard
#SBATCH --job-name=cleanJD
#SBATCH -c 4
#SBATCH -o /mnt/hippocampus/starkdata1/head_dog/slurmlog/cleanJD_%j.out

# Jessica Noche | May 22, 2023

# Make clean log Jacobian:
# 1. Mask the time point with the SST mask
# 2. Perform registration to skull-stripped SST
# 3. Combine these warps with the SST-to-template warps for the single log-jacobian
# 4. resample to 0.5mm (-master to the Johnson atlas so it's the same number of voxels)
# 5. Run in 3dLMEr

echo Job ID: $SLURM_JOB_ID
echo Job name: $SLURM_JOB_NAME
echo Submit host: $SLURM_SUBMIT_HOST
echo "Node(s) used": $SLURM_JOB_NODELIST
echo Started at: `date`

echo Using $SLURM_CPUS_PER_TASK slots
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

# Strip off any sub- and ses-Session
subj=`echo $1 | sed s/sub-//`
ses=`echo $2 | sed s/ses-//` # Strip off ses-
ses=`echo $ses | sed s/T//` # Strip off T from sesnum

umask 002

# Data paths
top_path=/mnt/hippocampus/starkdata1/head_dog
bidspath=$top_path/BIDS
code_path=$bidspath/code
longCTpath=$bidspath/derivatives/ANTS/longCT
antspath=$longCTpath/sub-${subj}
sstpath=$antspath/aCT_SingleSubjectTemplate
ctpath=`echo $antspath/sub-${subj}_ses-T${ses}_T1w_RIP_*`
template=$top_path/UCIAtlas/UCI0x33mm_RSP.nii.gz

echo Cleaning up skull stripped brain for $subj T${ses} at `date`

# container locations
SAFNI="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code_path/containers/afni_012821.sif"
SANTS="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code_path/containers/ants231_bc.sif"

# As a first step we will rigid-align the SST brain to the timepoint - the pipeline didn't do this very well
# This will simply be used as a mask for the segmentation maps because the timepoints aren't as clean around the edges
echo "+++ 1. Registering the skull-stripped SST to $sess brain +++"
if [ ! -e ${ctpath}/T_templateBrain_to_Timepoint_Warped.nii.gz ]; then
    $SANTS antsRegistrationSyNQuick.sh -d 3 \
    -f ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrain.nii.gz \
    -m ${sstpath}/T_templateBrainExtractionBrain.nii.gz \
    -t 'r' \
    -o ${ctpath}/T_templateBrain_to_Timepoint_ \
    -n $SLURM_CPUS_PER_TASK
  else echo ${ctpath}/T_templateBrain_to_Timepoint_Warped.nii.gz exists -- skipping
fi

# mask the skull-stripped time point brain
echo "+++ 2. Masking the skull-stripped brain with SST rigidly aligned to timepoint +++ "
if [ ! -e ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrainMaskedbySST.nii.gz ]; then
  
  $SAFNI 3dcalc \
    -a ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrain.nii.gz \
    -b ${ctpath}/T_templateBrain_to_Timepoint_Warped.nii.gz \
    -expr 'a*bool(b)' \
    -prefix ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrainMaskedbySST.nii.gz
  else echo ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrainMaskedbySST.nii.gz exists -- skipping
fi

# Non-linearly register this cleaner skull-stripped brain to the the skull-stripped SST
echo  "+++ 3. Registering the clean skull-stripped time point brain to SST +++"
if [ ! -e ${ctpath}/CleanSubjectToSSTWarped.nii.gz ]; then
  
  $SANTS antsRegistrationSyNQuick.sh -d 3 \
    -f ${sstpath}/T_templateBrainExtractionBrain.nii.gz \
    -m ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrainMaskedbySST.nii.gz \
    -o ${ctpath}/CleanSubjectToSST \
    -n $SLURM_CPUS_PER_TASK
  else echo ${ctpath}/CleanSubjectToSSTWarped.nii.gz exists -- skipping
fi

# Create combined time point to SST & SST to group template warps
# See documentation: https://github.com/ANTsX/ANTs/wiki/antsCorticalThickness-and-antsLongitudinalCorticalThickness-output 
echo " +++ 4. Making combined warp for all of these transformations +++ "
if [ ! -e ${ctpath}/CleanSubjectToGroupTemplateWarp.nii.gz ]; then
  $SANTS antsApplyTransforms \
    -d 3 \
    -r $template \
    -o [ ${ctpath}/CleanSubjectToGroupTemplateWarp.nii.gz,1 ] \
    -t ${sstpath}/T_templateSubjectToTemplate1Warp.nii.gz \
    -t ${sstpath}/T_templateSubjectToTemplate0GenericAffine.mat \
    -t ${ctpath}/CleanSubjectToSST1Warp.nii.gz \
    -t ${ctpath}/CleanSubjectToSST0GenericAffine.mat
else echo ${ctpath}/CleanSubjectToGroupTemplateWarp.nii.gz exists -- skipping
fi

# Create log jacobian determinant image of this combined warp
echo " +++ 5. Convert to logJacobian determinant image to run in 3dLMEr +++ "
if [ ! -e ${ctpath}/SubjectToGroupTemplateLogJacobianClean.nii.gz ]; then
    echo +++ Create geometric logJacobian using CreateJacobianDeterminantImage +++
    $SANTS CreateJacobianDeterminantImage 3 \
        ${ctpath}/CleanSubjectToGroupTemplateWarp.nii.gz \
        ${ctpath}/SubjectToGroupTemplateLogJacobianClean.nii.gz 1 1
else echo ${ctpath}/SubjectToGroupTemplateLogJacobianClean.nii.gz exists -- skipping
fi

# be aware that the default resampling mode is NN (nearest neighbor) since we did not specify -rmode (other option is Linear)
if [ ! -e ${ctpath}/sub-${subj}_ses-T${ses}_SubjectToGroupTemplateLogJacobianClean_0x5mm.nii.gz ]; then
    echo +++ resampling ${ctpath}/SubjectToGroupTemplateLogJacobianClean.nii.gz to 0.5mm +++
    $SAFNI 3dresample -master $top_path/UCIAtlas/UCI0x5mm_RSP.nii.gz -input ${ctpath}/SubjectToGroupTemplateLogJacobianClean.nii.gz \
        -prefix ${ctpath}/sub-${subj}_ses-T${ses}_SubjectToGroupTemplateLogJacobianClean_0x5mm.nii.gz
else echo ${ctpath}/sub-${subj}_ses-T${ses}_SubjectToGroupTemplateLogJacobianClean_0x5mm.nii.gz exists -- skipping
fi

echo FINISHED at `date`