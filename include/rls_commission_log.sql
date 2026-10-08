-- rls commission log: 2027/2028 leasing-season commission year
-- (aug 1, 2026 - jul 31, 2027 per commission program guidelines).
-- one-off validation queries, not yet wired into a dag.
--
-- two statements in this file so they can be run and compared side by side:
--   1. new contracts (Application) → regional_leasing_specialist_commission_program ($5)
--      plus left-joined events_leasing_scion rows via prospects guest card
--   2. renewals (Renewal)          → regional_leasing_specialist_commission_program_renewals ($3)
-- property → rls attribution on both; elise activity only on (1) for now.
--
-- known limitations, surfaced as columns rather than silently resolved:
--   - rls attribution is property assignment, not documented closer
--     activity: dim_properties.corporate_sales_specialist_id =
--     dim_employees.si_user_id. guidelines allow an rls to work leads off
--     their assigned properties, so this is the home rls, not proof they
--     closed the deal. unmatched property_id lands with null matched_rls_*
--     for review.
--   - rls_roster is filtered to employee_status = 'Active'. grain is one
--     row per rls × assigned property. left join to dim_properties so an
--     rls with no assigned properties still appears once with null
--     property_id/property_name.
--   - eligibility is contracts.is_approved_lease + lease_interval_type +
--     lease_approved_date in the guidelines' season window.
--     current_lease_status and move_in_date are informational only -- not
--     used for exclusions. lease_term_start_date / lease_term_end_date are
--     included the same way -- formal contract-term dates next to
--     lease_start/end so the difference is visible row by row.
--   - "27/28" here is the guidelines' leasing-season label (aug 1, 2026
--     start), not occupancy academic year (26/27 for residents living
--     through fall 2026). quarters and the where-clause window stay
--     hardcoded to the guidelines' calendar on purpose; dim_dates /
--     dim_prelease_dates use different cutoffs and would change scope.
--   - events_leasing_scion carries no message body -- sender_party,
--     message_type, message_action, and message come from a left join to
--     scion_elise_data_share.da.messages_scion on event_id (1:1 per event,
--     confirmed against live data; does not change the join's grain).
--     sender_party distinguishes 'elise' (ai), 'agent' (human staff), or
--     'lead' (the applicant) -- a cleaner ai-vs-human signal than event_type
--     prefix or channel. for message_type = 'VoiceCall' rows, message is an
--     ai-generated call summary, not a verbatim transcript (the verbatim
--     transcript, where available, lives in
--     scion_elise_data_share.da.voice_calls_scion.transcript, not joined
--     here). null message means no messages_scion row matched that event_id
--     (e.g. system/state events like lease_signed carry no message payload).
--
-- public.dim_employees, public.fact_employments, public.dim_properties, and
-- public.contracts are intentionally not database-qualified -- they resolve
-- against whichever database the running connection's own `database` extra
-- points at.
--
-- field references use the bare table name (no schema/database prefix,
-- no alias); from/join clauses stay schema-qualified so the object itself
-- resolves unambiguously.

-- ---------------------------------------------------------------------------
-- 1. new contracts (Application) — $5
--    grain: one row per approved Application × events_leasing_scion event
--    (contracts with no elise bridge / no events still appear once with null
--    event columns). bridge is prospects_scion on email + entrata property id
--    → primary_guest_card_id = events_leasing_scion.guest_card_id. when more
--    than one prospect matches a contract, the closest
--    prospects.lease_approved_time to contracts.lease_approved_date wins so
--    events are not duplicated across prospects; all events on that guest
--    card are kept (no event_type filter yet).
-- ---------------------------------------------------------------------------
-- create or replace table public.regional_leasing_specialist_commission_program as
with rls_roster as (
    -- position_name comes from fact_employments (si-dw model emp_fact_employments),
    -- which derives it from ukg_clean_employees.job_code joined to ukg_jobs'
    -- job-code title -- not from entrata's own employee title field. dim_employees
    -- and fact_employments share the same employee_key (md5(ukg_person_id)).
    -- property assignment is dim_properties.corporate_sales_specialist_id
    -- (= dim_employees.si_user_id), not fact_employments.property_key.
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
),

active_rls_people as (
    -- rls_roster's grain is one row per rls x assigned property. collapse to
    -- one row per person here so activity matching isn't scoped to a single
    -- property -- guidelines allow an rls to work leads off their assigned
    -- properties.
    select distinct
        employee_key,
        employee_name,
        employee_email,
        title
    from rls_roster
),

new_contracts as (
    select
        contracts.lease_interval_type,
        contracts.lease_id,
        contracts.contract_key,
        contracts.property_id,
        contracts.property_name,
        contracts.entrata_property_id,
        contracts.customer_id,
        contracts.full_name,
        contracts.email as customer_email,
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
        5 as commission_amount,
        rls_roster.employee_name as matched_rls_name,
        rls_roster.employee_email as matched_rls_email,
        rls_roster.title as matched_rls_title
    from public.contracts
    left join rls_roster
        on rls_roster.property_id = contracts.property_id
    where contracts.is_approved_lease = 1
      and contracts.lease_interval_type = 'Application'
      and contracts.lease_approved_date between '2026-08-01' and '2027-07-31'
),

contract_prospects as (
    -- one prospect per contract so leasing events are not fanned out across
    -- multiple prospect matches for the same email + property.
    select
        new_contracts.contract_key,
        prospects_scion.prospect_id,
        prospects_scion.primary_guest_card_id,
        prospects_scion.primary_conversation_id
    from new_contracts
    join scion_elise_data_share.da.prospects_scion
        on lower(trim(prospects_scion.contact_email_address)) = lower(trim(new_contracts.customer_email))
       and try_to_number(prospects_scion.external_property_id) = new_contracts.entrata_property_id
    qualify row_number() over (
        partition by new_contracts.contract_key
        order by abs(datediff(
            'day',
            new_contracts.lease_approved_date,
            coalesce(prospects_scion.lease_approved_time, prospects_scion.application_approved_time)::date
        )) asc nulls last,
        prospects_scion.prospect_updated_time desc nulls last
    ) = 1
)

select
    new_contracts.lease_interval_type,
    new_contracts.lease_id,
    new_contracts.contract_key,
    new_contracts.property_id,
    new_contracts.property_name,
    new_contracts.customer_id,
    new_contracts.full_name,
    new_contracts.floorplan_id,
    new_contracts.floorplan_name,
    new_contracts.lease_start_date,
    new_contracts.lease_end_date,
    new_contracts.lease_term_start_date,
    new_contracts.lease_term_end_date,
    new_contracts.lease_approved_date,
    new_contracts.current_lease_status,
    new_contracts.move_in_date,
    new_contracts.commission_quarter,
    new_contracts.commission_amount,
    new_contracts.matched_rls_name,
    new_contracts.matched_rls_email,
    new_contracts.matched_rls_title,
    contract_prospects.prospect_id,
    contract_prospects.primary_guest_card_id,
    events_leasing_scion.event_id,
    events_leasing_scion.conversation_id,
    events_leasing_scion.guest_card_id,
    events_leasing_scion.event_type,
    events_leasing_scion.event_datetime,
    events_leasing_scion.channel,
    events_leasing_scion.agent_name,
    events_leasing_scion.agent_email,
    events_leasing_scion.lead_first_name,
    events_leasing_scion.lead_last_name,
    events_leasing_scion.lead_email,
    messages_scion.sender_party,
    messages_scion.type as message_type,
    messages_scion.message_action,
    messages_scion.message
from new_contracts
left join contract_prospects
    on contract_prospects.contract_key = new_contracts.contract_key
left join scion_elise_data_share.da.events_leasing_scion
    on events_leasing_scion.guest_card_id = contract_prospects.primary_guest_card_id
left join scion_elise_data_share.da.messages_scion
    on messages_scion.event_id = events_leasing_scion.event_id
where event_type not like 'ai_%'
and lease_id = 16185382
order by new_contracts.lease_approved_date, events_leasing_scion.event_datetime;

-- ---------------------------------------------------------------------------
-- 2. renewals (Renewal) — $3
-- ---------------------------------------------------------------------------
create or replace table public.regional_leasing_specialist_commission_program_renewals as
with rls_roster as (
    -- same roster definition as the new-contracts statement above.
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


select *
from public.contracts
where customer_id = 32931355

