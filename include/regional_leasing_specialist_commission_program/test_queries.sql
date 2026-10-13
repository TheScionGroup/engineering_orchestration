/*
    ad hoc test queries for regional_leasing_specialist_commission_program.
    local/manual use only -- not part of any dag.
    refresh.sql aggregates events and messages into counts/exists flags per contract. these two queries fan that out instead, joining to the same event and message tables without aggregating, so each row is one underlying event/message rather than one contract.
    use them to spot-check a specific contract: confirm the individual event and message rows refresh.sql's counts/exists flags are summarizing actually look right.
*/

--test query 1 -- mirrors the new-contracts query in refresh.sql, but with raw event and message rows instead of aggregated counts/exists flags
select
    lease_start_dates.leasing_academic_year_label as leasing_academic_year,
    approval_dates.academic_year_label as current_academic_year,
    contracts.is_renewal,
    contracts.customer_id,
    contracts.application_id,
    contracts.lease_id,
    contracts.lease_interval_id,
    contracts.application_approved_date,
    contracts.lease_approved_date,
    null as previous_lease_id,
    null as previous_contract_id,
    null as previous_contract_approved_date,
    contracts.lease_interval_type,
    contracts.lease_start_date,
    contracts.lease_end_date,
    contracts.lease_term,
    contracts.first_name,
    contracts.last_name,
    contracts.email,
    contracts.application_status,
    contracts.property_id as si_property_id,
    contracts.entrata_property_id,
    contracts.property_name,
    dim_properties.corporate_sales_specialist_name as regional_leasing_specialist,
    case
        when month(contracts.lease_approved_date) in (8, 9, 10) then 'Q1'
        when month(contracts.lease_approved_date) in (11, 12, 1) then 'Q2'
        when month(contracts.lease_approved_date) in (2, 3, 4) then 'Q3'
        when month(contracts.lease_approved_date) in (5, 6, 7) then 'Q4'
    end as commission_quarter,
    events_leasing_scion.event_datetime,
    events_leasing_scion.event_type,
    events_leasing_scion.event_id,
    events_leasing_scion.agent_name,
    events_leasing_scion.agent_email,
    messages_scion.type as message_type,
    messages_scion.sender_party,
    messages_scion.message
from analytics.public.contracts
join analytics.public.dim_dates as approval_dates
    on approval_dates.date = contracts.lease_approved_date
join analytics.public.dim_dates as current_dates
    on current_dates.date = current_date
    and current_dates.academic_year = approval_dates.academic_year
join analytics.public.dim_dates as lease_start_dates
    on lease_start_dates.date = contracts.lease_start_date
    and lease_start_dates.leasing_academic_year = approval_dates.academic_year + 1
left join analytics.public.dim_properties
    on contracts.entrata_property_id = dim_properties.entrata_property_id
left join scion_elise_data_share.da.events_leasing_scion
    on events_leasing_scion.guest_card_id = contracts.application_id
left join scion_elise_data_share.da.messages_scion
    on messages_scion.event_id = events_leasing_scion.event_id
where contracts.is_approved_lease = 1
and contracts.is_renewal = 0
--and contracts.application_id = 22760539
and contracts.application_id = 21587908
order by events_leasing_scion.event_datetime;


--test query 2 -- mirrors the renewals query in refresh.sql, but with raw event and message rows instead of aggregated counts/exists flags
select
    lease_start_dates.leasing_academic_year_label as leasing_academic_year,
    approval_dates.academic_year_label as current_academic_year,
    contracts.is_renewal,
    contracts.customer_id,
    contracts.application_id,
    contracts.lease_id,
    contracts.lease_interval_id,
    contracts.application_approved_date,
    contracts.lease_approved_date,
    previous_contracts.previous_lease_id,
    previous_contracts.previous_contract_id,
    previous_contracts.previous_contract_approved_date,
    contracts.lease_interval_type,
    contracts.lease_start_date,
    contracts.lease_end_date,
    contracts.lease_term,
    contracts.first_name,
    contracts.last_name,
    contracts.email,
    contracts.application_status,
    contracts.property_id as si_property_id,
    contracts.entrata_property_id,
    contracts.property_name,
    dim_properties.corporate_sales_specialist_name as regional_leasing_specialist,
    case
        when month(contracts.lease_approved_date) in (8, 9, 10) then 'Q1'
        when month(contracts.lease_approved_date) in (11, 12, 1) then 'Q2'
        when month(contracts.lease_approved_date) in (2, 3, 4) then 'Q3'
        when month(contracts.lease_approved_date) in (5, 6, 7) then 'Q4'
    end as commission_quarter,
    events_resident_scion.event_datetime,
    events_resident_scion.event_type,
    events_resident_scion.event_id,
    events_resident_scion.agent_name,
    events_resident_scion.agent_email,
    messages_scion.type as message_type,
    messages_scion.sender_party,
    messages_scion.message
from analytics.public.contracts
left join (
    select
        lease_interval_id,
        lag(lease_id) over (partition by customer_id, property_id order by lease_start_date) as previous_lease_id,
        lag(lease_interval_id) over (partition by customer_id, property_id order by lease_start_date) as previous_contract_id,
        lag(lease_approved_date) over (partition by customer_id, property_id order by lease_start_date) as previous_contract_approved_date
    from analytics.public.contracts
    where is_approved_lease = 1
) as previous_contracts
    on previous_contracts.lease_interval_id = contracts.lease_interval_id
join analytics.public.dim_dates as approval_dates
    on approval_dates.date = contracts.lease_approved_date
join analytics.public.dim_dates as current_dates
    on current_dates.date = current_date
    and current_dates.academic_year = approval_dates.academic_year
join analytics.public.dim_dates as lease_start_dates
    on lease_start_dates.date = contracts.lease_start_date
    and lease_start_dates.leasing_academic_year = approval_dates.academic_year + 1
left join analytics.public.dim_properties
    on contracts.entrata_property_id = dim_properties.entrata_property_id
left join scion_elise_data_share.da.events_resident_scion
    on events_resident_scion.resident_email = contracts.email
    and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
    and events_resident_scion.event_datetime::date > previous_contracts.previous_contract_approved_date
    and events_resident_scion.event_type in ('ai_sent', 'ai_replied', 'ai_follow_up', 'agent_sent', 'agent_replied', 'resident_sent', 'resident_replied')
left join scion_elise_data_share.da.messages_scion
    on messages_scion.event_id = events_resident_scion.event_id
where contracts.lease_end_date > lease_start_dates.season_end
and contracts.is_approved_lease = 1
and contracts.is_renewal = 1
and contracts.application_id = 22679644
--and contracts.application_id = 22515709
--and contracts.application_id = 22760539
order by events_resident_scion.event_datetime;
