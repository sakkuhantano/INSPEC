/* INSPEC Scheduled STANDARD Chief Batch support objects. SQL Server 2008-compatible. */
SET NOCOUNT ON;
GO
IF OBJECT_ID('dbo.INSPEC_SchedulerNonce','U') IS NULL
BEGIN
    CREATE TABLE dbo.INSPEC_SchedulerNonce
    (
        Nonce VARCHAR(32) NOT NULL,
        CreatedDate DATETIME NOT NULL CONSTRAINT DF_INSPEC_SchedulerNonce_CreatedDate DEFAULT (GETDATE()),
        ExpiresDate DATETIME NOT NULL,
        CONSTRAINT PK_INSPEC_SchedulerNonce PRIMARY KEY CLUSTERED (Nonce)
    );
    CREATE NONCLUSTERED INDEX IX_INSPEC_SchedulerNonce_ExpiresDate ON dbo.INSPEC_SchedulerNonce(ExpiresDate);
END;
GO
IF OBJECT_ID('dbo.INSPEC_SchedulerLock','U') IS NULL
BEGIN
    CREATE TABLE dbo.INSPEC_SchedulerLock
    (
        LockID TINYINT NOT NULL,
        LockToken UNIQUEIDENTIFIER NULL,
        LockUntil DATETIME NULL,
        CONSTRAINT PK_INSPEC_SchedulerLock PRIMARY KEY CLUSTERED (LockID),
        CONSTRAINT CK_INSPEC_SchedulerLock_LockID CHECK (LockID=1)
    );
END;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.INSPEC_SchedulerLock WHERE LockID=1)
    INSERT dbo.INSPEC_SchedulerLock(LockID,LockToken,LockUntil) VALUES (1,NULL,NULL);
GO
IF OBJECT_ID('dbo.INSPEC_SchedulerRunLog','U') IS NULL
BEGIN
    CREATE TABLE dbo.INSPEC_SchedulerRunLog
    (
        JobRunID UNIQUEIDENTIFIER NOT NULL,
        StartedDate DATETIME NOT NULL,
        CompletedDate DATETIME NULL,
        RunStatus VARCHAR(20) NOT NULL,
        SectionsProcessed INT NOT NULL CONSTRAINT DF_INSPEC_SchedulerRunLog_SectionsProcessed DEFAULT (0),
        SectionsFailed INT NOT NULL CONSTRAINT DF_INSPEC_SchedulerRunLog_SectionsFailed DEFAULT (0),
        BatchesCreated INT NOT NULL CONSTRAINT DF_INSPEC_SchedulerRunLog_BatchesCreated DEFAULT (0),
        InspectionsBatched INT NOT NULL CONSTRAINT DF_INSPEC_SchedulerRunLog_InspectionsBatched DEFAULT (0),
        EmailsSent INT NOT NULL CONSTRAINT DF_INSPEC_SchedulerRunLog_EmailsSent DEFAULT (0),
        EmailsFailed INT NOT NULL CONSTRAINT DF_INSPEC_SchedulerRunLog_EmailsFailed DEFAULT (0),
        Summary NVARCHAR(2000) NOT NULL CONSTRAINT DF_INSPEC_SchedulerRunLog_Summary DEFAULT (N''),
        ErrorMessage NVARCHAR(4000) NOT NULL CONSTRAINT DF_INSPEC_SchedulerRunLog_ErrorMessage DEFAULT (N''),
        CONSTRAINT PK_INSPEC_SchedulerRunLog PRIMARY KEY CLUSTERED (JobRunID)
    );
