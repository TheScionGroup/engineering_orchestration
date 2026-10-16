truncate table public.regional_leasing_specialist_commission_program;

insert into public.regional_leasing_specialist_commission_program
with active_regional_leasing_specialists as (
    --dedupes to one row per person before the touchpoint CTEs below so those joins never fan out a contract across duplicate employment rows
    select distinct
        dim_employees.full_name,
        dim_employees.email
    from analytics.public.dim_employees
    join analytics.public.fact_employments
        on fact_employments.employee_key = dim_employees.employee_key
    where fact_employments.position_name = 'Regional Leasing Specialist'
    and fact_employments.is_current_role = 1
    and dim_employees.employee_status = 'Active'
)

(
    --query 1 -- new contracts
    with new_contract_touchpoints as (
        --one row per application x regional leasing specialist who messaged it
        select
            contracts.application_id as guest_card_id,
            active_regional_leasing_specialists.full_name,
            count(messages_scion.message) as touchpoint_count,
            row_number() over (
                partition by contracts.application_id
                order by count(messages_scion.message) desc, active_regional_leasing_specialists.full_name
            ) as touchpoint_rank,
            row_number() over (
                partition by contracts.application_id
                order by max(events_leasing_scion.event_datetime) desc, active_regional_leasing_specialists.full_name
            ) as recency_rank,
            max(events_leasing_scion.event_datetime) as last_touchpoint_datetime
        from analytics.public.contracts
        join scion_elise_data_share.da.events_leasing_scion
            on events_leasing_scion.guest_card_id = contracts.application_id
            and events_leasing_scion.event_datetime between ( --floor is the current-academic-year start
                --dim_dates has no academic_year_start column (unlike season_start/season_end)
                select min(dim_dates.date) over (partition by dim_dates.academic_year)
                from analytics.public.dim_dates
                qualify dim_dates.date = current_date
            ) and contracts.lease_approved_date --ceiling is the contract's approved date, so touchpoint counts lock in at approval instead of still growing from messages sent afterward
        join scion_elise_data_share.da.messages_scion
            on messages_scion.event_id = events_leasing_scion.event_id
        join active_regional_leasing_specialists
            on active_regional_leasing_specialists.email = events_leasing_scion.agent_email
        where contracts.is_approved_lease = 1
        and contracts.is_renewal = 0
        group by contracts.application_id, active_regional_leasing_specialists.full_name
    )
    select
        lease_start_dates.leasing_academic_year_label as leasing_academic_year,
        approval_dates.academic_year_label as current_academic_year,
        contracts.is_renewal,
        contracts.customer_id,
        contracts.application_id,
        contracts.lease_id,
        contracts.lease_interval_id as contract_id,
        contracts.application_approved_date,
        contracts.lease_approved_date as contract_approved_date,
        contracts.prelease_start_date as contract_signed_date,
        --new contracts should not have previous lease and contract information
        null as previous_lease_id,
        null as previous_contract_id,
        null as previous_contract_approved_date,
        contracts.lease_interval_type as contract_type,
        contracts.lease_start_date as contract_start_date,
        contracts.lease_end_date as contract_end_date,
        contracts.lease_term as contract_term,
        contracts.first_name as customer_first_name,
        contracts.last_name as customer_last_name,
        contracts.email as customer_email,
        contracts.application_status as contract_status,
        contracts.property_id as si_property_id,
        contracts.entrata_property_id,
        contracts.property_name,
        dim_properties.corporate_sales_specialist_name as property_leasing_specialist_name,
        case --these are custom quarters defined in the requirements
            when month(contracts.lease_approved_date) in (8, 9, 10) then 'Q1'
            when month(contracts.lease_approved_date) in (11, 12, 1) then 'Q2'
            when month(contracts.lease_approved_date) in (2, 3, 4) then 'Q3'
            when month(contracts.lease_approved_date) in (5, 6, 7) then 'Q4'
        end as commission_quarter,
        most_touchpoints.full_name as most_touchpoints_regional_leasing_specialist_name,
        most_touchpoints.touchpoint_count as most_touchpoints_message_count,
        second_most_touchpoints.full_name as second_most_touchpoints_regional_leasing_specialist_name,
        second_most_touchpoints.touchpoint_count as second_most_touchpoints_message_count,
        last_touchpoint.full_name as last_touchpoint_regional_leasing_specialist_name,
        datediff('day', last_touchpoint.last_touchpoint_datetime, contracts.lease_approved_date) as last_regional_leasing_specialist_touchpoint_to_contract_approved_days,
        (
           select max_by(events_leasing_scion.conversation_link, events_leasing_scion.event_datetime)
            from scion_elise_data_share.da.events_leasing_scion
            where events_leasing_scion.guest_card_id = contracts.application_id
            and events_leasing_scion.conversation_link is not null
        ) as conversation_link
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
    left join new_contract_touchpoints as most_touchpoints
        on most_touchpoints.guest_card_id = contracts.application_id
        and most_touchpoints.touchpoint_rank = 1
    left join new_contract_touchpoints as second_most_touchpoints
        on second_most_touchpoints.guest_card_id = contracts.application_id
        and second_most_touchpoints.touchpoint_rank = 2
    left join new_contract_touchpoints as last_touchpoint
        on last_touchpoint.guest_card_id = contracts.application_id
        and last_touchpoint.recency_rank = 1
    where contracts.is_approved_lease = 1 --this is garbage naming. this actually indicates that a contract, NOT a lease, is approved
    and contracts.is_renewal = 0 --indicates a new contract
    and contracts.lease_interval_type <> 'Transfer'
    and contracts.lease_term not in ('Immediate Move-in', 'Group', 'Spring-Summer')
)

