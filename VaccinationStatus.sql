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
    )
SELECT 
    ev.LDSBusinessId,
    ev.VaccineName,
    CASE 
        WHEN cv.VaccineID IS NOT NULL THEN 'Contraindicated'
        WHEN dv.VaccineID IS NOT NULL THEN 'Declined'
        WHEN ad.AdministeredCount < rd.TotalDoses THEN 'Missed'
        WHEN ad.AdministeredCount >= rd.TotalDoses THEN 'Completed'
        ELSE 'Eligible and Due'
    END AS VaccinationStatus,
    ad.LastAdministeredDate AS DateVaccinated,
    CASE 
        WHEN ve.OutOfSchedule = 'Yes' THEN 'Yes' 
        ELSE 'No' 
    END AS OutOfSchedule
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
LDSBusinessId	VaccineName	        VaccinationStatus	DateVaccinated	OutOfSchedule
patientA	    DTaP/IPV/Hib/HepB	Missed	            NULL	        No
patientA	    MenB	            Eligible and Due	NULL	        No
patientA	    Rotavirus	        Declined	        NULL	        No
patientB	    DTaP/IPV/Hib/HepB	Completed	        2019-06-15	    No
patientB	    MenB	            Contraindicated 	NULL	        No
patientB	    Rotavirus	        Eligible and Due	NULL	        No
patientC	    Influenza	        Completed	        2022-10-01	    Yes
patientC	    Influenza	        Eligible and Due	NULL	        No
patientD	    DTaP/IPV/Hib/HepB	Missed	            NULL	        No
patientD	    MenB	            Missed	            NULL	        No
patientD	    Rotavirus	        Eligible and Due	NULL	        No
*/
