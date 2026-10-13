/*
    ddl for public.regional_leasing_specialist_commission_program.
    regional_leasing_specialist_commission_program/refresh.sql truncates and reloads the table on every run.
    if the column list changes, manually drop the table and re-run the dag so it gets recreated with the new structure.
*/

create table if not exists public.regional_leasing_specialist_commission_program (
    leasing_academic_year varchar
        comment 'Leasing-season academic year label the lease start date falls in (dim_dates.leasing_academic_year_label, one year ahead of the approval academic year).',
    current_academic_year varchar
        comment 'Academic year label in which the contract was approved (dim_dates.academic_year_label for lease_approved_date).',
    is_renewal number(1, 0)
        comment '1 if this row is a lease renewal, 0 if it is a new contract.',
    customer_id number(38, 0)
        comment 'Source system customer identifier (contracts.customer_id).',
    application_id number(38, 0)
        comment 'Leasing application identifier (contracts.application_id).',
    lease_id number(38, 0)
        comment 'Lease identifier (contracts.lease_id).',
    lease_interval_id number(38, 0)
        comment 'Lease interval identifier; uniquely identifies this contract term (contracts.lease_interval_id).',
    application_approved_date date
        comment 'Date the leasing application was approved.',
    lease_approved_date date
        comment 'Date the lease contract was approved.',
    previous_lease_id number(38, 0)
        comment 'For renewals, the lease_id of the resident''s prior contract on this property. Null for new contracts.',
    previous_contract_id number(38, 0)
        comment 'For renewals, the lease_interval_id of the resident''s prior contract. Null for new contracts.',
    previous_contract_approved_date date
        comment 'For renewals, the approval date of the resident''s prior contract. Null for new contracts.',
    lease_interval_type varchar(50)
        comment 'Contract interval type from the source system (contracts.lease_interval_type).',
    lease_start_date date
        comment 'Lease start date.',
    lease_end_date date
        comment 'Lease end date.',
    lease_term varchar(50)
        comment 'Lease term from the source system (contracts.lease_term).',
    first_name varchar(10000)
        comment 'Resident first name.',
    last_name varchar(10000)
        comment 'Resident last name.',
    email varchar(240)
        comment 'Resident email address.',
    application_status varchar(50)
        comment 'Leasing application status at the time of extract (e.g. Approved).',
    si_property_id number(38, 0)
        comment 'Internal property identifier (contracts.property_id).',
    entrata_property_id number(38, 0)
        comment 'Entrata property identifier, used to join to dim_properties.',
    property_name varchar
        comment 'Property name.',
    regional_leasing_specialist varchar
        comment 'Name of the Regional Leasing Specialist assigned to the property (dim_properties.corporate_sales_specialist_name).',
    commission_quarter varchar
        comment 'Commission quarter (Q1-Q4) derived from the month of lease_approved_date.',
    regional_leasing_specialist_message_count number(18, 0)
        comment 'Count of leasing/resident messages sent or replied to by the assigned Regional Leasing Specialist for this contract.',
    agent_message_count number(18, 0)
        comment 'Count of leasing/resident messages sent or replied to by any agent for this contract.',
    message_touchpoint_count number(18, 0)
        comment 'Total count of messages exchanged across all leasing/resident events for this contract.',
    regional_leasing_specialist_tour_attended boolean
        comment 'True if the assigned Regional Leasing Specialist is recorded hosting a tour_attended event for this contract. New contracts only -- always null for renewals.',
    regional_leasing_specialist_lease_applied boolean
        comment 'True if the assigned Regional Leasing Specialist is recorded on a lease_applied event for this contract. New contracts only -- always null for renewals.',
    regional_leasing_specialist_lease_signed boolean
        comment 'True if the assigned Regional Leasing Specialist is recorded on a lease_signed event for this contract. New contracts only -- always null for renewals.'
)
comment = 'Regional Leasing Specialist commission source table: new contracts and renewals, each with commission quarter and RLS message/tour/signing attribution. Truncated and reloaded on every run of regional_leasing_specialist_commission_program/refresh.sql -- see dags/regional_leasing_specialist_commission_program.py.';
