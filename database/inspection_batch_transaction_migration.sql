/*
    BATCH Inspection transaction extension.
    SQL Server 2008 compatible.
    Run after:
      1. inspection_transaction_schema.sql
      2. master_template_inspection_schema.sql
      3. inspection_parameter_change_migration.sql
      4. inspection_mode_migration.sql
      5. the PIP_M_InspectionMap / PIP_M_InspectionPoint master schema
    Requires dbo.Type_N_Tbl_C13 and dbo.Type_N_Tbl_C5 (used by the existing sync SP).
    One PIP_T_Inspection row is one batch header. Checklist results and photos
    are linked to an InspectionPointTransactionID, never only to the batch.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.PIP_T_InspectionPoint', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_T_InspectionPoint
    (
        InspectionPointTransactionID BIGINT NOT NULL,
        InspectionID BIGINT NOT NULL,
        ClientPointID VARCHAR(36) NOT NULL,
        InspectionPointID BIGINT NOT NULL,
        InspectionDateTime DATETIME NOT NULL,
        Status VARCHAR(12) NOT NULL CONSTRAINT DF_PIP_T_InspectionPoint_Status DEFAULT ('PENDING'),
        AbnormalRemark VARCHAR(500) NULL,
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_InspectionPoint_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_InspectionPoint_UpdateDate DEFAULT (GETDATE()),
        CONSTRAINT PK_PIP_T_InspectionPoint PRIMARY KEY CLUSTERED (InspectionPointTransactionID),
        CONSTRAINT UQ_PIP_T_InspectionPoint_Client UNIQUE (InspectionID, ClientPointID),
        CONSTRAINT UQ_PIP_T_InspectionPoint_Master UNIQUE (InspectionID, InspectionPointID),
        CONSTRAINT FK_PIP_T_InspectionPoint_Header FOREIGN KEY (InspectionID)
            REFERENCES dbo.PIP_T_Inspection(InspectionID),
        CONSTRAINT FK_PIP_T_InspectionPoint_Master FOREIGN KEY (InspectionPointID)
            REFERENCES dbo.PIP_M_InspectionPoint(InspectionPointID),
        CONSTRAINT CK_PIP_T_InspectionPoint_Status CHECK (Status IN ('PENDING','INCOMPLETE','DONE','ABNORMAL'))
    );
END;
GO

IF COL_LENGTH('dbo.PIP_T_InspectionResult', 'InspectionPointTransactionID') IS NULL
    ALTER TABLE dbo.PIP_T_InspectionResult ADD InspectionPointTransactionID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_PIP_T_InspectionResult_Point')
    ALTER TABLE dbo.PIP_T_InspectionResult ADD CONSTRAINT FK_PIP_T_InspectionResult_Point
        FOREIGN KEY (InspectionPointTransactionID)
        REFERENCES dbo.PIP_T_InspectionPoint(InspectionPointTransactionID);
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionResult') AND name='UQ_PIP_T_InspectionResult_Inspection_Item')
    ALTER TABLE dbo.PIP_T_InspectionResult DROP CONSTRAINT UQ_PIP_T_InspectionResult_Inspection_Item;
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionResult') AND name='UQ_PIP_T_InspectionResult_Point_Item')
    ALTER TABLE dbo.PIP_T_InspectionResult ADD CONSTRAINT UQ_PIP_T_InspectionResult_Point_Item
        UNIQUE (InspectionID, InspectionPointTransactionID, IDItem);
GO

IF COL_LENGTH('dbo.PIP_T_InspectionPhoto', 'InspectionPointTransactionID') IS NULL
    ALTER TABLE dbo.PIP_T_InspectionPhoto ADD InspectionPointTransactionID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_PIP_T_InspectionPhoto_Point')
    ALTER TABLE dbo.PIP_T_InspectionPhoto ADD CONSTRAINT FK_PIP_T_InspectionPhoto_Point
        FOREIGN KEY (InspectionPointTransactionID)
        REFERENCES dbo.PIP_T_InspectionPoint(InspectionPointTransactionID);
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionPhoto') AND name='UX_PIP_T_InspectionPhoto_InspectionSeqNo')
    DROP INDEX UX_PIP_T_InspectionPhoto_InspectionSeqNo ON dbo.PIP_T_InspectionPhoto;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionPhoto') AND name='UX_PIP_T_InspectionPhoto_PointSeqNo')
    CREATE UNIQUE INDEX UX_PIP_T_InspectionPhoto_PointSeqNo
        ON dbo.PIP_T_InspectionPhoto(InspectionID, InspectionPointTransactionID, SeqNo);
GO

IF OBJECT_ID('dbo.PIP_T_InspectionBatchSequence','U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_T_InspectionBatchSequence
    (
        MonthKey CHAR(6) NOT NULL,
        LastSequence INT NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_InspectionBatchSequence_UpdateDate DEFAULT(GETDATE()),
        CONSTRAINT PK_PIP_T_InspectionBatchSequence PRIMARY KEY CLUSTERED(MonthKey),
        CONSTRAINT CK_PIP_T_InspectionBatchSequence_LastSequence CHECK(LastSequence BETWEEN 0 AND 9999)
    );
END;
GO

/* Continue the monthly sequence if BATCH numbers already exist in this database. */
INSERT dbo.PIP_T_InspectionBatchSequence(MonthKey,LastSequence,UpdateDate)
SELECT LEFT(I.InspectionNo,6),MAX(CAST(RIGHT(I.InspectionNo,4) AS INT)),GETDATE()
FROM dbo.PIP_T_Inspection I
WHERE LEN(I.InspectionNo)=10
  AND I.InspectionNo LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
  AND NOT EXISTS
      (SELECT 1 FROM dbo.PIP_T_InspectionBatchSequence S WHERE S.MonthKey=LEFT(I.InspectionNo,6))
