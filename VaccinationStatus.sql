-- VaccinationStatus.sql

-- Create a view for VaccinationStatusReport
CREATE VIEW VaccinationStatusReport AS
WITH 
    -- Step 1: AdministeredDoses - Add CodeUsed to this CTE
    AdministeredDoses AS (
        SELECT 
            ve.LDSBusinessId,
            ve.VaccineID,
            COUNT(*) AS AdministeredCount,
            MAX(ve.EventDate) AS LastAdministeredDate,
            -- Get the most recent code used
            MAX(CASE WHEN ve.EventDate = MAX(ve.EventDate) OVER (PARTITION BY ve.LDSBusinessId, ve.VaccineID) 
                 THEN ve.CodeUsed ELSE NULL END) AS CodeUsed
        FROM 
            VaccineEvents ve
        WHERE 
            ve.EventType = 'Administration'
            AND ve.IncorrectVaccine = 'No'  -- Only count correct vaccines
        GROUP BY 
            ve.LDSBusinessId,
            ve.VaccineID
    ),
    
    -- Step 2: DeclinedVaccines - Add CodeUsed
    DeclinedVaccines AS (
        SELECT 
            ve.LDSBusinessId,
            ve.VaccineID,
            MAX(ve.CodeUsed) AS CodeUsed
        FROM 
            VaccineEvents ve
        WHERE 
            ve.EventType = 'Declined'
        GROUP BY 
            ve.LDSBusinessId,
            ve.VaccineID
    ),
    
    -- Step 3: ContraindicatedVaccines - Add CodeUsed
    ContraindicatedVaccines AS (
        SELECT 
            ve.LDSBusinessId,
            ve.VaccineID,
            MAX(ve.CodeUsed) AS CodeUsed
        FROM 
            VaccineEvents ve
        WHERE 
            ve.EventType = 'Contraindicated'
        GROUP BY 
            ve.LDSBusinessId,
            ve.VaccineID
    ),
    
    -- Step 4: RequiredDoses
    RequiredDoses AS (
        SELECT 
            VaccineID,
            MAX(DoseNumber) AS TotalDoses
        FROM 
            IMMUNISATION_SCHEDULE
        GROUP BY 
            VaccineID
    ),
    
    -- New Step 5: Incorrect Vaccines - now includes explanation
    IncorrectVaccines AS (
        SELECT 
            ve.LDSBusinessId,
            ve.VaccineID,
            MAX(ve.EventDate) AS LastIncorrectDate,
            MAX(ve.EligibleAgainDate) AS EligibleAgainDate,
            -- Taking the most recent explanation (should be the same for a given vaccine type)
            MAX(ve.IncompleteReason) AS IncompleteReason,
            -- Storing the code used for reference
            MAX(ve.CodeUsed) AS CodeUsed
        FROM 
            VaccineEvents ve
        WHERE 
            ve.IncorrectVaccine = 'Yes'
        GROUP BY 
            ve.LDSBusinessId,
            ve.VaccineID
    )
SELECT 
    ev.LDSBusinessId,
    ev.VaccineName,
    CASE 
        WHEN cv.VaccineID IS NOT NULL THEN 'Contraindicated'
        WHEN dv.VaccineID IS NOT NULL THEN 'Declined'
        WHEN iv.VaccineID IS NOT NULL THEN 'Incomplete Course'
        WHEN ad.AdministeredCount < rd.TotalDoses THEN 'Missed'
        WHEN ad.AdministeredCount >= rd.TotalDoses THEN 'Completed'
        ELSE 'Eligible and Due'
    END AS VaccinationStatus,
    COALESCE(ad.LastAdministeredDate, iv.LastIncorrectDate) AS DateVaccinated,
    CASE 
        WHEN ve.OutOfSchedule = 'Yes' THEN 'Yes' 
        ELSE 'No' 
    END AS OutOfSchedule,
    iv.EligibleAgainDate AS NextEligibleDate,
    iv.IncompleteReason,
    -- Use COALESCE to get the code from whichever status applies
    COALESCE(iv.CodeUsed, ad.CodeUsed, dv.CodeUsed, cv.CodeUsed) AS CodeUsed
FROM 
    EligibleVaccinations ev
LEFT JOIN 
    AdministeredDoses ad 
    ON ev.LDSBusinessId = ad.LDSBusinessId AND ev.VaccineID = ad.VaccineID
LEFT JOIN 
    DeclinedVaccines dv 
    ON ev.LDSBusinessId = dv.LDSBusinessId AND ev.VaccineID = dv.VaccineID
LEFT JOIN 
    ContraindicatedVaccines cv 
    ON ev.LDSBusinessId = cv.LDSBusinessId AND ev.VaccineID = cv.VaccineID
LEFT JOIN 
    IncorrectVaccines iv
    ON ev.LDSBusinessId = iv.LDSBusinessId AND ev.VaccineID = iv.VaccineID
LEFT JOIN 
    RequiredDoses rd 
    ON ev.VaccineID = rd.VaccineID
LEFT JOIN 
    VaccineEvents ve 
    ON ev.LDSBusinessId = ve.LDSBusinessId 
       AND ev.VaccineID = ve.VaccineID 
       AND ve.EventType = 'Administration'
ORDER BY 
    ev.LDSBusinessId,
    ev.VaccineName;

-- Example Output: VaccinationStatusReport
/*
LDSBusinessId  VaccineName         VaccinationStatus   DateVaccinated  OutOfSchedule  NextEligibleDate  IncompleteReason                                                            CodeUsed
patientA       DTaP/IPV/Hib/HepB   Missed              2020-05-01      No             NULL              NULL                                                                        6IN1_ADM
patientA       MenB                Eligible and Due    NULL            No             NULL              NULL                                                                        NULL
patientA       Rotavirus           Declined            NULL            No             NULL              NULL                                                                        Rotavirus_DEC
patientB       DTaP/IPV/Hib/HepB   Completed           2019-06-15      No             NULL              NULL                                                                        6IN1_ADM
patientB       MenB                Contraindicated     NULL            No             NULL              NULL                                                                        MenB_CONTRA
patientB       Rotavirus           Eligible and Due    NULL            No             NULL              NULL                                                                        NULL
patientC       DTaP/IPV/Hib/HepB   Incomplete Course   2021-05-15      No             2022-05-15        Missing Hib and/or HepB protection. Recommend 6-in-1 dose after 12 months.  4IN1_ADM
patientC       dTaP/IPV            Completed           2021-06-01      Yes            NULL              NULL                                                                        DTAPIPV_ADM
patientD       DTaP/IPV/Hib/HepB   Missed              2016-01-20      No             NULL              NULL                                                                        6IN1_ADM
patientD       MenB                Missed              NULL            No             NULL              NULL                                                                        NULL
patientE       DTaP/IPV/Hib/HepB   Incomplete Course   2022-04-10      No             2023-04-10        Missing Hib and/or HepB protection. Recommend 6-in-1 dose after 12 months.  5IN1_ADM
patientE       dTaP/IPV            Completed           2022-04-10      Yes            NULL              NULL                                                                        DTAPIPV_ADM
patientF       DTaP/IPV/Hib/HepB   Incomplete Course   2021-09-01      No             2022-09-01        Missing Hib and/or HepB protection. Recommend 6-in-1 dose after 12 months.  4IN1_ADM
patientF       MenB                Eligible and Due    NULL            No             NULL              NULL                                                                        NULL
*/
