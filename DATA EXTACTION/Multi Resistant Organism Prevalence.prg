drop program wh_jw_temp_report go
create program wh_jw_temp_report
; Program Notes
    /*
    Temporary report template used by Jason Whittle for CCL programs
    Programmer: Jason Whittle
    Service Request - 1390951
    Date: 17 July 2026
    Request: 
    I am hoping to audit prevalence of multi-resistant organisms in WH emergency department presentations.
    Y.P (cc'd) thought you might be able to help.
    Could I please request a one-off data extraction for all ED presentations to Footscray and Sunshine
    emergency departments for the period 01/07/25 through 30/06/26 please?
    Y.P and I initially discussed excluding duplicates but on further consideration I would like to
    include all presentations for those who present more than once in this period as each presentation
    presents an opportunity for these MDRs to go unrecognised and untreated.
    Other data that would be useful (but not essential) would include length of ED stay, length of
    hospital stay and length of ICU stay where applicable as well as MET activation, code blue
    activation and ICU admission within 72 hours of presentation. Finally, if possible, could I also
    have a field for if the ED infectious screening was done please? (yes/no) is fine.
    Ideally these would be in separate files but understandable if this is not possible.

    Notes:
    - filtered for all 'Emergency' Encounter types on the ELH table for the given timeframe
    - filtered for Footscray and Sunshine sites
    COLUMNS Explained
    ED_INF_DIS_RSK_SCR_DONE = If the "Ed Infectious Disease Risk Screening" powerform was done for the encounter
    INF_DIS_ASSESS_DONE = If the "Infectious Disease Assessment" powerform was done for the encounter
    MULTI_RESIST_ORG_CNT = The number of organisms for the encounter that had resistances to more than one drug
    URN = Patients URN number
    ICU_WITHIN_72_HRS = This is an indication of if the patient was in an "ICU" Nurse unit within 72h after
    arrival of the encounter. Could be a different encounter.
    */

prompt
        "Output to File/Printer/MINE" = "MINE"
	
    WITH OUTDEV

; Record Structures
    RECORD RS_ENCOUNTERS (
    1 LIST_ENCOUNTERS [*]
        2 A_ENCOUNTER_ID            = F8
        2 A_ENCOUNTER_NO            = VC
        2 A_PERSON_ID               = F8
        2 A_URN                     = VC
        2 A_FACILITY                = VC
        2 A_NURSE_UNIT              = VC
        2 A_ARRIVE_DT_TM            = VC
        2 A_DEPART_DT_TM            = VC
        2 A_MINS_AT_LOC             = I4
        2 A_ARRIVE_DT_TM_DQ8        = DQ8
        2 A_ICU_WITHIN_72_HRS       = VC
        2 A_ED_INF_DIS_RSK_SCR_DONE = VC
        2 A_INF_DIS_ASSESS_DONE     = VC
        2 A_MULTI_RESIST_ORG_CNT    = I4
    )

; Variables
    ; Change dates below for final run, keep date range limited for testing
    DECLARE ENC_ARRIVE_START_DT_VAR = VC WITH CONSTANT("01-MAR-2026 00:00:00");"01-MAR-2026 00:00:00""01-JUL-2025 00:00:00"
    DECLARE ENC_ARRIVE_END_DT_VAR   = VC WITH CONSTANT("30-JUN-2026 23:59:59");"30-JUN-2026 23:59:59""03-MAR-2026 23:59:59"
    ; Variables for counting etc
    DECLARE NUM_ROWS                = I4 WITH NOCONSTANT(0),PROTECT ; To save the total no encounters
    DECLARE NUM_RESISTANCES         = I4 WITH NOCONSTANT(0),PROTECT ; To save the total no resistances
    DECLARE COUNTER                 = I4 WITH NOCONSTANT(0),PROTECT ; counter
    DECLARE i                       = I4 WITH NOCONSTANT(0),PROTECT ; counter
    DECLARE j                       = I4 WITH NOCONSTANT(0),PROTECT ; counter
    DECLARE X                       = I4 WITH NOCONSTANT(0),PROTECT ; counter
    DECLARE Y                       = I4 WITH NOCONSTANT(0),PROTECT ; counter
    DECLARE ICU_DIFF                = I4 WITH NOCONSTANT(0),PROTECT ; To save the hours between ED and ICU arrival

