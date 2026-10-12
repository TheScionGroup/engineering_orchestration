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
    template_searchpath="/usr/local/airflow/include",
)
def regional_leasing_specialist_commission_program():

    create_regional_leasing_specialist_commission_program = SQLExecuteQueryOperator(
        task_id="create_regional_leasing_specialist_commission_program",
        conn_id="snowflake",
        sql=["regional_leasing_specialist_commission_program/create.sql"],
    )

    refresh_regional_leasing_specialist_commission_program = SQLExecuteQueryOperator(
        task_id="refresh_regional_leasing_specialist_commission_program",
        conn_id="snowflake",
        sql=["regional_leasing_specialist_commission_program/refresh.sql"],
    )

    create_regional_leasing_specialist_commission_program >> refresh_regional_leasing_specialist_commission_program


regional_leasing_specialist_commission_program()
