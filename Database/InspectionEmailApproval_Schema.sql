/*
    INSPEC inspection approval routing and email foundation
    SQL Server 2008 compatible.

    Fixed workflow roles are intentionally represented as columns / StageCode values:
      SPV, CHIEF_ENG, CHIEF_SEC, CHIEF_HK.
    No role master table is introduced.

    Routing/configuration:
      - Stored in the existing dbo.SysWebCommonValue multi-setup table.
      - CommonGroup='EmailApproval'.
      - Chief Engineering / Chief Security / Chief Housekeeping: <CompanyID><LocationID>;CHIEF_ENG / CHIEF_SEC / CHIEF_HK.
      - SPV: <CompanyID><LocationID>;SPV;<SectionID>.
      - Workflow email flags: <CompanyID><LocationID>;STANDARD / BATCH;PARAM / BATCH;INSPECT.
      - Employee IDs are stored in Description; application resolves Name/emailaddress from M_HRD_Employee.
    Approval history/outbox supports the single canonical PIP_T_Inspection header
    for STANDARD and BATCH modes. Lightning uses the BATCH + INSPECT master mode and a LIGHTNING audit entity type. Workflow state lives on that header.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Inspection routing/configuration is stored in dbo.SysWebCommonValue.
   CommonGroup='EmailApproval':
     <CompanyID><LocationID>;CHIEF_ENG      -> Description=EmployeeID
     <CompanyID><LocationID>;CHIEF_SEC      -> Description=EmployeeID
     <CompanyID><LocationID>;CHIEF_HK       -> Description=EmployeeID
     <CompanyID><LocationID>;SPV;<SectionID> -> Description=EmployeeID
     <CompanyID><LocationID>;STANDARD / BATCH;PARAM / BATCH;INSPECT -> per-stage [LEVEL][TRUE/FALSE] tokens
   No INSPEC-specific setup tables are required. */

IF OBJECT_ID('dbo.PIP_T_InspectionApprovalHistory', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_T_InspectionApprovalHistory
    (
        ApprovalEventID BIGINT IDENTITY(1,1) NOT NULL,
        EntityType VARCHAR(20) NOT NULL,
        EntityID BIGINT NOT NULL,
        CompanyID VARCHAR(10) NOT NULL,
        LocationID VARCHAR(3) NOT NULL,
        SectionID VARCHAR(10) NULL,
        StageCode VARCHAR(20) NOT NULL,
        ActionCode VARCHAR(20) NOT NULL,
        ActorEmployeeID VARCHAR(50) NOT NULL,
        ActionDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_InspectionApprovalHistory_ActionDate DEFAULT (GETDATE()),
        Remark NVARCHAR(1000) NULL,
        CONSTRAINT PK_PIP_T_InspectionApprovalHistory PRIMARY KEY CLUSTERED (ApprovalEventID),
        CONSTRAINT CK_PIP_T_InspectionApprovalHistory_EntityType
            CHECK (EntityType IN ('INSPECTION', 'LIGHTNING')),
        CONSTRAINT CK_PIP_T_InspectionApprovalHistory_Stage
            CHECK (StageCode IN ('TECHNICIAN', 'SPV', 'CHIEF_ENG', 'CHIEF_SEC')),
        CONSTRAINT CK_PIP_T_InspectionApprovalHistory_Action
            CHECK (ActionCode IN ('SUBMITTED', 'APPROVED', 'VOIDED', 'RESUBMITTED', 'SKIPPED'))
    );
END;
GO

/* Permit the profit-center-derived Chief Housekeeping role in audit history. */
IF EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionApprovalHistory')
      AND name='CK_PIP_T_InspectionApprovalHistory_Stage'
)
    ALTER TABLE dbo.PIP_T_InspectionApprovalHistory DROP CONSTRAINT CK_PIP_T_InspectionApprovalHistory_Stage;
GO
ALTER TABLE dbo.PIP_T_InspectionApprovalHistory WITH CHECK
    ADD CONSTRAINT CK_PIP_T_InspectionApprovalHistory_Stage
    CHECK (StageCode IN ('TECHNICIAN','SPV','CHIEF_ENG','CHIEF_SEC','CHIEF_HK'));
GO

/* SKIPPED records are emitted when a configured workflow role is absent.
   Keep this constraint update repeatable on databases with the earlier schema. */
IF EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionApprovalHistory')
      AND name='CK_PIP_T_InspectionApprovalHistory_Action'
)
    ALTER TABLE dbo.PIP_T_InspectionApprovalHistory DROP CONSTRAINT CK_PIP_T_InspectionApprovalHistory_Action;
