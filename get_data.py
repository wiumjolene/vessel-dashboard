import os
import sys
import requests
import pandas as pd
import numpy as np
import random

from connect import DatabaseModelsClass



class GetData:
    """ Class to setup labour planning template """
    database_instance = DatabaseModelsClass('MYSQLLINUXP')
 
    def get_vessel_commodity(self):
        """ Get vessel positions """

        sql=f"""
            SELECT dim_vessels.VesselName as vessel_name
                , dim_vessels.VesselType as vessel_type
                , CASE WHEN latest.status = '0' THEN 'Under way using engine'
                    WHEN latest.status > '0' AND latest.status < '5' THEN 'At anchor'
                    WHEN latest.status = '5' THEN 'Moored'
                    ELSE 'Unsure' end as `status`
                , CASE WHEN latest.status = '0' THEN '#54Bf9E'
                    WHEN latest.status > '0' AND latest.status < '5' THEN '#FDBB1D'
                    WHEN latest.status = '5' THEN '#F37455'
                    ELSE '#002060' END as colours
                , latest.lat
                , latest.lon
                , latest.destination
                , latest.next_port_unlocode
                , latest.eta_calc
                , IF(latest.eta_calc > '2020-01-01', latest.eta_calc, null) as next_port_eta
                , IF(latest.eta_calc > '2020-01-01'
					, CONCAT(CONCAT(latest.next_port_unlocode, ": "), CONCAT(CONCAT(CONCAT(DATE(latest.eta_calc),' at '), HOUR(latest.eta_calc), ':00')))
                    , 'No next port information available')
					as next_eta
                , latest.timestamp as updated
                , summary.commodity
                , ROUND(summary.eqv_ctns, 1) as stdunits
            FROM agrihub.vessels_vessel_position_latest latest
            LEFT JOIN dim_vessels ON (latest.vessel_id=dim_vessels.id_vessel)
			LEFT JOIN (
				SELECT st.commodity, st.id_vessel, sum(st.eqv_ctns) as eqv_ctns FROM agrihub.SummaryTable st
				LEFT JOIN vessels_sail_date ON (st.sail_date_id=vessels_sail_date.id)
				WHERE vessels_sail_date.shipped_date > DATE_SUB(now(), INTERVAL 21 DAY)
				AND vessels_sail_date.shipped_date_confirmed=1
				GROUP BY st.commodity, st.id_vessel
			) summary ON (dim_vessels.id_vessel = summary.id_vessel)
            WHERE date(ah_datetime)=date(now())
            AND summary.eqv_ctns > 0
            -- WHERE date(ah_datetime)='2023-04-29';
        """
        df = self.database_instance.select_query_ssh(sql)
        df['stdunits'] = df['stdunits'].astype(int)
        df['next_port_eta'] = pd.to_datetime(df['next_port_eta'])
        #df['eta_calc'] = pd.to_datetime(df['eta_calc'])
        return df

    def get_colour(self, commodity):
        try:
            dic = {
                'AP': '#a9dfce',
                'PR': '#98c8b9',
                'GR': '#fedd8e',
                'OR': '#f9b9aa',
                'GF': '#e0a699',
                'LE': '#c79488',
                'SC': '#fac7bb',          

            }
            col = dic[commodity]
        except:
            col = '#C0C0C0'
        return col