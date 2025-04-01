-- VaccinationStatus.sql

-- Create a view for VaccinationStatusReport
CREATE VIEW VaccinationStatusReport AS
WITH 
    -- Step 1: AdministeredDoses
    AdministeredDoses AS (
        SELECT 
            ve.LDSBusinessId,
            ve.VaccineID,
            COUNT(*) AS AdministeredCount,
            MAX(ve.EventDate) AS LastAdministeredDate
        FROM 
            VaccineEvents ve
        WHERE 
            ve.EventType = 'Administration'
            AND ve.IncorrectVaccine = 'No'  -- Only count correct vaccines
        GROUP BY 
            ve.LDSBusinessId,
            ve.VaccineID
    ),
    
    -- Step 2: DeclinedVaccines
    DeclinedVaccines AS (
        SELECT 
            ve.LDSBusinessId,
            ve.VaccineID
        FROM 
            VaccineEvents ve
        WHERE 
            ve.EventType = 'Declined'
    ),
    
    -- Step 3: ContraindicatedVaccines
    ContraindicatedVaccines AS (
        SELECT 
            ve.LDSBusinessId,
            ve.VaccineID
        FROM 
            VaccineEvents ve
        WHERE 
            ve.EventType = 'Contraindicated'
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
    
    -- New Step 5: Incorrect Vaccines
    IncorrectVaccines AS (
        SELECT 
            ve.LDSBusinessId,
            ve.VaccineID,
            MAX(ve.EventDate) AS LastIncorrectDate,
            MAX(ve.EligibleAgainDate) AS EligibleAgainDate
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
        -- Add the new Incomplete Course status
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
    -- Add new column for when patient will be eligible again
    iv.EligibleAgainDate AS NextEligibleDate
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
LDSBusinessId	VaccineName	        VaccinationStatus	DateVaccinated	OutOfSchedule	NextEligibleDate
patientA	    DTaP/IPV/Hib/HepB	Missed	            NULL	        No	        NULL
patientA	    MenB	            Eligible and Due	NULL	        No	        NULL
patientA	    Rotavirus	        Declined	        NULL	        No	        NULL
patientB	    DTaP/IPV/Hib/HepB	Completed	        2019-06-15	    No	        NULL
patientB	    MenB	            Contraindicated 	NULL	        No	        NULL
patientB	    Rotavirus	        Eligible and Due	NULL	        No	        NULL
patientC	    Influenza	        Completed	        2022-10-01	    Yes	        NULL
patientC	    Influenza	        Eligible and Due	NULL	        No	        NULL
patientD	    DTaP/IPV/Hib/HepB	Missed	            NULL	        No	        NULL
patientD	    MenB	            Missed	            NULL	        No	        NULL
patientD	    Rotavirus	        Eligible and Due	NULL	        No	        NULL
*/