GO
ALTER TABLE dbo.PIP_T_InspectionApprovalHistory WITH CHECK
    ADD CONSTRAINT CK_PIP_T_InspectionApprovalHistory_Action
    CHECK (ActionCode IN ('SUBMITTED', 'APPROVED', 'VOIDED', 'RESUBMITTED', 'SKIPPED'));
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionApprovalHistory')
      AND name = 'IX_PIP_T_InspectionApprovalHistory_Entity'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_InspectionApprovalHistory_Entity
        ON dbo.PIP_T_InspectionApprovalHistory (EntityType, EntityID, ApprovalEventID);
END;
GO

IF OBJECT_ID('dbo.PIP_T_InspectionEmailOutbox', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_T_InspectionEmailOutbox
    (
        EmailOutboxID BIGINT IDENTITY(1,1) NOT NULL,
        NotificationKey VARCHAR(150) NOT NULL,
        ApprovalEventID BIGINT NULL,
        EntityType VARCHAR(20) NOT NULL,
        EntityID BIGINT NOT NULL,
        RecipientType VARCHAR(20) NOT NULL,
        RecipientEmployeeID VARCHAR(50) NOT NULL,
        RecipientEmail VARCHAR(320) NOT NULL,
        ApprovalToken UNIQUEIDENTIFIER NULL,
        EmailSubject NVARCHAR(300) NOT NULL,
        HtmlBody NVARCHAR(MAX) NOT NULL,
        PlainBody NVARCHAR(MAX) NULL,
        DeliveryStatus VARCHAR(20) NOT NULL
            CONSTRAINT DF_PIP_T_InspectionEmailOutbox_Status DEFAULT ('PENDING'),
        AttemptCount INT NOT NULL CONSTRAINT DF_PIP_T_InspectionEmailOutbox_Attempt DEFAULT (0),
        NextAttemptDate DATETIME NOT NULL
            CONSTRAINT DF_PIP_T_InspectionEmailOutbox_NextAttempt DEFAULT (GETDATE()),
        SentDate DATETIME NULL,
        LastError NVARCHAR(2000) NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_InspectionEmailOutbox_EntryDate DEFAULT (GETDATE()),
        CONSTRAINT PK_PIP_T_InspectionEmailOutbox PRIMARY KEY CLUSTERED (EmailOutboxID),
        CONSTRAINT UQ_PIP_T_InspectionEmailOutbox_NotificationKey UNIQUE (NotificationKey),
        CONSTRAINT FK_PIP_T_InspectionEmailOutbox_ApprovalHistory
            FOREIGN KEY (ApprovalEventID)
            REFERENCES dbo.PIP_T_InspectionApprovalHistory (ApprovalEventID),
        CONSTRAINT CK_PIP_T_InspectionEmailOutbox_EntityType
            CHECK (EntityType IN ('INSPECTION', 'LIGHTNING')),
        CONSTRAINT CK_PIP_T_InspectionEmailOutbox_RecipientType
            CHECK (RecipientType IN ('TECHNICIAN', 'APPROVER')),
        CONSTRAINT CK_PIP_T_InspectionEmailOutbox_Status
            CHECK (DeliveryStatus IN ('PENDING', 'SENDING', 'SENT', 'FAILED'))
    );
END;
GO

/* Per-recipient approval links. Tokens are unique and bound to one outbox recipient. */
IF COL_LENGTH('dbo.PIP_T_InspectionEmailOutbox','ApprovalToken') IS NULL
    ALTER TABLE dbo.PIP_T_InspectionEmailOutbox ADD ApprovalToken UNIQUEIDENTIFIER NULL;
GO
IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionEmailOutbox')
      AND name='UX_PIP_T_InspectionEmailOutbox_ApprovalToken'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_T_InspectionEmailOutbox_ApprovalToken
        ON dbo.PIP_T_InspectionEmailOutbox(ApprovalToken)
        WHERE ApprovalToken IS NOT NULL;
END;
GO

/* Track the latest dispatch attempt so abandoned SENDING rows can be recovered safely. */
IF COL_LENGTH('dbo.PIP_T_InspectionEmailOutbox','LastAttemptDate') IS NULL
    ALTER TABLE dbo.PIP_T_InspectionEmailOutbox ADD LastAttemptDate DATETIME NULL;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionEmailOutbox')
      AND name = 'IX_PIP_T_InspectionEmailOutbox_Queue'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_InspectionEmailOutbox_Queue
        ON dbo.PIP_T_InspectionEmailOutbox (DeliveryStatus, NextAttemptDate, EmailOutboxID);
END;
GO
