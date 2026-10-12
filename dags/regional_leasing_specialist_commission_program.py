"""
## regional_leasing_specialist_commission_program

https://app.clickup.com/t/14243987/86e3dryj1
"""

from airflow.sdk import dag
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from pendulum import datetime


@dag(
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    doc_md=__doc__,
    default_args={"owner": "data-eng", "retries": 0},
    template_searchpath="/usr/local/airflow/include/regional_leasing_specialist_commission_program",
)
def regional_leasing_specialist_commission_program():

    create_target = SQLExecuteQueryOperator(
        task_id="create_target",
        conn_id="snowflake",
        sql="create.sql",
    )

    refresh_target = SQLExecuteQueryOperator(
        task_id="refresh_target",
        conn_id="snowflake",
        sql="refresh.sql",
    )

    create_target >> refresh_target


regional_leasing_specialist_commission_program()
