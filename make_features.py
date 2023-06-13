import os
import sys
import requests
import pandas as pd
from get_data import GetData
import dash_bootstrap_components as dbc


import plotly.graph_objects as go
from plotly.subplots import make_subplots


class MakeFeatures:
    """ Class to setup labour planning template """
    gd = GetData()
 
    def map_viz(self, df):
        mapbox_center_lon=6.16
        mapbox_center_lat=15.30
        mapbox_zoom=1
        mapbox_access_token='pk.eyJ1Ijoid2l1bWpvbGVuZSIsImEiOiJja3l5Y3VkNGgwaW54MnBxa2Fza2NvMGY0In0.939ZUiX84zjJRGGr9Z6Dlw'

        Color = df['colours']
        Category = df['status']

        cats = {k:str(v) for k,v in zip(set(Color),set(Category))}

        df_type_1 = df.copy()

        fig = make_subplots(
            rows = 1, 
            cols = 1,
            specs = [[{"type": "scattermapbox"}]],
            vertical_spacing = 0.05,
            horizontal_spacing = 0.05
            )

        for c in df_type_1['colours'].unique():
            df_color = df_type_1[df_type_1['colours'] == c].reset_index(drop=True)
            fig.add_trace(go.Scattermapbox(
                                lat = df_color['lat'],
                                lon = df_color['lon'],
                                mode = 'markers',
                                name = cats[c],
                                marker = dict(color = c, size=12),#df_type_1['Color']
                                customdata=df_color['vessel_name'], 
                                hovertemplate='<b>%{customdata}</b><br>'+
                                    '%{text}<br><br>',
                                text = ['{}'.format(df_color['next_eta'][i]) for i in range(len(df_color))],
                                ),
                    row = 1,
                    col = 1
                    )

        fig.update_layout(
            autosize=True,
            hovermode='closest',
            margin={"r":0,"t":0,"l":0,"b":0},
            legend=dict(
                orientation="h",
                yanchor="bottom",
                y=1.02,
                xanchor="right",
                x=1
            ),
            mapbox=dict(
                accesstoken=mapbox_access_token,
                style="carto-positron",
                bearing=0,
                center=dict(
                    lat=mapbox_center_lat,
                    lon=mapbox_center_lon
                ),
                pitch=0,
                zoom=mapbox_zoom
            ),
        )

        return fig
    
    def vessel_table(self, df):
        df = df.sort_values(by='next_port_eta')
        df = df[['vessel_name', 'next_port_unlocode', 'eta_use']]
        df = df.drop_duplicates()
        df = df.dropna()
        
        df = df.rename(columns={'vessel_name':'VesselName','next_port_unlocode':'NextPort','eta_use':'ETA'})
        
        return df
    
    def commodity_table_DEPRICATE(self, df):
        df = df[['vessel_name', 'commodity', 'stdunits']]
        
        df = df.pivot_table(index='vessel_name', columns='commodity', values='stdunits')
        df = df.sort_values(by='vessel_name').reset_index(drop=False)
        df = df.rename(columns={'vessel_name':'VesselName'})

        return df