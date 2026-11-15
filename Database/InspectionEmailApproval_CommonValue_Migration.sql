/*
  INSPEC - Move approval routing from temporary dedicated setup tables
  into dbo.SysWebCommonValue, then remove those temporary tables.

  Run only when the previous INSPEC approval setup schema has already
  created PIP_M_InspectionEmailSetup*, otherwise this script has nothing to do.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.SysWebCommonValue','U') IS NULL
BEGIN
    RAISERROR('dbo.SysWebCommonValue is required for INSPEC approval configuration.',16,1);
    RETURN;
END;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionEmailSetup','U') IS NOT NULL
BEGIN
    INSERT dbo.SysWebCommonValue
        (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    SELECT 'INSPEC',CONVERT(VARCHAR(30),CompanyID)+CONVERT(VARCHAR(30),LocationID)+';CHIEF_ENG',
           ChiefEngEmployeeID,'EmailApproval','INSPEC Inspection Email Approval',0,0,
           ISNULL(EntryUser,'SYSTEM'),ISNULL(EntryDate,GETDATE()),ISNULL(UpdateUser,'SYSTEM'),ISNULL(UpdateDate,GETDATE())
    FROM dbo.PIP_M_InspectionEmailSetup S
    WHERE ISNULL(S.ChiefEngEmployeeID,'')<>''
      AND NOT EXISTS (
          SELECT 1 FROM dbo.SysWebCommonValue C
          WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval'
            AND C.ID=CONVERT(VARCHAR(30),S.CompanyID)+CONVERT(VARCHAR(30),S.LocationID)+';CHIEF_ENG'
      );

    INSERT dbo.SysWebCommonValue
        (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    SELECT 'INSPEC',CONVERT(VARCHAR(30),CompanyID)+CONVERT(VARCHAR(30),LocationID)+';CHIEF_SEC',
           ChiefSecEmployeeID,'EmailApproval','INSPEC Inspection Email Approval',0,0,
           ISNULL(EntryUser,'SYSTEM'),ISNULL(EntryDate,GETDATE()),ISNULL(UpdateUser,'SYSTEM'),ISNULL(UpdateDate,GETDATE())
    FROM dbo.PIP_M_InspectionEmailSetup S
    WHERE ISNULL(S.ChiefSecEmployeeID,'')<>''
      AND NOT EXISTS (
          SELECT 1 FROM dbo.SysWebCommonValue C
          WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval'
            AND C.ID=CONVERT(VARCHAR(30),S.CompanyID)+CONVERT(VARCHAR(30),S.LocationID)+';CHIEF_SEC'
      );
END;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionEmailSetupSection','U') IS NOT NULL
BEGIN
    INSERT dbo.SysWebCommonValue
        (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    SELECT 'INSPEC',CONVERT(VARCHAR(30),CompanyID)+CONVERT(VARCHAR(30),LocationID)+';SPV;'+SectionID,
           SPVEmployeeID,'EmailApproval','INSPEC Inspection Email Approval',0,0,
           ISNULL(EntryUser,'SYSTEM'),ISNULL(EntryDate,GETDATE()),ISNULL(UpdateUser,'SYSTEM'),ISNULL(UpdateDate,GETDATE())
    FROM dbo.PIP_M_InspectionEmailSetupSection S
    WHERE ISNULL(S.SPVEmployeeID,'')<>''
      AND NOT EXISTS (
          SELECT 1 FROM dbo.SysWebCommonValue C
          WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval'
            AND C.ID=CONVERT(VARCHAR(30),S.CompanyID)+CONVERT(VARCHAR(30),S.LocationID)+';SPV;'+S.SectionID
      );
END;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionEmailSetupMode','U') IS NOT NULL
BEGIN
    INSERT dbo.SysWebCommonValue
        (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    SELECT 'INSPEC',
           CONVERT(VARCHAR(30),CompanyID)+CONVERT(VARCHAR(30),LocationID)+';EMAIL;'+InspectionMode,
           CASE WHEN IsEmailEnabled=1 THEN '1' ELSE '0' END,
           'EmailApproval','INSPEC Inspection Email Approval',0,0,
           ISNULL(EntryUser,'SYSTEM'),ISNULL(EntryDate,GETDATE()),ISNULL(UpdateUser,'SYSTEM'),ISNULL(UpdateDate,GETDATE())
    FROM dbo.PIP_M_InspectionEmailSetupMode S
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.SysWebCommonValue C
        WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval'
          AND C.ID=CONVERT(VARCHAR(30),S.CompanyID)+CONVERT(VARCHAR(30),S.LocationID)+';EMAIL;'+S.InspectionMode
    );
END;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionEmailSetupSection','U') IS NOT NULL
    DROP TABLE dbo.PIP_M_InspectionEmailSetupSection;
GO
IF OBJECT_ID('dbo.PIP_M_InspectionEmailSetupMode','U') IS NOT NULL
    DROP TABLE dbo.PIP_M_InspectionEmailSetupMode;
GO
IF OBJECT_ID('dbo.PIP_M_InspectionEmailSetup','U') IS NOT NULL
    DROP TABLE dbo.PIP_M_InspectionEmailSetup;
GO
