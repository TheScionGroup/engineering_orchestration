/*
    ddl for public.regional_leasing_specialist_commission_program.
    regional_leasing_specialist_commission_program/refresh.sql truncates and reloads the table on every run.
    if the column list changes, manually drop the table and re-run the dag so it gets recreated with the new structure.
*/

create table if not exists public.regional_leasing_specialist_commission_program (
    leasing_academic_year varchar
        comment 'Leasing-season academic year label the lease start date falls in (dim_dates.leasing_academic_year_label, one year ahead of the approval academic year).',
    current_academic_year varchar
        comment 'Academic year label in which the contract was approved (dim_dates.academic_year_label for contract_approved_date).',
    is_renewal number(1, 0)
        comment '1 if this row is a lease renewal, 0 if it is a new contract.',
    customer_id number(38, 0)
        comment 'Source system customer identifier (contracts.customer_id).',
    application_id number(38, 0)
        comment 'Leasing application identifier (contracts.application_id).',
    lease_id number(38, 0)
        comment 'Lease identifier (contracts.lease_id).',
    contract_id number(38, 0)
        comment 'Lease interval identifier; uniquely identifies this contract term (contracts.lease_interval_id).',
    application_approved_date date
        comment 'Date the leasing application was approved.',
    contract_approved_date date
        comment 'Date the contract was approved (contracts.lease_approved_date).',
    contract_signed_date date
        comment 'Date the contract was signed, sourced from the start of the Entrata prelease period (contracts.prelease_start_date). Upstream sentinel (1900-01-01) for contracts where the source system never recorded a prelease start.',
    previous_lease_id number(38, 0)
        comment 'For renewals, the lease_id of the resident''s prior contract on this property. Null for new contracts.',
    previous_contract_id number(38, 0)
        comment 'For renewals, the lease_interval_id of the resident''s prior contract. Null for new contracts.',
    previous_contract_approved_date date
        comment 'For renewals, the approval date of the resident''s prior contract. Null for new contracts.',
    contract_type varchar(50)
        comment 'Contract interval type from the source system (contracts.lease_interval_type).',
    contract_start_date date
        comment 'Contract start date (contracts.lease_start_date).',
    contract_end_date date
        comment 'Contract end date (contracts.lease_end_date).',
    contract_term varchar(50)
        comment 'Contract term from the source system (contracts.lease_term). Excludes Immediate Move-in, Group, and Spring-Summer terms, and excludes the Transfer contract type.',
    customer_first_name varchar(10000)
        comment 'Customer first name (contracts.first_name).',
    customer_last_name varchar(10000)
        comment 'Customer last name (contracts.last_name).',
    customer_email varchar(240)
        comment 'Customer email address (contracts.email).',
    contract_status varchar(50)
        comment 'Contract status at the time of extract (e.g. Approved) (contracts.application_status).',
    si_property_id number(38, 0)
        comment 'Internal property identifier (contracts.property_id).',
    entrata_property_id number(38, 0)
        comment 'Entrata property identifier, used to join to dim_properties.',
    property_name varchar
        comment 'Property name.',
    property_leasing_specialist_name varchar
        comment 'Name of the Regional Leasing Specialist assigned to the property (dim_properties.corporate_sales_specialist_name).',
    commission_quarter varchar
        comment 'Commission quarter (Q1-Q4) derived from the month of contract_approved_date.',
    most_touchpoints_regional_leasing_specialist_name varchar
        comment 'Name of the active Regional Leasing Specialist (any Regional Leasing Specialist, not limited to the one assigned to the property) with the most message touchpoints to this contract''s applicant/resident, counting only touchpoints sent by a Regional Leasing Specialist on or after the start of the current academic year.',
    most_touchpoints_message_count number(18, 0)
        comment 'Message touchpoint count for most_touchpoints_regional_leasing_specialist_name.',
    second_most_touchpoints_regional_leasing_specialist_name varchar
        comment 'Name of the active Regional Leasing Specialist with the second-most message touchpoints to this contract''s applicant/resident, same scope as most_touchpoints_regional_leasing_specialist_name. Compare its count to most_touchpoints_message_count to check for a tie.',
    second_most_touchpoints_message_count number(18, 0)
        comment 'Message touchpoint count for second_most_touchpoints_regional_leasing_specialist_name.',
    last_touchpoint_regional_leasing_specialist_name varchar
        comment 'Name of the active Regional Leasing Specialist who sent the chronologically last message touchpoint to this contract''s applicant/resident, same scope as most_touchpoints_regional_leasing_specialist_name. Breaks a tie between most_touchpoints_regional_leasing_specialist_name and second_most_touchpoints_regional_leasing_specialist_name.',
    last_regional_leasing_specialist_touchpoint_to_contract_approved_days number(18, 0)
        comment 'Calendar days from last_touchpoint_regional_leasing_specialist_name''s message to contract_approved_date (contract_approved_date minus the message''s date). Negative if that message came after the contract was approved.',
    conversation_link varchar
        comment 'Link to this applicant''s/resident''s full conversation in Elise, covering every touchpoint (including non-Regional-Leasing-Specialist ones), for resolving credit disputes. Not scoped by date or by Regional Leasing Specialist -- scion_elise_data_share.da.events_leasing_scion.conversation_link for new contracts, reconstructed from scion_elise_data_share.da.messages_scion.mc_id (https://app.meetelise.com/conversations?mcId=<mc_id>) for renewals, since events_resident_scion has no conversation_link column of its own.'
)
comment = 'Regional Leasing Specialist commission source table: new contracts and renewals, each with commission quarter and Regional Leasing Specialist message attribution. Truncated and reloaded on every run of regional_leasing_specialist_commission_program/refresh.sql -- see dags/regional_leasing_specialist_commission_program.py.';
