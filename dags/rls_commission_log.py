"""
## rls_commission_log: Regional Leasing Specialist commission tables

Builds the two Regional Leasing Specialist commission tables described in
`docs/Commission_Program_Guidelines.pdf` for the 2027/2028 leasing season
(Aug 1, 2026 - Jul 31, 2027):

- `public.regional_leasing_specialist_commission_program` ($5 / new contract)
- `public.regional_leasing_specialist_commission_program_renewals`
  ($3 / renewal)

Both tables attribute commission by property assignment (the home RLS, not
proof of closer activity) and are built via `create or replace table`, so
each run fully replaces the table's contents. See each `.sql` file's own
header comment for known limitations.

The underlying queries are still being refined. For ad hoc exploration
(single-lease debugging, worked examples, scratch queries unrelated to this
DAG), use `include/rls_commission_log.sql` instead -- that file is not run
by any DAG. This DAG runs the clean, final versions only:
`include/regional_leasing_specialist_commission_program.sql` and
`include/regional_leasing_specialist_commission_program_renewals.sql`.

Manually triggered for now (`schedule=None`) while the query is still being
validated -- revisit once the eligibility-signal work is further along.
"""

from __future__ import annotations

from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from pendulum import datetime

try:
    from airflow.sdk import dag
except ImportError:  # pragma: no cover - fallback for older Airflow 3 SDK layouts
    from airflow.sdk import dag

SNOWFLAKE_CONN_ID = "snowflake_raw_conn"


@dag(
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    doc_md=__doc__,
    default_args={"owner": "data-eng", "retries": 2},
    tags=["rls_commission_log", "commission"],
    template_searchpath="/usr/local/airflow/include",
)
def rls_commission_log():
    SQLExecuteQueryOperator(
        task_id="build_commission_table",
        conn_id=SNOWFLAKE_CONN_ID,
        sql=["regional_leasing_specialist_commission_program.sql"],
    )


rls_commission_log()
