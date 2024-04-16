#!/bin/bash
# Setup slurm options
#SBATCH --partition=standard
#SBATCH --job-name=affineT1toUCI
#SBATCH -c 4
#SBATCH -o /mnt/hippocampus/starkdata1/head_dog/slurmlog/affineT1toUCI_%j.out


# DESRIPTION: Generates affine to the template for a given subject's SST and timepoints

# FS Wiki eTIV: https://surfer.nmr.mgh.harvard.edu/fswiki/eTIV 
# Calculate ICV https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4423585/
# how determinant is related to volume: https://textbooks.math.gatech.edu/ila/determinants-volumes.html
# reads in a nonlinear 3d warp and computes functions of the displacement:
# https://afni.nimh.nih.gov/pub/dist/doc/program_help/3dNwarpFuncs.html
# jacobian maps: https://pubmed.ncbi.nlm.nih.gov/17679333/
# most clear help from ENIGMA: http://enigma.ini.usc.edu/protocols/imaging-protocols/protocol-for-brain-and-intracranial-volumes/
# Geometric properties of the determinant: https://mathinsight.org/determinant_geometric_properties

# USAGE:
# ./get_affine.sh subID sess

umask 002

echo Job ID: $SLURM_JOB_ID
echo Job name: $SLURM_JOB_NAME
echo Submit host: $SLURM_SUBMIT_HOST
echo "Node(s) used": $SLURM_JOB_NODELIST
start=$(date +%s)
echo +++ Running get_affine.sh +++
echo Started at: `date`

echo Using $SLURM_CPUS_PER_TASK slots
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

# Strip off any sub- and ses-Session
subj=`echo $1 | sed s/sub-//`
sess=`echo $2 | sed s/ses-//`
sess=`echo $sess | sed s/T//`
echo Running on subj=$subj up to ses-T${sess}

# Data paths
top_path=/mnt/hippocampus/starkdata1/head_dog
bidspath=$top_path/BIDS
code_path=$bidspath/code

# container locations
SAFNI="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code/containers/afni_012821.sif"
SANTS="singularity exec -B /mnt/hippocampus:/mnt/hippocampus $code/containers/ants234_bc.sif"

antspath=$bidspath/derivatives/ANTS/longCT/sub-${subj}
sstpath=$antspath/aCT_SingleSubjectTemplate
ucipath=$top_path/UCIAtlas

# move SST and timepoints onto UCI TEMPLATE with 12-parameter affine

if [ -e $sstpath/T_template0.nii.gz ]; then
    if [ ! -e $sstpath/T_template0_0x33mm.nii.gz ]; then
    echo RESAMPLING SST to 0.33mm iso
    $SAFNI 3dresample -master $ucipath/UCI0x33mm_RSP.nii.gz \
        -input $sstpath/T_template0.nii.gz \
        -prefix $sstpath/T_template0_0x33mm.nii.gz
    fi
else echo $sstpath/T_template0.nii.gz does not exist - exiting
exit
fi

# register to TEMPLATE
echo Moving SST to template translation + rigid + affine only
if [ ! -e $sstpath/T_template0_toUCItemplate_AffineOnlyWarped.nii.gz ]; then
    $SANTS antsRegistrationSyNQuick.sh -d 3 -f $ucipath/UCI0x33mm_RSP.nii.gz \
    -m $sstpath/T_template0_0x33mm.nii.gz \
    -o $sstpath/T_template0_toUCItemplate_AffineOnly -n $SLURM_CPUS_PER_TASK -t a
else echo $sstpath/T_template0_toUCItemplate_AffineOnlyWarped.nii.gz exists -- skipping
fi

real_sessnum=(`seq 0 1 ${sess}`)
orders=(`seq 0 1 ${sess}`) # this is for if the session numbers don't match the suffix # if the sessions were shuffled in the call to ANTs
for idx in ${orders[@]}; do
    ses=${real_sessnum[${idx}]} 
    echo Processing ses-T${ses}
    ctpath=$antspath/sub-${subj}_ses-T${ses}_T1w_RIP_${idx} 

    # resample to same spacing as TEMPLATE
    echo +++ 1. to same spacing as TEMPLATE: 0.33mm iso +++
    if [ ! -e $ctpath/sub-${subj}_ses-T${ses}_T1w_RIPRigidToSSTWarped_0x33mm.nii.gz ]; then
        $SAFNI 3dresample -master $ucipath/UCI0x33mm_RSP.nii.gz \
            -input $ctpath/sub-${subj}_ses-T${ses}_T1w_RIPRigidToSSTWarped.nii.gz \
            -prefix $ctpath/sub-${subj}_ses-T${ses}_T1w_RIPRigidToSSTWarped_0x33mm.nii.gz
    
    else echo $ctpath/sub-${subj}_ses-T${ses}_T1w_RIPRigidToSSTWarped_0x33mm.nii.gz exists -- skipping
    fi

    # register to TEMPLATE
    echo +++ 2. Moving T${idx} to template translation + rigid + affine only +++
    if [ ! -e $ctpath/sub-${subj}_ses-T${ses}_T1wtoUCItemplate_AffineOnlyWarped.nii.gz ]; then
        $SANTS antsRegistrationSyNQuick.sh -d 3 -f $ucipath/UCI0x33mm_RSP.nii.gz \
        -m $ctpath/sub-${subj}_ses-T${ses}_T1w_RIPRigidToSSTWarped_0x33mm.nii.gz \
        -o $ctpath/sub-${subj}_ses-T${ses}_T1wtoUCItemplate_AffineOnly -n $SLURM_CPUS_PER_TASK -t a
    else echo $ctpath/sub-${subj}_ses-T${ses}_T1wtoUCItemplate_AffineOnlyWarped.nii.gz exists -- skipping
    fi
done

echo FINISHED at `date`
end=$(date +%s)
elapsed=$(( end - start ))
eval "echo Elapsed time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"