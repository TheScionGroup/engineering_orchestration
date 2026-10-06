


--This is an example of a regional leasing specialist not doing anything
--
-- unioned in two branches because new leases and renewals bridge to elise
-- activity through different tables: events_leasing_scion carries the
-- prospect/guest-card pipeline (new leases only -- confirmed 0 renewal
-- contracts in the season window match it), while events_resident_scion
-- carries the existing-resident pipeline (confirmed 12,808 of 12,824 renewal
-- contracts match it by email, 12,504 when also scoped to the same
-- building). keyed by guest_card_id = application_id for new leases, by
-- resident_email + external_building_id for renewals -- there is no
-- resident-side application_id to join on directly.
select
    dim_employees.first_name,
    dim_employees.last_name,
    dim_employees.email,
    events_leasing_scion.external_building_id as entrata_property_id,
    events_leasing_scion.guest_card_id as scion_person_id,
    events_leasing_scion.lead_first_name,
    events_leasing_scion.lead_last_name,
    events_leasing_scion.lead_email,
    events_leasing_scion.channel,
    events_leasing_scion.agent_id,
    events_leasing_scion.agent_name,
    events_leasing_scion.agent_email,
    events_leasing_scion.event_type,
    events_leasing_scion.event_datetime,
    messages_scion.message,
    messages_scion.sender_party,
    contracts.lease_id,
    contracts.application_id,
    contracts.application_completed_date as signed_date,
    contracts.lease_approved_date as approved_date,
    contracts.lease_start_date,
    contracts.lease_end_date,
    contracts.is_renewal
from analytics.public.contracts
left join analytics.public.dim_properties
    on contracts.entrata_property_id = dim_properties.entrata_property_id
left join analytics.public.dim_employees
    on dim_properties.corporate_sales_specialist_id = dim_employees.si_user_id
left join analytics.public.fact_employments
    on dim_employees.employee_key = fact_employments.employee_key
left join scion_elise_data_share.da.events_leasing_scion
    on contracts.application_id = events_leasing_scion.guest_card_id
left join scion_elise_data_share.da.messages_scion
    on messages_scion.event_id = events_leasing_scion.event_id
where true
    -- and fact_employments.position_name = 'Regional Leasing Specialist'
    -- 27/28 leasing-season window per commission program guidelines (aug 1,
    -- 2026 start) -- same hardcoded window used in the main commission query.
    --and contracts.lease_approved_date between '2026-08-01' and '2027-07-31'
    --and fact_employments.is_current_role = 1
    --and dim_employees.employee_status = 'Active'
    --and events_leasing_scion.agent_id is not null
    --and dim_employees.email = events_leasing_scion.agent_email
    --and contracts.application_id = 20195637
    and contracts.application_id = 22645327
    and contracts.customer_id = 31997322
    --and contracts.is_renewal = 0

union all

select
    dim_employees.first_name,
    dim_employees.last_name,
    dim_employees.email,
    events_resident_scion.external_building_id as entrata_property_id,
    events_resident_scion.resident_id as scion_person_id,
    events_resident_scion.resident_first_name as lead_first_name,
    events_resident_scion.resident_last_name as lead_last_name,
    events_resident_scion.resident_email as lead_email,
    null as channel,
    events_resident_scion.agent_id,
    events_resident_scion.agent_name,
    events_resident_scion.agent_email,
    events_resident_scion.event_type,
    events_resident_scion.event_datetime,
    messages_scion.message,
    messages_scion.sender_party,
    contracts.lease_id,
    contracts.application_id,
    contracts.application_completed_date as signed_date,
    contracts.lease_approved_date as approved_date,
    contracts.lease_start_date,
    contracts.lease_end_date,
    contracts.is_renewal
from analytics.public.contracts
left join analytics.public.dim_properties
    on contracts.entrata_property_id = dim_properties.entrata_property_id
left join analytics.public.dim_employees
    on dim_properties.corporate_sales_specialist_id = dim_employees.si_user_id
left join analytics.public.fact_employments
    on dim_employees.employee_key = fact_employments.employee_key
left join scion_elise_data_share.da.events_resident_scion
    on lower(trim(events_resident_scion.resident_email)) = lower(trim(contracts.email))
    and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
left join scion_elise_data_share.da.messages_scion
    on messages_scion.event_id = events_resident_scion.event_id