; Query to get all the initial E Loc Hist details for emergency presentations
    SELECT DISTINCT INTO "NL:"
          ELH.ENCNTR_ID
        , ELH_FACILITY_DISP         = UAR_GET_CODE_DISPLAY(ELH.LOC_FACILITY_CD)
        , ELH_LOC_NURSE_UNIT_DISP   = UAR_GET_CODE_DISPLAY(ELH.LOC_NURSE_UNIT_CD)
        , ARRIVE_DT_TM              = FORMAT(ELH.ARRIVE_DT_TM, "YYYY-MM-DD HH:MM:SS ;L;D")
        , DEPART_DT_TM              = FORMAT(ELH.DEPART_DT_TM, "YYYY-MM-DD HH:MM:SS ;L;D")
        , MINS_AT_LOC               = DATETIMEDIFF(ELH.DEPART_DT_TM, ELH.ARRIVE_DT_TM, 4)
        , ARRIVE_DT_TM_DQ8          = ELH.ARRIVE_DT_TM
    FROM
        ENCNTR_LOC_HIST       ELH
    WHERE
        ELH.ACTIVE_IND = 1 ; Active data only
        AND ELH.ARRIVE_DT_TM < ELH.DEPART_DT_TM ; Patient was at location for >0 time
        AND ELH.ARRIVE_DT_TM > CNVTDATETIME("01-JAN-2018 00:00:00") ; Arrive time exists in EMR timeframe
        AND ELH.DEPART_DT_TM > CNVTDATETIME("01-JAN-2018 00:00:00") ; Depart time exists in EMR timeframe
        AND ELH.LOC_FACILITY_CD IN 
            (
                  85758822.00 ; Footscray
                , 86163400.00 ; Sunshine
            )
        AND ELH.ENCNTR_TYPE_CD = 309310.00 ; 'Emergency' from code set 71, Emergency encounters only
        AND ELH.ARRIVE_DT_TM >= CNVTDATETIME(ENC_ARRIVE_START_DT_VAR)
        AND ELH.ARRIVE_DT_TM <= CNVTDATETIME(ENC_ARRIVE_END_DT_VAR)
    ORDER BY
    	ELH.ENCNTR_ID
    HEAD REPORT
        COUNTER = 0
    DETAIL
        COUNTER += 1 ; add one to the counter for the loop
        IF (MOD(COUNTER, 1000) = 1) ; On 1st row and every 1000th row after (1, 1001, 2001...), trigger expansion
            STAT = ALTERLIST(RS_ENCOUNTERS->LIST_ENCOUNTERS, COUNTER + 999) ; add storage space in chunks of 1000
        ENDIF
        ; Save the columns to the record structure
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_ENCOUNTER_ID  = ELH.ENCNTR_ID
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_FACILITY      = ELH_FACILITY_DISP
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_NURSE_UNIT    = ELH_LOC_NURSE_UNIT_DISP
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_ARRIVE_DT_TM  = ARRIVE_DT_TM
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_DEPART_DT_TM  = DEPART_DT_TM
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_MINS_AT_LOC   = MINS_AT_LOC
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_ARRIVE_DT_TM_DQ8 = ARRIVE_DT_TM_DQ8
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_ICU_WITHIN_72_HRS = "N" ; Changed later to Y if needed
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_ED_INF_DIS_RSK_SCR_DONE = "N" ; changed later
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_INF_DIS_ASSESS_DONE = "N" ; changed later
        RS_ENCOUNTERS->LIST_ENCOUNTERS[COUNTER].A_MULTI_RESIST_ORG_CNT = 0 ; changed later
    FOOT REPORT
        NUM_ROWS = COUNTER ; after the loop save the counter to the variable NUM_ROWS
        STAT = ALTERLIST(RS_ENCOUNTERS->LIST_ENCOUNTERS, NUM_ROWS) ; resize list to final row count
    WITH TIME = 1000

