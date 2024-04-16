#!/bin/bash
# Setup slurm options
#SBATCH --partition=standard
#SBATCH --job-name=ROIstats
#SBATCH -c 2
#SBATCH -o /mnt/hippocampus/starkdata1/head_dog/slurmlog/ROIstats_%j.out

# USAGE: ROI_stats.sh sub-CCACAI T3 /mnt/hippocampus/starkdata1/head_dog/BIDS/derivatives/ANTS/longCT \
# $top_path/Johnson_Atlas/Johnson2UCI/Johnson_space/RIP_whole_atlas_cortical_subcortical_gyri_updated.nii.gz \ 
# JohnsonGyrusAtlas

# DESCRIPTION:
# This moves an atlas to a cleaned up time point brain (masked by the SST)
# also updated the sequence of warps used here .. the ones in this former version were definitly in the wrong order
# See https://github.com/ANTsX/ANTs/wiki/Forward-and-inverse-warps-for-warping-images,-pointsets-and-Jacobians 

# atlases:
# Johnson full atlas: $top_path/Johnson_Atlas/Johnson2UCI/Johnson_space/whole_atlas_cortical_subcortical_reoriented_to_poptemplate_LIPtoUCIRSP_0x3mm.nii.gz
# Johnson gyrus atlas: $top_path/Johnson_Atlas/Johnson2UCI/Johnson_space/RIP_whole_atlas_cortical_subcortical_gyri_updated.nii.gz

# outnames:
# JohnsonAtlasCorticalSubcorticalLabels
# JohnsonGyrusAtlas

umask 002

if [[ ! -v SLURM_CPUS_PER_TASK ]]; then
  echo Defaulting to 8 CPU threads 
  SLURM_CPUS_PER_TASK=8
fi

echo Job ID: $SLURM_JOB_ID
echo Job name: $SLURM_JOB_NAME
echo Submit host: $SLURM_SUBMIT_HOST
echo "Node(s) used": $SLURM_JOB_NODELIST
echo Started at: `date`

echo Using $SLURM_CPUS_PER_TASK slots
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

# INPUT ARGUMENTS
subj=`echo $1 | sed s/sub-//` # Strip off any sub- and ses-Session
ses=`echo $2 | sed s/ses-//` # Strip off ses-
ses=`echo $ses | sed s/T//` # Strip off T from sesnum
longCTpath=$3
atlas=$4
outname=$5

echo Running ROI_stats2.sh 
echo Processing $subj ses-T${ses} Path: $longCTpath Atlas: $atlas Outpath: $outname

if (( `expr length "$ses"` < 1 )) ; then
echo invalid sessnum -- e.g. T3 analyzes up to timepoint 3 -- Exiting
exit
fi

# Data paths
top_path=/mnt/hippocampus/starkdata1/head_dog
bidspath=$top_path/BIDS
code_path=$bidspath/code
antspath=$longCTpath/sub-${subj}
sstpath=$antspath/aCT_SingleSubjectTemplate


# container locations
SAFNI="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code_path/containers/afni_012821.sif"
SANTS="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code_path/containers/ants234_bc.sif"


ctpath=`echo $antspath/sub-${subj}_ses-T${ses}_T1w_RIP_*`
echo $ctpath

# Apply group-template-to-SST warps to move atlas to SST
echo "+++ Warping $outname atlas to SST +++"
if [ ! -e ${sstpath}/T_template0_${outname}.nii.gz ]; then
    $SANTS antsApplyTransforms -d 3 \
    -i $atlas \
    -r ${sstpath}/T_templateBrainExtractionBrain.nii.gz \
    -o ${sstpath}/T_template0_${outname}.nii.gz \
    -n GenericLabel[Linear] \
    -t ${sstpath}/T_templateTemplateToSubject1GenericAffine.mat \
    -t ${sstpath}/T_templateTemplateToSubject0Warp.nii.gz \
    -v
else echo ${sstpath}/T_template0_${outname}.nii.gz exists -- skipping atlas to SST warp
fi

# make a binary brain mask w/o CSF
echo "+++ Making binary brain mask for SST +++"
if [ ! -e ${sstpath}/T_template_GM-WM-dGM-mask.nii.gz ]; then
    $SAFNI 3dcalc -a ${sstpath}/T_templateBrainSegmentation.nii.gz \
    -prefix ${sstpath}/T_template_GM-WM-dGM-mask.nii.gz -expr 'amongst(a,2,3,4)'
else echo ${sstpath}/T_template_GM-WM-dGM-mask.nii.gz exists -- skipping 3dcalc for making brain mask
fi

# Multiply labels by GM+WM+dGM mask
echo "+++ Multiply labels by brain mask +++"
if [ ! -e ${sstpath}/T_template0_${outname}-noCSF.nii.gz ]; then
    $SAFNI 3dcalc -a ${sstpath}/T_template0_${outname}.nii.gz \
    -b ${sstpath}/T_template_GM-WM-dGM-mask.nii.gz \
    -expr "(a*b)" -prefix ${sstpath}/T_template0_${outname}-noCSF.nii.gz \
    -overwrite
else echo ${sstpath}/T_template0_${outname}-noCSF.nii.gz exists -- skipping 3dcalc for masking atlas by brain mask
fi

#### Now for the given time point ####

