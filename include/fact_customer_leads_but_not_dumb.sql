create or replace table public.fact_customer_leads_but_not_dumb as (

with lead_data as (
  select
    cached_application_logs.primary_applicant_id,
    cached_application_logs.application_id,
    cached_application_logs.lease_interval_id,
    applicants.customer_id,
    entrata_properties.property_id as scion_property_id,
    cached_application_logs.property_id as entrata_scion_property_id,
    coalesce(
      iff(
        lease_start_windows.end_date - lease_start_windows.start_date < 40,
        dim_dates_for_created_on.leasing_academic_year,
        dim_dates_for_academic_year.academic_year
      ),
      dim_dates_for_created_on.leasing_academic_year
    ) as academic_year,
    min(iff(cached_application_logs.application_stage_id = 1, cached_application_logs.created_on, null)) as guest_card_stg_start_datetime,
    min(iff(cached_application_logs.application_stage_id = 3, cached_application_logs.created_on, null)) as application_stg_start_datetime,
    min(iff(cached_application_logs.application_stage_id = 4 and cached_application_logs.application_status_id in (1), cached_application_logs.created_on, null)) as lease_stg_start_datetime,
    min(iff(cached_application_logs.application_stage_id = 4 and cached_application_logs.application_status_id in (2,3), cached_application_logs.created_on, null)) as signed_stg_start_datetime,
    min(iff(cached_application_logs.application_stage_id = 4 and cached_application_logs.application_status_id in (4), cached_application_logs.created_on, null)) as approved_stg_start_datetime,
    max(iff(cached_application_logs.application_status_id = 6, cached_application_logs.created_on, null)) as cancelled_datetime
  from raw.entrata.cached_application_logs
  inner join raw.entrata.cached_applications on cached_applications.id = cached_application_logs.application_id
  left join raw.entrata.lease_start_windows on lease_start_windows.id = cached_applications.lease_start_window_id
  left join analytics.public.dim_dates as dim_dates_for_academic_year on dim_dates_for_academic_year.date = dateadd(month, -1, lease_start_windows.end_date)
  left join analytics.public.dim_dates as dim_dates_for_created_on on dim_dates_for_created_on.date = (cached_applications.created_on::date + 15)
  inner join raw.entrata.applicants on applicants.id = cached_application_logs.primary_applicant_id
  left join raw.scion_intelligence.entrata_properties on entrata_properties.entrata_id = cached_application_logs.property_id
  -- no "subject = true" property filter here (unlike the production model) -- it would silently
  -- drop one of our known test cases (customer 29940833's property is not flagged subject) and
  -- isn't needed just to prove the grain fix.
  where cached_application_logs.lease_interval_type_id = 1   -- applications only, not transfers/renewals
    and applicants.customer_id is not null
    -- TEST-CASE FILTER: verified against live data, while we validate the grain fix.
    -- Remove this filter for a full reload.
--     and applicants.customer_id in (
--       30028132,  -- genuine duplicate: 2 different primary_applicant_ids, same property, same academic_year -- this is the bug
--       29940833   -- baseline: single long-running application (primary_applicant_id 19002825), no duplication expected
--       -- add more test customer_ids here, one per line, as more cases are found
--     )
  group by all
)

select
  customer_id,
  scion_property_id,
  entrata_scion_property_id,
  academic_year,
  primary_applicant_id,
  application_id,
  lease_interval_id as lead_lease_interval_id,
  array_agg(distinct primary_applicant_id) over (partition by customer_id, scion_property_id, academic_year) as primary_applicant_ids,
  array_agg(distinct application_id) over (partition by customer_id, scion_property_id, academic_year) as application_ids,
  array_agg(distinct lease_interval_id) over (partition by customer_id, scion_property_id, academic_year) as lease_interval_ids,
  array_size(array_agg(distinct application_id) over (partition by customer_id, scion_property_id, academic_year)) as application_count,
  case
    when cancelled_datetime is not null then 'Cancelled'
    when approved_stg_start_datetime is not null then 'Approved'
    when signed_stg_start_datetime is not null then 'Signed'
    when lease_stg_start_datetime is not null then 'Lease Started' --TODO: what does this actually mean?
    when application_stg_start_datetime is not null then 'Application'
    when guest_card_stg_start_datetime is not null then 'Guest Card'
    else 'Unknown'
  end as lead_status,
  coalesce(
    guest_card_stg_start_datetime::date,
    application_stg_start_datetime::date,
    lease_stg_start_datetime::date,
    signed_stg_start_datetime::date,
    approved_stg_start_datetime::date
  ) as lead_start_date,
  guest_card_stg_start_datetime,
  application_stg_start_datetime,
  lease_stg_start_datetime,
  signed_stg_start_datetime,
  approved_stg_start_datetime,
  cancelled_datetime
from lead_data
-- grain fix: collapse to customer_id + scion_property_id + academic_year (not primary_applicant_id,
-- which is per-application and duplicates the grain whenever a customer reapplies).
-- the furthest-progressed application wins the singular ids/status; every applicant/application/
-- lease-interval id tied to the grain is still kept above via array_agg.
qualify row_number() over (
  partition by customer_id, scion_property_id, academic_year
  order by
    case
      when approved_stg_start_datetime is not null then 5
      when signed_stg_start_datetime is not null then 4
      when lease_stg_start_datetime is not null then 3
      when application_stg_start_datetime is not null then 2
      when guest_card_stg_start_datetime is not null then 1
      else 0
    end desc,
    application_id desc
) = 1

)



--IF NOT NULL --> GRAIN VIOLATION
-- select
--   customer_id,
--   scion_property_id,
--   academic_year,
--   count(*) as row_count
-- from dbt_jtate.public.fact_customer_leads_but_not_dumb
-- group by customer_id, scion_property_id, academic_year
-- having count(*) > 1
-- order by row_count desc;


/*

 great, I need to understand the difference between customer_id and primary_applicant_id

- customer_id (from raw.entrata.customers, surfaced via raw.entrata.applicants.customer_id) is the persistent identity for a person — it stays the same across every application, lease, or reapplication they ever have with Scion, at any property, in any year.

- primary_applicant_id (raw.entrata.applicants.id) is a record tied to one specific application process. Entrata creates a new applicant record every time someone goes through a new application — including reapplying for the same property in the same year after cancelling.
 */


/* Dealing with application_stg_start_datetime < guest_card_stg_start_datetime */
select *
from public.fact_customer_leads_but_not_dumb
where application_stg_start_datetime < guest_card_stg_start_datetime