where fact_employments.position_name = 'Regional Leasing Specialist'
    and fact_employments.is_current_role = 1
    and dim_employees.employee_status = 'Active'
    and events_resident_scion.agent_id is not null
    and dim_employees.email = events_resident_scion.agent_email
    --and contracts.is_renewal = 1
    and application_id = 22645327
order by
    scion_person_id,
    event_datetime

-- active regional leasing specialists with their matching elise_user_id
-- (null when the rls has no match). users_scion has one row per
-- elise_user_id per property (building_name/external_property_id) -- 31,262
-- rows / 2,926 distinct emails live, confirmed elise_user_id is consistent
-- per non-null email -- so it's deduped here before the join rather than
-- fanning out the join and collapsing it after.
with distinct_elise_users as (
    select distinct user_email, elise_user_id
    from scion_elise_data_share.da.users_scion
)
select
    dim_employees.employee_key,
    dim_employees.first_name,
    dim_employees.last_name,
    dim_employees.email,
    distinct_elise_users.elise_user_id
from analytics.public.dim_employees
join analytics.public.fact_employments
    on fact_employments.employee_key = dim_employees.employee_key
left join distinct_elise_users
    on lower(trim(distinct_elise_users.user_email)) = lower(trim(dim_employees.email))
where fact_employments.position_name = 'Regional Leasing Specialist'
    and fact_employments.is_current_role = 1
    and dim_employees.employee_status = 'Active'
order by dim_employees.last_name, dim_employees.first_name





/*
 trying to understand the customer journey from the perspective of public.contracts
 */

select
    contracts.is_renewal,
    contracts.customer_id,
    contracts.application_id,
    contracts.lease_id,
    contracts.lease_interval_id,
    contracts.application_approved_date,
    contracts.lease_approved_date,
    contracts.lease_interval_type,
    contracts.lease_start_date,
    contracts.lease_end_date,
    contracts.lease_term,
    contracts.first_name,
    contracts.last_name,
    contracts.application_status,
    contracts.property_id as si_property_id,
    contracts.entrata_property_id,
    contracts.property_name,
    dim_properties.corporate_sales_specialist_name,
    events_leasing_scion.channel,
    events_leasing_scion.agent_id,
    events_leasing_scion.agent_name,
    events_leasing_scion.agent_email,
    events_leasing_scion.event_type,
    events_leasing_scion.event_datetime,
    messages_scion.message,
    messages_scion.sender_party
from analytics.public.contracts
left join analytics.public.dim_properties
    on contracts.entrata_property_id = dim_properties.entrata_property_id
left join analytics.public.dim_employees
    on dim_properties.corporate_sales_specialist_id = dim_employees.si_user_id
left join analytics.public.fact_employments
    on dim_employees.employee_key = fact_employments.employee_key
left join scion_elise_data_share.da.events_leasing_scion
    on contracts.application_id = events_leasing_scion.guest_card_id
left join scion_elise_data_share.da.messages_scion
    on messages_scion.event_id = events_leasing_scion.event_id
where true
and contracts.lease_start_date between (
        select season_start
        from analytics.public.dim_dates
        where leasing_academic_year_label = '27/28'
        limit 1
    ) and (
        select season_end
        from analytics.public.dim_dates
        where leasing_academic_year_label = '27/28'
        limit 1
    )
and contracts.lease_approved_date between (
        select min(date)
        from analytics.public.dim_dates
        where academic_year_label = '26/27'
    ) and (
        select max(date)
        from analytics.public.dim_dates
        where academic_year_label = '26/27'
    )
and customer_id in (
-- 31997322, -- successful renewal contract
-- 32213426 -- successful new contract but not in the correct academic year
-- 31533574 -- successful new contract and in the correct academic year
32351586
)
and contracts.application_status = 'Approved'
--and application_approved_date = '1900-01-01'
and contracts.is_renewal = 0
and event_type not in ('state', 'message_handoff', 'first_lead_engagement')
--and events_leasing_scion.agent_id is not null

order by
    contracts.application_id,
    events_leasing_scion.event_datetime

