/*
    INSPEC inspection approval routing and email foundation
    SQL Server 2008 compatible.

    Fixed workflow roles are intentionally represented as columns / StageCode values:
      SPV, CHIEF_ENG, CHIEF_SEC.
    No role master table is introduced.

    Routing scope:
      - Chief Engineering and Chief Security: one configuration per Company + Location.
      - SPV: one employee mapping per Company + Location + Section.
      - Employee IDs are stored; application resolves Name/emailaddress from M_HRD_Employee.
    Generic approval history/outbox supports both PIP_T_Inspection and the separate
    Lightning daily inspection transaction without forcing Lightning into PIP_T_Inspection.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionEmailSetup', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_InspectionEmailSetup
    (
        CompanyID VARCHAR(10) NOT NULL,
        LocationID VARCHAR(3) NOT NULL,
        ChiefEngEmployeeID VARCHAR(50) NOT NULL,
        ChiefSecEmployeeID VARCHAR(50) NOT NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionEmailSetup_IsActive DEFAULT (1),
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionEmailSetup_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionEmailSetup_UpdateDate DEFAULT (GETDATE()),
        CONSTRAINT PK_PIP_M_InspectionEmailSetup PRIMARY KEY CLUSTERED (CompanyID, LocationID)
    );
END;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionEmailSetupSection', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_InspectionEmailSetupSection
    (
        CompanyID VARCHAR(10) NOT NULL,
        LocationID VARCHAR(3) NOT NULL,
        SectionID VARCHAR(10) NOT NULL,
        SPVEmployeeID VARCHAR(50) NOT NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionEmailSetupSection_IsActive DEFAULT (1),
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionEmailSetupSection_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionEmailSetupSection_UpdateDate DEFAULT (GETDATE()),
        CONSTRAINT PK_PIP_M_InspectionEmailSetupSection
            PRIMARY KEY CLUSTERED (CompanyID, LocationID, SectionID),
        CONSTRAINT FK_PIP_M_InspectionEmailSetupSection_Header
            FOREIGN KEY (CompanyID, LocationID)
            REFERENCES dbo.PIP_M_InspectionEmailSetup (CompanyID, LocationID)
    );
END;
GO

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
            CHECK (ActionCode IN ('SUBMITTED', 'APPROVED', 'VOIDED', 'RESUBMITTED'))
    );
END;
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
