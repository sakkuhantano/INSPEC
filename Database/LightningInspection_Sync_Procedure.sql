/*
    INSPEC - Lightning daily transaction sync.
    SQL Server 2008 compatible.
    Run after inspection_batch_transaction_migration.sql and
    Database/LightningInspection_Transaction_Migration.sql.
    TVP contract:
      @p_Schedules.C1 = configured ScheduleTime (HH:mm)
      @p_Points.C1..C6 = existing BATCH point fields
      @p_Points.C7 = ScheduleTime for that point
      @p_Items / @p_ItemValues / @p_Photos retain existing BATCH contracts.
    One PIP_T_Inspection header is created for the entire day. The first
    configured ScheduleTime is passed as the canonical header ScheduleTime;
    the complete schedule set is stored in PIP_T_InspectionLightningSchedule.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.PIP_T_InspectionLightningSchedule','U') IS NULL
    RAISERROR('Run Database/LightningInspection_Transaction_Migration.sql first.',16,1);
GO

IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Lightning_Sync','P') IS NOT NULL
    DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_Sync;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Lightning_Sync','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_Sync AS RETURN 0;');
GO

ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_Sync
    @p_ClientInspectionID VARCHAR(36),
    @p_CompanyID VARCHAR(10),
    @p_LocationID VARCHAR(3),
    @p_SectionID VARCHAR(10),
    @p_InspectionTypeCode VARCHAR(2),
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
    @p_InspectionNo VARCHAR(10),
    @p_Points dbo.Type_N_Tbl_C13 READONLY,
    @p_Schedules dbo.Type_N_Tbl_C13 READONLY,
    @p_Photos dbo.Type_N_Tbl_C5 READONLY,
    @p_Items dbo.Type_N_Tbl_C13 READONLY,
    @p_ItemValues dbo.Type_N_Tbl_C5 READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(@p_Status,'') <> 'DONE'
    BEGIN
        RAISERROR('Only submitted LIGHTNING inspections can be synchronized.',16,1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.PIP_M_InspectionType IT
        WHERE IT.InspectionTypeCode=@p_InspectionTypeCode
          AND IT.SectionID=@p_SectionID
          AND IT.IsActive=1
          AND ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING'
    )
    BEGIN
        RAISERROR('Inspection Type is not configured for LIGHTNING mode.',16,1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM @p_Schedules)
    BEGIN
        RAISERROR('A LIGHTNING daily inspection must include every configured ScheduleTime.',16,1);
        RETURN;
    END;

    IF EXISTS (SELECT C1 FROM @p_Schedules GROUP BY C1 HAVING COUNT(1)>1)
    BEGIN
        RAISERROR('Duplicate ScheduleTime in LIGHTNING daily inspection.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1 FROM @p_Schedules S
        WHERE LEN(ISNULL(S.C1,''))<>5
           OR S.C1 NOT LIKE '[0-2][0-9]:[0-5][0-9]'
           OR LEFT(S.C1,2)>'23'
           OR NOT EXISTS
           (
               SELECT 1 FROM dbo.PIP_M_InspectionTypeDetail D
               WHERE D.InspectionTypeCode=@p_InspectionTypeCode
                 AND D.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
                 AND D.CompanyID=@p_CompanyID AND D.LocationID=@p_LocationID
                 AND CHARINDEX(';' + S.C1 + ';',';' + REPLACE(ISNULL(D.ScheduleTime,''),' ','') + ';')>0
           )
    )
    BEGIN
        RAISERROR('One or more LIGHTNING ScheduleTime values are not configured for this Inspection Detail.',16,1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM @p_Points)
    BEGIN
        RAISERROR('A LIGHTNING inspection must contain at least one inspected point.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT C1 FROM @p_Points
        GROUP BY C1 HAVING COUNT(1)>1
    )
    BEGIN
        RAISERROR('Duplicate ClientPointID in LIGHTNING inspection.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT P.C7,P.C2 FROM @p_Points P
        GROUP BY P.C7,P.C2 HAVING COUNT(1)>1
    )
    BEGIN
        RAISERROR('A LIGHTNING Inspection Point may appear only once in each ScheduleTime.',16,1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1 FROM @p_Points P
        WHERE NOT EXISTS (SELECT 1 FROM @p_Schedules S WHERE S.C1=P.C7)
    )
    BEGIN
        RAISERROR('Every LIGHTNING Inspection Point must belong to a configured ScheduleTime.',16,1);
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
        FROM @p_Schedules S
        CROSS JOIN dbo.PIP_M_InspectionPoint M
        INNER JOIN dbo.PIP_M_InspectionMap MAP ON MAP.MapID=M.MapID
        WHERE MAP.CompanyID=@p_CompanyID AND MAP.LocationID=@p_LocationID
          AND MAP.InspectionTypeCode=@p_InspectionTypeCode
          AND MAP.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
          AND M.IsActive=1
          AND NOT EXISTS
          (
              SELECT 1 FROM @p_Points P
              WHERE P.C7=S.C1 AND ISNUMERIC(P.C2)=1
                AND CAST(P.C2 AS BIGINT)=M.InspectionPointID
          )
    )
    BEGIN
        RAISERROR('Every active Inspection Point in every LIGHTNING ScheduleTime must be submitted.',16,1);
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

    DECLARE @V_EntryTranCount INT;
    SET @V_EntryTranCount=@@TRANCOUNT;

    BEGIN TRY
        IF @V_EntryTranCount=0 BEGIN TRANSACTION;
        ELSE SAVE TRANSACTION InspectionBatchSyncSave;

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
            @p_InspectionNo=@V_InspectionNo,
            @p_Photos=@V_EmptyPhotos,
            @p_Items=@V_EmptyItems,
            @p_ItemValues=@V_EmptyValues;

        DECLARE @V_InspectionID BIGINT;
        SELECT @V_InspectionID=InspectionID
        FROM dbo.PIP_T_Inspection WITH (UPDLOCK,HOLDLOCK)
        WHERE ClientInspectionID=@p_ClientInspectionID;

        IF @V_InspectionID IS NULL
            RAISERROR('LIGHTNING header was not saved by the canonical Inspection sync procedure.',16,1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.PIP_T_Inspection
            WHERE InspectionID=@V_InspectionID AND InspectionMode='LIGHTNING'
        )
            RAISERROR('The saved daily header is not configured as LIGHTNING mode.',16,1);

        DELETE T
        FROM dbo.PIP_T_InspectionLightningSchedule T
        WHERE T.InspectionID=@V_InspectionID
          AND NOT EXISTS (SELECT 1 FROM @p_Schedules S WHERE S.C1=T.ScheduleTime);

        UPDATE T
        SET T.ScheduleStatus='SUBMITTED',T.SubmittedDate=GETDATE(),
            T.UpdateUser=@p_UpdateUser,T.UpdateDate=GETDATE()
        FROM dbo.PIP_T_InspectionLightningSchedule T
        JOIN @p_Schedules S ON S.C1=T.ScheduleTime
        WHERE T.InspectionID=@V_InspectionID;

        INSERT dbo.PIP_T_InspectionLightningSchedule
        (InspectionID,ScheduleTime,ScheduleStatus,SubmittedDate,EntryUser,EntryDate,UpdateUser,UpdateDate)
        SELECT @V_InspectionID,S.C1,'SUBMITTED',GETDATE(),@p_UpdateUser,GETDATE(),@p_UpdateUser,GETDATE()
        FROM @p_Schedules S
        WHERE NOT EXISTS
        (
            SELECT 1 FROM dbo.PIP_T_InspectionLightningSchedule T
            WHERE T.InspectionID=@V_InspectionID AND T.ScheduleTime=S.C1
        );

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
            T.ScheduleTime=P.C7,
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
                   P.C7 ScheduleTime,
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
            InspectionDateTime,Status,AbnormalRemark,ScheduleTime,EntryUser,EntryDate,UpdateUser,UpdateDate
        )
        OUTPUT inserted.ClientPointID, inserted.InspectionPointTransactionID
            INTO @V_PointMap(ClientPointID,InspectionPointTransactionID)
        SELECT N.NewID,@V_InspectionID,N.ClientPointID,N.InspectionPointID,
               N.InspectionDateTime,N.Status,N.AbnormalRemark,N.ScheduleTime,@p_UpdateUser,GETDATE(),@p_UpdateUser,GETDATE()
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
            InspectionResultID,FieldName,Value,EntryUser,EntryDate,UpdateUser,UpdateDate
        )
        SELECT RM.InspectionResultID,V.C3,ISNULL(V.C4,''),
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

        IF @V_EntryTranCount=0 COMMIT TRANSACTION;

        SELECT @V_InspectionID InspectionID,@p_ClientInspectionID ClientInspectionID,
               InspectionNo
        FROM dbo.PIP_T_Inspection
        WHERE InspectionID=@V_InspectionID;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()=1
        BEGIN
            IF @V_EntryTranCount=0 ROLLBACK TRANSACTION;
            ELSE ROLLBACK TRANSACTION InspectionBatchSyncSave;
        END
        ELSE IF XACT_STATE()=-1 AND @V_EntryTranCount=0
            ROLLBACK TRANSACTION;

        DECLARE @V_ErrorMessage NVARCHAR(4000);
        DECLARE @V_ErrorSeverity INT;
        DECLARE @V_ErrorState INT;
        SELECT @V_ErrorMessage=ERROR_MESSAGE(),@V_ErrorSeverity=ERROR_SEVERITY(),@V_ErrorState=ERROR_STATE();
        RAISERROR(@V_ErrorMessage,@V_ErrorSeverity,@V_ErrorState);
    END CATCH;
END;
GO
