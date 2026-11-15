/*
  INSPEC - Email approval configuration in the shared SysWebCommonValue table.
  SQL Server 2008 compatible.

  CommonGroup : EmailApproval
  Key format  : <CompanyID><LocationID>;CHIEF_ENG
                <CompanyID><LocationID>;CHIEF_SEC
                <CompanyID><LocationID>;SPV;<SectionID>
                <CompanyID><LocationID>;EMAIL;STANDARD
                <CompanyID><LocationID>;EMAIL;BATCH
                <CompanyID><LocationID>;EMAIL;LIGHTNING

  For employee routing rows, Description = EmployeeID/NIK.
  For email mode rows, Description = '1' or '0'.
  Approval is always ONLINE. These values only control email notification.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Seed safe defaults only when the Company + Location already has an INSPEC setup.
   No new table is created. */
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
    SELECT 1
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC'
      AND C.CommonGroup='EmailApproval'
      AND C.ID=CONVERT(VARCHAR(30),H.CompanyID)+CONVERT(VARCHAR(30),H.LocationID)+';EMAIL;'+M.InspectionMode
);
GO
