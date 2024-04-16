# canine-long-sMRI
## Structural analysis pipeline for longitudinal T1w images in beagles  

This code was used to generate the results in the paper: [Noche et al., (2024) Age-related brain atrophy and the positive effects of behavioral enrichment in middle-aged beagles, _The Journal of Neuroscience_](https://doi.org/10.1523/JNEUROSCI.2366-23.2024).

The cortical gyrus atlas used in this project was created from combining subregions defined in the stereotactic cortical atlas developed by [Johnson et al. (2020)](https://doi.org/10.1038/s41598-020-61665-0)

_**Please cite if using any part of this repository:**_  
Noche et al. (2024) Age-related brain atrophy and the positive effects of behavioral enrichment in middle-aged beagles. _The Journal Of Neuroscience_, DOI: 10.1523/JNEUROSCI.2366-23.2024

Please contact Jessica Noche at nochej@uci.edu for help.

Make sure anat files are in BIDs format before proceeding. (https://github.com/NILAB-UvA/bidsify).

**Pipeline**:  
1. `antsLongCT.sh` will run the ANTs longitudinal cortical thickness pipeline using modified ANTs scripts (`antsBrainExtraction_k9.sh` and `antsCorticalThickness_k9.sh`).
2. `proc_singlesub.sh` is to be run on all subjects and will clean up the edges of the time point segmentations and calculate ROI statistics from each with `ROI_stats.sh`, will generate the log-Jacobian maps with `make_clean_logJacobian.sh`, and will generate the affine matrix from linear transformations between time point to SST and SST to template with `get_affine.sh`.
3. `get_determinant.py` extracts the determinant of each affine matrix to be used as a proxy for intracranial volume (ICV). ROI volumes are then adjusted for ICV with `regressICV.py`.
4. `3dLMEr_logJacobians.sh` will run the AFNI program [3dLMEr](https://afni.nimh.nih.gov/pub/dist/doc/program_help/3dLMEr.html) for a voxel-wise analysis of the log-Jacobian maps for conducting deformation-based morphometry.

**Singularity containers**:
All Singularity (Apptainer) containers for executing the software used above can be downloaded [here](https://ucirvine-my.sharepoint.com/:f:/g/personal/nochej_ad_uci_edu/Et42sAJ3cKROovYv8t6Q4MYBtSNJa9GbfH-ZbdTj3-mnGg?e=PV2Q3z).
