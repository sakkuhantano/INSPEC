/*
  INSPEC - Email approval configuration in dbo.SysWebCommonValue.
  SQL Server 2008 compatible.

  CommonGroup = EmailApproval
  Employee routing:
    <CompanyID><LocationID>;CHIEF_ENG
    <CompanyID><LocationID>;CHIEF_SEC
    <CompanyID><LocationID>;SPV;<SectionID>
  Email switches:
    <CompanyID><LocationID>;EMAIL;STANDARD
    <CompanyID><LocationID>;EMAIL;BATCH
    <CompanyID><LocationID>;EMAIL;LIGHTNING

  Employee rows store EmployeeID/NIK in Description.
  Email switch rows store '1' or '0' in Description.
  Approval itself is always ONLINE.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Optional default email switches for existing Company + Location setup rows.
   This script does not create any table. */
INSERT dbo.SysWebCommonValue
    (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
SELECT 'INSPEC',
       CONVERT(VARCHAR(30),H.CompanyID)+CONVERT(VARCHAR(30),H.LocationID)+';EMAIL;'+M.InspectionMode,
       CASE WHEN M.InspectionMode='LIGHTNING' THEN '1' ELSE '0' END,
       'EmailApproval','INSPEC Inspection Email Approval',0,0,
       H.UpdateUser,GETDATE(),H.UpdateUser,GETDATE()
FROM dbo.PIP_M_InspectionEmailSetup H
CROSS JOIN
(
    SELECT 'STANDARD' InspectionMode
    UNION ALL SELECT 'BATCH'
    UNION ALL SELECT 'LIGHTNING'
) M
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC'
      AND C.CommonGroup='EmailApproval'
      AND C.ID=CONVERT(VARCHAR(30),H.CompanyID)+CONVERT(VARCHAR(30),H.LocationID)+';EMAIL;'+M.InspectionMode
);
GO
