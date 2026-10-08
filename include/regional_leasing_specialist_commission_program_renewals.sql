-- rls commission log: 2027/2028 leasing-season commission year
-- (aug 1, 2026 - jul 31, 2027 per commission program guidelines).
--
-- 2. renewals (Renewal) → regional_leasing_specialist_commission_program_renewals ($3)
-- final/production version run by dags/rls_commission_log.py. for ad hoc
-- exploration, use include/rls_commission_log.sql instead -- that file is
-- not run by any dag.
--
-- same rls_roster definition, property->rls attribution, and known
-- limitations as regional_leasing_specialist_commission_program.sql (see
-- that file's header). no events_leasing_scion/messages_scion bridge on
-- this statement yet -- elise activity join is new-contracts only for now.
create or replace table public.regional_leasing_specialist_commission_program_renewals as
with rls_roster as (
    select
        dim_employees.employee_key,
        dim_employees.full_name as employee_name,
        lower(trim(dim_employees.email)) as employee_email,
        fact_employments.position_name as title,
        dim_properties.property_id,
        dim_properties.property_name
    from public.dim_employees
    join public.fact_employments
        on fact_employments.employee_key = dim_employees.employee_key
    left join public.dim_properties
        on dim_properties.corporate_sales_specialist_id = dim_employees.si_user_id
    where fact_employments.position_name = 'Regional Leasing Specialist'
      and fact_employments.is_current_role = 1
      and dim_employees.employee_status = 'Active'
)
select
    contracts.lease_interval_type,
    contracts.lease_id,
    contracts.contract_key,
    contracts.property_id,
    contracts.property_name,
    contracts.customer_id,
    contracts.full_name,
    contracts.floorplan_id,
    contracts.floorplan_name,
    contracts.lease_start_date,
    contracts.lease_end_date,
    contracts.lease_term_start_date,
    contracts.lease_term_end_date,
    contracts.lease_approved_date,
    contracts.current_lease_status,
    contracts.move_in_date,
    case
        when contracts.lease_approved_date between '2026-08-01' and '2026-10-31 23:59:59.999' then 'Q1'
        when contracts.lease_approved_date between '2026-11-01' and '2027-01-31 23:59:59.999' then 'Q2'
        when contracts.lease_approved_date between '2027-02-01' and '2027-04-30 23:59:59.999' then 'Q3'
        when contracts.lease_approved_date between '2027-05-01' and '2027-07-31 23:59:59.999' then 'Q4'
    end as commission_quarter,
    3 as commission_amount,
    rls_roster.employee_name as matched_rls_name,
    rls_roster.employee_email as matched_rls_email,
    rls_roster.title as matched_rls_title
from public.contracts
left join rls_roster
    on rls_roster.property_id = contracts.property_id
where contracts.is_approved_lease = 1
  and contracts.lease_interval_type = 'Renewal'
  and contracts.lease_approved_date between '2026-08-01' and '2027-07-31'
order by contracts.lease_approved_date;