; Query to get all the patient person id's for each encounter id
    SELECT INTO "NL:"
        E.PERSON_ID
        , E.ENCNTR_ID
    FROM
        (DUMMYT D1 WITH SEQ = NUM_ROWS)
        , ENCOUNTER E
    PLAN D1
    JOIN E WHERE E.ENCNTR_ID = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_ENCOUNTER_ID
        AND E.ACTIVE_IND = 1
    DETAIL ; For each row in the table returned from the above SELECT FROM WHERE
        ; For the current row, using locateval, find the first location in the record structure that matches
        ; with the current encounter_id, else locateval will return 0
        X = LOCATEVAL(Y, 1, NUM_ROWS, E.ENCNTR_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_ENCOUNTER_ID)
        ; If there is a match update the row for each matching row, also do this for any further matches
        WHILE (X>0)
            RS_ENCOUNTERS->LIST_ENCOUNTERS[X].A_PERSON_ID = E.PERSON_ID ; save the person_id at loc X
            ; find the location of the next matching row, else return 0
            X = LOCATEVAL(Y, X+1, NUM_ROWS, E.ENCNTR_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_ENCOUNTER_ID)
        ENDWHILE ; when X = 0 (a matching encounter isn't found) go to the next encounter id in the table
    WITH TIME = 1000

; Query to get all the patient URN's
    SELECT INTO "NL:"
          PA.PERSON_ID
        , PA.ALIAS
    FROM
        (DUMMYT D1 WITH SEQ = NUM_ROWS)
        , PERSON_ALIAS PA
    PLAN D1
    JOIN PA WHERE PA.PERSON_ID = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_PERSON_ID
        AND PA.ACTIVE_IND = 1	; ACTIVE URNS ONLY
        AND PA.PERSON_ALIAS_TYPE_CD = 10 ; 'URN' FROM CODE SET 319
        AND PA.ALIAS_POOL_CD = 9569589.00 ; WHS UR Number
        AND PA.END_EFFECTIVE_DT_TM > SYSDATE	; EFFECTIVE URNS ONLY
    DETAIL
        X = LOCATEVAL(Y, 1, NUM_ROWS, PA.PERSON_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_PERSON_ID)
        WHILE (X>0)
            RS_ENCOUNTERS->LIST_ENCOUNTERS[X].A_URN = PA.ALIAS ; save the URN for the person_id at loc X
            X = LOCATEVAL(Y, X+1, NUM_ROWS, PA.PERSON_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_PERSON_ID)
        ENDWHILE
    WITH TIME = 1000

; Query to get all the Encounter No's (FIN's)
    SELECT INTO "NL:"
        EA.ENCNTR_ID
        , EA.ALIAS
    FROM
        (DUMMYT D1 WITH SEQ = NUM_ROWS)
        , ENCNTR_ALIAS EA
    PLAN D1
    JOIN EA WHERE EA.ENCNTR_ID = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_ENCOUNTER_ID
        AND EA.ACTIVE_IND = 1 ; ACTIVE FINs ONLY
        AND EA.ENCNTR_ALIAS_TYPE_CD = 1077 ; 'FIN/ENCOUNTER/VISIT NBR' from code set 319
        AND EA.END_EFFECTIVE_DT_TM > SYSDATE ; EFFECTIVE FINs ONLY
    DETAIL
        X = LOCATEVAL(Y, 1, NUM_ROWS, EA.ENCNTR_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_ENCOUNTER_ID)
        WHILE (X>0)
            RS_ENCOUNTERS->LIST_ENCOUNTERS[X].A_ENCOUNTER_NO = EA.ALIAS ; save the FIN for the encounter_id at loc X
            X = LOCATEVAL(Y, X+1, NUM_ROWS, EA.ENCNTR_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_ENCOUNTER_ID)
        ENDWHILE
    WITH TIME = 1000

