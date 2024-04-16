import numpy as np
import scipy.io
import os
import pandas as pd
import glob
import sys
import subprocess

# Requirement: First run ICV_determinant.sh
# makes .csv of all subjects' affine determinant for each warp to the template

code_path='/mnt/hippocampus/starkdata1/head_dog/BIDS/code'
longCTdir=sys.argv[1]
sess=sys.argv[2]

print(" +++ Running get_determinant.py +++ ")
print("input dir: {}".format(longCTdir))

subdirs = os.listdir(longCTdir) # list of the subjects
subjects = [x for x in subdirs if 'sub-' in x] # get the subject ID from filenames
subjects=np.sort(subjects)
print(subjects)

# runs ICV_determinant.sh to warp the whole timepoint to the whole UCI template:
sessions=np.arange(int(sess)+1) # make list of runs
det_cols=['T{} Det'.format(i) for i in sessions]
detinv_cols=['T{} DetInv'.format(i) for i in sessions]
columns=det_cols+detinv_cols
# columns=['T0 Det','T1 Det','T2 Det','T3 Det','T0 DetInv','T1 DetInv','T2 DetInv','T3 DetInv']
df=pd.DataFrame(index=subjects)

# sst dataframe
sst_df=pd.DataFrame(index=subjects,columns=['SST_Det','SST_DetInv'])

# do this for SST
for subj in subjects:
    sstpath=os.path.join(longCTdir,subj,'aCT_SingleSubjectTemplate')
    affine=os.path.join(sstpath,'T_template0_toUCItemplate_AffineOnly0GenericAffine.mat')
    print('LOOKING FOR AFFINE {}'.format(affine))
    if os.path.isfile(affine):
        print('{} exists'.format(affine))
    else:
        print('{} does not exist: running ICV_determinant.sh'.format(affine))
        icv_script=os.path.join(code_path,"ICV_determinant.sh")
        # This will get the determinant for the SST and all of the timepoints
        val = subprocess.check_call("{} %s %s %s".format(icv_script) % (subj,sess,longCTdir), shell=True)
        print('Done running ICV_determinant.sh')

    # now if the affine exists then we can get the determinant
    if os.path.isfile(affine):
        print('Getting determinant of SST to template affine for {}'.format(subj))
        full_mat=scipy.io.loadmat(affine,matlab_compatible=True)
        mat=full_mat['AffineTransform_double_3_3'].reshape((4,3))
        #print(mat)
        notrans=mat[0:3,0:3] 
        det=np.linalg.det(notrans) # get determinant
        inv=np.linalg.inv(notrans) # get the inverse matrix
        detinv=np.linalg.det(inv) # get determinant of inverse matrix
        # print('{} {} Determinant: {:.3f}'.format(subj,ses,det))
        # print('{} {} Determinant on Inverse Matrix: {:.3f}'.format(subj,ses,detinv))
        sst_df.loc[subj,'SST_Det']=det
        sst_df.loc[subj,'SST_DetInv']=detinv
    else:
        sst_df.loc[subj,'SST_Det']=np.nan
        sst_df.loc[subj,'SST_DetInv']=np.nan
        print('Affine still does not exist: skipping {}'.format(subj))
        continue

sst_df.to_csv(os.path.join(longCTdir,'SST-to-UCItemplate-affinemat-determinant.csv'),index_label='Dog#')

# now for the timepoints
timepoints=['T{}'.format(i) for i in sessions]
print("Now processing timepoints:")
for ses in timepoints:
    print('ses-{}'.format(ses))
    timepoint_df=pd.DataFrame(index=subjects,columns=['{} Det'.format(ses)])
    for subj in subjects:
        #timepoint='{0}/{1}/{1}_ses-{2}_T1w_RIP_{3}'.format(longCTdir,subj,ses,ses[-1])
        try:
            timepoint=glob.glob('{0}/{1}/{1}_ses-{2}_T1w_RIP_*'.format(longCTdir,subj,ses))[0]
            affine='{0}/{1}_ses-{2}_T1wtoUCItemplate_AffineOnly0GenericAffine.mat'.format(timepoint,subj,ses)
            #affine='{0}/{1}_ses-{2}_InvertedBrainMasktoUCI_AffineOnly0GenericAffine.mat'.format(timepoint,subj,ses)
            full_mat=scipy.io.loadmat(affine,matlab_compatible=True)
            mat=full_mat['AffineTransform_double_3_3'].reshape((4,3))
            #print(mat)
            notrans=mat[0:3,0:3] 
            det=np.linalg.det(notrans) # get determinant
            inv=np.linalg.inv(notrans) # get the inverse matrix
            detinv=np.linalg.det(inv) # get determinant of inverse matrix
            # print('{} {} Determinant: {:.3f}'.format(subj,ses,det))
            # print('{} {} Determinant on Inverse Matrix: {:.3f}'.format(subj,ses,detinv))
            timepoint_df.loc[subj,'{} Det'.format(ses)]=det
            timepoint_df.loc[subj,'{} DetInv'.format(ses)]=detinv
        except:
            print('{} does not have timepoint {} - cannot calculate determinant'.format(subj,ses))
            continue
    df=pd.concat([df,timepoint_df],axis=1,join="inner")

df.to_csv(os.path.join(longCTdir,'Timepoints-to-UCItemplate-affinemat-determinant.csv'),index_label='Dog#')