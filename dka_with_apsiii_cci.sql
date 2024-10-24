WITH patient_info AS (
    SELECT
        icu.stay_id, -- Use stay_id where available
        icu.hadm_id, -- Use hadm_id for joining with tables that don't have stay_id
        pat.subject_id,
        pat.gender,
        pat.anchor_age,
        icu.intime AS admit_time,  -- Admission time
        icu.outtime AS discharge_time,  -- Discharge time
        icu.los AS LoS,
        -- Combine ICD codes into a list per ICU stay
        ARRAY_AGG(DISTINCT diag.icd_code) AS icd_codes, 
        -- Assign DKA label if any of the ICD codes match DKA-related codes
        MAX(CASE 
            WHEN diag.icd_code IN ('E101', 'E1010', 'E1011', 'E111', 'E1110', 'E1111') THEN 1
            ELSE 0
        END) AS developed_dka
    FROM
        `physionet-data.mimiciv_hosp.patients` pat
    JOIN
        `physionet-data.mimiciv_icu.icustays` icu
    ON
        pat.subject_id = icu.subject_id
    JOIN
        `physionet-data.mimiciv_hosp.diagnoses_icd` diag
    ON
        icu.hadm_id = diag.hadm_id
    WHERE
        diag.icd_code LIKE 'E10%' 
        OR diag.icd_code LIKE 'E11%'
    GROUP BY
        icu.stay_id, icu.hadm_id, icu.intime, icu.outtime, pat.gender, pat.anchor_age, pat.subject_id,icu.los
),

-- Extract vital signs (chartevents using stay_id)
vitals AS (
    SELECT
        vitals.stay_id, -- Use stay_id for chartevents
        AVG(CASE WHEN itemid = 220045 THEN valuenum END) AS avg_heart_rate,
        AVG(CASE WHEN itemid = 220621 THEN valuenum END) AS avg_glucose,
        AVG(CASE WHEN itemid = 220210 THEN valuenum END) AS avg_resp_rate,
        AVG(CASE WHEN itemid = 223761 THEN valuenum END) AS avg_temperature,
        AVG(CASE WHEN itemid = 220277 THEN valuenum END) AS avg_spo2,
        AVG(CASE WHEN itemid = 220545 THEN valuenum END) AS avg_hematocrit,
        AVG(CASE WHEN itemid = 220228 THEN valuenum END) AS avg_hemoglobin,
        AVG(CASE WHEN itemid = 227073 THEN valuenum END) AS avg_aniongap
    FROM
        `physionet-data.mimiciv_icu.chartevents` vitals
    WHERE
        itemid IN (220045, 220210, 223761, 220277, 220545, 220228, 227073,220621)
    GROUP BY
        stay_id
),

-- Extract bicarbonate using hadm_id (for labevents)
bicarbonate_lab AS (
    SELECT
        labevents.hadm_id, -- Use hadm_id for joining
        AVG(CASE WHEN itemid = 50882 THEN valuenum END) AS avg_bicarbonate
    FROM
        `physionet-data.mimiciv_hosp.labevents` labevents
    WHERE
        itemid = 50882
    GROUP BY
        hadm_id
),

-- Extract Charlson Comorbidity Index
charlson_comorbidity AS (
    SELECT
        cc.subject_id, -- Use subject_id for consistency
        cc.hadm_id, -- Use hadm_id for joining with other tables
        cc.charlson_comorbidity_index
    FROM
        `physionet-data.mimiciv_derived.charlson` cc
),

apsiii_data AS (
    SELECT
        aps.stay_id,
        aps.apsiii,  -- APSIII score
    FROM
        `physionet-data.mimiciv_derived.apsiii` aps
)

-- Final selection
SELECT
    pi.stay_id,  -- stay_id used where available
    pi.hadm_id,  -- hadm_id included for other table joins
    pi.subject_id,
    pi.gender,
    pi.anchor_age,
    pi.admit_time,  
    pi.discharge_time,
    pi.LoS, 
    vit.avg_heart_rate,
    vit.avg_resp_rate,
    vit.avg_temperature,
    vit.avg_spo2,
    vit.avg_hematocrit,
    vit.avg_hemoglobin,
    vit.avg_aniongap,
    bicarb.avg_bicarbonate,  
    cc.charlson_comorbidity_index,  
    aps.apsiii,  -- APSIII score
    pi.developed_dka  -- Final DKA label
FROM
    patient_info pi
LEFT JOIN
    vitals vit ON pi.stay_id = vit.stay_id
LEFT JOIN
    bicarbonate_lab bicarb ON pi.hadm_id = bicarb.hadm_id  -- Join on hadm_id for labevents
LEFT JOIN
    charlson_comorbidity cc ON pi.hadm_id = cc.hadm_id  -- Join on hadm_id for Charlson Comorbidity Index
LEFT JOIN
    apsiii_data aps ON pi.stay_id = aps.stay_id  -- Join using stay_id for APSIII data
