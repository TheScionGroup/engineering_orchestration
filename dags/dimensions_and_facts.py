"""
## Grain-fix validation for fact_customer_leads (issue #3)

Scratch validation DAG — NOT a dbt model, does not touch `si-dw`. Rebuilds a
throwaway table in Snowflake to prove a grain fix for the production dbt
model at `si-dw`'s `models/transform/fact_customer_leads/fcl_fact_customer_leads.sql`.

That model's grain key is `md5(property_id, primary_applicant_id, academic_year)`.
`primary_applicant_id` is a per-application id, so a customer who cancels and
reapplies in the same academic year gets a second row for what should be one
customer/property/year lead. The correct grain is `customer_id + property_id +
academic_year`.

`rebuild_table` fully recreates `public.fact_customer_leads_but_not_dumb` on
every run (`create or replace table`) from `include/fact_customer_leads_but_not_dumb.sql`.
That file currently filters to two verified test customers (see the
TEST-CASE FILTER comment in the SQL) — remove that filter for a full reload:
  - customer 30028132: genuine duplicate, 2 different primary_applicant_ids
    at the same property in the same academic_year (the exact bug this fixes)
  - customer 29940833: baseline, single long-running application, no
    duplication expected (confirms the fix doesn't over-collapse)

It enforces the `customer_id + property_id + academic_year` grain directly
with a plain natural-key tuple (no md5 surrogate key, to keep the grain
trivially inspectable). When a customer has multiple applications at the same
property/year, the furthest-progressed application (Approved > Signed >
Lease Started > Application > Guest Card) wins and supplies the
representative status/dates/singular IDs; every applicant/application/
lease-interval id tied to the grain is kept in array columns.

Runs against the `snowflake_raw_conn` connection, whose `database` extra sets
the session's current database (locally `DBT_JTATE`) — so the `public.*`
target is intentionally left unqualified in the SQL, while every `raw.*`/
`analytics.*` source is fully qualified.
"""

from __future__ import annotations

from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.sdk import dag
from pendulum import datetime

SNOWFLAKE_CONN_ID = "snowflake_raw_conn"


@dag(
    dag_id="dimensions_and_facts",
    start_date=datetime(2025, 1, 1),
    schedule=None,
    catchup=False,
    tags=["facts", "snowflake", "transform"],
    template_searchpath="/usr/local/airflow/include",
)
def dimensions_and_facts():
    SQLExecuteQueryOperator(
        task_id="rebuild_table",
        conn_id=SNOWFLAKE_CONN_ID,
        sql="fact_customer_leads_but_not_dumb.sql",
    )


dimensions_and_facts()
