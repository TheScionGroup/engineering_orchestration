create or replace table public.regional_leasing_specialist_commission_program as
--query 1 -- new contracts
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
        and events_leasing_scion.event_type in (
            'ai_sent', 'ai_replied', 'ai_follow_up',
            'agent_sent', 'agent_replied',
            'lead_sent', 'lead_replied'
        )
    ) as regional_leasing_specialist_message_count,
    (
        select count(*)
        from scion_elise_data_share.da.events_leasing_scion
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.agent_id is not null
        and events_leasing_scion.event_type in (
            'ai_sent', 'ai_replied', 'ai_follow_up',
            'agent_sent', 'agent_replied',
            'lead_sent', 'lead_replied'
        )
    ) as agent_message_count,
    (
        select count(messages_scion.message)
        from scion_elise_data_share.da.events_leasing_scion
        join scion_elise_data_share.da.messages_scion
            on messages_scion.event_id = events_leasing_scion.event_id
        where events_leasing_scion.guest_card_id = contracts.application_id
        and events_leasing_scion.event_type in (
            'ai_sent', 'ai_replied', 'ai_follow_up',
            'agent_sent', 'agent_replied',
            'lead_sent', 'lead_replied'
        )
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

union all

--query 2 -- renewals
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
        from scion_elise_data_share.da.events_resident_scion
        where events_resident_scion.resident_email = contracts.email
        and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
        and events_resident_scion.event_datetime between contracts.lease_term_start_date and contracts.lease_term_end_date
        and events_resident_scion.agent_email = dim_employees.email
        and events_resident_scion.event_type in (
            'ai_sent', 'ai_replied', 'ai_follow_up',
            'agent_sent', 'agent_replied',
            'resident_sent', 'resident_replied'
        )
    ) as regional_leasing_specialist_message_count,
    (
        select count(*)
        from scion_elise_data_share.da.events_resident_scion
        where events_resident_scion.resident_email = contracts.email
        and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
        and events_resident_scion.event_datetime between contracts.lease_term_start_date and contracts.lease_term_end_date
        and events_resident_scion.agent_id is not null
        and events_resident_scion.event_type in (
            'ai_sent', 'ai_replied', 'ai_follow_up',
            'agent_sent', 'agent_replied',
            'resident_sent', 'resident_replied'
        )
    ) as agent_message_count,
    (
        select count(messages_scion.message)
        from scion_elise_data_share.da.events_resident_scion
        join scion_elise_data_share.da.messages_scion
            on messages_scion.event_id = events_resident_scion.event_id
        where events_resident_scion.resident_email = contracts.email
        and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
        and events_resident_scion.event_datetime between contracts.lease_term_start_date and contracts.lease_term_end_date
        and events_resident_scion.event_type in (
            'ai_sent', 'ai_replied', 'ai_follow_up',
            'agent_sent', 'agent_replied',
            'resident_sent', 'resident_replied'
        )
    ) as message_touchpoint_count,
    null as regional_leasing_specialist_tour_attended,
    null as regional_leasing_specialist_lease_applied,
    null as regional_leasing_specialist_lease_signed
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
and is_renewal = 1

order by application_id;