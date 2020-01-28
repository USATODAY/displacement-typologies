#!/usr/bin/env python
# coding: utf-8

# ### Import libraries

# In[1]:


import census
import pandas as pd
import numpy as np


# ### Read files

# In[2]:


# Data files
city_name = 'Atlanta'

census_90 = pd.read_csv(city_name+'census_90.csv', index_col = 0)
census_00 = pd.read_csv(city_name+'census_00.csv', index_col = 0)

# Crosswalk files
xwalk_90_10 = pd.read_csv('crosswalk_1990_2010.csv')
xwalk_00_10 = pd.read_csv('crosswalk_2000_2010.csv')


# ### Choose city and census tracts of interest

# In[3]:


if city_name == 'Chicago':
    state = '17'
    FIPS = ['031', '043', '089', '093', '097', '111', '197']

elif city_name == 'Atlanta':
    state = '13'
    FIPS = ['057', '063', '067', '089', '097', '113', '121', '135', '151', '247']
    
elif city_name == 'Denver':
    state = '08'
    FIPS = ['001', '005', '013', '014', '019', '031', '035', '047', '059']
    
elif city_name == 'Memphis':
    state = ['28', '47']
    FIPS = {'28':['033', '093'], '47': ['047', '157']}

else:
    print ('There is no information for the selected city')


# ### Creates filter function
# Note - Memphis is different bc it's located in 2 states

# In[4]:


def filter_FIPS(df):
    if city_name != 'Memphis':
        df = df[df['county'].isin(FIPS)].reset_index(drop = True)

    else:
        fips_list = []
        for i in state:
            county = FIPS[i]
            a = list((df['FIPS'][(df['county'].isin(county))&(df['state']==i)]))
            fips_list = fips_list + a
        df = df[df['FIPS'].isin(fips_list)].reset_index(drop = True)
    return df


# ### Creates crosswalking function

# In[5]:


def crosswalk_files (df, xwalk, counts, medians, df_fips_base, xwalk_fips_base, xwalk_fips_horizon):

    # merge dataframe with xwalk file
    df_merge = df.merge(xwalk[['weight', xwalk_fips_base, xwalk_fips_horizon]], left_on = df_fips_base, right_on = xwalk_fips_base, how='left')                             

    df = df_merge
    
    # apply interpolation weight
    new_var_list = list(counts)+(medians)
    for var in new_var_list:
        df[var] = df[var]*df['weight']

    # aggregate by horizon census tracts fips
    df = df.groupby(xwalk_fips_horizon).sum().reset_index()
    
    # rename trtid10 to FIPS & FIPS to trtid_base
    df = df.rename(columns = {'FIPS':'trtid_base',
                              'trtid10':'FIPS'})
    
    # fix state, county and fips code
    df ['state'] = df['FIPS'].astype('int64').astype(str).str.zfill(11).str[0:2]
    df ['county'] = df['FIPS'].astype('int64').astype(str).str.zfill(11).str[2:5]
    df ['tract'] = df['FIPS'].astype('int64').astype(str).str.zfill(11).str[5:]
    
    # drop weight column
    df = df.drop(columns = ['weight'])
    
    return df


# ### Crosswalking

# ###### 1990 Census Data

# In[6]:


counts = census_90.columns.drop(['county', 'state', 'tract', 'mrent_90', 'mhval_90', 'hinc_90', 'FIPS'])
medians = ['mrent_90', 'mhval_90', 'hinc_90']
df_fips_base = 'FIPS'
xwalk_fips_base = 'trtid90'
xwalk_fips_horizon = 'trtid10'
census_90_xwalked = crosswalk_files (census_90, xwalk_90_10,  counts, medians, df_fips_base, xwalk_fips_base, xwalk_fips_horizon )


# ###### 2000 Census Data

# In[7]:


counts = census_00.columns.drop(['county', 'state', 'tract', 'mrent_00', 'mhval_00', 'hinc_00', 'FIPS'])
medians = ['mrent_00', 'mhval_00', 'hinc_00']
df_fips_base = 'FIPS'
xwalk_fips_base = 'trtid00'
xwalk_fips_horizon = 'trtid10'
census_00_xwalked = crosswalk_files (census_00, xwalk_00_10,  counts, medians, df_fips_base, xwalk_fips_base, xwalk_fips_horizon )


# ###### Filters and exports data

# In[8]:


census_90_filtered = filter_FIPS(census_90_xwalked)
census_00_filtered = filter_FIPS(census_00_xwalked)


# In[9]:


census_90_filtered.to_csv(city_name+'census_90_10.csv')
census_00_filtered.to_csv(city_name+'census_00_10.csv')

