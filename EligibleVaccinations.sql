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
        WHEN pa.AgeInDays >= sched.EligibleAgeFromDays 
             AND pa.AgeInDays <= sched.MaximumAgeDays THEN 'Yes' 
        ELSE 'No' 
    END AS CurrentlyEligible
FROM 
    PatientAge pa
CROSS JOIN 
    IMMUNISATION_SCHEDULE sched
WHERE 
    pa.AgeInDays >= sched.EligibleAgeFromDays;

-- Example Output: EligibleVaccinations
/*
LDSBusinessId	VaccineID	VaccineName	        DoseNumber	EligibleFromDate	EligibleToDate	MaximumAgeDays	CurrentlyEligible
patientA	    1	        DTaP/IPV/Hib/HepB	1	        2020-03-01	        2021-01-01	    365	            No
patientA	    1	        DTaP/IPV/Hib/HepB	2	        2020-05-01	        2021-03-01	    365	            No
patientA	    1	        DTaP/IPV/Hib/HepB	3	        2020-09-01	        2021-09-01	    365	            No
patientA	    2	        MenB	            1	        2020-04-01	        2026-01-01	    1825	        Yes
patientA	    3	        Rotavirus	        1	        2022-01-01	        2023-01-01	    730	            No
patientB	    1	        DTaP/IPV/Hib/HepB	1	        2018-08-15	        2019-06-15	    365	            No
patientB	    1	        DTaP/IPV/Hib/HepB	2	        2019-02-15	        2020-02-15	    365	            No
patientB	    1	        DTaP/IPV/Hib/HepB	3	        2019-06-15	        2020-06-15	    365	            No
patientB	    2	        MenB	            1	        2018-08-15	        2024-06-15	    9125	        Yes
patientB	    3	        Rotavirus	        1	        2019-06-15	        2020-06-15	    730	            No
patientC	    4	        Influenza	        1	        2021-10-01	        2023-10-01	    365	            No
patientC	    4	        Influenza	        2	        2022-10-01	        2024-10-01	    365	            No
patientD	    1	        DTaP/IPV/Hib/HepB	1	        2015-07-20	        2016-07-20	    365	            No
patientD	    1	        DTaP/IPV/Hib/HepB	2	        2016-01-20	        2017-01-20	    365	            No
patientD	    1	        DTaP/IPV/Hib/HepB	3	        2016-05-20	        2017-05-20	    365	            No
patientD	    2	        MenB	            1	        2015-08-20	        2021-05-20	    9125	        Yes
patientD	    3	        Rotavirus	        1	        2017-05-20	        2018-05-20	    730	            No
*/