GROUP BY LEFT(I.InspectionNo,6);
GO

IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_BatchNumber_Reserve','P') IS NOT NULL
    DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_BatchNumber_Reserve;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_BatchNumber_Reserve','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_BatchNumber_Reserve AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_BatchNumber_Reserve
    @p_InspectionDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @V_MonthKey CHAR(6);
    DECLARE @V_Next INT;
    DECLARE @V_TranCount INT;
    SET @V_MonthKey=CONVERT(CHAR(6),@p_InspectionDate,112);
    SET @V_TranCount=@@TRANCOUNT;
    BEGIN TRY
        IF @V_TranCount=0 BEGIN TRANSACTION;
        ELSE SAVE TRANSACTION InspectionBatchNumberSave;

        SELECT @V_Next=LastSequence+1
        FROM dbo.PIP_T_InspectionBatchSequence WITH (UPDLOCK,HOLDLOCK)
        WHERE MonthKey=@V_MonthKey;

        IF @V_Next IS NULL
        BEGIN
            SET @V_Next=1;
            INSERT dbo.PIP_T_InspectionBatchSequence(MonthKey,LastSequence,UpdateDate)
            VALUES(@V_MonthKey,@V_Next,GETDATE());
        END
        ELSE
            UPDATE dbo.PIP_T_InspectionBatchSequence
            SET LastSequence=@V_Next,UpdateDate=GETDATE()
            WHERE MonthKey=@V_MonthKey;

        IF @V_Next>9999
            RAISERROR('Monthly Inspection Batch number sequence is exhausted.',16,1);

        IF @V_TranCount=0 COMMIT TRANSACTION;
        SELECT @V_MonthKey+RIGHT('0000'+CAST(@V_Next AS VARCHAR(4)),4) AS InspectionNo;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()=1
        BEGIN
            IF @V_TranCount=0 ROLLBACK TRANSACTION;
            ELSE ROLLBACK TRANSACTION InspectionBatchNumberSave;
        END
        ELSE IF XACT_STATE()=-1 AND @V_TranCount=0 ROLLBACK TRANSACTION;
        DECLARE @V_Message NVARCHAR(4000),@V_Severity INT,@V_State INT;
        SELECT @V_Message=ERROR_MESSAGE(),@V_Severity=ERROR_SEVERITY(),@V_State=ERROR_STATE();
        RAISERROR(@V_Message,@V_Severity,@V_State);
    END CATCH;
END;
GO

IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Batch_Sync', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_Batch_Sync;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Batch_Sync', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_Batch_Sync AS RETURN 0;');
GO

ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_Batch_Sync
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
        RAISERROR('Inspection Type is not configured for BATCH mode.',16,1);
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
              WHERE M.InspectionPointID=CAST(P.C2 AS BIGINT)
                AND M.CompanyID=@p_CompanyID AND M.LocationID=@p_LocationID
                AND M.InspectionTypeCode=@p_InspectionTypeCode
                AND M.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
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
        WHERE M.CompanyID=@p_CompanyID AND M.LocationID=@p_LocationID
          AND M.InspectionTypeCode=@p_InspectionTypeCode
          AND M.InspectionTypeDetailCode=@p_InspectionTypeDetailCode
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
        SET @V_InspectionNo=NULLIF(LTRIM(RTRIM(ISNULL(@p_InspectionNo,''))),'');
        IF @V_InspectionNo IS NULL
            RAISERROR('Reserve the monthly BATCH InspectionNo before calling the sync procedure.',16,1);

        IF @V_InspectionNo NOT LIKE CONVERT(VARCHAR(6),@p_InspectionDate,112)+'[0-9][0-9][0-9][0-9]'
            RAISERROR('InspectionNo must use the yyyymmxxxx batch format for the inspection date.',16,1);

        IF EXISTS
        (
            SELECT 1 FROM dbo.PIP_T_Inspection
            WHERE InspectionNo=@V_InspectionNo
              AND ClientInspectionID<>@p_ClientInspectionID
        )
            RAISERROR('The reserved InspectionNo is already assigned to another inspection.',16,1);

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
            InspectionDateTime,Status,EntryUser,EntryDate,UpdateUser,UpdateDate
        )
        OUTPUT inserted.ClientPointID, inserted.InspectionPointTransactionID
            INTO @V_PointMap(ClientPointID,InspectionPointTransactionID)
        SELECT N.NewID,@V_InspectionID,N.ClientPointID,N.InspectionPointID,
               N.InspectionDateTime,N.Status,@p_UpdateUser,GETDATE(),@p_UpdateUser,GETDATE()
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
