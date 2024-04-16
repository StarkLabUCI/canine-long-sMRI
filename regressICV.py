import pandas as pd
import scipy.stats as stats
import statsmodels.api as sm
import os
import sys
import numpy as np
from sklearn import linear_model
import matplotlib.pyplot as plt
import seaborn as sns # should run sns version 11.1 or greater
import subprocess

# run on python 3.9.12
# USAGE for running up to time point 3:
# python regressICV.py 3 /mnt/hippocampus/starkdata1/head_dog/BIDS/derivatives/ANTS/longCT

# 2/18/23 update
# Adjusted volume = raw vol - (b * (ICV - mean ICV)) 
# where b is the slope of regression of a region of interest volume on ICV
# See Raz et al 2005 and Dima et al., 2022 Human Brain Mapping

def regress(df,colx,coly):
    '''
    Takes in a dataframe, and the two column names. 
    Does an ordinary least squares regression on the two series.
    Returns input series x , input series y, predicted values, residual values, indices (dog IDs), and slope
    '''
    df=df[df[colx].notna()] # exclude values from series x where series x has missing values
    df=df[df[coly].notna()] # exclude values from series y where series y has missing values
    ind=df.index.tolist()
    x=np.array(df[colx])
    y=np.array(df[coly])

    # linear regression with sklearn
    regr= linear_model.LinearRegression()
    regr.fit(x.reshape(-1, 1),y) # must reshape the data to a 1D array since we have one feature
    intercept=regr.intercept_ # intercept
    slope=regr.coef_[0] # slope
    pred=(slope*x)+intercept # y=mx+b for plotting predicted values
    residual=y-pred # actual-predicted
    return x,y,pred,residual,ind,slope

def adjust_vol(raw,icv,meanicv,slope):
    '''
    raw: subject's raw ROI volume value
    icv: subject's ICV
    meanicv: mean ICV of entire group of subjects
    slope: the slope of original ROI volume regressed onto ICV (from regress)
    returns ICV-adjusted volume
    '''
    adj = raw-(slope*(icv-meanicv))
    return round(adj,3)


