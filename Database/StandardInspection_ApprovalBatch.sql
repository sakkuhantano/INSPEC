/*
  STANDARD Inspection approval batch.
  SQL Server 2008 compatible; no detail table is used.
  PIP_T_Inspection.ApprovalBatchID links inspections directly to the header.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.PIP_T_Inspection_ApprovalBatch','U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_T_Inspection_ApprovalBatch
    (
        ApprovalBatchID BIGINT IDENTITY(1,1) NOT NULL,
        CompanyID VARCHAR(10) NOT NULL,
        LocationID VARCHAR(3) NOT NULL,
        SectionID VARCHAR(10) NOT NULL,
        InspectionDate DATETIME NOT NULL,
        ProfitCenterNo VARCHAR(20) NOT NULL,
        CreatedBy VARCHAR(50) NOT NULL,
        CreatedDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_CreatedDate DEFAULT (GETDATE()),
        SentDate DATETIME NULL,
        BatchStatus VARCHAR(20) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_BatchStatus DEFAULT ('PENDING'),
        ApprovedBy VARCHAR(50) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_ApprovedBy DEFAULT (''),
        ApprovedDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_ApprovedDate DEFAULT ('19000101'),
        EmailStatus VARCHAR(20) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_EmailStatus DEFAULT ('NOT_REQUIRED'),
        ChiefRecipients VARCHAR(4000) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_ChiefRecipients DEFAULT (''),
        EmailTo VARCHAR(4000) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_EmailTo DEFAULT (''),
        ReportSnapshotFolder NVARCHAR(1000) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_ReportSnapshotFolder DEFAULT (N''),
        EmailError NVARCHAR(2000) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_EmailError DEFAULT (N''),
        EmailAttemptCount INT NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_EmailAttemptCount DEFAULT (0),
        LastEmailAttemptDate DATETIME NULL,
        CONSTRAINT PK_PIP_T_Inspection_ApprovalBatch PRIMARY KEY CLUSTERED (ApprovalBatchID),
        CONSTRAINT CK_PIP_T_Inspection_ApprovalBatch_BatchStatus
            CHECK (BatchStatus IN ('PENDING','APPROVED')),
        CONSTRAINT CK_PIP_T_Inspection_ApprovalBatch_EmailStatus
            CHECK (EmailStatus IN ('NOT_REQUIRED','PENDING','SENT','FAILED'))
    );
END;
GO

IF COL_LENGTH('dbo.PIP_T_Inspection','ApprovalBatchID') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD ApprovalBatchID BIGINT NULL;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE name='FK_PIP_T_Inspection_ApprovalBatch'
      AND parent_object_id=OBJECT_ID('dbo.PIP_T_Inspection')
)
BEGIN
    ALTER TABLE dbo.PIP_T_Inspection WITH CHECK
        ADD CONSTRAINT FK_PIP_T_Inspection_ApprovalBatch
        FOREIGN KEY (ApprovalBatchID)
        REFERENCES dbo.PIP_T_Inspection_ApprovalBatch(ApprovalBatchID);
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_Inspection')
      AND name='IX_PIP_T_Inspection_ApprovalBatchID'
)
    CREATE NONCLUSTERED INDEX IX_PIP_T_Inspection_ApprovalBatchID
        ON dbo.PIP_T_Inspection(ApprovalBatchID,InspectionID);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_Inspection_ApprovalBatch')
      AND name='IX_PIP_T_Inspection_ApprovalBatch_Queue'
)
    CREATE NONCLUSTERED INDEX IX_PIP_T_Inspection_ApprovalBatch_Queue
        ON dbo.PIP_T_Inspection_ApprovalBatch(CompanyID,LocationID,BatchStatus,InspectionDate,SectionID);
GO

IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Create','P') IS NOT NULL
    DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Create;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Create','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Create AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Create
    @p_InspectionIDs VARCHAR(4000),
    @p_EmployeeID VARCHAR(50),
    @p_CompanyID VARCHAR(10),
    @p_LocationID VARCHAR(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Ids TABLE (InspectionID BIGINT NOT NULL PRIMARY KEY);
    DECLARE @Raw TABLE (Value VARCHAR(50) NOT NULL);
    INSERT @Raw(Value)
    SELECT LTRIM(RTRIM(val))
    FROM dbo.SplitStringConvertToTable(ISNULL(@p_InspectionIDs,''),',')
    WHERE LTRIM(RTRIM(val))<>'';

    IF EXISTS (SELECT 1 FROM @Raw WHERE Value LIKE '%[^0-9]%')
        OR (SELECT COUNT(*) FROM @Raw)=0
        OR (SELECT COUNT(*) FROM @Raw)>200
    BEGIN
        RAISERROR('Selected InspectionID list is invalid. Select 1 to 200 inspections.',16,1);
        RETURN;
    END;

    INSERT @Ids(InspectionID)
    SELECT DISTINCT CONVERT(BIGINT,Value) FROM @Raw;

    IF (SELECT COUNT(*) FROM @Ids)<>(SELECT COUNT(*) FROM @Raw)
    BEGIN
        RAISERROR('Duplicate InspectionID values are not allowed.',16,1);
        RETURN;
    END;

    DECLARE @C VARCHAR(10),@L VARCHAR(3),@S VARCHAR(10),@InspectionDate DATETIME,
            @ProfitCenterNo VARCHAR(20),@ChiefRole VARCHAR(20),@Chief VARCHAR(4000),
            @EmailEnabled BIT,@BatchID BIGINT,@SelectedCount INT;

    SELECT @SelectedCount=COUNT(*) FROM @Ids;
    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.SysWebUser SU
        WHERE SU.EmployeeID=@p_EmployeeID AND SU.IsActive=1
          AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') M WHERE M.MenuID='20022')
          AND
          (
              EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                      WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                        AND C.CompanyID=@p_CompanyID AND C.LocationID=@p_LocationID)
              OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L
                         WHERE L.CompanyID=@p_CompanyID AND L.LocationID=@p_LocationID)
          )
    )
    BEGIN
        RAISERROR('Employee is not authorized for Inspection approval in this Company/Location.',16,1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF (SELECT COUNT(*) FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
            JOIN @Ids X ON X.InspectionID=I.InspectionID
            JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
            WHERE I.CompanyID=@p_CompanyID AND I.LocationID=@p_LocationID
              AND ISNULL(I.IsActive,1)=1 AND I.Status='DONE'
              AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved,0)=1
              AND I.ApprovalBatchID IS NULL
              AND I.InspectionDate IS NOT NULL
              AND NOT (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'')
              AND ISNULL(NULLIF(I.InspectionMode,''),'STANDARD')='STANDARD'
              AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')='STANDARD'
              AND ISNULL(LTRIM(RTRIM(I.InspectionTypeCode)),'')<>''
        )<>@SelectedCount
        BEGIN
            RAISERROR('Every selected inspection must be active, submitted, SPV-approved STANDARD, and not assigned to another batch.',16,1);
        END;

        SELECT @C=MIN(I.CompanyID),@L=MIN(I.LocationID),@S=MIN(I.SectionID),
               @InspectionDate=MIN(CONVERT(DATETIME,CONVERT(VARCHAR(10),I.InspectionDate,120),120))
        FROM dbo.PIP_T_Inspection I
        JOIN @Ids X ON X.InspectionID=I.InspectionID;

        IF EXISTS
        (
            SELECT 1 FROM dbo.PIP_T_Inspection I
            JOIN @Ids X ON X.InspectionID=I.InspectionID
            WHERE I.CompanyID<>@C OR I.LocationID<>@L OR I.SectionID<>@S
               OR CONVERT(VARCHAR(10),I.InspectionDate,120)<>CONVERT(VARCHAR(10),@InspectionDate,120)
        )
        BEGIN
            RAISERROR('All inspections in one batch must have the same Company, Location, Section, and Inspection Date.',16,1);
        END;

        IF @C<>@p_CompanyID OR @L<>@p_LocationID
        BEGIN
            RAISERROR('Selected inspections are outside the logged-in Company/Location.',16,1);
        END;

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SysWebCommonValue C
            WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
              AND C.ID=@C+@L+';STANDARD'
              AND (CHARINDEX('[SPV][TRUE]',UPPER(ISNULL(C.Description,'')))>0 OR CHARINDEX('[SPV][FALSE]',UPPER(ISNULL(C.Description,'')))>0)
              AND (CHARINDEX('[CHIEF][TRUE]',UPPER(ISNULL(C.Description,'')))>0 OR CHARINDEX('[CHIEF][FALSE]',UPPER(ISNULL(C.Description,'')))>0)
        )
        BEGIN
            RAISERROR('STANDARD workflow COMVAL must contain both [SPV][TRUE/FALSE] and [CHIEF][TRUE/FALSE].',16,1);
        END;

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SysWebCommonValue C
            WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
              AND C.ID=@C+@L+';SPV;'+@S
              AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X
                          WHERE LTRIM(RTRIM(X.val))=@p_EmployeeID)
        )
        BEGIN
            RAISERROR('Employee is not the configured SPV for the selected Section.',16,1);
        END;

        SELECT @ProfitCenterNo=UPPER(LTRIM(RTRIM(ISNULL(S.ProfitCenterNo,''))))
        FROM dbo.PIP_M_Section S
        WHERE S.CompanyID=@C AND S.LocationID=@L AND S.SectionID=@S;

        SET @ChiefRole=CASE @ProfitCenterNo WHEN 'PENG' THEN 'CHIEF_ENG' WHEN 'PSEC' THEN 'CHIEF_SEC' WHEN 'PHKP' THEN 'CHIEF_HK' ELSE '' END;
        IF ISNULL(@ChiefRole,'')=''
        BEGIN
            RAISERROR('No CHIEF role is mapped to the Section ProfitCenterNo.',16,1);
        END;

        SELECT @Chief=NULLIF(LTRIM(RTRIM(C.Description)),'')
        FROM dbo.SysWebCommonValue C
        WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
          AND C.ID=@C+@L+';'+@ChiefRole;

        IF ISNULL(@Chief,'')=''
        BEGIN
            RAISERROR('CHIEF approver configuration is missing for this Company/Location and ProfitCenterNo.',16,1);
        END;

        IF EXISTS
        (
            SELECT 1 FROM dbo.SplitStringConvertToTable(@Chief,';') X
            WHERE NOT EXISTS
            (
                SELECT 1 FROM dbo.M_HRD_Employee E
                WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@C
                  AND ISNULL(E.TerminationDate,'')=''
                  AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                    AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') M WHERE M.MenuID='20022'))
                  AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
                    WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@C AND CL.LocationID=@L)
                    OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',E.EmployeeID,'') L WHERE L.CompanyID=@C AND L.LocationID=@L))
            )
        )
        BEGIN
            RAISERROR('One or more configured CHIEF approvers are inactive or lack approval access for this ProfitCenter.',16,1);
        END;

        SET @EmailEnabled=dbo.fnINSPEC_ApprovalEmailEnabled(@C,@L,'STANDARD','CHIEF');
        IF @EmailEnabled=1 AND EXISTS
        (
            SELECT 1 FROM dbo.SplitStringConvertToTable(@Chief,';') X
            WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E
                              WHERE E.EmployeeID=LTRIM(RTRIM(X.val))
                                AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'')
        )
        BEGIN
            RAISERROR('Every configured CHIEF approver needs an email address while CHIEF notification is enabled.',16,1);
        END;

        INSERT dbo.PIP_T_Inspection_ApprovalBatch
        (
            CompanyID,LocationID,SectionID,InspectionDate,ProfitCenterNo,
            CreatedBy,CreatedDate,SentDate,BatchStatus,EmailStatus,ChiefRecipients
        )
        VALUES
        (
            @C,@L,@S,@InspectionDate,@ProfitCenterNo,
            @p_EmployeeID,GETDATE(),GETDATE(),'PENDING',
            CASE WHEN ISNULL(@EmailEnabled,0)=1 THEN 'PENDING' ELSE 'NOT_REQUIRED' END,
            @Chief
        );

        SET @BatchID=CONVERT(BIGINT,SCOPE_IDENTITY());

        UPDATE I
        SET ApprovalBatchID=@BatchID,UpdateUser=@p_EmployeeID,UpdateDate=GETDATE()
        FROM dbo.PIP_T_Inspection I
        JOIN @Ids X ON X.InspectionID=I.InspectionID
        WHERE I.ApprovalBatchID IS NULL;

        IF @@ROWCOUNT<>@SelectedCount
            RAISERROR('Some inspections could not be assigned to the new approval batch.',16,1);

        COMMIT TRANSACTION;

        SELECT @BatchID AS ApprovalBatchID,@C AS CompanyID,@L AS LocationID,
               @S AS SectionID,@InspectionDate AS InspectionDate,
               @ProfitCenterNo AS ProfitCenterNo,@ChiefRole AS ChiefRole,
               @Chief AS ChiefRecipients,@EmailEnabled AS EmailEnabled,
               @SelectedCount AS InspectionCount;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
        SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
        RAISERROR(@Err,@Sev,@State);
        RETURN;
    END CATCH;
END;
GO

IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Approve','P') IS NOT NULL
    DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Approve;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Approve','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Approve AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Approve
    @p_ApprovalBatchID BIGINT,
    @p_EmployeeID VARCHAR(50),
    @p_CompanyID VARCHAR(10),
    @p_LocationID VARCHAR(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @C VARCHAR(10),@L VARCHAR(3),@S VARCHAR(10),@ChiefRole VARCHAR(20),
            @Chief VARCHAR(4000),@BatchStatus VARCHAR(20),@InspectionCount INT,
            @ProfitCenterNo VARCHAR(20),@InspectionDate DATETIME;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @C=CompanyID,@L=LocationID,@S=SectionID,@BatchStatus=BatchStatus,
               @ProfitCenterNo=ProfitCenterNo,@InspectionDate=InspectionDate
        FROM dbo.PIP_T_Inspection_ApprovalBatch WITH (UPDLOCK,HOLDLOCK)
        WHERE ApprovalBatchID=@p_ApprovalBatchID;

        IF @C IS NULL OR @BatchStatus<>'PENDING'
            RAISERROR('Approval batch is not available for approval.',16,1);

        IF @C<>@p_CompanyID OR @L<>@p_LocationID
            RAISERROR('Approval batch is outside the logged-in Company/Location.',16,1);

        SET @ChiefRole=CASE UPPER(LTRIM(RTRIM(ISNULL(@ProfitCenterNo,''))))
            WHEN 'PENG' THEN 'CHIEF_ENG' WHEN 'PSEC' THEN 'CHIEF_SEC' WHEN 'PHKP' THEN 'CHIEF_HK' ELSE '' END;
        SELECT @Chief=NULLIF(LTRIM(RTRIM(C.Description)),'')
        FROM dbo.SysWebCommonValue C
        WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
          AND C.ID=@C+@L+';'+@ChiefRole;

        IF ISNULL(@Chief,'')=''
            RAISERROR('Current CHIEF approver configuration is missing.',16,1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SysWebUser SU
            WHERE SU.EmployeeID=@p_EmployeeID AND SU.IsActive=1
              AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') M WHERE M.MenuID='20022')
              AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@Chief,';') X
                          WHERE LTRIM(RTRIM(X.val))=@p_EmployeeID)
              AND EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E
                          WHERE E.EmployeeID=@p_EmployeeID AND E.CompanyID=@C
                            AND ISNULL(E.TerminationDate,'')='')
              AND
              (
                  EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                          WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                            AND C.CompanyID=@C AND C.LocationID=@L)
                  OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L
                             WHERE L.CompanyID=@C AND L.LocationID=@L)
              )
        )
            RAISERROR('Employee is not an authorized CHIEF approver for this batch.',16,1);

        SELECT @InspectionCount=COUNT(*)
        FROM dbo.PIP_T_Inspection I
        JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        WHERE I.ApprovalBatchID=@p_ApprovalBatchID
          AND I.CompanyID=@C AND I.LocationID=@L AND I.SectionID=@S
          AND ISNULL(I.IsActive,1)=1 AND I.Status='DONE'
          AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved,0)=1
          AND ISNULL(NULLIF(I.InspectionMode,''),'STANDARD')='STANDARD'
              AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')='STANDARD'

        IF ISNULL(@InspectionCount,0)=0
            RAISERROR('This batch contains no valid SPV-approved STANDARD inspections.',16,1);

        IF EXISTS
        (
            SELECT 1
            FROM dbo.PIP_T_Inspection I
            JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
            WHERE I.ApprovalBatchID=@p_ApprovalBatchID
              AND (I.CompanyID<>@C OR I.LocationID<>@L OR I.SectionID<>@S
                   OR I.InspectionDate IS NULL
                   OR CONVERT(VARCHAR(10),I.InspectionDate,120)<>CONVERT(VARCHAR(10),@InspectionDate,120)
                   OR ISNULL(I.IsActive,1)=0 OR I.Status<>'DONE'
                   OR ISNULL(I.IsSubmitted,0)=0 OR ISNULL(I.IsApproved,0)=0
                   OR ISNULL(NULLIF(I.InspectionMode,''),'STANDARD')<>'STANDARD'
                   OR ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')<>'STANDARD')
        )
            RAISERROR('Batch membership or SPV approval state is inconsistent. No approval was recorded.',16,1);

        UPDATE dbo.PIP_T_Inspection_ApprovalBatch
        SET BatchStatus='APPROVED',ApprovedBy=@p_EmployeeID,ApprovedDate=GETDATE()
        WHERE ApprovalBatchID=@p_ApprovalBatchID AND BatchStatus='PENDING';

        IF @@ROWCOUNT<>1
            RAISERROR('Approval batch was changed by another request. Refresh the page and try again.',16,1);

        COMMIT TRANSACTION;

        SELECT @p_ApprovalBatchID AS ApprovalBatchID,@p_EmployeeID AS ApprovedBy,
               GETDATE() AS ApprovedDate,@InspectionCount AS InspectionCount;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
        SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
        RAISERROR(@Err,@Sev,@State);
        RETURN;
    END CATCH;
END;
GO
