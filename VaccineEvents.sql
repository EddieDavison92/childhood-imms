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
        END AS OutOfSchedule
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
    ev.OutOfSchedule
FROM 
    AllVaccineEvents ev;

-- Example Output: VaccineEvents
/*
LDSBusinessId	VaccineID	VaccineName	        DoseNumber	EventType	        EventDate	    OutOfSchedule
patientA	    1	        DTaP/IPV/Hib/HepB	1	        Administration	    2020-03-01	    No
patientA	    1	        DTaP/IPV/Hib/HepB	2	        Administration	    2020-05-01	    No
patientA	    3	        Rotavirus	        1	        Declined	        NULL	        No
patientB	    1	        DTaP/IPV/Hib/HepB	1	        Administration	    2018-08-15	    No
patientB	    1	        DTaP/IPV/Hib/HepB	2	        Administration	    2019-02-15	    No
patientB	    1	        DTaP/IPV/Hib/HepB	3	        Administration	    2019-06-15	    No
patientB	    2	        MenB	            1	        Contraindicated 	NULL	        No
patientC	    4	        Influenza	        1	        Administration	    2021-10-01	    Yes
patientC	    4	        Influenza	        2	        Administration	    2022-10-01	    No
patientD	    1	        DTaP/IPV/Hib/HepB	1	        Administration	    2015-07-20	    No
patientD	    1	        DTaP/IPV/Hib/HepB	2	        Administration	    2016-01-20	    No
patientD	    2	        MenB	            1	        Contraindicated 	NULL	        No
*/