; Query for if the infectious screening was done 'infectious disease risk screening' powerform
   SELECT INTO "NL:"
        D.ENCNTR_ID
        , D.PERSON_ID
        , D_DESC = CNVTUPPER(D.DESCRIPTION)

    FROM
        (DUMMYT D1 WITH SEQ = NUM_ROWS)
        , DCP_FORMS_ACTIVITY   D
    PLAN D1
    JOIN D WHERE D.ENCNTR_ID = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_ENCOUNTER_ID
        AND D.ACTIVE_IND = 1
        AND CNVTUPPER(D.DESCRIPTION) IN (
            "ED INFECTIOUS DISEASE RISK SCREENING",
            "INFECTIOUS DISEASE ASSESSMENT"
        )
        AND D.FORM_STATUS_CD = 25 ; Auth (Verified)
    DETAIL
        X = LOCATEVAL(Y, 1, NUM_ROWS, D.ENCNTR_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_ENCOUNTER_ID)
        WHILE (X>0)
            IF (D_DESC = "ED INFECTIOUS DISEASE RISK SCREENING")
                RS_ENCOUNTERS->LIST_ENCOUNTERS[X].A_ED_INF_DIS_RSK_SCR_DONE = "Y" ; Record that it was done
            ELSEIF (D_DESC = "INFECTIOUS DISEASE ASSESSMENT")
                RS_ENCOUNTERS->LIST_ENCOUNTERS[X].A_INF_DIS_ASSESS_DONE = "Y" ; Record that it was done
            ENDIF
            X = LOCATEVAL(Y, X+1, NUM_ROWS, D.ENCNTR_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_ENCOUNTER_ID)
        ENDWHILE
    WITH TIME = 1000

; Check if patient was in ICU within 72 hrs of ED arrive time for the person
    SELECT INTO "NL:"
        E.PERSON_ID
        , ICU_ARRIVE_DT_TM = ELH.ARRIVE_DT_TM
    FROM
        (DUMMYT D1 WITH SEQ = NUM_ROWS)
        , ENCOUNTER         E
        , ENCNTR_LOC_HIST ELH
    PLAN D1
    JOIN E ; Get all encounters for the pre filtered patients
        WHERE E.PERSON_ID = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_PERSON_ID
            AND E.ACTIVE_IND = 1
    JOIN ELH WHERE ; join with just ICU encounters
            ELH.ENCNTR_ID = E.ENCNTR_ID
        AND ELH.ARRIVE_DT_TM < ELH.DEPART_DT_TM ; was at loc > 0
        AND ELH.ACTIVE_IND = 1 ; active data only
        ; ICU nurse units only (assuming that "ICU is in the name of the unit")
        AND ELH.LOC_NURSE_UNIT_CD IN
            (
                SELECT CV.CODE_VALUE 
                FROM CODE_VALUE CV 
                WHERE 
                CV.CODE_SET = 220
                and cv.CDF_MEANING = "NURSEUNIT"
                AND CV.DISPLAY = "*ICU*"
            )
    HEAD REPORT
        ICU_DIFF = 0
    DETAIL ; Loop though each row in the table returned
        ; Locate the position of the current patient
        X = LOCATEVAL(Y, 1, NUM_ROWS, E.PERSON_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_PERSON_ID)
        WHILE (X>0)
            ICU_DIFF = DATETIMEDIFF(ICU_ARRIVE_DT_TM, RS_ENCOUNTERS->LIST_ENCOUNTERS[X].A_ARRIVE_DT_TM_DQ8, 3)
            IF (ICU_DIFF > 0 AND ICU_DIFF <= 72)
                RS_ENCOUNTERS->LIST_ENCOUNTERS[X].A_ICU_WITHIN_72_HRS = "Y"
            ENDIF
            X = LOCATEVAL(Y, X+1, NUM_ROWS, E.PERSON_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_PERSON_ID)
        ENDWHILE
    WITH TIME = 1000

