import dash
from dash import dcc, html, Input, Output
from flask_caching import Cache
import dash_bootstrap_components as dbc
import json
import pandas as pd
import uuid

import plotly.graph_objects as go
from plotly.subplots import make_subplots

from get_data import GetData
from make_features import MakeFeatures

features = MakeFeatures()
gd = GetData()


dash_app = dash.Dash(__name__,
                     external_stylesheets=[dbc.themes.SPACELAB, 
                                           dbc.icons.FONT_AWESOME])
dash_app.title = 'Agrihub Vessels'
cache = Cache(dash_app.server, config={
    'CACHE_TYPE': 'redis',
    # Note that filesystem cache doesn't work on systems with ephemeral
    # filesystems like Heroku.
    'CACHE_TYPE': 'filesystem',
    'CACHE_DIR': 'cache-directory',

    # should be equal to maximum number of users on the app at a single time
    # higher numbers will store more data in the filesystem / redis cache
    'CACHE_THRESHOLD': 200
})

app = dash_app.server

def get_dataframe(session_id):
    @cache.memoize()
    def query_and_serialize_data(session_id):
        # expensive or user/session-unique data processing step goes here
        df = gd.get_vessel_commodity()

        return df.to_json()

    return pd.read_json(query_and_serialize_data(session_id))

########################################################################
# Define dashboard aspects
########################################################################
# Select commodity card
commdodity_select_card = dbc.Card(
    [dbc.CardHeader("Select Commodity"),
     dbc.CardBody(dcc.Dropdown(
         [], 'ALL', clearable=False, id='commodity-dropdown')),
     ], className="mt-4",
)

# Select vessel card
vessel_select_card = dbc.Card(
    [dbc.CardHeader("Select Vessel"),
     dbc.CardBody(dcc.Dropdown(
         [], 'ALL', clearable=False, id='vessel-dropdown')),
     ], className="mt-4",
)

# Map card for geolocation of vessels
map_card = dbc.Card(
    [
        html.Div(id='map-vis', className="mb-2"),
    ],
    className="mt-4",
)

# Next port table card
next_port_card = dbc.Card(
    [
        dbc.CardHeader("Next port information"),
        dbc.CardBody(
            html.Div(id='vessel-table'),
        ),
    ],
    className="mt-4",
)

# Commodity summary card
commodity_card = dbc.Card(
    [
        dbc.CardHeader("Commodity information"),
        dbc.CardBody(
            html.Div(id='commodity-table'),
        ),
    ],
    className="mt-4",
)

# Footer card
footer = html.Div(
    dcc.Markdown(
        """
        Agrihub 2022-2023    
        """
    ),
    className="p-2 mt-5 bg-primary text-white small",
)

########################################################################
# Define app
########################################################################
def serve_layout():
    session_id = str(uuid.uuid4())

    return dbc.Container(
        [
            dcc.Store(data=session_id, id='session-id'),
            dbc.Row(
                dbc.Col(
                    html.H2(
                        "Agrihub Active Vessels",
                        className="text-center bg-primary text-white p-2",
                    ),
                )
            ),
            dbc.Row(
                [
                    dbc.Col([map_card,
                            next_port_card
                            ],
                            width=12,
                            lg=6,
                            className="pt-4",
                            ),
                    dbc.Col(commodity_card, width=12, lg=4, className="mt-4"),
                    dbc.Col([commdodity_select_card, vessel_select_card,
                            ], width=12, lg=2, className="mt-4 border"),

                ],
                className="ms-1",
            ),
            dbc.Row(dbc.Col(footer)),
        ],
        fluid=True,
    )
dash_app.layout = serve_layout


########################################################################
# Define callbacks for interactivity
########################################################################
# Get data
def clean_data(session_id, commodity='ALL', vessel='ALL'):
    df_4 = get_dataframe(session_id)

    if commodity != 'ALL':
        df_4 = df_4[df_4['commodity'] == commodity]

    if vessel != 'ALL':
        df_4 = df_4[df_4['vessel_name'] == vessel]

    return df_4

# Callback to manage commodity dropdown
@dash_app.callback(
    Output('commodity-dropdown', 'options'),
    Input('session-id', 'data'),
    Input('vessel-dropdown', 'value'),
)
def update_com_dropdown(session_id, vessel):
    """ Update commodity dropdown based on vessel

    Parameters
    ----------
    vessel : strings
        Filter data by vessels. 
        If vessel='ALL', use all rows in data set.

    Returns
    ----------
    commlist : list
        A list of commodities on the selected vessels.
    """
    table_df=clean_data(session_id, vessel=vessel)

    commlist = list(table_df['commodity'].unique())
    commlist.sort()
    commlist = ['ALL'] + commlist

    return commlist