union all

(
    --query 2 -- renewals
    with renewal_touchpoints as (
        select
            contracts.lease_interval_id,
            active_regional_leasing_specialists.full_name,
            count(messages_scion.message) as touchpoint_count,
            row_number() over (
                partition by contracts.lease_interval_id
                order by count(messages_scion.message) desc, active_regional_leasing_specialists.full_name
            ) as touchpoint_rank,
            row_number() over (
                partition by contracts.lease_interval_id
                order by max(events_resident_scion.event_datetime) desc, active_regional_leasing_specialists.full_name
            ) as recency_rank,
            max(events_resident_scion.event_datetime) as last_touchpoint_datetime
        from analytics.public.contracts
        join scion_elise_data_share.da.events_resident_scion
            on events_resident_scion.resident_email = contracts.email
            and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
            and events_resident_scion.event_datetime::date between (
                select min(dim_dates.date) over (partition by dim_dates.academic_year)
                from analytics.public.dim_dates
                qualify dim_dates.date = current_date
            ) and contracts.lease_approved_date
        join scion_elise_data_share.da.messages_scion
            on messages_scion.event_id = events_resident_scion.event_id
        join active_regional_leasing_specialists
            on active_regional_leasing_specialists.email = events_resident_scion.agent_email
        where contracts.is_approved_lease = 1
        and contracts.is_renewal = 1
        group by contracts.lease_interval_id, active_regional_leasing_specialists.full_name
    )
    select
        lease_start_dates.leasing_academic_year_label as leasing_academic_year,
        approval_dates.academic_year_label as current_academic_year,
        contracts.is_renewal,
        contracts.customer_id,
        contracts.application_id,
        contracts.lease_id,
        contracts.lease_interval_id as contract_id,
        contracts.application_approved_date,
        contracts.lease_approved_date as contract_approved_date,
        contracts.prelease_start_date as contract_signed_date,
        previous_contracts.previous_lease_id,
        previous_contracts.previous_contract_id,
        previous_contracts.previous_contract_approved_date,
        contracts.lease_interval_type as contract_type,
        contracts.lease_start_date as contract_start_date,
        contracts.lease_end_date as contract_end_date,
        contracts.lease_term as contract_term,
        contracts.first_name as customer_first_name,
        contracts.last_name as customer_last_name,
        contracts.email as customer_email,
        contracts.application_status as contract_status,
        contracts.property_id as si_property_id,
        contracts.entrata_property_id,
        contracts.property_name,
        dim_properties.corporate_sales_specialist_name as property_leasing_specialist_name,
        case
            when month(contracts.lease_approved_date) in (8, 9, 10) then 'Q1'
            when month(contracts.lease_approved_date) in (11, 12, 1) then 'Q2'
            when month(contracts.lease_approved_date) in (2, 3, 4) then 'Q3'
            when month(contracts.lease_approved_date) in (5, 6, 7) then 'Q4'
        end as commission_quarter,
        most_touchpoints.full_name as most_touchpoints_regional_leasing_specialist_name,
        most_touchpoints.touchpoint_count as most_touchpoints_message_count,
        second_most_touchpoints.full_name as second_most_touchpoints_regional_leasing_specialist_name,
        second_most_touchpoints.touchpoint_count as second_most_touchpoints_message_count,
        last_touchpoint.full_name as last_touchpoint_regional_leasing_specialist_name,
        datediff('day', last_touchpoint.last_touchpoint_datetime, contracts.lease_approved_date) as last_regional_leasing_specialist_touchpoint_to_contract_approved_days,
        (
            --events_resident_scion has no conversation_link column; reconstructed from messages_scion.mc_id using the same url pattern events_leasing_scion.conversation_link already uses
            select max_by('https://app.meetelise.com/conversations?mcId=' || messages_scion.mc_id, events_resident_scion.event_datetime)
            from scion_elise_data_share.da.events_resident_scion
            join scion_elise_data_share.da.messages_scion
                on messages_scion.event_id = events_resident_scion.event_id
            where events_resident_scion.resident_email = contracts.email
            and try_to_number(events_resident_scion.external_building_id) = contracts.entrata_property_id
            and messages_scion.mc_id is not null
        ) as conversation_link
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
    left join renewal_touchpoints as most_touchpoints
        on most_touchpoints.lease_interval_id = contracts.lease_interval_id
        and most_touchpoints.touchpoint_rank = 1
    left join renewal_touchpoints as second_most_touchpoints
        on second_most_touchpoints.lease_interval_id = contracts.lease_interval_id
        and second_most_touchpoints.touchpoint_rank = 2
    left join renewal_touchpoints as last_touchpoint
        on last_touchpoint.lease_interval_id = contracts.lease_interval_id
        and last_touchpoint.recency_rank = 1
    where contracts.lease_end_date > lease_start_dates.season_end --excludes short extensions that don't count as a full renewal
    and contracts.is_approved_lease = 1
    and contracts.is_renewal = 1 --indicates a renewed contract
    and contracts.lease_interval_type <> 'Transfer'
    and contracts.lease_term not in ('Immediate Move-in', 'Group', 'Spring-Summer')
)
;