; Query to count multi-resistant organisms for each encounter
    SELECT DISTINCT
          CE.ENCNTR_ID
        , MIC.ORGANISM_CD
        , CE_S.ANTIBIOTIC_CD
    FROM
        (DUMMYT D1 WITH SEQ = NUM_ROWS)
        , CLINICAL_EVENT CE
        , CE_MICROBIOLOGY   MIC
        , CE_SUSCEPTIBILITY   CE_S
    PLAN D1
    JOIN CE
        WHERE CE.ENCNTR_ID = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_ENCOUNTER_ID
            AND CE.VALID_UNTIL_DT_TM > SYSDATE ; still valid results only
            ; filter to events updated after the encounter filter date
            AND CE.UPDT_DT_TM > CNVTDATETIME(ENC_ARRIVE_START_DT_VAR)
            AND CE.EVENT_ID > 0.00  ; has an event_id
    JOIN MIC ; CE_MICROBIOLOGY
        WHERE
            MIC.EVENT_ID = CE.EVENT_ID
            AND MIC.VALID_UNTIL_DT_TM > SYSDATE ; still valid results only
    JOIN CE_S ; CE_SUSCEPTIBILITY
        WHERE 
                CE_S.EVENT_ID = MIC.EVENT_ID
            AND CE_S.MICRO_SEQ_NBR = MIC.MICRO_SEQ_NBR 
            AND CE_S.VALID_UNTIL_DT_TM > SYSDATE ; Remove historical duplicates
            AND CE_S.RESULT_CD = 309713.00 ; only 'R' for organism is resistant to the antibiotic
    ORDER BY
        CE.ENCNTR_ID
        , MIC.ORGANISM_CD
        , CE_S.ANTIBIOTIC_CD
    HEAD REPORT
        NUM_RESISTANCES = 0
        COUNTER = 0
        NUM_RESISTANCES = 0
    ; Loop for each encoounter id
    HEAD CE.ENCNTR_ID
        ; Set the number of multi drug resistant orgs to 0 when looking at a new encounter
        COUNTER = 0
            ; Do this for each organism within the encounter
    HEAD MIC.ORGANISM_CD
        ; Reset the number of resistant antibiotics for each organism to 0 when looking at a new organism
        NUM_RESISTANCES = 0             
    FOOT MIC.ORGANISM_CD
        ; count the number of antibiotics for this organism within the encounter
        NUM_RESISTANCES = COUNT(CE_S.ANTIBIOTIC_CD)
        ; If it is multi drug resistant
        IF (NUM_RESISTANCES > 1)
            ; Add 1 to the number of multi-drug resistant organisms for this encounter
            COUNTER +=1
        ENDIF
    FOOT CE.ENCNTR_ID
        ; Locate a position of the current encounter
        X = LOCATEVAL(Y, 1, NUM_ROWS, CE.ENCNTR_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_ENCOUNTER_ID)
        ; Save the count of multi drug resistant orgs for all rows with this encounter id
        WHILE (X>0) 
            RS_ENCOUNTERS->LIST_ENCOUNTERS[X].A_MULTI_RESIST_ORG_CNT = COUNTER
            ; See if the encounter id is in the list again at least 1 postition after the one already found
            X = LOCATEVAL(Y, X+1, NUM_ROWS, CE.ENCNTR_ID, RS_ENCOUNTERS->LIST_ENCOUNTERS[Y].A_ENCOUNTER_ID)
        ENDWHILE
    WITH TIME = 1000

; Display the record structure to the person running the program
    SELECT INTO $OUTDEV
          
          ENCOUNTER_NO              = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_ENCOUNTER_NO
        ; , ENCOUNTER_ID              = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_ENCOUNTER_ID
        ; , PERSON_ID                 = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_PERSON_ID
        , URN                       = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_URN
        , FACILITY                  = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_FACILITY
        , NURSE_UNIT                = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_NURSE_UNIT
        , MINS_AT_UNIT              = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_MINS_AT_LOC
        , UNIT_ARRIVE_DT_TM         = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_ARRIVE_DT_TM
        , UNIT_DEPART_DT_TM         = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_DEPART_DT_TM
        , ICU_WITHIN_72_HRS         = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_ICU_WITHIN_72_HRS
        , ED_INF_DIS_RSK_SCR_DONE   = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_ED_INF_DIS_RSK_SCR_DONE
        , INF_DIS_ASSESS_DONE       = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_INF_DIS_ASSESS_DONE
        , MULTI_RESIST_ORG_CNT      = RS_ENCOUNTERS->LIST_ENCOUNTERS[D1.SEQ].A_MULTI_RESIST_ORG_CNT
        , EXTRACTED_TIME            = IF(D1.SEQ = 1) 
                                        CONCAT(FORMAT(SYSDATE,"YYYY-MM-DD HH:MM:SS;3;Q")
                                        , " FROM:", TRIM(CURDOMAIN)) ELSE ""
                                      ENDIF
    FROM
        (DUMMYT   D1  WITH SEQ = NUM_ROWS)
    WITH NOCOUNTER, SEPARATOR=" ", FORMAT, TIME = 1000

end
go