if __name__=="__main__":

    sess=int(sys.argv[1])
    sessnums=np.arange(sess+1) 
    longCT=sys.argv[2] # full path to longCT directory
    mask='wholebrain'
    savedir=os.path.join(longCT,'processed')
    if os.path.exists(os.path.join(savedir))==False:
        os.mkdir(os.path.join(savedir))
    plotdir=os.path.join(savedir,'figures')
    if os.path.exists(os.path.join(plotdir))==False:
        os.mkdir(os.path.join(plotdir))
    dog_bids_dir=os.path.join('/mnt/hippocampus/starkdata1/head_dog/BIDS')
    code_dir=os.path.join(dog_bids_dir,'code','Jess_ANTs')

    print('+++ Running regressICVfromVolumes_Razmethod.py +++')
    print('Sessions: {}'.format(sessnums))
    print('longCT directory: {}'.format(longCT))
    print('mask: {}'.format(mask))
    print('save directory: {}'.format(savedir))
    print('plot directory: {}'.format(plotdir))
    groups={
            'placebo':['2001374','2306922','2336732','2337992','2342342','2351090','CCCCUR','CCDCJM','CCFCUI','CDBCVB','CDHCPP','CDICJH','CEICER', 'CEJCLY'],
            'q134r':['2217181','2239002','2353475','2370574','CCADBD','CCBCHK','CCBCPK','CCCCJP','CCECUM','CCLDAL','CDGCTP','CDLDEL','CEHCSW','CEKCMG'],
            'tac':['2153069','2278937','2323916','2372462','2398380','2456428','CBECPU','CBICBX','CCACAI','CCACKM','CCBCMP','CCFCGY','CCLCBX','CEACSR','CELCBU']   
            }
    
    source={
            '1':
            ["2001374","2306922","2336732","2337992","2342342","2351090", "2217181","2239002","2353475","2370574","2153069","2278937","2323916","2372462","2398380", "2456428"],
            '2':
            ["CCCCUR","CCDCJM","CCFCUI","CDBCVB","CDHCPP","CDICJH", "CEICER","CEJCLY", "CCADBD", "CCBCHK", "CCBCPK", "CCCCJP", "CCECUM", "CCLDAL", 
            "CDGCTP","CDLDEL","CEHCSW","CEKCMG","CBECPU","CBICBX","CCACAI","CCACKM","CCBCMP","CCFCGY","CCLCBX","CEACSR","CELCBU"]
            }

    alldogs=np.concatenate((groups['placebo'],groups['q134r'],groups['tac']),axis=0)
    alldogs=np.sort(alldogs)
    allruns_df=pd.DataFrame(index=alldogs)

    group_df=pd.DataFrame(columns=['Group','Source'],index=alldogs)

    # add group column
    for group,dogs in groups.items():
        for dog in dogs:
            group_df.loc[dog,'Group']=group
    for source,dogs in source.items():
        for dog in dogs:
            group_df.loc[dog,'Source']=source

    # make .csv of tissue volumes
    brainsegmentations=pd.DataFrame()
    for timepoint in sessnums:
        timepoint_segmentations=pd.DataFrame()
        roi_stats=pd.read_csv(os.path.join(longCT,'3dROIstats_T{0}_CSF-GM-WM-dGM_{1}.txt'.format(timepoint,mask)),header=None,delim_whitespace=True)
        firstcol=roi_stats[0].str.split('/',expand=True)
        roi_stats['Dog#']=[ sub[4:] for sub in firstcol[9] ] # strip off the sub-
        # roi_stats['Dog#']=[ sub[4:] for sub in firstcol[10] ] # strip off the sub-
        
        roi_stats=roi_stats.drop(columns=0)
        roi_stats=roi_stats.set_index('Dog#')     
        roi_stats=roi_stats.rename(columns={1:'T{}_CSF'.format(timepoint),2:'T{}_GM'.format(timepoint),3:'T{}_WM'.format(timepoint),4:'T{}_dGM'.format(timepoint)})
        
        brainsegmentations=pd.concat([brainsegmentations,roi_stats],axis=1)

    # get columns for brain volumes (GM+WM+dGM)
    for timepoint in sessnums:
        brainsegmentations['T{}_GM+WM+dGM'.format(timepoint)]=brainsegmentations['T{}_GM'.format(timepoint)] + brainsegmentations['T{}_WM'.format(timepoint)] + brainsegmentations['T{}_dGM'.format(timepoint)]

    # save raw brain segmentations for reference
    if os.path.isfile(os.path.join(savedir,'JohnsonBrainSegmentations_raw_{}.csv'.format(mask))):
        print('segmentation csv exists in {}'.format(os.path.join(savedir,'JohnsonBrainSegmentations_raw_{}.csv'.format(mask))))
    else:
        print('Saving segmentations to {}'.format(os.path.join(savedir,'JohnsonBrainSegmentations_raw_{}.csv'.format(mask))))
        brainsegmentations.to_csv(os.path.join(savedir,'JohnsonBrainSegmentations_raw_{}.csv'.format(mask)),index_label='Dog#')
    
    # 2/16/23 - "ICV" used now will be the determinant of the linear transformation from SST to template - this corresponds better to actual dog size

    # Concatenate segmentations df to volumes df
    volumes=pd.read_csv(os.path.join(longCT,'JohnsonGyrusAtlas_volumes.csv'))
    volumes=volumes.set_index('Dog#')
    volumes=pd.concat([volumes,brainsegmentations],axis=1)  # concatenate segmentations df

    # get list of ROIs
    regions=volumes.columns.tolist()
    regions=regions[1:]
    regions=[region[3:] for region in regions ]
    regions=np.unique(regions)

    # Get ICV (Determinant of whole-image SST-to-Template linear transformation matrix) - this was generated by get_determinant.py
    if os.path.isfile(os.path.join(longCT,'SST-to-UCItemplate-affinemat-determinant.csv')):
        print('{} exists - skipping get_determinant.py'.format(os.path.join(longCT,'SST-to-UCItemplate-affinemat-determinant.csv')))
    else:
        print('Running get_determinant.py {}'.format(longCT))
        determinant_script=os.path.join(code_dir,"get_determinant.py")
        subprocess.run(["python",determinant_script,longCT,str(sess)])
    
    icv=pd.read_csv(os.path.join(longCT,'SST-to-UCItemplate-affinemat-determinant.csv')) 
    icv['Dog#']=[ sub[4:] for sub in icv['Dog#'] ] # strip off the sub-
    icv=icv.set_index('Dog#')
    print('Loading up csv with determinants: {}'.format(icv))

    icv=icv.rename(columns={'SST_Det':'ICV'})
    icv=icv.drop(columns=['SST_DetInv'])

    # concatenate ICV and volumes
    df=pd.concat([icv,volumes],axis=1)

    # set up dataframe to store the final adjusted values for all regions
    adjusted=pd.DataFrame(index=alldogs)
    adjusted['Group']=group_df['Group']
    adjusted['Source']=group_df['Source']
    adjusted['ICV']=df['ICV']

    # adjust each ROI
    print("Adjusting regions by ICV...")
    for region in regions:

        # 1. run ICV by T0 regression
        t0_x,t0_y,t0_pred,t0_residual,ind,t0_slope = regress(df,'ICV','T0_{}'.format(region))

        # 2. adjust each value at each timepoint by the T0 slope
        for timepoint in sessnums:

            # 2a. create df of features needed for volume adjustment
            d = {   'Dog#': df['ICV'].index.tolist(), # dog IDs
                    'T{}_{}'.format(timepoint,region): df['T{}_{}'.format(timepoint,region)], # raw timepoint vol
                    'ICV': df['ICV'] # ICV
                    }

            adjusted_roi=pd.DataFrame(data=d).set_index('Dog#')
            # add in columns of constants: 1) mean ICV and 2) slope
            adjusted_roi['meanICV']=adjusted_roi["ICV"].mean()# add in column for mean ICV
            adjusted_roi['slope T0']=t0_slope # add in column of T0 slope constant
            
            # 2b. apply adjust_vol on all rows
            adjusted['T{}_{}'.format(timepoint,region)] = adjusted_roi.apply(
                lambda row : adjust_vol(
                    row['T{}_{}'.format(timepoint,region)],
                    row['ICV'],
                    row['meanICV'],
                    row['slope T0']
                    ),
                    axis = 1)
    
    # check things out
    print(adjusted.tail())

    ###### plot ######

    import scipy as sp

    print('Making plots:')

    def plot_icv_roi(df,x,y,name):
        # pass in df, x=xname, y=yname, name=raw or adjusted

        g=sns.lmplot(data=df,x=x, y=y)

        # annotate with stats
        def annotate(data, **kws):
            r, p = sp.stats.pearsonr(df[x], df[y])
            ax = plt.gca()
            ax.text(.05, .8, 'r ={:.2f}, p={:.2g}'.format(r, p),
                    transform=ax.transAxes)
            ax.set_title(y)

        g.map_dataframe(annotate) 

        # plot one ROI and the correlation to ICV
        plt.xlabel(x)
        plt.ylabel(y)
        plt.tight_layout()
        plt.savefig(os.path.join(plotdir,'{}_by_{}_{}.jpg'.format(x,y,name)))
        print('plot saved in {}'.format(os.path.join(plotdir,'{}_by_{}_{}.jpg'.format(x,y,name))))

    # check this frontal region that we know is correlated with ICV
    roi='T0_Hippocampus_R'
    
    plot_df=pd.DataFrame(data=df['ICV'])
    plot_df[roi]=df[roi]
    plot_df = plot_df.dropna()
    plot_icv_roi(plot_df,'ICV',roi,'raw')

    plot_df=pd.DataFrame(data=adjusted['ICV'])
    plot_df = plot_df.dropna()
    plot_df[roi]=adjusted[roi]
    plot_icv_roi(plot_df,'ICV',roi,'adjusted')
    
    # mutliply by voxel dimensions to convert volumes to mm3
    scalar=0.352*0.352*0.7
    adjusted.loc[:,'T0_Amygdala_L':] *= scalar


    ###### end plots ######

    # save to csv
    if os.path.isfile(os.path.join(savedir,'JohnsonGyrusAtlas_volumes_ICVadjusted_mm3.csv')):
        print('adjusted vol csv exists in {}'.format(os.path.join(savedir,'JohnsonGyrusAtlas_volumes_ICVadjusted_mm3.csv')))
    else:
        adjusted.to_csv(os.path.join(savedir,'JohnsonGyrusAtlas_volumes_ICVadjusted_mm3.csv'),index_label='Dog#')


