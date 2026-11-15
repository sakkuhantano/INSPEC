/*
  INSPEC - Per inspection-mode email notification configuration.
  SQL Server 2008 compatible.
  Run after Database/InspectionEmailApproval_Schema.sql.

  Email is notification/routing only. Approval itself remains ONLINE in INSPEC.
  Defaults:
    STANDARD = OFF
    BATCH    = OFF
    LIGHTNING= ON
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionEmailSetupMode','U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_InspectionEmailSetupMode
    (
        CompanyID VARCHAR(10) NOT NULL,
        LocationID VARCHAR(3) NOT NULL,
        InspectionMode VARCHAR(10) NOT NULL,
        IsEmailEnabled BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionEmailSetupMode_IsEmailEnabled DEFAULT (0),
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionEmailSetupMode_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionEmailSetupMode_UpdateDate DEFAULT (GETDATE()),
        CONSTRAINT PK_PIP_M_InspectionEmailSetupMode PRIMARY KEY CLUSTERED (CompanyID,LocationID,InspectionMode),
        CONSTRAINT FK_PIP_M_InspectionEmailSetupMode_Header
            FOREIGN KEY (CompanyID,LocationID)
            REFERENCES dbo.PIP_M_InspectionEmailSetup (CompanyID,LocationID),
        CONSTRAINT CK_PIP_M_InspectionEmailSetupMode_Mode
            CHECK (InspectionMode IN ('STANDARD','BATCH','LIGHTNING'))
    );
END;
GO

/* Seed every configured Company + Location with safe defaults.
   Existing Lightning deployments keep email enabled; Standard/Batch remain silent. */
INSERT dbo.PIP_M_InspectionEmailSetupMode
    (CompanyID,LocationID,InspectionMode,IsEmailEnabled,EntryUser,UpdateUser)
SELECT H.CompanyID,H.LocationID,M.InspectionMode,
       CASE WHEN M.InspectionMode='LIGHTNING' THEN 1 ELSE 0 END,
       H.UpdateUser,H.UpdateUser
FROM dbo.PIP_M_InspectionEmailSetup H
CROSS JOIN
(
    SELECT 'STANDARD' InspectionMode
    UNION ALL SELECT 'BATCH'
    UNION ALL SELECT 'LIGHTNING'
) M
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.PIP_M_InspectionEmailSetupMode X
    WHERE X.CompanyID=H.CompanyID
      AND X.LocationID=H.LocationID
      AND X.InspectionMode=M.InspectionMode
);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_M_InspectionEmailSetupMode')
      AND name='IX_PIP_M_InspectionEmailSetupMode_Lookup'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_M_InspectionEmailSetupMode_Lookup
        ON dbo.PIP_M_InspectionEmailSetupMode (CompanyID,LocationID,IsEmailEnabled,InspectionMode);
END;
GO
