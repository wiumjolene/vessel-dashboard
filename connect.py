import logging
import os
import time

import pandas as pd
from dotenv import find_dotenv, load_dotenv
from sqlalchemy import create_engine, event
from sshtunnel import SSHTunnelForwarder


class DatabaseModelsClass:
    def __init__(self, server_name):

        load_dotenv(find_dotenv())
        database_url = os.environ.get(server_name)

        self.alchemy_engine = create_engine(database_url)

    def select_query_ssh(self, query_str):
        server = SSHTunnelForwarder(
            (os.environ.get('SSHH'), 22),
            ssh_username=os.environ.get('SSHUN'),
            ssh_password=os.environ.get('SSHUP'),
            remote_bind_address=('127.0.0.1', 3306)
            )

        server.start()
        local_port = str(server.local_bind_port)
        engine = create_engine('mysql+pymysql://{}:{}@{}:{}/{}'.format("agrihub", "4gr1hu8", "127.0.0.1", local_port, "agrihub"))

        data_set = pd.read_sql(query_str, engine)

        server.stop()

        return data_set


    def select_query(self, query_str):
        data_set = pd.read_sql(query_str, con=self.alchemy_engine,
                               index_col=None,
                               coerce_float=True,
                               params=None,
                               parse_dates=None,
                               columns=None,
                               chunksize=None)

        return data_set

    def select_query_chunks(self, query_str, chunk_size):
        data_set = pd.DataFrame({})
        valid_response = False

        while not valid_response:
            try:
                i = 1
                for chunk in pd.read_sql_query(query_str, self.alchemy_engine, chunksize=chunk_size):
                    start_time = time.time()
                    data_set = data_set.append(chunk)
                    i += 1
                valid_response = True

                valid_response = True
            except:
                continue
        
        return data_set

    def insert_table(self, data, table_name, schema, if_exists, index=False):

        conn = self.alchemy_engine
        @event.listens_for(self.alchemy_engine, "before_cursor_execute")
        def receive_before_cursor_execute(
                conn, cursor, statement, params, context, executemany
        ):
            if executemany:
                cursor.fast_executemany = True

        data.to_sql(table_name, schema=schema, con=conn,
                    if_exists=if_exists, index=index)

    def insert_table_chunks(self, data, table_name, schema, if_exists, chunk_size, index=False):
        conn = self.alchemy_engine
        data.to_sql(table_name, schema=schema, con=conn,
                    if_exists=if_exists, chunksize=chunk_size, index=index)

    def delete_table(self, query):
        conn = self.alchemy_engine.connect()
        conn.execute(query)
        conn.close()

    def execute_query(self, query):
        conn = self.alchemy_engine.connect()
        conn.execute(query)
        conn.close()
