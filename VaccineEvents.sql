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
        COALESCE(sched.IneligibilityPeriodMonths, 0) AS IneligibilityPeriodMonths
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
    END AS EligibleAgainDate
FROM 
    AllVaccineEvents ev;

-- Example Output: VaccineEvents
/*
LDSBusinessId	VaccineID	VaccineName	        DoseNumber	EventType	        EventDate	    OutOfSchedule	CorrectVaccine	EligibleAgainDate
patientA	    1	        DTaP/IPV/Hib/HepB	1	        Administration	    2020-03-01	    No	        Yes	        NULL
patientA	    1	        DTaP/IPV/Hib/HepB	2	        Administration	    2020-05-01	    No	        Yes	        NULL
patientA	    3	        Rotavirus	        1	        Declined	        NULL	        No	        No	        NULL
patientB	    1	        DTaP/IPV/Hib/HepB	1	        Administration	    2018-08-15	    No	        Yes	        NULL
patientB	    1	        DTaP/IPV/Hib/HepB	2	        Administration	    2019-02-15	    No	        Yes	        NULL
patientB	    1	        DTaP/IPV/Hib/HepB	3	        Administration	    2019-06-15	    No	        Yes	        NULL
patientB	    2	        MenB	            1	        Contraindicated 	NULL	        No	        No	        NULL
patientC	    4	        Influenza	        1	        Administration	    2021-10-01	    Yes	        No	        NULL
patientC	    4	        Influenza	        2	        Administration	    2022-10-01	    No	        No	        NULL
patientD	    1	        DTaP/IPV/Hib/HepB	1	        Administration	    2015-07-20	    No	        Yes	        NULL
patientD	    1	        DTaP/IPV/Hib/HepB	2	        Administration	    2016-01-20	    No	        Yes	        NULL
patientD	    2	        MenB	            1	        Contraindicated 	NULL	        No	        No	        NULL
*/
