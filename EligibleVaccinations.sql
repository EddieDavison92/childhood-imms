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
LDSBusinessId  VaccineID  VaccineName         DoseNumber  EligibleFromDate  EligibleToDate  MaximumAgeDays  CurrentlyEligible  EligibleAgainDate
patientA       1          DTaP/IPV/Hib/HepB   1           2020-03-01        2021-01-01      365             No                 NULL
patientA       1          DTaP/IPV/Hib/HepB   2           2020-05-01        2021-03-01      365             No                 NULL
patientA       1          DTaP/IPV/Hib/HepB   3           2020-09-01        2021-09-01      365             No                 NULL
patientA       2          MenB                1           2020-04-01        2026-01-01      1825            Yes                NULL
patientB       1          DTaP/IPV/Hib/HepB   1           2018-08-15        2019-06-15      365             No                 NULL
patientB       1          DTaP/IPV/Hib/HepB   2           2019-02-15        2020-02-15      365             No                 NULL
patientB       1          DTaP/IPV/Hib/HepB   3           2019-06-15        2020-06-15      365             No                 NULL
patientC       1          DTaP/IPV/Hib/HepB   1           2021-03-15        2022-03-15      365             No                 2022-05-15
patientC       1          DTaP/IPV/Hib/HepB   2           2021-05-15        2022-05-15      365             No                 2022-05-15
patientC       1          DTaP/IPV/Hib/HepB   3           2021-08-15        2022-08-15      365             No                 2022-05-15
patientC       14         dTaP/IPV            Booster     2024-07-15        2025-09-15      2190            No                 NULL
patientD       1          DTaP/IPV/Hib/HepB   1           2015-07-20        2016-07-20      365             No                 NULL
patientD       1          DTaP/IPV/Hib/HepB   2           2016-01-20        2017-01-20      365             No                 NULL
patientE       1          DTaP/IPV/Hib/HepB   1           2022-02-10        2023-02-10      365             No                 2023-04-10
patientE       1          DTaP/IPV/Hib/HepB   2           2022-04-10        2023-04-10      365             No                 2023-04-10
patientE       14         dTaP/IPV            Booster     2025-06-10        2026-08-10      2190            No                 NULL
patientF       1          DTaP/IPV/Hib/HepB   1           2021-07-01        2022-07-01      365             No                 2022-09-01
patientF       1          DTaP/IPV/Hib/HepB   2           2021-09-01        2022-09-01      365             No                 2022-09-01
patientF       2          MenB                1           2021-07-01        2027-04-01      9125            Yes                NULL
*/