-- count of distinct new approved contracts - 2097
select
    contracts.is_renewal,
    contracts.customer_id,
    contracts.application_id,
    contracts.lease_id,
    contracts.lease_interval_id,
    contracts.application_approved_date,
    contracts.lease_approved_date,
    contracts.lease_interval_type,
    contracts.lease_start_date,
    contracts.lease_end_date,
    contracts.lease_term,
    contracts.first_name,
    contracts.last_name,
    contracts.application_status,
    contracts.property_id as si_property_id,
    contracts.entrata_property_id,
    contracts.property_name
from analytics.public.contracts
where true
and contracts.lease_start_date between (
        select season_start
        from analytics.public.dim_dates
        where leasing_academic_year_label = '27/28'
        limit 1
    ) and (
        select season_end
        from analytics.public.dim_dates
        where leasing_academic_year_label = '27/28'
        limit 1
    )
and contracts.lease_approved_date between (
        select min(date)
        from analytics.public.dim_dates
        where academic_year_label = '26/27'
    ) and (
        select max(date)
        from analytics.public.dim_dates
        where academic_year_label = '26/27'
    )
-- and customer_id in (
-- 31997322, -- successful renewal contract
-- 32213426 -- successful new contract but not in the correct academic year
-- 31533574 -- successful new contract and in the correct academic year
and customer_id = 32351586
-- )
and contracts.application_status = 'Approved'
--and application_approved_date = '1900-01-01'
and is_renewal = 0

order by
    contracts.application_id

--Checks application IDs are unique
--Are lead_ids unique?
--Are lease_interval_ids unique?
--Why are unit IDs not populated for some of these?
--How are application approved dates = 1900-01-01




select
    contracts.is_renewal,
    contracts.customer_id,
    contracts.application_id,
    contracts.lease_id,
    contracts.lease_interval_id,
    contracts.application_approved_date,
    contracts.lease_approved_date,
    contracts.lease_interval_type,
    contracts.lease_start_date,
    contracts.lease_end_date,
    contracts.lease_term,
    contracts.first_name,
    contracts.last_name,
    contracts.application_status,
    contracts.property_id as si_property_id,
    contracts.entrata_property_id,
    contracts.property_name,
    dim_properties.corporate_sales_specialist_name as regional_leasing_specialist,
    (
        select count(*)
        from scion_elise_data_share.da.events_leasing_scion
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.agent_email = dim_employees.email
    ) as regional_leasing_specialist_event_count,
    (
        select count(*)
        from scion_elise_data_share.da.events_leasing_scion
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.agent_id is not null
    ) as agent_event_count,
    (
        select count(distinct messages_scion.created_at, messages_scion.message)
        from scion_elise_data_share.da.events_leasing_scion
        join scion_elise_data_share.da.messages_scion
            on messages_scion.event_id = events_leasing_scion.event_id
        where events_leasing_scion.guest_card_id = contracts.application_id
    ) as message_touchpoint_count
from analytics.public.contracts
left join analytics.public.dim_properties
    on contracts.entrata_property_id = dim_properties.entrata_property_id
left join analytics.public.dim_employees
    on dim_properties.corporate_sales_specialist_id = dim_employees.si_user_id
left join analytics.public.fact_employments
    on dim_employees.employee_key = fact_employments.employee_key
where true
and contracts.lease_start_date between (
        select season_start from analytics.public.dim_dates where leasing_academic_year_label = '27/28' limit 1
    ) and (
        select season_end from analytics.public.dim_dates where leasing_academic_year_label = '27/28' limit 1
    )
and contracts.lease_approved_date between (
        select min(date) from analytics.public.dim_dates where academic_year_label = '26/27'
    ) and (
        select max(date) from analytics.public.dim_dates where academic_year_label = '26/27'
    )
and contracts.application_status = 'Approved'
and is_renewal = 0
order by contracts.application_id




select
    events_leasing_scion.event_id,
    agent_name,
    agent_email,
    event_type,
    messages_scion.*
from scion_elise_data_share.da.events_leasing_scion
join scion_elise_data_share.da.messages_scion
    on messages_scion.event_id = events_leasing_scion.event_id
where true
    and events_leasing_scion.guest_card_id = 20693186
    and event_type not in ('message_handoff', 'first_lead_engagement')
order by events_leasing_scion.event_datetime



select event_type, count(*)
from scion_elise_data_share.da.events_leasing_scion
group by 1 order by 2 desc