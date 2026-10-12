truncate table public.regional_leasing_specialist_commission_program;

insert into public.regional_leasing_specialist_commission_program
--query 1 -- new contracts
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
    --new contracts should not have previous lease and contract information
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
    case --these are custom quarters defined in the requirements
        when month(contracts.lease_approved_date) in (8, 9, 10) then 'Q1'
        when month(contracts.lease_approved_date) in (11, 12, 1) then 'Q2'
        when month(contracts.lease_approved_date) in (2, 3, 4) then 'Q3'
        when month(contracts.lease_approved_date) in (5, 6, 7) then 'Q4'
    end as commission_quarter,
    (
        select count(*)
        from scion_elise_data_share.da.events_leasing_scion
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.agent_email = dim_employees.email
        and events_leasing_scion.event_type in ('ai_sent', 'ai_replied', 'ai_follow_up', 'agent_sent', 'agent_replied', 'lead_sent', 'lead_replied')
    ) as regional_leasing_specialist_message_count,
    (
        select count(*)
        from scion_elise_data_share.da.events_leasing_scion
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.agent_id is not null
        and events_leasing_scion.event_type in ('ai_sent', 'ai_replied', 'ai_follow_up', 'agent_sent', 'agent_replied', 'lead_sent', 'lead_replied')
    ) as agent_message_count,
    (
        select count(messages_scion.message)
        from scion_elise_data_share.da.events_leasing_scion
        join scion_elise_data_share.da.messages_scion
            on messages_scion.event_id = events_leasing_scion.event_id
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.event_type in ('ai_sent', 'ai_replied', 'ai_follow_up', 'agent_sent', 'agent_replied', 'lead_sent', 'lead_replied')
    ) as message_touchpoint_count,
    exists (
        select 1
        from scion_elise_data_share.da.events_leasing_scion
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.agent_email = dim_employees.email
        and events_leasing_scion.event_type = 'tour_attended'
    ) as regional_leasing_specialist_tour_attended,
    exists (
        select 1
        from scion_elise_data_share.da.events_leasing_scion
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.agent_email = dim_employees.email
        and events_leasing_scion.event_type = 'lease_applied'
    ) as regional_leasing_specialist_lease_applied,
    exists (
        select 1
        from scion_elise_data_share.da.events_leasing_scion
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.agent_email = dim_employees.email
        and events_leasing_scion.event_type = 'lease_signed'
    ) as regional_leasing_specialist_lease_signed
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
left join analytics.public.dim_employees
    on dim_properties.corporate_sales_specialist_id = dim_employees.si_user_id
left join analytics.public.fact_employments
    on dim_employees.employee_key = fact_employments.employee_key
where contracts.is_approved_lease = 1 --this is garbage naming. this actually indicates that a contract, NOT a lease, is approved
and contracts.is_renewal = 0 --indicates a new contract

union all

--query 2 -- renewals
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
    (
        select count(*)
        from scion_elise_data_share.da.events_resident_scion
        where events_resident_scion.resident_email = contracts.email
        and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
        and events_resident_scion.event_datetime::date > previous_contracts.previous_contract_approved_date
        and events_resident_scion.agent_email = dim_employees.email
        and events_resident_scion.event_type in ('ai_sent', 'ai_replied', 'ai_follow_up', 'agent_sent', 'agent_replied', 'resident_sent', 'resident_replied')
    ) as regional_leasing_specialist_message_count,
    (
        select count(*)
        from scion_elise_data_share.da.events_resident_scion
        where events_resident_scion.resident_email = contracts.email
        and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
        and events_resident_scion.event_datetime::date > previous_contracts.previous_contract_approved_date
        and events_resident_scion.agent_id is not null
        and events_resident_scion.event_type in ('ai_sent', 'ai_replied', 'ai_follow_up', 'agent_sent', 'agent_replied', 'resident_sent', 'resident_replied')
    ) as agent_message_count,
    (
        select count(messages_scion.message)
        from scion_elise_data_share.da.events_resident_scion
        join scion_elise_data_share.da.messages_scion
            on messages_scion.event_id = events_resident_scion.event_id
        where events_resident_scion.resident_email = contracts.email
        and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
        and events_resident_scion.event_datetime::date > previous_contracts.previous_contract_approved_date
        and events_resident_scion.event_type in ('ai_sent', 'ai_replied', 'ai_follow_up', 'agent_sent', 'agent_replied', 'resident_sent', 'resident_replied')
    ) as message_touchpoint_count,
    null as regional_leasing_specialist_tour_attended,
    null as regional_leasing_specialist_lease_applied,
    null as regional_leasing_specialist_lease_signed
from analytics.public.contracts
left join ( --gets previous lease and contract information
    select
        lease_interval_id,
        lag(lease_id) over (partition by customer_id, property_id order by lease_start_date) as previous_lease_id,
        lag(lease_interval_id) over (partition by customer_id, property_id order by lease_start_date) as previous_contract_id,
        lag(lease_approved_date) over (partition by customer_id, property_id order by lease_start_date) as previous_contract_approved_date
    from analytics.public.contracts
    where is_approved_lease = 1
) as previous_contracts
    on previous_contracts.lease_interval_id = contracts.lease_interval_id
join analytics.public.dim_dates as approval_dates --academic year the contract was approved
    on approval_dates.date = contracts.lease_approved_date
join analytics.public.dim_dates as current_dates --limits to contracts approved in the current academic year
    on current_dates.date = current_date
    and current_dates.academic_year = approval_dates.academic_year
join analytics.public.dim_dates as lease_start_dates --leasing season is one year ahead of the approval academic year
    on lease_start_dates.date = contracts.lease_start_date
    and lease_start_dates.leasing_academic_year = approval_dates.academic_year + 1
left join analytics.public.dim_properties
    on contracts.entrata_property_id = dim_properties.entrata_property_id
left join analytics.public.dim_employees
    on dim_properties.corporate_sales_specialist_id = dim_employees.si_user_id
left join analytics.public.fact_employments
    on dim_employees.employee_key = fact_employments.employee_key
where contracts.lease_end_date > lease_start_dates.season_end --excludes short extensions that don't count as a full renewal
and contracts.is_approved_lease = 1
and contracts.is_renewal = 1 --indicates a renewed contract
;