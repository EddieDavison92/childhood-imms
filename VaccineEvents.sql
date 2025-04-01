-- VaccineEvents.sql

-- Create a view for VaccineEvents
CREATE VIEW VaccineEvents AS
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
-- Define a function to split IncompatibleClusterIDs
IncompatibleCodesExpanded AS (
    SELECT 
        i.VaccineID,
        i.VaccineName,
        i.DoseNumber,
        value AS IncompatibleClusterID
    FROM 
        IMMUNISATION_SCHEDULE i
    CROSS APPLY STRING_SPLIT(i.IncompatibleClusterIDs, ',')
    WHERE 
        i.IncompatibleClusterIDs IS NOT NULL 
        AND i.IncompatibleClusterIDs <> ''
),
AllVaccineEvents AS (
    SELECT 
        pa.LDSBusinessId,
        sched.VaccineID,
        sched.VaccineName,
        sched.DoseNumber,
        -- Determine EventType based on which ClusterID matched
        CASE 
            WHEN clut.ClusterID = sched.AdministeredClusterID THEN 'Administration'
            WHEN clut.ClusterID = sched.DrugClusterID THEN 'Administration'
            WHEN clut.ClusterID = sched.ContraindicatedClusterID THEN 'Contraindicated'
            WHEN clut.ClusterID = sched.DeclinedClusterID THEN 'Declined'
            ELSE 'Other'
        END AS EventType,
        obs.ClinicalEffectiveDate AS EventDate,
        -- Determine if the event was out of schedule (only for Administration)
        CASE 
            WHEN clut.ClusterID = sched.AdministeredClusterID 
                 AND DATEDIFF(DAY, pa.DateOfBirth, obs.ClinicalEffectiveDate) > sched.MaximumAgeDays 
            THEN 'Yes' 
            ELSE 'No' 
        END AS OutOfSchedule,
        -- Determine if this is an incompatible vaccine
        CASE 
            WHEN ic.IncompatibleClusterID IS NOT NULL THEN 'Yes'
            ELSE 'No'
        END AS IncorrectVaccine,
        -- Get the ineligibility period if applicable
        COALESCE(sched.IneligibilityPeriodMonths, 0) AS IneligibilityPeriodMonths,
        -- Add the explanation from the schedule
        CASE
            WHEN ic.IncompatibleClusterID IS NOT NULL THEN sched.IncompatibleExplanation
            ELSE NULL
        END AS IncompleteReason,
        -- Store the actual code used for reference
        clut.ClusterID AS CodeUsed
    FROM 
        OBSERVATION obs
    INNER JOIN 
        CODES_LUT clut ON obs.CoreConceptId = clut.ClusterID
    INNER JOIN 
        IMMUNISATION_SCHEDULE sched ON 
            sched.AdministeredClusterID = clut.ClusterID OR
            sched.DrugClusterID = clut.ClusterID OR
            sched.DeclinedClusterID = clut.ClusterID OR
            sched.ContraindicatedClusterID = clut.ClusterID 
    LEFT JOIN
        IncompatibleCodesExpanded ic ON sched.VaccineID = ic.VaccineID 
                                    AND sched.DoseNumber = ic.DoseNumber
                                    AND clut.ClusterID = ic.IncompatibleClusterID
    INNER JOIN 
        PatientAge pa ON pa.LDSBusinessId = obs.LDSBusinessId
    WHERE 
        obs.IsDeleted = 0
)
SELECT 
    ev.LDSBusinessId,
    ev.VaccineID,
    ev.VaccineName,
    ev.DoseNumber,
    ev.EventType,
    ev.EventDate,
    ev.OutOfSchedule,
    ev.IncorrectVaccine,
    CASE 
        WHEN ev.IncorrectVaccine = 'Yes' THEN 
            DATEADD(MONTH, ev.IneligibilityPeriodMonths, ev.EventDate)
        ELSE NULL
    END AS EligibleAgainDate,
    ev.IncompleteReason,
    ev.CodeUsed
FROM 
    AllVaccineEvents ev;

-- Example Output: VaccineEvents
/*
LDSBusinessId  VaccineID  VaccineName         DoseNumber  EventType       EventDate     OutOfSchedule  IncorrectVaccine  EligibleAgainDate  IncompleteReason                                                          CodeUsed
patientA       1          DTaP/IPV/Hib/HepB   1           Administration  2020-03-01    No             No                NULL               NULL                                                                      6IN1_ADM
patientA       1          DTaP/IPV/Hib/HepB   2           Administration  2020-05-01    No             No                NULL               NULL                                                                      6IN1_ADM
patientA       3          Rotavirus           1           Declined        NULL          No             No                NULL               NULL                                                                      Rotavirus_DEC
patientB       1          DTaP/IPV/Hib/HepB   1           Administration  2018-08-15    No             No                NULL               NULL                                                                      6IN1_ADM
patientB       1          DTaP/IPV/Hib/HepB   2           Administration  2019-02-15    No             No                NULL               NULL                                                                      6IN1_ADM
patientB       1          DTaP/IPV/Hib/HepB   3           Administration  2019-06-15    No             No                NULL               NULL                                                                      6IN1_ADM
patientB       2          MenB                1           Contraindicated NULL          No             No                NULL               NULL                                                                      MenB_CONTRA
patientC       1          DTaP/IPV/Hib/HepB   1           Administration  2021-05-15    No             Yes               2022-05-15         Missing Hib and/or HepB protection. Recommend 6-in-1 dose after ineligibility period.  4IN1_ADM
patientC       14         dTaP/IPV            Booster     Administration  2021-06-01    Yes            No                NULL               NULL                                                                      DTAPIPV_ADM
patientD       1          DTaP/IPV/Hib/HepB   1           Administration  2015-07-20    No             No                NULL               NULL                                                                      6IN1_ADM
patientD       1          DTaP/IPV/Hib/HepB   2           Administration  2016-01-20    No             No                NULL               NULL                                                                      6IN1_ADM
patientE       1          DTaP/IPV/Hib/HepB   1           Administration  2022-04-10    No             Yes               2023-04-10         Missing Hib and/or HepB protection. Recommend 6-in-1 dose after ineligibility period.  5IN1_ADM
patientE       14         dTaP/IPV            Booster     Administration  2022-04-10    Yes            No                NULL               NULL                                                                      DTAPIPV_ADM
patientF       1          DTaP/IPV/Hib/HepB   1           Administration  2021-09-01    No             Yes               2022-09-01         Missing Hib and/or HepB protection. Recommend 6-in-1 dose after ineligibility period.  4IN1_ADM
*/