# Callback to manage vessel dropdown
@dash_app.callback(
    Output('vessel-dropdown', 'options'),
    Input('session-id', 'data'),
    Input('commodity-dropdown', 'value'),
)
def update_ves_dropdown(session_id, commodity):
    """ Update vessel dropdown based on commodity

    Parameters
    ----------
    commodity : string
        Filter data by commodity. 
        If commodity='ALL', use all rows in data set.

    Returns
    ----------
    vessellist : list
        A list of vessels on the selected commodities.
    """
    #datasets = json.loads(jsonified_cleaned_data)
    #table_df = pd.read_json(datasets['df_4'], orient='split')
    table_df=clean_data(session_id, commodity=commodity)

    vessellist = list(table_df['vessel_name'].unique())
    vessellist.sort()
    vessellist = ['ALL'] + vessellist

    return vessellist


# Update vessel-commodity bar graph
@dash_app.callback(
    Output('commodity-table', 'children'),
    Input('session-id', 'data'),
    Input('commodity-dropdown', 'value'),
    Input('vessel-dropdown', 'value'),
)
def update_com_table(session_id, commodity, vessel):
    """ Generates bar graph indicating commodity volumes by vessel

    Parameters
    ----------
    commodity : string
        Filter data by commodity. 
        If commodity='ALL', use all rows in data set.
    vessel : string
        Filter data by vessel. 
        If vessel='ALL', use all rows in data set.
        
    Returns
    ----------
    graph : dash core graph component
        An HTML package of a barchart
    """
    #datasets = json.loads(jsonified_cleaned_data)
    #table_df = pd.read_json(datasets['df_4'], orient='split')
    table_df=clean_data(session_id, commodity, vessel)

    table_df = table_df.sort_values(by='vessel_name', ascending=False)
    vessels = table_df.vessel_name.unique()
    commodities = table_df.commodity.unique()

    fig = go.Figure()

    for com in commodities:
        df = table_df[table_df['commodity'] == com]
        vessels = list(df.vessel_name)
        values = list(df.stdunits)

        fig.add_trace(go.Bar(
            y=vessels,
            x=values,
            text=values,
            textposition='inside',
            name=com,
            orientation='h',
            marker=dict(
                color=gd.get_colour(com),
                line=dict(color=gd.get_colour(com), width=1)
            )
        ))

    fig.update_layout(barmode='stack',
                      margin={"r": 0, "t": 0, "l": 0, "b": 0},
                      uniformtext_minsize=8, uniformtext_mode='hide',
                      legend=dict(
                          orientation="h",
                          yanchor="bottom",
                          y=1.02,
                          xanchor="right",
                          x=1
                      ))

    graph = dcc.Graph(figure=fig, style={'height': '90vh'}, config={
                      'displayModeBar': False})

    return graph


# Update vessel next port location and ETA
@dash_app.callback(
    Output('vessel-table', 'children'),
    Input('session-id', 'data'),
    Input('commodity-dropdown', 'value'),
    Input('vessel-dropdown', 'value'),
)
def update_vessel_table(session_id, commodity, vessel):
    """ Generates table indicating Next Port by vessel

    Parameters
    ----------
    commodity : string
        Filter data by commodity. 
        If commodity='ALL', use all rows in data set.
    vessel : string
        Filter data by vessel. 
        If vessel='ALL', use all rows in data set.
        
    Returns
    ----------
    table : dash core table component
        An HTML package of a table
    """
    #datasets = json.loads(jsonified_cleaned_data)
    #table_df = pd.read_json(datasets['df_4'], orient='split')
    table_df=clean_data(session_id, commodity, vessel)

    table_df = features.vessel_table(table_df)
    table = dbc.Table.from_dataframe(
        table_df, striped=True, bordered=True, hover=True)
    
    return table


# Update map visual
@dash_app.callback(
    Output('map-vis', 'children'),
    Input('session-id', 'data'),
    Input('commodity-dropdown', 'value'),
    Input('vessel-dropdown', 'value'),
)
def update_map(session_id, commodity, vessel):
    """ Generates MAP visual to locate all active vessels

    Parameters
    ----------
    commodity : string
        Filter data by commodity. 
        If commodity='ALL', use all rows in data set.
    vessel : string
        Filter data by vessel. 
        If vessel='ALL', use all rows in data set.
        
    Returns
    ----------
    map : dash core table component
        An HTML package of a map visual
    """
    #datasets = json.loads(jsonified_cleaned_data)
    #table_df = pd.read_json(datasets['df_4'], orient='split')
    table_df=clean_data(session_id, commodity, vessel)


    map = dcc.Graph(figure=features.map_viz(table_df), config={
                    'displayModeBar': False}, className="mb-2")
    return map


if __name__ == '__main__':
    dash_app.run_server(debug=True)
