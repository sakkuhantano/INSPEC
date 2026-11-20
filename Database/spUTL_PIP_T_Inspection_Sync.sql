ALTER PROCEDURE [dbo].[spUTL_PIP_T_Inspection_Sync]
(
    @p_ClientInspectionID VARCHAR(36),
    @p_CompanyID VARCHAR(10),
    @p_LocationID VARCHAR(3),
    @p_SectionID VARCHAR(10),
    @p_InspectionTypeCode VARCHAR(10),
    @p_InspectionTypeDetailCode VARCHAR(20),
    @p_ScheduledTime VARCHAR(5),
    @p_IDTemplate INT,
    @p_IDVersion INT,
    @p_TemplateNo VARCHAR(50),
    @p_TemplateVersion VARCHAR(10),
    @p_InspectionDate DATETIME,
    @p_StartDateTime DATETIME = NULL,
    @p_EndDateTime DATETIME = NULL,
    @p_Status VARCHAR(10),
    @p_Summary VARCHAR(500),
    @p_FollowUp VARCHAR(30),
    @p_FollowUpSection VARCHAR(10),
    @p_FollowUpRemark VARCHAR(300),
    @p_UpdateUser VARCHAR(50),
    @p_GPSLatitude DECIMAL(10,7) = NULL,
    @p_GPSLongitude DECIMAL(10,7) = NULL,
    @p_GPSAccuracy DECIMAL(10,2) = NULL,
    @p_GPSCapturedAt DATETIME = NULL,
    @p_InspectionMode VARCHAR(10) = 'STANDARD',
    @p_ApprovalUrl NVARCHAR(1000) = NULL,
    @p_InspectionNo VARCHAR(10),
    @p_Photos dbo.Type_N_Tbl_C5 READONLY,
    @p_Items dbo.Type_N_Tbl_C13 READONLY,
    @p_ItemValues dbo.Type_N_Tbl_C5 READONLY
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @p_InspectionMode=UPPER(LTRIM(RTRIM(ISNULL(NULLIF(@p_InspectionMode,''),'STANDARD'))));
    IF @p_InspectionMode NOT IN ('STANDARD','BATCH','LIGHTNING')
    BEGIN RAISERROR('Invalid InspectionMode for canonical inspection sync.',16,1); RETURN; END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.PIP_M_InspectionType IT
        WHERE IT.InspectionTypeCode=@p_InspectionTypeCode
          AND IT.SectionID=@p_SectionID
          AND IT.IsActive=1
          AND ISNULL(IT.InspectionMode,'STANDARD')=@p_InspectionMode
    )
    BEGIN
        RAISERROR('Inspection Type is not configured for the requested InspectionMode.',16,1);
        RETURN;
    END;

    SET @p_ScheduledTime = ISNULL(@p_ScheduledTime, '');
    SET @p_StartDateTime = ISNULL(@p_StartDateTime, CONVERT(DATETIME,'19000101',112));
    SET @p_EndDateTime = ISNULL(@p_EndDateTime, CONVERT(DATETIME,'19000101',112));
    SET @p_Summary = ISNULL(@p_Summary, '');
    SET @p_FollowUp = ISNULL(NULLIF(LTRIM(RTRIM(@p_FollowUp)), ''), 'No Follow Up');
    SET @p_FollowUpSection = ISNULL(@p_FollowUpSection, '');
    SET @p_FollowUpRemark = ISNULL(@p_FollowUpRemark, '');

    /* Map shared generic TVPs to the inspection-specific row shape. */
    DECLARE @tbl_Items TABLE
    (
        IDItem INT NOT NULL,
        ItemLabel VARCHAR(500) NOT NULL,
        ItemType VARCHAR(20) NOT NULL,
        Value VARCHAR(50) NULL,
        Remark1 VARCHAR(500) NULL,
        Remark2 VARCHAR(500) NULL,
        IsAnomali BIT NOT NULL,
        DisplayOrder INT NOT NULL
    );
    INSERT INTO @tbl_Items (IDItem, ItemLabel, ItemType, Value, Remark1, IsAnomali, DisplayOrder, Remark2)
    SELECT CAST(C1 AS INT), ISNULL(C2,''), ISNULL(C3,''), ISNULL(C4,''), ISNULL(C5,''),
           CAST(ISNULL(NULLIF(C6, ''), '0') AS BIT),
           CAST(ISNULL(NULLIF(C7, ''), '0') AS INT), ISNULL(C8,'')
    FROM @p_Items;

    DECLARE @tbl_ItemValues TABLE
    (
        IDItem INT NOT NULL,
        ObjectIndex INT NOT NULL,
        FieldName VARCHAR(100) NOT NULL,
        Value NVARCHAR(500) NULL
    );
    INSERT INTO @tbl_ItemValues (IDItem, ObjectIndex, FieldName, Value)
    SELECT CAST(C1 AS INT), CAST(ISNULL(NULLIF(C4,''),'0') AS INT), ISNULL(C2,''), ISNULL(C3,'')
    FROM @p_ItemValues;

    /* Server-side REPEAT validation for STANDARD sync. BATCH validates each point in its
       canonical C# validation path and persists the same ObjectIndex shape below. */
    IF EXISTS
    (
        SELECT 1 FROM @tbl_Items I
        WHERE I.ItemType='REPEAT'
          AND (NOT EXISTS (SELECT 1 FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R WHERE R.IDItem=I.IDItem)
               OR NOT EXISTS (SELECT 1 FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F WHERE F.IDItem=I.IDItem))
    )
    BEGIN RAISERROR('REPEAT checklist item has no valid master configuration.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @tbl_ItemValues V
        JOIN @tbl_Items I ON I.IDItem=V.IDItem AND I.ItemType='REPEAT'
        WHERE NOT EXISTS
        (
            SELECT 1 FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
            WHERE F.IDItem=V.IDItem AND CONVERT(VARCHAR(11),F.IDRepeat)=V.FieldName
        )
    )
    BEGIN RAISERROR('Unknown REPEAT child IDRepeat submitted.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @tbl_Items I
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeat R ON R.IDItem=I.IDItem
        WHERE I.ItemType='REPEAT'
          AND R.RepeatMode='FIELDS'
          AND
          (
              (SELECT COUNT(DISTINCT V.ObjectIndex) FROM @tbl_ItemValues V WHERE V.IDItem=I.IDItem)<>1
              OR EXISTS (SELECT 1 FROM @tbl_ItemValues V WHERE V.IDItem=I.IDItem AND V.ObjectIndex<>0)
          )
    )
    BEGIN RAISERROR('REPEAT FIELDS must contain exactly ObjectIndex 0.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @tbl_Items I
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeat R ON R.IDItem=I.IDItem
        WHERE I.ItemType='REPEAT' AND R.RepeatMode='OBJECTS'
          AND
          (
              (R.CountMode='FIXED' AND (SELECT COUNT(DISTINCT V.ObjectIndex) FROM @tbl_ItemValues V WHERE V.IDItem=I.IDItem)<>R.FixedCount)
              OR (R.CountMode='FLEX' AND R.MinCount IS NOT NULL AND (SELECT COUNT(DISTINCT V.ObjectIndex) FROM @tbl_ItemValues V WHERE V.IDItem=I.IDItem)<R.MinCount)
              OR (R.CountMode='FLEX' AND R.MaxCount IS NOT NULL AND (SELECT COUNT(DISTINCT V.ObjectIndex) FROM @tbl_ItemValues V WHERE V.IDItem=I.IDItem)>R.MaxCount)
          )
    )
    BEGIN RAISERROR('REPEAT OBJECTS count does not match its master configuration.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @tbl_ItemValues V
        JOIN @tbl_Items I ON I.IDItem=V.IDItem AND I.ItemType='REPEAT'
        WHERE V.ObjectIndex<0
    )
    BEGIN RAISERROR('REPEAT ObjectIndex cannot be negative.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @tbl_Items I
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeat R ON R.IDItem=I.IDItem
        JOIN @tbl_ItemValues V ON V.IDItem=I.IDItem
        WHERE I.ItemType='REPEAT' AND R.RepeatMode='OBJECTS'
        GROUP BY I.IDItem
        HAVING MIN(V.ObjectIndex)<>0 OR MAX(V.ObjectIndex)<>COUNT(DISTINCT V.ObjectIndex)-1
    )
    BEGIN RAISERROR('REPEAT OBJECTS ObjectIndex values must be sequential from zero.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @tbl_Items I
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F ON F.IDItem=I.IDItem AND F.IsRequired=1
        JOIN (SELECT DISTINCT IDItem,ObjectIndex FROM @tbl_ItemValues) O ON O.IDItem=I.IDItem
        LEFT JOIN @tbl_ItemValues V ON V.IDItem=O.IDItem AND V.ObjectIndex=O.ObjectIndex AND V.FieldName=CONVERT(VARCHAR(11),F.IDRepeat)
        WHERE I.ItemType='REPEAT' AND ISNULL(LTRIM(RTRIM(V.Value)),'')=''
    )
    BEGIN RAISERROR('A required REPEAT child field is missing.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @tbl_ItemValues V
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F
          ON F.IDItem=V.IDItem AND CONVERT(VARCHAR(11),F.IDRepeat)=V.FieldName AND F.FieldType='OPTION'
        WHERE ISNULL(LTRIM(RTRIM(V.Value)),'')<>''
          AND NOT EXISTS
          (
              SELECT 1 FROM dbo.SplitStringConvertToTable(F.OptionList,';') O
              WHERE UPPER(LTRIM(RTRIM(O.val)))=UPPER(LTRIM(RTRIM(V.Value)))
          )
    )
    BEGIN RAISERROR('A REPEAT OPTION value is not in the configured option list.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_Items V
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=CAST(V.C1 AS INT)
        WHERE I.ItemType='OPTION' AND ISNULL(I.IsValueRequired,0)=1
          AND ISNULL(LTRIM(RTRIM(V.C4)),'')=''
    )
    BEGIN RAISERROR('A required OPTION checklist item must be selected before Inspection sync.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_Items V
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=CAST(V.C1 AS INT) AND I.ItemType='OPTION'
        WHERE ISNULL(LTRIM(RTRIM(V.C4)),'')<>''
          AND ISNULL(I.OptionList,'')<>''
          AND NOT EXISTS
          (
              SELECT 1 FROM dbo.SplitStringConvertToTable(I.OptionList,';') O
              WHERE UPPER(LTRIM(RTRIM(O.val)))=UPPER(LTRIM(RTRIM(V.C4)))
          )
    )
    BEGIN RAISERROR('An Inspection OPTION value is not in the configured option list.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM @tbl_ItemValues V
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F ON F.IDItem=V.IDItem AND CONVERT(VARCHAR(11),F.IDRepeat)=V.FieldName
        WHERE F.FieldType IN ('NUMBER','RANGE') AND ISNULL(LTRIM(RTRIM(V.Value)),'')<>'' AND ISNUMERIC(V.Value)=0
    )
    BEGIN RAISERROR('A REPEAT numeric value must be a valid number.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM @tbl_ItemValues V
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F ON F.IDItem=V.IDItem AND CONVERT(VARCHAR(11),F.IDRepeat)=V.FieldName
        WHERE F.MinValue IS NOT NULL AND ISNULL(LTRIM(RTRIM(V.Value)),'')<>''
          AND (CONVERT(FLOAT,V.Value)<F.MinValue OR (F.MinInclusive=0 AND CONVERT(FLOAT,V.Value)=F.MinValue))
    )
    BEGIN RAISERROR('A REPEAT numeric value is below its minimum.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM @tbl_ItemValues V
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F ON F.IDItem=V.IDItem AND CONVERT(VARCHAR(11),F.IDRepeat)=V.FieldName
        WHERE F.MaxValue IS NOT NULL AND ISNULL(LTRIM(RTRIM(V.Value)),'')<>''
          AND (CONVERT(FLOAT,V.Value)>F.MaxValue OR (F.MaxInclusive=0 AND CONVERT(FLOAT,V.Value)=F.MaxValue))
    )
    BEGIN RAISERROR('A REPEAT numeric value exceeds its maximum.',16,1); RETURN; END;

    /* Drafts are device-local only. SQL may persist completed inspections only. */
    IF ISNULL(@p_Status, '') <> 'DONE'
    BEGIN
        RAISERROR('Only completed inspections (DONE) can be saved to SQL Server.', 16, 1);
        RETURN;
    END;

    SET @p_FollowUp = LTRIM(RTRIM(ISNULL(@p_FollowUp, 'No Follow Up')));
    SET @p_FollowUpSection = LTRIM(RTRIM(ISNULL(@p_FollowUpSection, '')));
    SET @p_FollowUpRemark = LTRIM(RTRIM(ISNULL(@p_FollowUpRemark, '')));

    /* Follow Up is controlled by the selected checklist Version for both STANDARD and BATCH.
       BATCH delegates its header to this canonical procedure, so one rule covers both modes. */
    DECLARE @V_IsFollowUpRequired BIT;
    SELECT @V_IsFollowUpRequired=ISNULL(V.IsFollowUpRequired,1)
    FROM dbo.PIP_M_CheckListWOPM_Version V
    WHERE V.IDVersion=@p_IDVersion AND V.IDTemplate=@p_IDTemplate;
    IF ISNULL(@V_IsFollowUpRequired,1)=0
    BEGIN
        SET @p_FollowUp='No Follow Up';
        SET @p_FollowUpSection='';
        SET @p_FollowUpRemark='';
    END;

    IF @p_FollowUp NOT IN ('No Follow Up', 'Recommend Follow Up')
    BEGIN
        RAISERROR('Invalid Inspection Follow Up selection.', 16, 1);
        RETURN;
    END;

    IF @p_FollowUp = 'Recommend Follow Up'
    BEGIN
        IF @p_Status = 'DONE'
        BEGIN
            IF @p_FollowUpSection NOT IN ('ACON','COMM','MECH','ELEC','CIVIL','PFIT','PHKP','PSEC')
            BEGIN
                RAISERROR('A valid Responsible Section is required for Follow Up.', 16, 1);
                RETURN;
            END;
            IF @p_FollowUpRemark = ''
            BEGIN
                RAISERROR('Follow Up Work Order Description is required.', 16, 1);
                RETURN;
            END;
        END;
    END
    ELSE
    BEGIN
        SET @p_FollowUpSection = '';
        SET @p_FollowUpRemark = '';
    END;

    /* Match the current INSPEC authorization model used by inspection.aspx:
       SysWebUser + menu 20021 + Company/Location + the same section resolution
       priority as GFC.GetEmployeeSection(). */
    DECLARE @V_SectionList VARCHAR(8000);
    SET @V_SectionList='';

    IF EXISTS
    (
        SELECT 1
        FROM dbo.SysWebUserUserGroup
        WHERE UserID=@p_UpdateUser
          AND UserGroupID='administrator'
    )
    BEGIN
        SELECT @V_SectionList=ISNULL(STUFF((
            SELECT ';'+S.SectionID
            FROM dbo.PIP_M_Section S
            WHERE S.ProfitCenterNo IN ('peng','phkp','psec')
            FOR XML PATH(''), TYPE).value('.','varchar(8000)'),1,1,''),'');
    END;

    IF ISNULL(@V_SectionList,'')=''
    BEGIN
        SELECT TOP 1 @V_SectionList=ISNULL(I.SectionList,'')
        FROM dbo.INSPEC_User I
        WHERE I.UserID=@p_UpdateUser
          AND ISNULL(I.IsActive,0)=1;
    END;

    IF ISNULL(@V_SectionList,'')=''
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM dbo.SysWebUserProfit P
            WHERE P.AppID='inspec'
              AND P.UserID=@p_UpdateUser
              AND P.ProfitCenterNo='*ALL'
        )
        BEGIN
            SELECT @V_SectionList=ISNULL(STUFF((
                SELECT ';'+S.SectionID
                FROM dbo.PIP_M_Section S
                WHERE S.ProfitCenterNo IN ('peng','phkp','psec')
                FOR XML PATH(''), TYPE).value('.','varchar(8000)'),1,1,''),'');
        END
        ELSE
        BEGIN
            SELECT @V_SectionList=ISNULL(STUFF((
                SELECT DISTINCT ';'+S.SectionID
                FROM dbo.SysWebUserProfit P
                INNER JOIN dbo.PIP_M_Section S ON S.ProfitCenterNo=P.ProfitCenterNo
                WHERE P.AppID='inspec'
                  AND P.UserID=@p_UpdateUser
                  AND ISNULL(P.ProfitCenterNo,'')<>''
                FOR XML PATH(''), TYPE).value('.','varchar(8000)'),1,1,''),'');
        END;
    END;

    IF ISNULL(@V_SectionList,'')=''
    BEGIN
        SELECT TOP 1 @V_SectionList=ISNULL(E.SectionID,'')
        FROM dbo.M_HRD_Employee E
        WHERE E.EmployeeID=@p_UpdateUser;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.SysWebUser SU
        WHERE SU.EmployeeID=@p_UpdateUser
          AND SU.IsActive=1
          AND EXISTS
          (
              SELECT 1
              FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM
              WHERE AM.MenuID='20021'
          )
          AND
          (
              EXISTS
              (
                  SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                  WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                    AND C.CompanyID=@p_CompanyID AND C.LocationID=@p_LocationID
              )
              OR EXISTS
              (
                  SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L
                  WHERE L.CompanyID=@p_CompanyID AND L.LocationID=@p_LocationID
              )
          )
    )
    BEGIN
        RAISERROR('Employee is not authorized for INSPEC access or this company/location.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.SysWebUser SU
        WHERE SU.EmployeeID=@p_UpdateUser
          AND SU.IsActive=1
          AND EXISTS
          (
              SELECT 1
              FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM
              WHERE AM.MenuID='20021'
          )
          AND EXISTS
          (
              SELECT 1
              FROM dbo.SplitStringConvertToTable(@V_SectionList,';') S
              WHERE S.val=@p_SectionID
          )
    )
    BEGIN
        RAISERROR('Employee is not authorized for this inspection section.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.PIP_M_InspectionType T
        JOIN dbo.PIP_M_InspectionTypeDetail D
          ON D.InspectionTypeCode=T.InspectionTypeCode
        WHERE T.InspectionTypeCode=@p_InspectionTypeCode
          AND D.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
          AND D.CompanyID=@p_CompanyID
          AND D.LocationID=@p_LocationID
          AND T.SectionID=@p_SectionID
          AND T.IsActive=1 AND D.IsActive=1
    )
    BEGIN
        RAISERROR('Inspection Type or detail is inactive, missing, or belongs to another section.', 16, 1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.PIP_M_InspectionTypeDetail D
        WHERE D.InspectionTypeCode=@p_InspectionTypeCode
          AND D.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
          AND D.CompanyID=@p_CompanyID
          AND D.LocationID=@p_LocationID
          AND LEN(LTRIM(RTRIM(ISNULL(D.ScheduleTime,'')))) > 0
    )
       AND ISNULL(@p_ScheduledTime, '') = ''
    BEGIN
        RAISERROR('Scheduled time is required for this inspection detail.', 16, 1);
        RETURN;
    END;

    IF ISNULL(@p_ScheduledTime, '') <> ''
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.PIP_M_InspectionTypeDetail D
           WHERE D.InspectionTypeCode=@p_InspectionTypeCode
             AND D.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
             AND D.CompanyID=@p_CompanyID
             AND D.LocationID=@p_LocationID
             AND CHARINDEX(';' + @p_ScheduledTime + ';', ';' + REPLACE(D.ScheduleTime, ' ', '') + ';') > 0
       )
    BEGIN
        RAISERROR('Scheduled time is not configured for this inspection detail.', 16, 1);
        RETURN;
    END;

    /* A returned, unapproved inspection may change parameters/template.
       The same ClientInspectionID is updated and its checklist/photo snapshot is replaced atomically. */

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.PIP_M_CheckListWOPM T
        JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=@p_IDVersion AND V.IDTemplate=T.IDTemplate
        WHERE T.IDTemplate=@p_IDTemplate
          AND T.TemplateNo=@p_TemplateNo
          AND T.SectionID=@p_SectionID
          AND T.TemplateType='I'
          AND T.InspectionTypeCode=@p_InspectionTypeCode
          AND T.IsActive=1
          AND V.Version=@p_TemplateVersion
          AND (V.Status='Active' OR
          (V.Status='Archieved' AND EXISTS
             (SELECT 1 FROM dbo.PIP_T_Inspection Existing
              WHERE Existing.ClientInspectionID=@p_ClientInspectionID
                AND Existing.IDTemplate=T.IDTemplate AND Existing.IDVersion=V.IDVersion
                AND Existing.OwnerEmployeeID=@p_UpdateUser AND ISNULL(Existing.IsApproved,0)=0)))
          AND
          (
              ISNULL(T.EmployeeList,'')='' OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + @p_UpdateUser + ';%')
          )
          AND
          (
              ISNULL(T.CompanyScope,'S')='A'
              OR (';' + ISNULL(T.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%')
          )
    )
    BEGIN
        RAISERROR('Inspection template is inactive, missing, or unavailable for this company/location.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        -- Transaction lifecycle is owned by BRC.PIP_T_WO.SyncInspection().

        /* One scheduled inspection per company/location, section, date, type, detail, time, and template.
           ClientInspectionID is excluded so syncing an existing offline record remains an update. */
        IF EXISTS
        (
            SELECT 1
            FROM dbo.PIP_T_Inspection WITH (UPDLOCK, HOLDLOCK)
            WHERE ClientInspectionID <> @p_ClientInspectionID
              AND ISNULL(IsActive,1)=1
              AND CompanyID = @p_CompanyID
              AND LocationID = @p_LocationID
              AND SectionID = @p_SectionID
              AND InspectionTypeCode = @p_InspectionTypeCode
              AND InspectionTypeDetailCode = @p_InspectionTypeDetailCode
              AND ISNULL(ScheduledTime, '') = ISNULL(@p_ScheduledTime, '')
              AND IDTemplate = @p_IDTemplate
              AND InspectionDate >= CONVERT(DATETIME, CONVERT(VARCHAR(10), @p_InspectionDate, 120), 120)
              AND InspectionDate < DATEADD(DAY, 1, CONVERT(DATETIME, CONVERT(VARCHAR(10), @p_InspectionDate, 120), 120))
        )
        BEGIN
            RAISERROR('An inspection already exists for this date, company/location, section, type, detail, schedule, and template.', 16, 1);
        END;

        DECLARE @V_InspectionID BIGINT;
        DECLARE @V_InspectionTypeName VARCHAR(100);
        DECLARE @V_InspectionTypeDetailName VARCHAR(100);
        DECLARE @V_TemplateName VARCHAR(200);

        SELECT @V_InspectionTypeName=T.InspectionTypeName,
               @V_InspectionTypeDetailName=D.InspectionTypeDetailName
        FROM dbo.PIP_M_InspectionType T
        JOIN dbo.PIP_M_InspectionTypeDetail D ON D.InspectionTypeCode=T.InspectionTypeCode
        WHERE T.InspectionTypeCode=@p_InspectionTypeCode
          AND D.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
          AND D.CompanyID=@p_CompanyID
          AND D.LocationID=@p_LocationID;

        SELECT @V_TemplateName=TemplateName
        FROM dbo.PIP_M_CheckListWOPM
        WHERE IDTemplate=@p_IDTemplate;

        SELECT @V_InspectionID=InspectionID
        FROM dbo.PIP_T_Inspection WITH (UPDLOCK, HOLDLOCK)
        WHERE ClientInspectionID=@p_ClientInspectionID;

        IF @V_InspectionID IS NOT NULL
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PIP_T_Inspection
                WHERE InspectionID=@V_InspectionID AND OwnerEmployeeID=@p_UpdateUser
            )
            BEGIN
                RAISERROR('This offline inspection belongs to another employee.', 16, 1);
            END;

            IF EXISTS
            (
                SELECT 1 FROM dbo.PIP_T_Inspection
                WHERE InspectionID=@V_InspectionID AND ISNULL(IsActive,1)=0
            )
            BEGIN
                RAISERROR('Inactive inspections cannot be changed or resubmitted.', 16, 1);
            END;

            IF EXISTS
            (
                SELECT 1 FROM dbo.PIP_T_Inspection
                WHERE InspectionID=@V_InspectionID AND (ISNULL(IsSubmitted,0)=1 OR ISNULL(IsApproved,0)=1)
            )
            BEGIN
                RAISERROR('Submitted inspections are locked until an approver returns them to the technician.', 16, 1);
            END;

            UPDATE dbo.PIP_T_Inspection
            SET InspectionNo=CASE WHEN ISNULL(@p_InspectionNo,'')<>'' THEN @p_InspectionNo ELSE InspectionNo END,
                CompanyID=@p_CompanyID, LocationID=@p_LocationID, SectionID=@p_SectionID,
                InspectionTypeCode=@p_InspectionTypeCode, InspectionMode=@p_InspectionMode, InspectionTypeName=@V_InspectionTypeName,
                InspectionTypeDetailCode=@p_InspectionTypeDetailCode,
                InspectionTypeDetailName=@V_InspectionTypeDetailName, ScheduledTime=@p_ScheduledTime,
                IDTemplate=@p_IDTemplate, IDVersion=@p_IDVersion, TemplateNo=@p_TemplateNo,
                TemplateName=@V_TemplateName, TemplateVersion=@p_TemplateVersion,
                InspectionDate=@p_InspectionDate, StartDateTime=@p_StartDateTime,
                EndDateTime=@p_EndDateTime, Status=@p_Status, Summary=@p_Summary,
                FollowUp=@p_FollowUp, FollowUpSection=ISNULL(@p_FollowUpSection,''), FollowUpRemark=ISNULL(@p_FollowUpRemark,''),
                IsApproved=0, ApprovedBy='', ApprovedDate=CONVERT(DATETIME,'19000101',112), ApprovalRemark='',
                ReasonVoid='',
                GPSLatitude=@p_GPSLatitude, GPSLongitude=@p_GPSLongitude, GPSAccuracy=@p_GPSAccuracy, GPSCapturedAt=@p_GPSCapturedAt,
                UpdateUser=@p_UpdateUser, UpdateDate=GETDATE(), SyncDate=GETDATE()
            WHERE InspectionID=@V_InspectionID;
        END
        ELSE
        BEGIN
            DECLARE @V_InspectionNo VARCHAR(10);
            DECLARE @V_AutoNum VARCHAR(30);
            DECLARE @V_AutoNumResult TABLE (ID VARCHAR(10), SeqNo INT);

            SET @V_InspectionNo = NULLIF(LTRIM(RTRIM(@p_InspectionNo)), '');
            IF @V_InspectionNo IS NULL
            BEGIN
                SET @V_AutoNum = 'PIPINS' + @p_CompanyID + @p_LocationID;
                INSERT INTO @V_AutoNumResult
                EXECUTE dbo.sp_GetGenerateAutoNumID 'pip', @V_AutoNum, 1;
                SELECT @V_InspectionNo = ID FROM @V_AutoNumResult;
            END;

            IF ISNULL(@V_InspectionNo, '') = ''
            BEGIN
                RAISERROR('Failed to generate InspectionNo.', 16, 1);
            END;

            SELECT @V_InspectionID=ISNULL(MAX(InspectionID),0)+1
            FROM dbo.PIP_T_Inspection WITH (UPDLOCK, HOLDLOCK);

            INSERT dbo.PIP_T_Inspection
            (
                InspectionID, ClientInspectionID, InspectionNo, CompanyID, LocationID, SectionID,
                InspectionTypeCode, InspectionMode, InspectionTypeName, InspectionTypeDetailCode,
                InspectionTypeDetailName, ScheduledTime, IDTemplate, IDVersion,
                TemplateNo, TemplateName, TemplateVersion, InspectionDate,
                StartDateTime, EndDateTime, Status, Summary, FollowUp, FollowUpSection, FollowUpRemark, OwnerEmployeeID,
                GPSLatitude, GPSLongitude, GPSAccuracy, GPSCapturedAt,
                EntryUser, EntryDate, UpdateUser, UpdateDate, SyncDate, IsActive
            )
            VALUES
            (
                @V_InspectionID, @p_ClientInspectionID, @V_InspectionNo, @p_CompanyID, @p_LocationID, @p_SectionID,
                @p_InspectionTypeCode, @p_InspectionMode, @V_InspectionTypeName, @p_InspectionTypeDetailCode,
                @V_InspectionTypeDetailName, @p_ScheduledTime, @p_IDTemplate, @p_IDVersion,
                @p_TemplateNo, @V_TemplateName, @p_TemplateVersion, @p_InspectionDate,
                @p_StartDateTime, @p_EndDateTime, @p_Status, @p_Summary, @p_FollowUp,
                ISNULL(@p_FollowUpSection,''), ISNULL(@p_FollowUpRemark,''), @p_UpdateUser,
                @p_GPSLatitude, @p_GPSLongitude, @p_GPSAccuracy, @p_GPSCapturedAt,
                @p_UpdateUser, GETDATE(), @p_UpdateUser, GETDATE(), GETDATE(), 1
            );
        END;

        DELETE V
        FROM dbo.PIP_T_InspectionResultValue V
        JOIN dbo.PIP_T_InspectionResult R ON R.InspectionResultID=V.InspectionResultID
        WHERE R.InspectionID=@V_InspectionID;

        DELETE FROM dbo.PIP_T_InspectionResult WHERE InspectionID=@V_InspectionID;

        DECLARE @V_ResultMap TABLE (IDItem INT NOT NULL, InspectionResultID BIGINT NOT NULL);
        DECLARE @V_NextResultID BIGINT;
        SELECT @V_NextResultID=ISNULL(MAX(InspectionResultID),0)
        FROM dbo.PIP_T_InspectionResult WITH (UPDLOCK, HOLDLOCK);
        ;WITH ResultRows AS
        (
            SELECT I.*,
                   @V_NextResultID + ROW_NUMBER() OVER (ORDER BY I.IDItem) AS NewInspectionResultID
            FROM @tbl_Items I
        )
        INSERT dbo.PIP_T_InspectionResult
        (
            InspectionResultID, InspectionID, IDItem, ItemLabel, ItemType, Value, Remark1, Remark2, IsAnomali,
            DisplayOrder, EntryUser, EntryDate, UpdateUser, UpdateDate
        )
        OUTPUT inserted.IDItem, inserted.InspectionResultID
            INTO @V_ResultMap (IDItem, InspectionResultID)
        SELECT I.NewInspectionResultID, @V_InspectionID, I.IDItem, I.ItemLabel, I.ItemType, I.Value, I.Remark1, I.Remark2,
               I.IsAnomali, I.DisplayOrder, @p_UpdateUser, GETDATE(), @p_UpdateUser, GETDATE()
        FROM ResultRows I;

        INSERT dbo.PIP_T_InspectionResultValue
        (
            InspectionResultID, ObjectIndex, FieldName, Value, EntryUser, EntryDate, UpdateUser, UpdateDate
        )
        SELECT M.InspectionResultID, V.ObjectIndex, V.FieldName, V.Value,
               @p_UpdateUser, GETDATE(), @p_UpdateUser, GETDATE()
        FROM @tbl_ItemValues V
        JOIN @V_ResultMap M ON M.IDItem=V.IDItem;

        /* Header, checklist, and photo metadata commit or roll back together. */
        DELETE FROM dbo.PIP_T_InspectionPhoto WHERE InspectionID=@V_InspectionID;
        DECLARE @V_NextPhotoID BIGINT;
        SELECT @V_NextPhotoID=ISNULL(MAX(InspectionPhotoID),0)
        FROM dbo.PIP_T_InspectionPhoto WITH (UPDLOCK, HOLDLOCK);
        ;WITH PhotoRows AS
        (
            SELECT P.C1, P.C2, P.C3, P.C4,
                   @V_NextPhotoID + ROW_NUMBER() OVER (ORDER BY CAST(ISNULL(NULLIF(P.C4,''),'0') AS INT), P.C2) AS NewInspectionPhotoID
            FROM @p_Photos P
        )
        INSERT dbo.PIP_T_InspectionPhoto
            (InspectionPhotoID, InspectionID, PhotoType, FileName, FileType, SeqNo, EntryUser, EntryDate)
        SELECT P.NewInspectionPhotoID, @V_InspectionID, ISNULL(P.C1,''), ISNULL(P.C2,''), ISNULL(P.C3,''),
               CAST(ISNULL(NULLIF(P.C4,''),'0') AS INT), @p_UpdateUser, GETDATE()
        FROM PhotoRows P;

        IF @p_Status='DONE' AND @p_InspectionMode='STANDARD'
        BEGIN
            EXEC dbo.spUTL_PIP_T_Inspection_SubmitWorkflow
                @p_InspectionID=@V_InspectionID,
                @p_ActorEmployeeID=@p_UpdateUser,
                @p_ApprovalUrl=@p_ApprovalUrl;
        END;

        SELECT @V_InspectionID AS InspectionID,
               @p_ClientInspectionID AS ClientInspectionID,
               InspectionNo
        FROM dbo.PIP_T_Inspection
        WHERE InspectionID=@V_InspectionID;
    END TRY
    BEGIN CATCH
        DECLARE @V_ErrorMessage NVARCHAR(4000);
        DECLARE @V_ErrorSeverity INT;
        DECLARE @V_ErrorState INT;
        SELECT @V_ErrorMessage=ERROR_MESSAGE(), @V_ErrorSeverity=ERROR_SEVERITY(), @V_ErrorState=ERROR_STATE();
        RAISERROR(@V_ErrorMessage, @V_ErrorSeverity, @V_ErrorState);
    END CATCH;
END;
