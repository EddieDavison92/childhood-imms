-- EligibleVaccinations.sql

-- Create a view for EligibleVaccinations with CurrentlyEligible flag
CREATE VIEW EligibleVaccinations AS
WITH PatientAge AS (
    SELECT 
        p.LDSBusinessId,
        p.DateOfBirth,
        DATEDIFF(DAY, p.DateOfBirth, GETDATE()) AS AgeInDays
    FROM 
        PATIENT_IDENTIFIABLE p
    WHERE 
        p.IsDeleted = 0
        AND DATEDIFF(DAY, p.DateOfBirth, GETDATE()) < 9125 -- Limit to individuals younger than ~25 years
),
-- Get the most recent incorrect vaccines for each patient and vaccine type
IncorrectVaccineHistory AS (
    SELECT 
        ve.LDSBusinessId,
        ve.VaccineID,
        MAX(ve.EventDate) AS LastIncorrectVaccineDate,
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
    pa.LDSBusinessId,
    sched.VaccineID,
    sched.VaccineName,
    sched.DoseNumber,
    DATEADD(DAY, sched.EligibleAgeFromDays, pa.DateOfBirth) AS EligibleFromDate,
    DATEADD(DAY, sched.EligibleAgeToDays, pa.DateOfBirth) AS EligibleToDate,
    sched.MaximumAgeDays,
    CASE 
        -- Check if patient had an incorrect vaccine and is still in the ineligibility period
        WHEN ivh.EligibleAgainDate IS NOT NULL AND GETDATE() < ivh.EligibleAgainDate THEN 'No'
        -- Normal eligibility check
        WHEN pa.AgeInDays >= sched.EligibleAgeFromDays 
             AND pa.AgeInDays <= sched.MaximumAgeDays THEN 'Yes' 
        ELSE 'No' 
    END AS CurrentlyEligible,
    ivh.EligibleAgainDate
FROM 
    PatientAge pa
CROSS JOIN 
    IMMUNISATION_SCHEDULE sched
LEFT JOIN
    IncorrectVaccineHistory ivh ON pa.LDSBusinessId = ivh.LDSBusinessId 
                              AND sched.VaccineID = ivh.VaccineID
WHERE 
    pa.AgeInDays >= sched.EligibleAgeFromDays;

-- Example Output: EligibleVaccinations
/*
LDSBusinessId	VaccineID	VaccineName	        DoseNumber	EligibleFromDate	EligibleToDate	MaximumAgeDays	CurrentlyEligible	EligibleAgainDate
patientA	    1	        DTaP/IPV/Hib/HepB	1	        2020-03-01	        2021-01-01	    365	            No	            NULL
patientA	    1	        DTaP/IPV/Hib/HepB	2	        2020-05-01	        2021-03-01	    365	            No	            NULL
patientA	    1	        DTaP/IPV/Hib/HepB	3	        2020-09-01	        2021-09-01	    365	            No	            NULL
patientA	    2	        MenB	            1	        2020-04-01	        2026-01-01	    1825	        Yes	            NULL
patientA	    3	        Rotavirus	        1	        2022-01-01	        2023-01-01	    730	            No	            NULL
patientB	    1	        DTaP/IPV/Hib/HepB	1	        2018-08-15	        2019-06-15	    365	            No	            NULL
patientB	    1	        DTaP/IPV/Hib/HepB	2	        2019-02-15	        2020-02-15	    365	            No	            NULL
patientB	    1	        DTaP/IPV/Hib/HepB	3	        2019-06-15	        2020-06-15	    365	            No	            NULL
patientB	    2	        MenB	            1	        2018-08-15	        2024-06-15	    9125	        Yes	            NULL
patientB	    3	        Rotavirus	        1	        2019-06-15	        2020-06-15	    730	            No	            NULL
patientC	    4	        Influenza	        1	        2021-10-01	        2023-10-01	    365	            No	            NULL
patientC	    4	        Influenza	        2	        2022-10-01	        2024-10-01	    365	            No	            NULL
patientD	    1	        DTaP/IPV/Hib/HepB	1	        2015-07-20	        2016-07-20	    365	            No	            NULL
patientD	    1	        DTaP/IPV/Hib/HepB	2	        2016-01-20	        2017-01-20	    365	            No	            NULL
patientD	    1	        DTaP/IPV/Hib/HepB	3	        2016-05-20	        2017-05-20	    365	            No	            NULL
patientD	    2	        MenB	            1	        2015-08-20	        2021-05-20	    9125	        Yes	            NULL
patientD	    3	        Rotavirus	        1	        2017-05-20	        2018-05-20	    730	            No	            NULL
*/
