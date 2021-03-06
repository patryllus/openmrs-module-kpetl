
SET @OLD_SQL_MODE=@@SQL_MODE$$
SET SQL_MODE=''$$

DROP PROCEDURE IF EXISTS sp_populate_etl_client_registration$$
CREATE PROCEDURE sp_populate_etl_client_registration()
  BEGIN
    -- initial set up of etl_client_registration table
    SELECT "Processing client registration data ", CONCAT("Time: ", NOW());
    insert into kp_etl.etl_client_registration(
        client_id,
        registration_date,
        given_name,
        middle_name,
        family_name,
        Gender,
        DOB,
        dead,
        voided,
        death_date)
    select
           p.person_id,
           p.date_created,
           p.given_name,
           p.middle_name,
           p.family_name,
           p.gender,
           p.birthdate,
           p.dead,
           p.voided,
           p.death_date
    FROM (
         select
                p.person_id,
                p.date_created,
                pn.given_name,
                pn.middle_name,
                pn.family_name,
                p.gender,
                p.birthdate,
                p.dead,
                p.voided,
                p.death_date
         from person p
                left join patient pa on pa.patient_id=p.person_id
                left join person_name pn on pn.person_id = p.person_id and pn.voided=0
         where p.voided=0
         GROUP BY p.person_id
         ) p
    ON DUPLICATE KEY UPDATE given_name = p.given_name, middle_name=p.middle_name, family_name=p.family_name;

    -- update etl_client_registration with patient attributes: birthplace, citizenship, mother_name, phone number and kin's details
    update kp_etl.etl_client_registration r
    left outer join
    (
    select
           pa.person_id,
           max(if(pat.uuid='aec1b592-1d8a-11e9-ab14-d663bd873d93', pa.value, null)) as alias_name,
           max(if(pat.uuid='b2c38640-2603-4629-aebd-3b54f33f1e3a', pa.value, null)) as phone_number,
           max(if(pat.uuid='94614350-84c8-41e0-ac29-86bc107069be', pa.value, null)) as alt_phone_number,
           max(if(pat.uuid='b8d0b331-1d2d-4a9a-b741-1816f498bdb6', pa.value, null)) as email_address
    from person_attribute pa
           inner join
             (
             select
                    pat.person_attribute_type_id,
                    pat.name,
                    pat.uuid
             from person_attribute_type pat
             where pat.retired=0
             ) pat on pat.person_attribute_type_id = pa.person_attribute_type_id
                        and pat.uuid in (
            'aec1b592-1d8a-11e9-ab14-d663bd873d93', -- alias_name
            'b2c38640-2603-4629-aebd-3b54f33f1e3a', -- phone contact
            '94614350-84c8-41e0-ac29-86bc107069be', -- alternative phone contact
            'b8d0b331-1d2d-4a9a-b741-1816f498bdb6' -- email address

            )
    where pa.voided=0
    group by pa.person_id
    ) att on att.person_id = r.client_id
    set r.alias_name = att.alias_name,
        r.phone_number=att.phone_number,
        r.alt_phone_number=att.alt_phone_number,
        r.email_address=att.email_address;


    update kp_etl.etl_client_registration r
    join (select pi.patient_id,
                 max(if(pit.uuid='49af6cdc-7968-4abb-bf46-de10d7f4859f',pi.identifier,null)) national_id,
                 max(if(pit.uuid='aec1b20e-1d8a-11e9-ab14-d663bd873d93',pi.identifier,null)) passport_number
          from patient_identifier pi
                 join patient_identifier_type pit on pi.identifier_type=pit.patient_identifier_type_id
          where voided=0
          group by pi.patient_id) pid on pid.patient_id=r.client_id
    set
        r.national_id_number=pid.national_id,
        r.passport_number=pid.passport_number;

    update kp_etl.etl_client_registration r
    join (select pa.person_id as client_id,
                 pa.address1 as postal_address,
                 pa.county_district as county,
                 pa.state_province as sub_county,
                 pa.address6 as location,
                 pa.address5 as sub_location,
                 pa.city_village as village
          from person_address pa
          group by person_id) pstatus on pstatus.client_id=r.client_id
    set r.postal_address=pstatus.postal_address,
        r.county=pstatus.county,
        r.sub_county= pstatus.sub_county,
        r.location= pstatus.location,
        r.sub_location= pstatus.sub_location,
        r.village= pstatus.village;

    END$$
    DROP PROCEDURE IF EXISTS sp_populate_etl_contact$$
    CREATE PROCEDURE sp_populate_etl_contact()
      BEGIN
        SELECT "Processing client contact data ", CONCAT("Time: ", NOW());
        insert into kp_etl.etl_contact (
            uuid,
            client_id,
            visit_id,
            visit_date,
            location_id,
            encounter_id,
            encounter_provider,
            date_created,
            key_population_type,
            contacted_by_peducator,
            program_name,
            frequent_hotspot_name,
            frequent_hotspot_type,
            year_started_sex_work,
            year_started_sex_with_men,
            year_started_drugs,
            avg_weekly_sex_acts,
            avg_weekly_anal_sex_acts,
            avg_weekly_drug_injections,
            contact_person_name,
            contact_person_alias,
            contact_person_phone,
            voided
            )
        select
               e.uuid,
               e.patient_id,
               e.visit_id,
               e.encounter_datetime as visit_date,
               e.location_id,
               e.encounter_id,
               e.creator,
               e.date_created,
               max(if(o.concept_id=164929,(case o.value_coded when 165083 then "Female sex worker" when 160578 then "Male who have sex with Men" when 165084 then "Male sex worker" when 165085
                                                     then  "People who use drugs" when 105 then "People who inject drugs"  when  165108 then "Transgender"  when 165107 then "Transgender" else "" end),null)) as key_population_type,
               max(if(o.concept_id=165004,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as contacted_by_peducator,
               max(if(o.concept_id=165137,o.value_text,null)) as program_name,
               max(if(o.concept_id=165006,o.value_text,null)) as frequent_hotspot_name,
               max(if(o.concept_id=165005,( case o.value_coded
                                              when 165011 then "Street"
                                              when 165012 then "Injecting den"
                                              when 165013 then "Uninhabitable building"
                                              when 165014 then "Public Park"
                                              when 165015 then "Beach"
                                              when 165016 then "Casino"
                                              when 165017 then "Bar with lodging"
                                              when 165018 then "Bar without lodging"
                                              when 165019 then "Sex den"
                                              when 165020 then "Strip club"
                                              when 165021 then "Highway"
                                              when 165022 then "Brothel"
                                              when 165023 then "Guest house/hotel"
                                              when 165025 then "illicit brew den"
                                              when 165026 then "Barber shop/salon" else "" end),null)) as frequent_hotspot_type,
               max(if(o.concept_id=165030,o.value_numeric,null)) as year_started_sex_work,
               max(if(o.concept_id=165031,o.value_numeric,null)) as year_started_sex_with_men,
               max(if(o.concept_id=165032,o.value_numeric,null)) as year_started_drugs,
               max(if(o.concept_id=165007,o.value_numeric,null)) as avg_weekly_sex_acts,
               max(if(o.concept_id=165008,o.value_numeric,null)) as avg_weekly_anal_sex_acts,
               max(if(o.concept_id=165009,o.value_numeric,null)) as avg_weekly_drug_injections,
               max(if(o.concept_id=160638,o.value_text,null)) as contact_person_name,
               max(if(o.concept_id=165038,o.value_text,null)) as contact_person_alias,
               max(if(o.concept_id=160642,o.value_text,null)) as contact_person_phone,
               e.voided
        from encounter e
               inner join
                 (
                 select encounter_type_id, uuid, name from encounter_type where uuid='ea68aad6-4655-4dc5-80f2-780e33055a9e'
                 ) et on et.encounter_type_id=e.encounter_type
               join patient p on p.patient_id=e.patient_id and p.voided=0
               left outer join obs o on o.encounter_id=e.encounter_id and o.voided=0
                                          and o.concept_id in (164929,165004,165137,165006,165005,165030,165031,165032,165007,165008,165009,160638,165038,160642)
        where e.voided=0
        group by e.patient_id, e.encounter_id;

        SELECT "Completed processing KP contact data", CONCAT("Time: ", NOW());

        update kp_etl.etl_contact c
        join (select pi.patient_id,
                     max(if(pit.uuid='b7bfefd0-239b-11e9-ab14-d663bd873d93',pi.identifier,null)) unique_identifier
              from patient_identifier pi
                     join patient_identifier_type pit on pi.identifier_type=pit.patient_identifier_type_id
              where voided=0
              group by pi.patient_id) pid on pid.patient_id=c.client_id
        set
            c.unique_identifier=pid.unique_identifier;

        END$$

        DROP PROCEDURE IF EXISTS sp_populate_etl_client_enrollment$$
        CREATE PROCEDURE sp_populate_etl_client_enrollment()
          BEGIN
            SELECT "Processing client enrollment data ", CONCAT("Time: ", NOW());
            insert into kp_etl.etl_client_enrollment (
                uuid,
                client_id,
                visit_id,
                visit_date,
                location_id,
                encounter_id,
                encounter_provider,
                date_created,
                contacted_for_prevention,
                has_regular_free_sex_partner,
                year_started_sex_work,
                year_started_sex_with_men,
                year_started_drugs,
                has_expereienced_sexual_violence,
                has_expereienced_physical_violence,
                ever_tested_for_hiv,
                test_type,
                share_test_results,
                willing_to_test,
                test_decline_reason,
                receiving_hiv_care,
                care_facility_name,
                ccc_number,
                vl_test_done,
                vl_results_date,
                contact_for_appointment,
                contact_method,
                buddy_name,
                buddy_phone_number,
                voided
                )
            select
                   e.uuid,
                   e.patient_id,
                   e.visit_id,
                   e.encounter_datetime as visit_date,
                   e.location_id,
                   e.encounter_id,
                   e.creator,
                   e.date_created,
                   max(if(o.concept_id=165004,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as contacted_for_prevention,
                   max(if(o.concept_id=165027,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as has_regular_free_sex_partner,
                   max(if(o.concept_id=165030,o.value_numeric,null)) as year_started_sex_work,
                   max(if(o.concept_id=165031,o.value_numeric,null)) as year_started_sex_with_men,
                   max(if(o.concept_id=165032,o.value_numeric,null)) as year_started_drugs,
                   max(if(o.concept_id=123160,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as has_expereienced_sexual_violence,
                   max(if(o.concept_id=165034,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as has_expereienced_physical_violence,
                   max(if(o.concept_id=164401,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as ever_tested_for_hiv,
                   max(if(o.concept_id=164956,(case o.value_coded when 163722 then "Rapid HIV Testing" when 164952 THEN "Self Test" else "" end),null)) as ever_tested_for_hiv,
                   max(if(o.concept_id=165153,(case o.value_coded when 703 then "Yes I tested positive" when 664 THEN "Yes I tested negative" when 1066 THEN "No I do not want to share" else "" end),null)) as share_test_results,
                   max(if(o.concept_id=165154,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as willing_to_test,
                   max(if(o.concept_id=159803,o.value_text,null)) as test_decline_reason,
                   max(if(o.concept_id=159811,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as receiving_hiv_care,
                   max(if(o.concept_id=162724,o.value_text,null)) as care_facility_name,
                   max(if(o.concept_id=162053,o.value_numeric,null)) as ccc_number,
                   max(if(o.concept_id=164437,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as vl_test_done,
                   max(if(o.concept_id=163281,o.value_datetime,null)) as vl_results_date,
                   max(if(o.concept_id=165036,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as contact_for_appointment,
                   max(if(o.concept_id=164966,(case o.value_coded when 161642 then "Treatment supporter" when 165037 then "Peer educator"  when 1555 then "Outreach worker"
                                                                  when 159635 then "Phone number" else "" end),null)) as contact_method,
                   max(if(o.concept_id=160638,o.value_text,null)) as buddy_name,
                   max(if(o.concept_id=160642,o.value_text,null)) as buddy_phone_number,
                   e.voided
            from encounter e
                   inner join
                     (
                     select encounter_type_id, uuid, name from encounter_type where uuid='c7f47a56-207b-11e9-ab14-d663bd873d93'
                     ) et on et.encounter_type_id=e.encounter_type
                   join patient p on p.patient_id=e.patient_id and p.voided=0
                   left outer join obs o on o.encounter_id=e.encounter_id and o.voided=0
                                              and o.concept_id in (165004,165027,165030,165031,165032,123160,165034,164401,164956,165153,165154,159803,159811,
                    162724,162053,164437,163281,165036,164966,160638,160642)
            where e.voided=0
            group by e.patient_id, e.encounter_id;
            SELECT "Completed processing KP client enrollment data", CONCAT("Time: ", NOW());
            END$$


            -- ------------- populate etl_clinical_visit--------------------------------

            DROP PROCEDURE IF EXISTS sp_populate_etl_clinical_visit$$
            CREATE PROCEDURE sp_populate_etl_clinical_visit()
              BEGIN
                SELECT "Processing Clinical Visit ", CONCAT("Time: ", NOW());
                INSERT INTO kp_etl.etl_clinical_visit(
                    uuid,
                    client_id,
                    visit_id,
                    visit_date,
                    location_id,
                    encounter_id,
                    encounter_provider,
                    date_created,
                    sti_screened,
                    sti_results,
                    sti_treated,
                    sti_referred,
                    sti_referred_text,
                    tb_screened,
                    tb_results,
                    tb_treated,
                    tb_referred,
                    tb_referred_text,
                    hepatitisB_screened,
                    hepatitisB_results,
                    hepatitisB_treated,
                    hepatitisB_referred,
                    hepatitisB_text,
                    hepatitisC_screened,
                    hepatitisC_results,
                    hepatitisC_treated,
                    hepatitisC_referred,
                    hepatitisC_text,
                    overdose_screened,
                    overdose_results,
                    overdose_treated,
                    received_naloxone,
                    overdose_referred,
                    overdose_text,
                    abscess_screened,
                    abscess_results,
                    abscess_treated,
                    abscess_referred,
                    abscess_text,
                    alcohol_screened,
                    alcohol_results,
                    alcohol_treated,
                    alcohol_referred,
                    alcohol_text,
                    cerv_cancer_screened,
                    cerv_cancer_results,
                    cerv_cancer_treated,
                    cerv_cancer_referred,
                    cerv_cancer_text,
                    prep_screened,
                    prep_results,
                    prep_treated,
                    prep_referred,
                    prep_text,
                    violence_screened,
                    violence_results,
                    violence_treated,
                    violence_referred,
                    violence_text,
                    risk_red_counselling_screened,
                    risk_red_counselling_eligibility,
                    risk_red_counselling_support,
                    risk_red_counselling_ebi_provided,
                    risk_red_counselling_text,
                    fp_screened,
                    fp_eligibility,
                    fp_treated,
                    fp_referred,
                    fp_text,
                    mental_health_screened,
                    mental_health_results,
                    mental_health_support,
                    mental_health_referred,
                    mental_health_text,
                    hiv_self_rep_status,
                    last_hiv_test_setting,
                    counselled_for_hiv,
                    hiv_tested,
                    test_frequency,
                    received_results,
                    test_results,
                    linked_to_art,
                    facility_linked_to,
                    self_test_education,
                    self_test_kits_given,
                    self_use_kits,
                    distribution_kits,
                    self_tested,
                    self_test_date,
                    self_test_frequency,
                    self_test_results,
                    test_confirmatory_results,
                    confirmatory_facility,
                    offsite_confirmatory_facility,
                    self_test_linked_art,
                    self_test_link_facility,
                    hiv_care_facility,
                    other_hiv_care_facility,
                    initiated_art_this_month,
                    active_art,
                    eligible_vl,
                    vl_test_done,
                    vl_results,
                    condom_use_education,
                    post_abortal_care,
                    linked_to_psychosocial,
                    male_condoms_no,
                    female_condoms_no,
                    lubes_no,
                    syringes_needles_no,
                    pep,
                    exposure_type,
                    other_exposure_type,
                    clinical_notes,
                    appointment_date,
                    voided
                    )
                select
                       e.uuid,
                       e.patient_id,
                       e.visit_id,
                       (e.encounter_datetime) as visit_date,
                       e.location_id,
                       e.encounter_id as encounter_id,
                       e.creator,
                       e.date_created as date_created,
                       max(if(o.concept_id=161558,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as sti_screened,
                       max(if(o.concept_id=165199,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" else "" end),null)) as sti_results,
                       max(if(o.concept_id=165200,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as sti_treated,
                       max(if(o.concept_id=165249,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as sti_referred,
                       max(if(o.concept_id=165250,o.value_text,null)) as sti_referred_text,
                       max(if(o.concept_id=165197,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as tb_screened,
                       max(if(o.concept_id=165198,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" else "" end),null)) as tb_results,
                       max(if(o.concept_id=1111,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as tb_treated,
                       max(if(o.concept_id=162310,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as tb_referred,
                       max(if(o.concept_id=163323,o.value_text,null)) as tb_referred_text,
                       max(if(o.concept_id=165040,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as hepatitisB_screened,
                       max(if(o.concept_id=1322,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" else "" end),null)) as hepatitisB_results,
                       max(if(o.concept_id=165251,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as hepatitisB_treated,
                       max(if(o.concept_id=165252,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as hepatitisB_referred,
                       max(if(o.concept_id=165253,o.value_text,null)) as hepatitisB_text,
                       max(if(o.concept_id=165041,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as hepatitisC_screened,
                       max(if(o.concept_id=161471,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" else "" end),null)) as hepatitisC_results,
                       max(if(o.concept_id=165254,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as hepatitisC_treated,
                       max(if(o.concept_id=165255,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as hepatitisC_referred,
                       max(if(o.concept_id=165256,o.value_text,null)) as hepatitisC_text,
                       max(if(o.concept_id=165042,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as overdose_screened,
                       max(if(o.concept_id=165046,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" else "" end),null)) as overdose_results,
                       max(if(o.concept_id=165257,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as overdose_treated,
                       max(if(o.concept_id=165201,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as received_naloxone,
                       max(if(o.concept_id=165258,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as overdose_referred,
                       max(if(o.concept_id=165259,o.value_text,null)) as overdose_text,
                       max(if(o.concept_id=165044,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as abscess_screened,
                       max(if(o.concept_id=165051,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" else "" end),null)) as abscess_results,
                       max(if(o.concept_id=165260,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as abscess_treated,
                       max(if(o.concept_id=165261,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as abscess_referred,
                       max(if(o.concept_id=165262,o.value_text,null)) as abscess_text,
                       max(if(o.concept_id=165043,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as alcohol_screened,
                       max(if(o.concept_id=165047,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" else "" end),null)) as alcohol_results,
                       max(if(o.concept_id=165263,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as alcohol_treated,
                       max(if(o.concept_id=165264,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as alcohol_referred,
                       max(if(o.concept_id=165265,o.value_text,null)) as alcohol_text,
                       max(if(o.concept_id=164934,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as cerv_cancer_screened,
                       max(if(o.concept_id=165196,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" else "" end),null)) as cerv_cancer_results,
                       max(if(o.concept_id=165266,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as cerv_cancer_treated,
                       max(if(o.concept_id=165267,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as cerv_cancer_referred,
                       max(if(o.concept_id=165268,o.value_text,null)) as cerv_cancer_text,
                       max(if(o.concept_id=165076,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as prep_screened,
                       max(if(o.concept_id=165202,(case o.value_coded when 165087 then "Eligible" when 165078 THEN "Not eligible" else "" end),null)) as prep_results,
                       max(if(o.concept_id=165203,(case o.value_coded when 1065 then "Initiated" when 1066 THEN "Not Initiated" else "" end),null)) as prep_treated,
                       max(if(o.concept_id=165270,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as prep_referred,
                       max(if(o.concept_id=165271,o.value_text,null)) as prep_text,
                       max(if(o.concept_id=165204,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as violence_screened,
                       max(if(o.concept_id=165205,(case o.value_coded when 165206 then "Harrasment" when 165207 THEN "Illegal arrest" when 123007 THEN "Verbal Abuse" when 127910 THEN "Rape/Sexual assault" when 126312 THEN "Discrimination"  else "" end),null)) as violence_results,
                       max(if(o.concept_id=165208,(case o.value_coded when  1065 then "Supported" when 1066 THEN "Not supported" else "" end),null)) as violence_treated,
                       max(if(o.concept_id=165273,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as violence_referred,
                       max(if(o.concept_id=165274,o.value_text,null)) as violence_text,
                       max(if(o.concept_id=165045,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as risk_red_counselling_screened,
                       max(if(o.concept_id=165050,(case o.value_coded when 165087 then "Eligible" when 165078 THEN "Not eligible" else "" end),null)) as risk_red_counselling_eligibility,
                       max(if(o.concept_id=165053,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as risk_red_counselling_support,
                       max(if(o.concept_id=161595,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as risk_red_counselling_ebi_provided,
                       max(if(o.concept_id=165277,o.value_text,null)) as risk_red_counselling_text,
                       max(if(o.concept_id=1382,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as fp_screened,
                       max(if(o.concept_id=165209,(case o.value_coded when 165087 then "Eligible" when 165078 THEN "Not eligible" else "" end),null)) as fp_eligibility,
                       max(if(o.concept_id=160653,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as fp_treated,
                       max(if(o.concept_id=165279,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as fp_referred,
                       max(if(o.concept_id=165280,o.value_text,null)) as fp_text,
                       max(if(o.concept_id=165210,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as mental_health_screened,
                       max(if(o.concept_id=165211,(case o.value_coded when 165212 then "Depression unlikely" when 157790 THEN "Mild depression" when 134017 THEN "Moderate depression" when 134011 THEN "Moderate-severe depression" when 126627 THEN "Severe Depression"  else "" end),null)) as mental_health_results,
                       max(if(o.concept_id=165213,(case o.value_coded when 1065 then "Supported" when 1066 THEN "Not supported" else "" end),null)) as mental_health_support,
                       max(if(o.concept_id=165281,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as mental_health_referred,
                       max(if(o.concept_id=165282,o.value_text,null)) as mental_health_text,
                       max(if(o.concept_id=165214,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" when 1067 then "Unknown" else "" end),null)) as hiv_self_rep_status,
                       max(if(o.concept_id=165215,(case o.value_coded when 165216 then "Universal HTS" when 165217 THEN "Self-testing" when 1402 then "Never tested" else "" end),null)) as last_hiv_test_setting,
                       max(if(o.concept_id=159382,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as counselled_for_hiv,
                       max(if(o.concept_id=164401,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" when 1175 then "Not Applicable" else "" end),null)) as hiv_tested,
                       max(if(o.concept_id=165218,(case o.value_coded when 162080 THEN "Initial" when 162081 then "Repeat" when 1175 then "Not Applicable" else "" end),null)) as test_frequency,
                       max(if(o.concept_id=164848,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" when 1067 then "Not Applicable" else "" end),null)) as received_results,
                       max(if(o.concept_id=159427,(case o.value_coded when 664 then "Negative" when 703 THEN "Positive" when 1118 then "Not done" else "" end),null)) as test_results,
                       max(if(o.concept_id=1648,(case o.value_coded when 1 then "Yes" when 0 then "No" else "" end),null)) as linked_to_art,
                       max(if(o.concept_id=163042,o.value_text,null)) as facility_linked_to,
                       max(if(o.concept_id=165220,(case o.value_coded when 1065 then "Yes" when 1066 THEN "No" else "" end),null)) as self_test_education,
                       max(if(o.concept_id=165221,(case o.value_coded when 165222 then "Self use" when 165223 THEN "Distribution" else "" end),null)) as self_test_kits_given,
                       max(if(o.concept_id=165222,o.value_text,null)) as self_use_kits,
                       max(if(o.concept_id=165223,o.value_text,null)) as distribution_kits,
                       max(if(o.concept_id=164952,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as self_tested,
                       max(if(o.concept_id=164400,o.value_datetime,null)) as self_test_date,
                       max(if(o.concept_id=165231,(case o.value_coded when 162080 THEN "Initial" when 162081 then "Repeat" else "" end),null)) as self_test_frequency,
                       max(if(o.concept_id=165233,(case o.value_coded when 664 THEN "Negative" when 703 then "Positive" when 165232 then "Inconclusive" else "" end),null)) as self_test_results,
                       max(if(o.concept_id=165234,(case o.value_coded when 664 THEN "Negative" when 703 then "Positive" when 1118 then "Not done" else "" end),null)) as test_confirmatory_results,
                       max(if(o.concept_id=165237,o.value_text,null)) as confirmatory_facility,
                       max(if(o.concept_id=162724,o.value_text,null)) as offsite_confirmatory_facility,
                       max(if(o.concept_id=165238,(case o.value_coded when 1 then "Yes" when 0 then "No" else "" end),null)) as self_test_linked_art,
                       max(if(o.concept_id=161562,o.value_text,null)) as self_test_link_facility,
                       max(if(o.concept_id=165239,(case o.value_coded when 163266 THEN "Provided here" when 162723 then "Provided elsewhere" when 160563 then "Referred" else "" end),null)) as hiv_care_facility,
                       max(if(o.concept_id=163042,o.value_text,null)) as other_hiv_care_facility,
                       max(if(o.concept_id=165240,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" when 1175 then "Not Applicable" else "" end),null)) as initiated_art_this_month,
                       max(if(o.concept_id=160119,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" when 1175 then "Not Applicable" else "" end),null)) as active_art,
                       max(if(o.concept_id=165242,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" when 1175 then "Not Applicable" else "" end),null)) as eligible_vl,
                       max(if(o.concept_id=165243,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" when 1175 then "Not Applicable" else "" end),null)) as vl_test_done,
                       max(if(o.concept_id=165246,(case o.value_coded when 165244 THEN "Suppressed" when 165245 then "Not suppressed" when 164369 then "Results not yet received" when 1175 then "Not Applicable" else "" end),null)) as vl_results,
                       max(if(o.concept_id=165247,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as condom_use_education,
                       max(if(o.concept_id=164820,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as post_abortal_care,
                       max(if(o.concept_id=165302,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as linked_to_psychosocial,
                       max(if(o.concept_id=165055,o.value_numeric,null)) as male_condoms_no,
                       max(if(o.concept_id=165056,o.value_numeric,null)) as female_condoms_no,
                       max(if(o.concept_id=165057,o.value_numeric,null)) as lubes_no,
                       max(if(o.concept_id=165058,o.value_numeric,null)) as syringes_needles_no,
                       max(if(o.concept_id=164845,(case o.value_coded when 127910 THEN "Rape" when 165045 then "Condom burst" when 5622 then "Others" else "" end),null)) as pep,
                       max(if(o.concept_id=165060,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as exposure_type,
                       max(if(o.concept_id=163042,o.value_text,null)) as other_exposure_type,
                       max(if(o.concept_id=165248,o.value_text,null)) as clinical_notes,
                       max(if(o.concept_id=5096,o.value_datetime,null)) as appointment_date,
                       e.voided as voided
                from encounter e
                       inner join
                         (
                         select encounter_type_id, uuid, name from encounter_type where uuid in('92e03f22-9686-11e9-bc42-526af7764f64')
                         ) et on et.encounter_type_id=e.encounter_type
                       left outer join obs o on o.encounter_id=e.encounter_id and o.voided=0
                                                  and o.concept_id in (161558,165199,165200,165249,165250,165197,165198,1111,162310,163323,165040,1322,165251,165252,165253,
                        165041,161471,165254,165255,165256,165042,165046,165257,165201,165258,165259,165044,165051,165260,165261,165262,165043,165047,165263,165264,165265,
                        164934,165196,165266,165267,165268,165076,165202,165203,165270,165271,165204,165205,165208,165273,165274,165045,165050,165053,161595,165277,1382,
                        165209,160653,165279,165280,165210,165211,165213,165281,165282,165214,165215,159382,164401,165218,164848,159427,1648,163042,165220,165221,165222,165223,
                        164952,164400,165231,165233,165234,165237,162724,165238,161562,165239,163042,165240,160119,165242,165243,165246,165247,164820,165302,165055,165056,
                        165057,165058,164845,165248,5096)
                where e.voided=0
                group by e.patient_id, e.encounter_id, visit_date;
                SELECT "Completed processing Clinical visit data ", CONCAT("Time: ", NOW());
                END$$

            -- ------------- populate etl_sti_Treatment--------------------------------

                DROP PROCEDURE IF EXISTS sp_populate_etl_sti_Treatment$$
                CREATE PROCEDURE sp_populate_etl_sti_Treatment()
                  BEGIN
                    SELECT "Processing STI Treatment ", CONCAT("Time: ", NOW());
                    INSERT INTO kp_etl.etl_sti_Treatment(
                        uuid,
                        client_id,
                        visit_id,
                        visit_date,
                        location_id,
                        encounter_id,
                        encounter_provider,
                        date_created,
                        visit_reason,
                        syndrome,
                        other_syndrome,
                        drug_prescription,
                        other_drug_prescription,
                        genital_exam_done,
                        lab_referral,
                        lab_form_number,
                        referred_to_facility,
                        facility_name,
                        partner_referral_done,
                        given_lubes,
                        no_of_lubes,
                        given_condoms,
                        no_of_condoms,
                        provider_comments,
                        provider_name,
                        appointment_date,
                        voided
                        )
                    select
                           e.uuid,
                           e.patient_id,
                           e.visit_id,
                           (e.encounter_datetime) as visit_date,
                           e.location_id,
                           e.encounter_id as encounter_id,
                           e.creator,
                           e.date_created as date_created,
                           max(if(o.concept_id=164082,(case o.value_coded when 1068 THEN "Symptomatic" when 5006 then "Asymptomatic" when 163139 then "Quartely Screening" when 160523 then "Follow up" else "" end),null)) as visit_reason,
                          max(if(o.concept_id=165098,(case o.value_coded when 145762 THEN "Genital Ulcer Disease" when 130644 then "Pelvic Inflammation Disease" when 120939 then "Candidiasis" when 123529 then "Urethral Discharge/Urethritis"
                                                                         when 139505 then "Genital Warts" when 116995 then "Cervicitis" when 112493 then "Syphilis" when 117829 then "Herpes Genitalia" when 130309 then "Pharyngeal Discharge"
                                                                         when 121809 then "Vaginitis" when 155080 then "Anal Warts" when 148895 then "Anal Discharge" when 148902 then "Anal Rectal Ulcer" when 110172 then "Pharyngeal Ulcer" when 114732 then "Orchitis"
                                                                         when 5622 then "Other(Specify)" else "" end),null)) as syndrome,
                           max(if(o.concept_id=165138,o.value_text,null)) as other_syndrome,
                           max(if(o.concept_id=1282,(case o.value_coded when 75842 THEN "Erythromycin" when 73041 then "Ceftriaxone" when 82228 then "Podophyllin" when 73449 then "Ciprofloxacin"
                                                                        when 70245 THEN "Acyclovir Tablets" when 70166 then "Paracetamol" when 72039 then "Benzathine" when 84221 then "Spectinomycin"
                                                                        when 77897 THEN "Brufen" when 73006 then "Cefixime" when 100 then "Inj. Gentamycin" when 71160 then "Amoxycillin"
                                                                        when 75222 THEN "Doxycycline" when 73624 then "Clotrimazole Pessaries"
                                                                        else "" end),null)) as drug_prescription,
                           max(if(o.concept_id=163101,o.value_text,null)) as other_drug_prescription,
                           max(if(o.concept_id=163743,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as genital_exam_done,
                           max(if(o.concept_id=1272,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as lab_referral,
                           max(if(o.concept_id=163042,o.value_text,null)) as lab_form_number,
                           max(if(o.concept_id=1788,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as referred_to_facility,
                           max(if(o.concept_id=162724,o.value_text,null)) as facility_name,
                           max(if(o.concept_id=165128,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as partner_referral_done,
                           max(if(o.concept_id=165127,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as given_lubes,
                           max(if(o.concept_id=163169,o.value_numeric,null)) as no_of_lubes,
                           max(if(o.concept_id=159777,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as given_condoms,
                           max(if(o.concept_id=165055,o.value_numeric,null)) as no_of_condoms,
                           max(if(o.concept_id=162749,o.value_text,null)) as provider_comments,
                           max(if(o.concept_id=1473,o.value_text,null)) as provider_name,
                           max(if(o.concept_id=5096,o.value_datetime,null)) as appointment_date,
                           e.voided as voided
                    from encounter e
                           inner join
                             (
                             select encounter_type_id, uuid, name from encounter_type where uuid in('2cc8c535-bbfa-4668-98c7-b12e3550ee7b')
                             ) et on et.encounter_type_id=e.encounter_type
                           left outer join obs o on o.encounter_id=e.encounter_id and o.voided=0
                                                      and o.concept_id in (164082,165098,165138,1282,163101,163743,1272,163042,1788,162724,165128,165127,163169,
                            159777,165055,162749,1473,5096)
                    where e.voided=0
                    group by e.patient_id, e.encounter_id, visit_date;
                    SELECT "Completed processing STI Treatment data ", CONCAT("Time: ", NOW());

           END$$
            -- ------------- populate etl_peer_calendar--------------------------------

                DROP PROCEDURE IF EXISTS sp_populate_etl_peer_calendar$$
                CREATE PROCEDURE sp_populate_etl_peer_calendar()
                  BEGIN
                    SELECT "Processing Peer calendar ", CONCAT("Time: ", NOW());
                    INSERT INTO kp_etl.etl_peer_calendar(
                        uuid,
                        client_id,
                        visit_id,
                        visit_date,
                        location_id,
                        encounter_id,
                        encounter_provider,
                        date_created,
                        hotspot_name,
                        typology,
                        other_hotspots,
                        weekly_condoms_required,
                        monthly_condoms_required,
                        weekly_lubes_required,
                        monthly_lubes_required,
                        daily_syringes_required,
                        monthly_syringes_required,
                        years_in_sexwork_drugs,
                        experienced_violence,
                        visited_clinic,
                        week1_n_and_s,
                        week1_male_condoms,
                        week1_lubes,
                        week1_female_condoms,
                        week1_self_test_kits_distributed,
                        week1_received_clinical_service,
                        week1_violence_reported,
                        week1_remarks,
                        week2_n_and_s,
                        week2_male_condoms,
                        week2_lubes,
                        week2_female_condoms,
                        week2_self_test_kits_distributed,
                        week2_received_clinical_service,
                        week2_violence_reported,
                        week2_remarks,
                        week3_n_and_s,
                        week3_male_condoms,
                        week3_lubes,
                        week3_female_condoms,
                        week3_self_test_kits_distributed,
                        week3_received_clinical_service,
                        week3_violence_reported,
                        week3_remarks,
                        week4_n_and_s,
                        week4_male_condoms,
                        week4_lubes,
                        week4_female_condoms,
                        week4_self_test_kits_distributed,
                        week4_received_clinical_service,
                        week4_violence_reported,
                        week4_remarks,
                        referred,
                        health_edu,
                        voided
                        )
                    select
                           e.uuid,
                           e.patient_id,
                           e.visit_id,
                           (e.encounter_datetime) as visit_date,
                           e.location_id,
                           e.encounter_id as encounter_id,
                           e.creator,
                           e.date_created as date_created,
                           max(if(o.concept_id=165006,o.value_text,null)) as hotspot_name,
                           max(if(o.concept_id=165005,(case o.value_coded when  165011 then "Street" when  165012 then" Injecting den" when  165013 then" Uninhabitable building"
                                                                          when  165014 then" Park" when  1536 then" Homes" when  165015 then" Beach" when  165016 then" Casino"
                                                                          when  165017 then "Bar with lodging" when  165018 then "Bar without lodging"
                                                                          when  165019 then "Sex den" when  165020 then "Strip club" when  165021 then "Highways" when  165022 then "Brothel"
                                                                          when  165023 then "Guest house/Hotels/Lodgings" when 165024 then "Massage parlor" when 165025 then "Chang’aa den" when 165026 then "Barbershop/Salon"
                                                                          when  165297 then "Virtual Space" when  5622 then "Other (Specify)" else "" end),null)) as typology,
                           max(if(o.concept_id=165298,o.value_text,null)) as other_hotspots,
                           max(if(o.concept_id=165007,o.value_numeric,null)) as weekly_condoms_required,
                           max(if(o.concept_id=165299,o.value_numeric,null)) as monthly_condoms_required,
                           max(if(o.concept_id=165008,o.value_numeric,null)) as weekly_lubes_required,
                           max(if(o.concept_id=165300,o.value_numeric,null)) as monthly_lubes_required,
                           max(if(o.concept_id=165009,o.value_numeric,null)) as daily_syringes_required,
                           max(if(o.concept_id=165308,o.value_numeric,null)) as monthly_syringes_required,
                           max(if(o.concept_id=165301,o.value_numeric,null)) as years_in_sexwork_drugs,
                           max(if(o.concept_id=123160,(case o.value_coded when 1065 THEN "Yes" when 1066 then "No" else "" end),null)) as experienced_violence,
                           max(if(o.concept_id=165302,(case o.value_coded when 161643 THEN "Yes" else "" end),null)) as visited_clinic,
                           max(if(o.concept_id=165309,o.value_text,null)) as week1_n_and_s,
                           max(if(o.concept_id=165310,o.value_text,null)) as week1_male_condoms,
                           max(if(o.concept_id=165311,o.value_text,null)) as week1_self_test_kits_distributed,
                           max(if(o.concept_id=165312,o.value_text,null)) as week1_violence_reported,
                           max(if(o.concept_id=165313,o.value_text,null)) as week1_lubes,
                           max(if(o.concept_id=165314,o.value_text,null)) as week1_female_condoms,
                           max(if(o.concept_id=165315,o.value_text,null)) as week1_received_clinical_service,
                           max(if(o.concept_id=165316,o.value_text,null)) as week1_remarks,
                           max(if(o.concept_id=165317,o.value_text,null)) as week2_n_and_s,
                           max(if(o.concept_id=165318,o.value_text,null)) as week2_male_condoms,
                           max(if(o.concept_id=165319,o.value_text,null)) as week2_self_test_kits_distributed,
                           max(if(o.concept_id=165320,o.value_text,null)) as week2_violence_reported,
                           max(if(o.concept_id=165321,o.value_text,null)) as week2_lubes,
                           max(if(o.concept_id=165322,o.value_text,null)) as week2_female_condoms,
                           max(if(o.concept_id=165323,o.value_text,null)) as week2_received_clinical_service,
                           max(if(o.concept_id=165324,o.value_text,null)) as week2_remarks,
                           max(if(o.concept_id=165325,o.value_text,null)) as week3_n_and_s,
                           max(if(o.concept_id=165326,o.value_text,null)) as week3_male_condoms,
                           max(if(o.concept_id=165327,o.value_text,null)) as week3_self_test_kits_distributed,
                           max(if(o.concept_id=165328,o.value_text,null)) as week3_violence_reported,
                           max(if(o.concept_id=165329,o.value_text,null)) as week3_lubes,
                           max(if(o.concept_id=165330,o.value_text,null)) as week3_female_condoms,
                           max(if(o.concept_id=165331,o.value_text,null)) as week3_received_clinical_service,
                           max(if(o.concept_id=165332,o.value_text,null)) as week3_remarks,
                           max(if(o.concept_id=165333,o.value_text,null)) as week4_n_and_s,
                           max(if(o.concept_id=165334,o.value_text,null)) as week4_male_condoms,
                           max(if(o.concept_id=165335,o.value_text,null)) as week4_self_test_kits_distributed,
                           max(if(o.concept_id=165336,o.value_text,null)) as week4_violence_reported,
                           max(if(o.concept_id=165337,o.value_text,null)) as week4_lubes,
                           max(if(o.concept_id=165338,o.value_text,null)) as week4_female_condoms,
                           max(if(o.concept_id=165339,o.value_text,null)) as week4_received_clinical_service,
                           max(if(o.concept_id=165340,o.value_text,null)) as week4_remarks,
                           max(if(o.concept_id=1272,o.value_text,null)) as referred,
                           max(if(o.concept_id=165147,o.value_text,null)) as health_edu,
                           e.voided as voided
                    from encounter e
                           inner join
                             (
                             select encounter_type_id, uuid, name from encounter_type where uuid in('c4f9db39-2c18-49a6-bf9b-b243d673c64d')
                             ) et on et.encounter_type_id=e.encounter_type
                           left outer join obs o on o.encounter_id=e.encounter_id and o.voided=0
                                                      and o.concept_id in (165006,165005,165298,165007,165299,165008,165300,165009,165301,123160,165308,165309,165310,165311,165312,165313,
                            165315,165316,165317,165318,165321,165319,165320,165322,165323,165324,165325,165326,165327,165328,165329,165330,165331,165332,165333,165334,165335,165336,165337,
                            165147,1272,165338,165339,165340)
                                          where e.voided=0
                    group by e.patient_id, e.encounter_id, visit_date;
                    SELECT "Completed processing Peer calendar data ", CONCAT("Time: ", NOW());
                    END$$

SET sql_mode=@OLD_SQL_MODE$$
-- ------------------------------------------- running all procedures -----------------------------

DROP PROCEDURE IF EXISTS sp_first_time_setup$$
CREATE PROCEDURE sp_first_time_setup()
  BEGIN
DECLARE populate_script_id INT(11);
SELECT "Beginning first time setup", CONCAT("Time: ", NOW());
INSERT INTO kP_etl.etl_script_status(script_name, start_time) VALUES('initial_population_of_tables', NOW());
SET populate_script_id = LAST_INSERT_ID();

CALL sp_populate_etl_client_registration();
CALL sp_populate_etl_contact();
CALL sp_populate_etl_client_enrollment();
CALL sp_populate_etl_clinical_visit();
CALL sp_populate_etl_sti_Treatment();
CALL sp_populate_etl_peer_calendar();

UPDATE kp_etl.etl_script_status SET stop_time=NOW() where id= populate_script_id;

SELECT "Completed first time setup", CONCAT("Time: ", NOW());
  
END$$



