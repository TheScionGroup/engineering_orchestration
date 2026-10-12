# Data Engineering Standards

Response to [#13](https://github.com/TheScionGroup/engineering_orchestration/issues/13). The warehouse ([si-dw](https://github.com/TheScionGroup/si-dw)) has been built up without a shared set of conventions. These rules are binding for all new work in [engineering_orchestration](https://github.com/TheScionGroup/engineering_orchestration) (an Astro/Airflow project — DAGs in [`dags/`](https://github.com/TheScionGroup/engineering_orchestration/tree/main/dags), SQL in [`include/`](https://github.com/TheScionGroup/engineering_orchestration/tree/main/include)) and in [si-dw](https://github.com/TheScionGroup/si-dw).

## Gold-layer tables

- **One DAG for all dimensions, named `dimensions`. One DAG for all facts, named `facts`.** Both live in this repository's [`dags/`](https://github.com/TheScionGroup/engineering_orchestration/tree/main/dags) alongside the existing DAGs here (e.g. `raw_static`). Dimension and fact models are not scattered across per-domain DAGs.
- **Grain is documented as commented metadata on the table itself in Snowflake** (e.g. a `COMMENT ON TABLE` with "Grain: one row per ..."). Anyone looking at the table directly in Snowflake must be able to read the grain.
- **Every target table and every column must be commented.** Good column comments include example values whenever no personally identifiable information is involved — this is especially important for status, type, and stage columns. When the domain is small, list every distinct value in the comment rather than a sample.
- **The table-definition work is its own task, using this repository's existing `create_<table_name>` DAG task convention.** `create_<table_name>` owns the table's DDL, its table-level comment, and its column comments, and is `>>`-chained ahead of whichever load task populates the table. Query/definition responsibility does not get folded into a load task.
- **Loads are incremental by default, and the task name reflects how.** A true incremental load is an upsert — task named `merge_<table_name>`, built on a `MERGE` statement. `refresh_<table_name>` (truncate + insert) is reserved for tables that are genuinely fully reloaded every run; it is not a stand-in for incremental loading. A full-refresh (`refresh_<table_name>`) is permitted only with a documented reason at the table level explaining why an incremental `merge_<table_name>` isn't viable for that table.
- **A full-refresh table uses `TRUNCATE` + `INSERT`, never `DROP` + `CREATE`.** `TRUNCATE` clears the rows but keeps the same table object, so Snowflake's query-optimizer statistics (column min/max, distinct-value estimates, micro-partition pruning metadata), any clustering key, and any search optimization configuration all carry forward and get refreshed against the new data automatically. `DROP` + `CREATE` destroys that object and replaces it with a brand-new one that starts with none of that — and because grants are attached to the object, not the table name, every privilege granted on the table is lost and must be manually reapplied on every single run. This isn't hypothetical: `analytics.public.dim_properties` currently has `SELECT` granted to six roles (`ACCOUNTING`, `ANALYST`, `ETLWORKS`, `LOOKER_ROLE`, `OMNI_POC_ROLE`, `STAFF_STREAMLINE`) — a `DROP`/`CREATE`-based refresh would silently break all six downstream consumers' access until someone noticed and re-granted them. The table-level and column-level comments required above would also need to be reapplied in full on every run instead of being set once by `create_<table_name>`.
- **Gold-layer tables must be self-sufficient.** No consumer of a gold table should ever need to join back to silver or raw to get what they need. If that happens, it means a data engineer needs to engineer the missing data into the appropriate gold table — not leave it for the consumer to patch over with an upstream join.

## Bronze-layer tables

This layer is nothing more than replicated raw data, no transformation.

Do not use listeners (webhooks, change-data-capture event streams, or similar push-based ingestion) for bronze-layer tables. Use batch or incremental pulls. The only exception is a source API that offers no viable batch or incremental extraction path — document that exception at the model level when it applies.

## Silver-layer tables

Silver = [`models/transform`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform) in [si-dw](https://github.com/TheScionGroup/si-dw). This layer is a staging area, nothing more. A model belongs here only if it materializes an intermediate result that multiple downstream gold-layer models actually reuse. Logic needed by exactly one gold table does not get promoted to its own silver model — it stays inline in that gold model (or a private CTE within it).

## SQL style

- Block comments use a single `/* */` block, not stacked `--` lines. `/*` and `*/` each alone on their own line, one point per indented line in between, no leading `*` per line. Don't split one explanation into multiple adjacent `/* */` blocks — fold extra points into the same block.
- Don't use a CTE (or subquery) purely for readability/structuring or to avoid a top-level `distinct`. Only reach for one when it provides a real optimization — e.g. deduping/aggregating a fanned-out table down to the right grain *before* a join, so the join itself never produces extra rows.
- When a table has a dedicated DDL file, write inserts into it as plain `insert into <table> select ...` — no explicit column list. The DDL is the source of truth for column order; don't duplicate it.
- Keep an `in (...)` value list on one line rather than spreading each value across its own line.
- Prefer `property_id` over `property_key` when joining/partitioning/grouping on a property in `analytics.public.contracts` (or similarly-keyed tables) — they're in a strict 1:1 relationship, and `property_id` (NUMBER) is cheaper to partition on than `property_key` (TEXT hash). If `property_key` is genuinely required, add an inline comment explaining why.
- Don't leave commented-out single-case debug filters (e.g. `--and contracts.application_id = 12345`) in a production query file. Move them into the matching query in a `test_queries.sql` file instead.
- Do not alias tables. Qualify every column reference with the full table name, and always specify the table name in a `select`, even for a single-table query. E.g. `select * from public.dim_property where dim_property.entrata_property_id is not null`, not `select * from public.dim_property dp where dp.entrata_property_id is not null`.

## Python / Airflow DAG files

- No unused imports, including scaffold/template boilerplate (e.g. Astro's default `from __future__ import annotations` when nothing in the file uses annotation syntax).
- No dead-code `try/except ImportError` import fallbacks where both branches import the exact same thing. A fallback is only legitimate when the branches import from genuinely different module paths (version compatibility).
- Don't wrap an expression in parentheses (or otherwise split it) just to fit a conventional line-length limit (e.g. Black's 88 characters). Let it run long on one line. Split a line only when it improves readability for some other reason (a long argument list, a complex boolean).
- Don't introduce a module-level variable purely to avoid repeating a literal 2-3 times in one function — explicit, fully-written-out literals are preferred over a variable/dictionary layer of indirection for a small, fixed set of values.

## File & DAG naming

- Check the full resolved name — with whatever prefix/namespace wraps it (environment-variable prefixes like `AIRFLOW_CONN_`, a DAG task's `create_`/`merge_`/`refresh_` prefix, etc.) — for a repeated word before naming something. Drop the redundant part (e.g. an Airflow connection id should be `snowflake`, not `snowflake_conn`, since `AIRFLOW_CONN_` already says "connection").
- DAG task naming for table-building DAGs: see the `create_<table_name>` / `merge_<table_name>` / `refresh_<table_name>` convention under Gold-layer tables above.
- For a table's DAG file and its SQL files, drop the repeated table-name prefix once a folder already provides it. E.g. `include/<table_name>/create.sql`, `include/<table_name>/merge.sql`, `include/<table_name>/test_queries.sql` rather than repeating `<table_name>_` in every filename.

## Column naming conventions

**Booleans end in `_flag`.** Not an `is_`/`has_` prefix.
- Correct: `advisory_flag`, `in_golden_set_flag`
- Existing violations (legacy, not required to rename on sight): `is_subject`, `is_scion_managed`, `is_corporate_record`, `is_unknown_record`, `has_preleasing`, `has_fcr_data` — the `is_`/`has_` prefix is the dominant pattern in [si-dw](https://github.com/TheScionGroup/si-dw) today. New columns use `_flag`; do not add more `is_`/`has_` columns.

**Use `_name` for the human-readable label of an entity**, never the bare entity noun.
- Correct: `property_name`, `market_name` (both already in use — [`dim_properties.property_name`](https://github.com/TheScionGroup/si-dw/blob/master/models/transform/dim_property/dpr_dim_properties.sql), `fcs_fact_chainscale_property_audits.market_name`)
- Incorrect: a column called `property` holding a display string, or `name` with no qualifying prefix once a table has more than one name-like concept. `si_markets.name` is a live example to rename to `market_name` on any new model that surfaces it.

**Use `_datetime` for every timestamp column.** Not `_at`.
- Correct: `created_datetime`, `deleted_datetime`, `updated_datetime`
- Existing violations (legacy): `created_at`, `updated_at`, `deleted_at` are used almost everywhere in [si-dw](https://github.com/TheScionGroup/si-dw) today, including on every raw/source table. New gold-layer models rename these on the way out; silver and bronze layers are not required to rename a straight passthrough of the source column.

**Prefix identifiers with their source system. Never ship a bare `property_id`, `id`, or similar unqualified key on a gold-layer table.**
- Correct: `scion_intelligence_property_id`, `entrata_property_id`, `rate_scraper_property_id`
- This is the single biggest violation found in the current warehouse: `si_properties.id` is exposed as four different names across four different models — `property_id` ([`dim_properties`](https://github.com/TheScionGroup/si-dw/blob/master/models/transform/dim_property/dpr_dim_properties.sql)), `si_property_id` (`fact_competitor_rates`, `fcs_chainscale_avg_rates`), `chainscale_property_id` (`fact_chainscale_property_audits`), and bare `id` at the source layer. All four are the exact same value. See [#11](https://github.com/TheScionGroup/engineering_orchestration/issues/11) for the full trace. A reader should never have to run a join to discover that two columns in two different tables are the same key.

**Avoid abbreviations everywhere — identifiers, file and folder names, DAG and task names, and documentation prose. Spell words out in full.**
- Correct: `scion_intelligence_property_id`, "repository" (not "repo"), "documentation" (not "docs" in prose — [`docs/`](https://github.com/TheScionGroup/engineering_orchestration/tree/main/docs) as a folder name is a path, not prose)
- Incorrect: `si_property_id` — "si" is not self-explanatory to anyone outside the current team, and it already collides with an unrelated `ch_` prefix used by two different vendors in this same warehouse (ChainScale and College House both show up as `ch_*` in different places — see [#11](https://github.com/TheScionGroup/engineering_orchestration/issues/11)'s notes on `ch_property_id`). Spelling the source out in full prevents this kind of collision by construction.
- This is not limited to warehouse columns. The same logic is already codified in the naming rules above for this repository's own connection IDs (don't repeat what the namespace already says, e.g. an Airflow connection id is `snowflake`, not `snowflake_conn`), and it applies to how this document and any other project writing refers to things in prose — "repository," not "repo"; "database," not "db"; "configuration," not "config." A standards document that tells engineers to avoid abbreviations should not itself contain any.

**Calculated/aggregate columns are suffixed with the operation that produced them: `_count`, `_sum`, `_percent`.**
- Correct: `bedroom_types_scraped_count`, `exclusion_sum`, `signed_new_aytd_percent`
- Existing violations — counts: `_count` is otherwise well-established (132 existing uses in [si-dw](https://github.com/TheScionGroup/si-dw)), but plenty of `count(*)`/`count(distinct ...)` results still carry no indicator at all or an inconsistent one: `contract_total`, `incomplete_total`, `observations`, `cnt`, `rate_group_n`, `months_charged`, `leads_eow`, `leads_eos`, `number_of_openings`, `days_in_week`, `n_changes`, `total_props_in_group`, `bedroom_types_scraped`, `academic_years_scraped`, `total_floorplans_scraped`.
- Existing violations — sums: `_sum` is used **nowhere** in [si-dw](https://github.com/TheScionGroup/si-dw) today despite `sum()` being everywhere. Current patterns instead: `_total` (`balance_due_total`), reusing the pre-aggregation column's own name unchanged (`sum(day_value) as day_value`, `sum(bed_count) as bed_count`), or no indicator at all (`month_budget`, `evicted_beds_leased`).
- Existing violations — percentages: two abbreviated spellings already compete for this and both violate the no-abbreviations rule above — `_perc` (87 uses, e.g. `signed_new_aytd_perc`) and `_pct` (7 uses, e.g. `confidence_pct`). Neither is used going forward; spell it out as `_percent`.
- Separately-documented defect, not just a naming gap: `fcs_fact_chainscale_property_audit_attributes.attribute_weight_perc` is suffixed like a percentage but isn't one — per its own doc block it's a raw weight-point value, not a ratio. A false calculation suffix is its own category of violation, distinct from a missing one.

**Table names are singular.**
- Correct: `dim_property`, `dim_market`
- Incorrect: `dim_properties`
- Current state: **every one of the 23 dimension models at the gold ([`models/public`](https://github.com/TheScionGroup/si-dw/tree/master/models/public)) layer in [si-dw](https://github.com/TheScionGroup/si-dw) is plural** — `dim_properties`, `dim_gh_candidates`, `dim_gl_entities`, `dim_property_feeds`, `dim_units`, `dim_contracts`, `dim_customers`, `dim_calendar_events`, `dim_employees`, `dim_market_projects`, `dim_unit_spaces`, `dim_maintenance_requests`, `dim_customer_roles`, `dim_contract_flags`, `dim_dates`, `dim_gl_accounts`, and more. Notably, the underlying **silver-layer folder structure has already moved toward singular in about half of these** — [`dim_property/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_property), [`dim_employee/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_employee), [`dim_contract/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_contract), [`dim_contract_flag/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_contract_flag), [`dim_customer_role/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_customer_role), [`dim_maintenance_request/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_maintenance_request), [`dim_unit/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_unit), [`dim_gl_account/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_gl_account), [`dim_date/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_date), and [`dim_gl_entity/`](https://github.com/TheScionGroup/si-dw/tree/master/models/transform/dim_gl_entity) are all already singular folders — the file inside often still produces a plural model name (e.g. [`dpr_dim_properties.sql`](https://github.com/TheScionGroup/si-dw/blob/master/models/transform/dim_property/dpr_dim_properties.sql) builds `dim_properties`, not `dim_property`, despite living in a singular-named folder). Enforcing this rule is mostly a matter of renaming the final gold-layer model to match the folder it already sits in.

## Why these rules, concretely

[Issue #11 — Create Property Dimension](https://github.com/TheScionGroup/engineering_orchestration/issues/11) traces real violations of these rules against the current warehouse and should be read alongside this one: the `property_id`/`si_property_id`/`chainscale_property_id` naming collision, a meaningless `property_key` surrogate, 17 staff-assignment columns and address fields that don't belong on a property dimension, and several vendor-ID columns (`coupa_id`, `concur_id`, `g4_id`) that don't exist anywhere in the warehouse at all.

## Database & environment structure

Six databases, one per layer × environment: `bronze_test`, `bronze_prod`, `silver_test`, `silver_prod`, `gold_test`, `gold_prod`. Layer and environment are both expressed at the database level, not folded into a schema name or a dbt target suffix.

**Within bronze, every source system gets its own schema** — e.g. `bronze_prod.scion_intelligence`, `bronze_prod.entrata_api`, `bronze_prod.rate_scraper`, `bronze_prod.college_house`, `bronze_prod.greenhouse` — mirrored identically in `bronze_test`. This rule is scoped to bronze; silver stays organized around reusable staging models, not source systems (see Silver-layer tables above), and gold is organized around dimensions and facts (see Gold-layer tables above), not by source.

Current state: a single `RAW` database already does roughly this — about 40 schemas, each one a source system (`SCION_INTELLIGENCE`, `RATE_SCRAPER`, `COLLEGE_HOUSE`, `GREENHOUSE`, `QUALTRICS`, `UKG`, and more). The schema-per-source pattern is mostly already in place; what's missing to reach the target structure:
- **No test/prod split at all today.** One `RAW` database does double duty for every environment, alongside a grab-bag of individual-developer databases (`DBT_JTATE`, `DBT_DHUSSAIN`, `DBT_PTANNER`, `DBT_TREDENCE`) and a shared `SANDBOX` database standing in for what should be a dedicated `bronze_test` (and `silver_test`/`gold_test`).
- **Silver and gold are schemas inside one `ANALYTICS` database (`TRANSFORM` and `PUBLIC`) today, not their own databases.** Migrating means `silver_prod` and `gold_prod` become top-level databases, not schemas nested under `ANALYTICS`.
- **The schema-per-source rule is already being violated in one concrete place.** Entrata's data is split across three separate schemas today — `ENTRATA`, `ENTRATA_API`, and `ENTRATA_DELETED` — instead of one `entrata` schema. Decide whether to consolidate these when migrating into `bronze_prod` rather than carrying the split forward.