echo "+++ ses-T${ses} Registering atlas to cleaned up time point +++"
# As a first step we have to rigid align the SST brain to the timepoint
# This will simply be used as a mask for the segmentation maps because the timepoints aren't as clean around the edges
echo "+++ 1. Registering the skull-stripped SST to skull-stripped T${ses} +++"
if [ ! -e ${ctpath}/T_templateBrain_to_Timepoint_Warped.nii.gz ]; then
    $SANTS antsRegistrationSyNQuick.sh -d 3 \
    -f ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrain.nii.gz \
    -m ${sstpath}/T_templateBrainExtractionBrain.nii.gz \
    -t 'r' \
    -o ${ctpath}/T_templateBrain_to_Timepoint_ \
    -n $SLURM_CPUS_PER_TASK
else echo ${ctpath}/T_templateBrain_to_Timepoint_Warped.nii.gz exists -- skipping warp
fi

# mask the skull-stripped time point brain by the SST mask
echo "+++ 2. Masking the skull-stripped timepoint by the SST +++ "
if [ ! -e ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrainMaskedbySST.nii.gz ]; then
  $SAFNI 3dcalc \
    -a ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrain.nii.gz \
    -b ${ctpath}/T_templateBrain_to_Timepoint_Warped.nii.gz \
    -expr 'a*bool(b)' \
    -prefix ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrainMaskedbySST.nii.gz
  else echo ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrainMaskedbySST.nii.gz exists -- skipping
fi

# Generate Non-linear warps for this cleaner skull-stripped brain to the the skull-stripped SST
echo  "+++ 3. Registering the clean skull-stripped time point brain to SST +++"
if [ ! -e ${ctpath}/CleanSubjectToSSTWarped.nii.gz ]; then
  $SANTS antsRegistrationSyNQuick.sh -d 3 \
    -f ${sstpath}/T_templateBrainExtractionBrain.nii.gz \
    -m ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrainMaskedbySST.nii.gz \
    -o ${ctpath}/CleanSubjectToSST \
    -n $SLURM_CPUS_PER_TASK
  else echo ${ctpath}/CleanSubjectToSSTWarped.nii.gz exists -- skipping
fi

# Let's mask the segmentation too
echo "+++ 4. Masking the brain segmentation map by the SST +++ "
if [ ! -e ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainSegmentation_MaskedSST.nii.gz ]; then
$SAFNI 3dcalc \
    -a ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainSegmentation.nii.gz \
    -b ${ctpath}/T_templateBrain_to_Timepoint_Warped.nii.gz \
    -expr 'a*bool(b)' \
    -prefix ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainSegmentation_MaskedSST.nii.gz
  else echo ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainSegmentation_MaskedSST.nii.gz exists -- skipping
fi

# Warp atlas labels to time point - yes these warps are correct, see link to documentation above
echo "+++ 5. Warping the atlas to ses-T${ses} clean skull stripped brain +++"
if [ ! -e ${ctpath}/sub-${subj}_ses-T${ses}_${outname}.nii.gz ]; then
    $SANTS antsApplyTransforms -d 3 \
    -i $atlas \
    -r ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainExtractionBrainMaskedbySST.nii.gz \
    -o ${ctpath}/sub-${subj}_ses-T${ses}_${outname}.nii.gz \
    -n GenericLabel[Linear] \
    -t "[${ctpath}/CleanSubjectToSST0GenericAffine.mat,1]" \
    -t ${ctpath}/CleanSubjectToSST1InverseWarp.nii.gz \
    -t ${ctpath}/T_templateBrain_to_Timepoint_0GenericAffine.mat \
    -t ${sstpath}/T_templateTemplateToSubject1GenericAffine.mat \
    -t ${sstpath}/T_templateTemplateToSubject0Warp.nii.gz \
    -v
else echo ${ctpath}/sub-${subj}_ses-T${ses}_${outname}.nii.gz exists -- exiting
fi

# make a binary brain mask w/o CSF
echo "+++ 6. Making binary brain mask for Timepoint T${ses} +++"
if [ ! -e ${ctpath}/sub-${subj}_ses-T${ses}_GM-WM-dGM-mask.nii.gz ]; then
    $SAFNI 3dcalc -a ${ctpath}/sub-${subj}_ses-T${ses}_T1w_RIPBrainSegmentation_MaskedSST.nii.gz \
    -prefix ${ctpath}/sub-${subj}_ses-T${ses}_GM-WM-dGM-mask.nii.gz -expr 'amongst(a,2,3,4)'
else echo ${ctpath}/sub-${subj}_ses-T${ses}_GM-WM-dGM-mask.nii.gz exists -- skipping
fi

# Multiply labels by GM+WM+dGM mask
echo "+++ 7. Mask out CSF from ${outname} labels +++"
if [ ! -e ${ctpath}/sub-${subj}_ses-T${ses}_${outname}-noCSF.nii.gz ]; then
    
    $SAFNI 3dcalc -a ${ctpath}/sub-${subj}_ses-T${ses}_${outname}.nii.gz \
    -b ${ctpath}/sub-${subj}_ses-T${ses}_GM-WM-dGM-mask.nii.gz \
    -expr "(a*b)" -prefix ${ctpath}/sub-${subj}_ses-T${ses}_${outname}-noCSF.nii.gz \
    -overwrite
else echo ${ctpath}/sub-${subj}_ses-T${ses}_${outname}-noCSF.nii.gz exists -- skipping
fi

# get voxel counts inside each label
echo "+++ 8. Running 3dROIstats and saving to ${ctpath}/3dROIstats_${outname}.txt +++"
$SAFNI 3dROIstats -nzvoxels -nomeanout \
    -mask ${ctpath}/sub-${subj}_ses-T${ses}_${outname}-noCSF.nii.gz  \
    ${ctpath}/sub-${subj}_ses-T${ses}_${outname}-noCSF.nii.gz > ${ctpath}/3dROIstats_${outname}.txt

echo FINISHED at `date`