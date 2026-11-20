ALTER PROCEDURE [dbo].[spUTL_PIP_T_Inspection_Batch_Sync]
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
    @p_ApprovalUrl NVARCHAR(1000) = NULL,
    @p_InspectionNo VARCHAR(10),
    @p_Points dbo.Type_N_Tbl_C13 READONLY,
    @p_Photos dbo.Type_N_Tbl_C5 READONLY,
    @p_Items dbo.Type_N_Tbl_C13 READONLY,
    @p_ItemValues dbo.Type_N_Tbl_C5 READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(@p_Status,'') <> 'DONE'
    BEGIN
        RAISERROR('Only submitted BATCH inspections can be synchronized.',16,1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.PIP_M_InspectionType IT
        WHERE IT.InspectionTypeCode=@p_InspectionTypeCode
          AND IT.SectionID=@p_SectionID
          AND IT.IsActive=1
          AND ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
    )
    BEGIN
        DECLARE @V_DiagnosticMessage VARCHAR(2047);
        SET @V_DiagnosticMessage =
            'Inspection Type is not configured for BATCH mode.'
            + ' [DB=' + ISNULL(DB_NAME(), '<NULL>')
            + '; ClientInspectionID=' + ISNULL(@p_ClientInspectionID, '<NULL>')
            + '; CompanyID=' + ISNULL(@p_CompanyID, '<NULL>')
            + '; LocationID=' + ISNULL(@p_LocationID, '<NULL>')
            + '; SectionID=' + ISNULL(@p_SectionID, '<NULL>')
            + '; InspectionTypeCode=' + ISNULL(@p_InspectionTypeCode, '<NULL>')
            + '; InspectionTypeDetailCode=' + ISNULL(@p_InspectionTypeDetailCode, '<NULL>')
            + '; InspectionMode=BATCH'
            + '; IDTemplate=' + ISNULL(CONVERT(VARCHAR(20), @p_IDTemplate), '<NULL>')
            + '; IDVersion=' + ISNULL(CONVERT(VARCHAR(20), @p_IDVersion), '<NULL>')
            + '; TemplateNo=' + ISNULL(@p_TemplateNo, '<NULL>')
            + '; TemplateVersion=' + ISNULL(@p_TemplateVersion, '<NULL>')
            + '; UpdateUser=' + ISNULL(@p_UpdateUser, '<NULL>') + ']';
        RAISERROR('%s', 16, 1, @V_DiagnosticMessage);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM @p_Points)
    BEGIN
        RAISERROR('A BATCH inspection must contain at least one inspected point.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT C1 FROM @p_Points
        GROUP BY C1 HAVING COUNT(1)>1
    )
    BEGIN
        RAISERROR('Duplicate ClientPointID in BATCH inspection.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_Points P
        WHERE ISNULL(P.C1,'')=''
           OR ISNUMERIC(P.C2)=0
           OR NOT EXISTS
             (SELECT 1 FROM dbo.PIP_M_InspectionPoint M
              INNER JOIN dbo.PIP_M_InspectionMap MAP ON MAP.MapID=M.MapID
              WHERE M.InspectionPointID=CAST(P.C2 AS BIGINT)
                AND MAP.CompanyID=@p_CompanyID AND MAP.LocationID=@p_LocationID
                AND MAP.InspectionTypeCode=@p_InspectionTypeCode
                AND MAP.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
                AND M.IsActive=1)
    )
    BEGIN
        RAISERROR('One or more Inspection Point records are invalid or inactive.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.PIP_M_InspectionPoint M
        INNER JOIN dbo.PIP_M_InspectionMap MAP ON MAP.MapID=M.MapID
        WHERE MAP.CompanyID=@p_CompanyID AND MAP.LocationID=@p_LocationID
          AND MAP.InspectionTypeCode=@p_InspectionTypeCode
          AND MAP.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
          AND M.IsActive=1
          AND NOT EXISTS
          (
              SELECT 1 FROM @p_Points P
              WHERE ISNUMERIC(P.C2)=1 AND CAST(P.C2 AS BIGINT)=M.InspectionPointID
          )
    )
    BEGIN
        RAISERROR('Every active Inspection Point for this BATCH must be submitted.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_Points P
        INNER JOIN dbo.PIP_M_InspectionPoint M ON M.InspectionPointID=CAST(P.C2 AS BIGINT)
        WHERE ISNULL(M.IsNormalAbnormalRequired,0)=1
          AND ISNULL(P.C6,'') NOT IN ('NORMAL','ABNORMAL')
    )
    BEGIN
        RAISERROR('Normal/Abnormal must be selected for every required Inspection Point.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1 FROM @p_Points
        WHERE UPPER(ISNULL(C6,''))='ABNORMAL'
          AND ISNULL(LTRIM(RTRIM(C5)),'')=''
    )
    BEGIN
        RAISERROR('Abnormal Remark is required when an Inspection Point is ABNORMAL.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1 FROM @p_Points
        WHERE UPPER(ISNULL(C6,''))='NORMAL'
          AND ISNULL(LTRIM(RTRIM(C5)),'')<>''
    )
    BEGIN
        RAISERROR('Abnormal Remark must be empty when an Inspection Point is NORMAL.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1 FROM @p_Points
        WHERE ISNULL(C4,'') NOT IN ('DONE','ABNORMAL')
    )
    BEGIN
        RAISERROR('All selected Inspection Points must be DONE or ABNORMAL before batch submission.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_Items V
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=CAST(V.C2 AS INT) AND I.ItemType='OPTION'
        WHERE ISNULL(I.IsValueRequired,0)=1 AND ISNULL(LTRIM(RTRIM(V.C5)),'')=''
    )
    BEGIN RAISERROR('A required OPTION item must be selected in every BATCH Inspection Point.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_Items V
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=CAST(V.C2 AS INT) AND I.ItemType='OPTION'
        WHERE ISNULL(LTRIM(RTRIM(V.C5)),'')<>''
          AND ISNULL(I.OptionList,'')<>''
          AND NOT EXISTS
          (
              SELECT 1 FROM dbo.SplitStringConvertToTable(I.OptionList,';') O
              WHERE UPPER(LTRIM(RTRIM(O.val)))=UPPER(LTRIM(RTRIM(V.C5)))
          )
    )
    BEGIN RAISERROR('A BATCH Inspection OPTION value is not in the configured option list.',16,1); RETURN; END;

    /* Validate native REPEAT values per submitted inspection point. */
    IF EXISTS
    (
        SELECT 1
        FROM @p_Items I
        WHERE UPPER(ISNULL(I.C4,''))='REPEAT'
          AND (NOT EXISTS (SELECT 1 FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R WHERE R.IDItem=CAST(I.C2 AS INT))
               OR NOT EXISTS (SELECT 1 FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F WHERE F.IDItem=CAST(I.C2 AS INT)))
    )
    BEGIN RAISERROR('A BATCH REPEAT item has no master field configuration.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM @p_ItemValues V
        JOIN @p_Items I ON I.C1=V.C1 AND I.C2=V.C2 AND UPPER(ISNULL(I.C4,''))='REPEAT'
        WHERE NOT EXISTS
        (
            SELECT 1 FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
            WHERE F.IDItem=CAST(V.C2 AS INT) AND CONVERT(VARCHAR(11),F.IDRepeat)=V.C3
        )
    )
    BEGIN RAISERROR('Unknown REPEAT child IDRepeat submitted for BATCH inspection.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_Items I
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeat R ON R.IDItem=CAST(I.C2 AS INT)
        WHERE UPPER(ISNULL(I.C4,''))='REPEAT'
          AND
          (
              (R.RepeatMode='FIELDS' AND
                ((SELECT COUNT(DISTINCT CAST(V.C5 AS INT)) FROM @p_ItemValues V WHERE V.C1=I.C1 AND V.C2=I.C2)<>1
                 OR EXISTS (SELECT 1 FROM @p_ItemValues V WHERE V.C1=I.C1 AND V.C2=I.C2 AND CAST(V.C5 AS INT)<>0)))
              OR (R.RepeatMode='OBJECTS' AND R.CountMode='FIXED' AND
                (SELECT COUNT(DISTINCT CAST(V.C5 AS INT)) FROM @p_ItemValues V WHERE V.C1=I.C1 AND V.C2=I.C2)<>R.FixedCount)
              OR (R.RepeatMode='OBJECTS' AND R.CountMode='FLEX' AND R.MinCount IS NOT NULL AND
                (SELECT COUNT(DISTINCT CAST(V.C5 AS INT)) FROM @p_ItemValues V WHERE V.C1=I.C1 AND V.C2=I.C2)<R.MinCount)
              OR (R.RepeatMode='OBJECTS' AND R.CountMode='FLEX' AND R.MaxCount IS NOT NULL AND
                (SELECT COUNT(DISTINCT CAST(V.C5 AS INT)) FROM @p_ItemValues V WHERE V.C1=I.C1 AND V.C2=I.C2)>R.MaxCount)
          )
    )
    BEGIN RAISERROR('REPEAT object count does not match BATCH template configuration.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_ItemValues V
        JOIN @p_Items I ON I.C1=V.C1 AND I.C2=V.C2 AND UPPER(ISNULL(I.C4,''))='REPEAT'
        WHERE CAST(ISNULL(NULLIF(V.C5,''),'0') AS INT)<0
    )
    BEGIN RAISERROR('BATCH REPEAT ObjectIndex cannot be negative.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT V.C1,V.C2
        FROM @p_ItemValues V
        JOIN @p_Items I ON I.C1=V.C1 AND I.C2=V.C2 AND UPPER(ISNULL(I.C4,''))='REPEAT'
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeat R ON R.IDItem=CAST(I.C2 AS INT) AND R.RepeatMode='OBJECTS'
        GROUP BY V.C1,V.C2
        HAVING MIN(CAST(ISNULL(NULLIF(V.C5,''),'0') AS INT))<>0
            OR MAX(CAST(ISNULL(NULLIF(V.C5,''),'0') AS INT))<>COUNT(DISTINCT CAST(ISNULL(NULLIF(V.C5,''),'0') AS INT))-1
    )
    BEGIN RAISERROR('BATCH REPEAT ObjectIndex values must be sequential from zero.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_Items I
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F ON F.IDItem=CAST(I.C2 AS INT) AND F.IsRequired=1
        JOIN (SELECT DISTINCT C1,C2,C5 FROM @p_ItemValues) O ON O.C1=I.C1 AND O.C2=I.C2
        LEFT JOIN @p_ItemValues V ON V.C1=O.C1 AND V.C2=O.C2 AND V.C5=O.C5 AND V.C3=CONVERT(VARCHAR(11),F.IDRepeat)
        WHERE UPPER(ISNULL(I.C4,''))='REPEAT' AND ISNULL(LTRIM(RTRIM(V.C4)),'')=''
    )
    BEGIN RAISERROR('A required REPEAT child field is missing in BATCH inspection.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1
        FROM @p_ItemValues V
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F
          ON F.IDItem=CAST(V.C2 AS INT) AND CONVERT(VARCHAR(11),F.IDRepeat)=V.C3 AND F.FieldType='OPTION'
        WHERE ISNULL(LTRIM(RTRIM(V.C4)),'')<>''
          AND NOT EXISTS
          (
              SELECT 1 FROM dbo.SplitStringConvertToTable(F.OptionList,';') O
              WHERE UPPER(LTRIM(RTRIM(O.val)))=UPPER(LTRIM(RTRIM(V.C4)))
          )
    )
    BEGIN RAISERROR('A BATCH REPEAT OPTION value is not in the configured option list.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM @p_ItemValues V
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F ON F.IDItem=CAST(V.C2 AS INT) AND CONVERT(VARCHAR(11),F.IDRepeat)=V.C3
        WHERE F.FieldType IN ('NUMBER','RANGE') AND ISNULL(LTRIM(RTRIM(V.C4)),'')<>'' AND ISNUMERIC(V.C4)=0
    )
    BEGIN RAISERROR('A BATCH REPEAT numeric value must be a valid number.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM @p_ItemValues V
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F ON F.IDItem=CAST(V.C2 AS INT) AND CONVERT(VARCHAR(11),F.IDRepeat)=V.C3
        WHERE F.MinValue IS NOT NULL AND ISNULL(LTRIM(RTRIM(V.C4)),'')<>''
          AND (CONVERT(FLOAT,V.C4)<F.MinValue OR (F.MinInclusive=0 AND CONVERT(FLOAT,V.C4)=F.MinValue))
    )
    BEGIN RAISERROR('A BATCH REPEAT numeric value is below its minimum.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM @p_ItemValues V
        JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F ON F.IDItem=CAST(V.C2 AS INT) AND CONVERT(VARCHAR(11),F.IDRepeat)=V.C3
        WHERE F.MaxValue IS NOT NULL AND ISNULL(LTRIM(RTRIM(V.C4)),'')<>''
          AND (CONVERT(FLOAT,V.C4)>F.MaxValue OR (F.MaxInclusive=0 AND CONVERT(FLOAT,V.C4)=F.MaxValue))
    )
    BEGIN RAISERROR('A BATCH REPEAT numeric value exceeds its maximum.',16,1); RETURN; END;

    BEGIN TRY
        -- Transaction lifecycle is owned by BRC.PIP_T_WO.SyncInspection().

        DECLARE @V_InspectionNo VARCHAR(10);
        SET @V_InspectionNo=NULLIF(LTRIM(RTRIM(ISNULL(@p_InspectionNo,''))), '');

        /* The canonical Inspection sync generates InspectionNo when this parameter is empty.
           Batch inspections use the same InspectionNo mechanism; no separate batch sequence is required. */

        /* Reuse the current canonical header sync procedure. Empty checklist/photo
           TVPs ensure no batch-level results are written; all child data is saved below. */
        DECLARE @V_EmptyPhotos dbo.Type_N_Tbl_C5;
        DECLARE @V_EmptyItems dbo.Type_N_Tbl_C13;
        DECLARE @V_EmptyValues dbo.Type_N_Tbl_C5;

        EXEC dbo.spUTL_PIP_T_Inspection_Sync
            @p_ClientInspectionID=@p_ClientInspectionID,
            @p_CompanyID=@p_CompanyID,
            @p_LocationID=@p_LocationID,
            @p_SectionID=@p_SectionID,
            @p_InspectionTypeCode=@p_InspectionTypeCode,
            @p_InspectionTypeDetailCode=@p_InspectionTypeDetailCode,
            @p_ScheduledTime=@p_ScheduledTime,
            @p_IDTemplate=@p_IDTemplate,
            @p_IDVersion=@p_IDVersion,
            @p_TemplateNo=@p_TemplateNo,
            @p_TemplateVersion=@p_TemplateVersion,
            @p_InspectionDate=@p_InspectionDate,
            @p_StartDateTime=@p_StartDateTime,
            @p_EndDateTime=@p_EndDateTime,
            @p_Status=@p_Status,
            @p_Summary=@p_Summary,
            @p_FollowUp=@p_FollowUp,
            @p_FollowUpSection=@p_FollowUpSection,
            @p_FollowUpRemark=@p_FollowUpRemark,
            @p_UpdateUser=@p_UpdateUser,
            @p_GPSLatitude=@p_GPSLatitude,
            @p_GPSLongitude=@p_GPSLongitude,
            @p_GPSAccuracy=@p_GPSAccuracy,
            @p_GPSCapturedAt=@p_GPSCapturedAt,
            @p_InspectionMode='BATCH',
            @p_InspectionNo=@V_InspectionNo,
            @p_Photos=@V_EmptyPhotos,
            @p_Items=@V_EmptyItems,
            @p_ItemValues=@V_EmptyValues;

        DECLARE @V_InspectionID BIGINT;
        SELECT @V_InspectionID=InspectionID
        FROM dbo.PIP_T_Inspection WITH (UPDLOCK,HOLDLOCK)
        WHERE ClientInspectionID=@p_ClientInspectionID;

        IF @V_InspectionID IS NULL
            RAISERROR('BATCH header was not saved by the canonical Inspection sync procedure.',16,1);

        /* Remove old child results/photos before rebuilding the submitted local snapshot. */
        DELETE V
        FROM dbo.PIP_T_InspectionResultValue V
        JOIN dbo.PIP_T_InspectionResult R ON R.InspectionResultID=V.InspectionResultID
        WHERE R.InspectionID=@V_InspectionID;

        DELETE FROM dbo.PIP_T_InspectionResult WHERE InspectionID=@V_InspectionID;
        DELETE FROM dbo.PIP_T_InspectionPhoto WHERE InspectionID=@V_InspectionID;

        DECLARE @V_PointMap TABLE
        (
            ClientPointID VARCHAR(36) NOT NULL PRIMARY KEY,
            InspectionPointTransactionID BIGINT NOT NULL
        );

        UPDATE T
        SET T.InspectionPointID=CAST(P.C2 AS BIGINT),
            T.InspectionDateTime=ISNULL(CONVERT(DATETIME,NULLIF(P.C3,''),126),GETDATE()),
            T.Status=P.C4,
            T.AbnormalRemark=NULLIF(LTRIM(RTRIM(ISNULL(P.C5,''))),''),
            T.UpdateUser=@p_UpdateUser,
            T.UpdateDate=GETDATE()
        FROM dbo.PIP_T_InspectionPoint T
        JOIN @p_Points P ON P.C1=T.ClientPointID
        WHERE T.InspectionID=@V_InspectionID;

        DECLARE @V_NextPointID BIGINT;
        SELECT @V_NextPointID=ISNULL(MAX(InspectionPointTransactionID),0)
        FROM dbo.PIP_T_InspectionPoint WITH (UPDLOCK,HOLDLOCK);

        ;WITH NewPoints AS
        (
            SELECT P.C1 ClientPointID, CAST(P.C2 AS BIGINT) InspectionPointID,
                   ISNULL(CONVERT(DATETIME,NULLIF(P.C3,''),126),GETDATE()) InspectionDateTime,
                   P.C4 Status,
                   NULLIF(LTRIM(RTRIM(ISNULL(P.C5,''))),'') AbnormalRemark,
                   @V_NextPointID+ROW_NUMBER() OVER (ORDER BY P.C1) NewID
            FROM @p_Points P
            WHERE NOT EXISTS
            (
                SELECT 1 FROM dbo.PIP_T_InspectionPoint T
                WHERE T.InspectionID=@V_InspectionID AND T.ClientPointID=P.C1
            )
        )
        INSERT dbo.PIP_T_InspectionPoint
        (
            InspectionPointTransactionID,InspectionID,ClientPointID,InspectionPointID,
            InspectionDateTime,Status,AbnormalRemark,EntryUser,EntryDate,UpdateUser,UpdateDate
        )
        OUTPUT inserted.ClientPointID, inserted.InspectionPointTransactionID
            INTO @V_PointMap(ClientPointID,InspectionPointTransactionID)
        SELECT N.NewID,@V_InspectionID,N.ClientPointID,N.InspectionPointID,
               N.InspectionDateTime,N.Status,N.AbnormalRemark,@p_UpdateUser,GETDATE(),@p_UpdateUser,GETDATE()
        FROM NewPoints N;

        INSERT @V_PointMap(ClientPointID,InspectionPointTransactionID)
        SELECT T.ClientPointID,T.InspectionPointTransactionID
        FROM dbo.PIP_T_InspectionPoint T
        JOIN @p_Points P ON P.C1=T.ClientPointID
        WHERE T.InspectionID=@V_InspectionID
          AND NOT EXISTS (SELECT 1 FROM @V_PointMap M WHERE M.ClientPointID=T.ClientPointID);

        DELETE T
        FROM dbo.PIP_T_InspectionPoint T
        WHERE T.InspectionID=@V_InspectionID
          AND NOT EXISTS (SELECT 1 FROM @p_Points P WHERE P.C1=T.ClientPointID);

        DECLARE @V_ResultMap TABLE
        (
            InspectionPointTransactionID BIGINT NOT NULL,
            IDItem INT NOT NULL,
            InspectionResultID BIGINT NOT NULL,
            PRIMARY KEY(InspectionPointTransactionID,IDItem)
        );
        DECLARE @V_NextResultID BIGINT;
        SELECT @V_NextResultID=ISNULL(MAX(InspectionResultID),0)
        FROM dbo.PIP_T_InspectionResult WITH (UPDLOCK,HOLDLOCK);

        ;WITH ResultRows AS
        (
            SELECT I.C1 ClientPointID, CAST(I.C2 AS INT) IDItem,
                   I.C3 ItemLabel, I.C4 ItemType, ISNULL(I.C5,'') Value,
                   ISNULL(I.C6,'') Remark1,
                   CASE WHEN ISNULL(I.C7,'0') IN ('1','True','true') THEN 1 ELSE 0 END IsAnomali,
                   ISNULL(CAST(NULLIF(I.C8,'') AS INT),0) DisplayOrder,
                   ISNULL(I.C9,'') Remark2,
                   @V_NextResultID+ROW_NUMBER() OVER (ORDER BY I.C1,CAST(I.C2 AS INT)) NewID
            FROM @p_Items I
        )
        INSERT dbo.PIP_T_InspectionResult
        (
            InspectionResultID,InspectionID,InspectionPointTransactionID,IDItem,ItemLabel,ItemType,
            Value,Remark1,Remark2,IsAnomali,DisplayOrder,EntryUser,EntryDate,UpdateUser,UpdateDate
        )
        OUTPUT inserted.InspectionPointTransactionID, inserted.IDItem, inserted.InspectionResultID
            INTO @V_ResultMap(InspectionPointTransactionID,IDItem,InspectionResultID)
        SELECT R.NewID,@V_InspectionID,PM.InspectionPointTransactionID,R.IDItem,R.ItemLabel,R.ItemType,
               R.Value,R.Remark1,R.Remark2,R.IsAnomali,R.DisplayOrder,
               @p_UpdateUser,GETDATE(),@p_UpdateUser,GETDATE()
        FROM ResultRows R
        JOIN @V_PointMap PM ON PM.ClientPointID=R.ClientPointID;

        INSERT dbo.PIP_T_InspectionResultValue
        (
            InspectionResultID,ObjectIndex,FieldName,Value,EntryUser,EntryDate,UpdateUser,UpdateDate
        )
        SELECT RM.InspectionResultID,CAST(ISNULL(NULLIF(V.C5,''),'0') AS INT),V.C3,ISNULL(V.C4,''),
               @p_UpdateUser,GETDATE(),@p_UpdateUser,GETDATE()
        FROM @p_ItemValues V
        JOIN @V_PointMap PM ON PM.ClientPointID=V.C1
        JOIN @V_ResultMap RM ON RM.InspectionPointTransactionID=PM.InspectionPointTransactionID
                            AND RM.IDItem=CAST(V.C2 AS INT);

        DECLARE @V_NextPhotoID BIGINT;
        SELECT @V_NextPhotoID=ISNULL(MAX(InspectionPhotoID),0)
        FROM dbo.PIP_T_InspectionPhoto WITH (UPDLOCK,HOLDLOCK);

        ;WITH PhotoRows AS
        (
            SELECT P.C1 ClientPointID,P.C2 PhotoType,P.C3 FileName,P.C4 FileType,
                   CAST(ISNULL(NULLIF(P.C5,''),'0') AS INT) SeqNo,
                   @V_NextPhotoID+ROW_NUMBER() OVER (ORDER BY P.C1,CAST(ISNULL(NULLIF(P.C5,''),'0') AS INT),P.C3) NewID
            FROM @p_Photos P
        )
        INSERT dbo.PIP_T_InspectionPhoto
        (
            InspectionPhotoID,InspectionID,InspectionPointTransactionID,PhotoType,
            FileName,FileType,SeqNo,EntryUser,EntryDate
        )
        SELECT P.NewID,@V_InspectionID,PM.InspectionPointTransactionID,
               P.PhotoType,P.FileName,P.FileType,P.SeqNo,@p_UpdateUser,GETDATE()
        FROM PhotoRows P
        JOIN @V_PointMap PM ON PM.ClientPointID=P.ClientPointID;

        EXEC dbo.spUTL_PIP_T_Inspection_SubmitWorkflow
            @p_InspectionID=@V_InspectionID,
            @p_ActorEmployeeID=@p_UpdateUser,
            @p_ApprovalUrl=@p_ApprovalUrl;

        SELECT @V_InspectionID InspectionID,@p_ClientInspectionID ClientInspectionID,
               InspectionNo
        FROM dbo.PIP_T_Inspection
        WHERE InspectionID=@V_InspectionID;
    END TRY
    BEGIN CATCH
        DECLARE @V_ErrorMessage NVARCHAR(4000);
        DECLARE @V_ErrorSeverity INT;
        DECLARE @V_ErrorState INT;
        SELECT @V_ErrorMessage=ERROR_MESSAGE(),@V_ErrorSeverity=ERROR_SEVERITY(),@V_ErrorState=ERROR_STATE();
        RAISERROR(@V_ErrorMessage,@V_ErrorSeverity,@V_ErrorState);
    END CATCH;
END;
GO