END;
GO
IF OBJECT_ID('dbo.INSPEC_SchedulerSectionLog','U') IS NULL
BEGIN
    CREATE TABLE dbo.INSPEC_SchedulerSectionLog
    (
        ID BIGINT IDENTITY(1,1) NOT NULL,
        JobRunID UNIQUEIDENTIFIER NOT NULL,
        CompanyID VARCHAR(10) NOT NULL,
        LocationID VARCHAR(3) NOT NULL,
        SectionID VARCHAR(10) NOT NULL,
        InspectionDate DATETIME NOT NULL,
        RunStatus VARCHAR(20) NOT NULL,
        BatchesCreated INT NOT NULL,
        InspectionsBatched INT NOT NULL,
        EmailsSent INT NOT NULL,
        EmailsFailed INT NOT NULL,
        ErrorMessage NVARCHAR(4000) NOT NULL CONSTRAINT DF_INSPEC_SchedulerSectionLog_ErrorMessage DEFAULT (N''),
        LoggedDate DATETIME NOT NULL CONSTRAINT DF_INSPEC_SchedulerSectionLog_LoggedDate DEFAULT (GETDATE()),
        CONSTRAINT PK_INSPEC_SchedulerSectionLog PRIMARY KEY CLUSTERED (ID)
    );
    CREATE NONCLUSTERED INDEX IX_INSPEC_SchedulerSectionLog_JobRunID
        ON dbo.INSPEC_SchedulerSectionLog(JobRunID,CompanyID,LocationID,SectionID,InspectionDate);
END;
GO
IF OBJECT_ID('dbo.spUTL_INSPEC_Scheduler_RegisterNonce','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_INSPEC_Scheduler_RegisterNonce AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_INSPEC_Scheduler_RegisterNonce
    @p_Nonce VARCHAR(32)
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(LEN(@p_Nonce),0)<>32 OR @p_Nonce LIKE '%[^0-9A-Fa-f]%'
    BEGIN
        SELECT CAST(0 AS BIT) AS Accepted;
        RETURN;
    END;
    BEGIN TRY
        BEGIN TRANSACTION;
        DELETE FROM dbo.INSPEC_SchedulerNonce WHERE ExpiresDate<GETDATE();
        INSERT dbo.INSPEC_SchedulerNonce(Nonce,ExpiresDate)
        VALUES (LOWER(@p_Nonce),DATEADD(MINUTE,10,GETDATE()));
        COMMIT TRANSACTION;
        SELECT CAST(1 AS BIT) AS Accepted;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2601,2627)
            SELECT CAST(0 AS BIT) AS Accepted;
        ELSE
        BEGIN
            DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
            SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
            RAISERROR(@Err,@Sev,@State);
        END;
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.spUTL_INSPEC_Scheduler_AcquireLock','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_INSPEC_Scheduler_AcquireLock AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_INSPEC_Scheduler_AcquireLock
    @p_RunID UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.INSPEC_SchedulerLock WITH (UPDLOCK,ROWLOCK)
    SET LockToken=@p_RunID,LockUntil=DATEADD(MINUTE,360,GETDATE())
    WHERE LockID=1 AND (LockToken IS NULL OR LockUntil<GETDATE());
    SELECT CASE WHEN @@ROWCOUNT=1 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS Acquired;
END;
GO
IF OBJECT_ID('dbo.spUTL_INSPEC_Scheduler_RenewLock','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_INSPEC_Scheduler_RenewLock AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_INSPEC_Scheduler_RenewLock
    @p_RunID UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.INSPEC_SchedulerLock
    SET LockUntil=DATEADD(MINUTE,360,GETDATE())
    WHERE LockID=1 AND LockToken=@p_RunID;
    SELECT @@ROWCOUNT AS Renewed;
END;
GO
IF OBJECT_ID('dbo.spUTL_INSPEC_Scheduler_ReleaseLock','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_INSPEC_Scheduler_ReleaseLock AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_INSPEC_Scheduler_ReleaseLock
    @p_RunID UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.INSPEC_SchedulerLock
    SET LockToken=NULL,LockUntil=NULL
    WHERE LockID=1 AND LockToken=@p_RunID;
    SELECT @@ROWCOUNT AS Released;
END;
GO
