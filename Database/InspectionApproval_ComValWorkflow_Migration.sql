/*
    Convert legacy per-mode email switches into per-workflow, per-level flags.
    Run after InspectionEmailApproval_CommonValue_Migration.sql, if that
    legacy migration is needed. Existing workflow ComVal rows are never overwritten.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.SysWebCommonValue','U') IS NULL
BEGIN
    RAISERROR('dbo.SysWebCommonValue is required.',16,1);
    RETURN;
END;

BEGIN TRANSACTION;

/* STANDARD: SPV approval followed by manual CHIEF batch approval. The two email flags use the same legacy STANDARD switch. */
INSERT dbo.SysWebCommonValue
    (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
SELECT 'INSPEC',S.ScopeID+';STANDARD',
       '[SPV]['+CASE WHEN S.Enabled=1 THEN 'TRUE' ELSE 'FALSE' END+'];[CHIEF]['+
       CASE WHEN S.Enabled=1 THEN 'TRUE' ELSE 'FALSE' END+']',
       'EmailApproval','INSPEC Approval Email per Stage',0,0,'SYSTEM',GETDATE(),'SYSTEM',GETDATE()
FROM
(
    SELECT LEFT(C.ID,CHARINDEX(';EMAIL;',C.ID)-1) ScopeID,
           CASE WHEN LTRIM(RTRIM(C.Description))='1' THEN 1 ELSE 0 END Enabled
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID LIKE '%;EMAIL;STANDARD'
) S
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue X
    WHERE X.AppID='INSPEC' AND X.CommonGroup='EmailApproval' AND X.ID=S.ScopeID+';STANDARD'
);

/* Existing STANDARD rows from an earlier version receive the missing CHIEF token.
   Preserve the existing SPV switch; CHIEF starts with the same value as that switch. */
UPDATE C
SET Description=ISNULL(C.Description,'')+';[CHIEF]['+
    CASE WHEN CHARINDEX('[SPV][TRUE]',UPPER(ISNULL(C.Description,'')))>0 THEN 'TRUE' ELSE 'FALSE' END+']'
FROM dbo.SysWebCommonValue C
WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
  AND C.ID LIKE '%;STANDARD'
  AND CHARINDEX('[CHIEF][TRUE]',UPPER(ISNULL(C.Description,'')))=0
  AND CHARINDEX('[CHIEF][FALSE]',UPPER(ISNULL(C.Description,'')))=0
  AND (CHARINDEX('[SPV][TRUE]',UPPER(ISNULL(C.Description,'')))>0
       OR CHARINDEX('[SPV][FALSE]',UPPER(ISNULL(C.Description,'')))>0);

/* BATCH / PARAM: SPV -> one Section ProfitCenter-derived Chief (CHIEF_ENG / CHIEF_SEC / CHIEF_HK). The email flag uses the generic CHIEF token. */
INSERT dbo.SysWebCommonValue
    (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
SELECT 'INSPEC',S.ScopeID+';BATCH;PARAM',
       '[SPV]['+CASE WHEN S.Enabled=1 THEN 'TRUE' ELSE 'FALSE' END+'];[CHIEF]['+
       CASE WHEN S.Enabled=1 THEN 'TRUE' ELSE 'FALSE' END+']',
       'EmailApproval','INSPEC Approval Email per Stage',0,0,'SYSTEM',GETDATE(),'SYSTEM',GETDATE()
FROM
(
    SELECT LEFT(C.ID,CHARINDEX(';EMAIL;',C.ID)-1) ScopeID,
           CASE WHEN LTRIM(RTRIM(C.Description))='1' THEN 1 ELSE 0 END Enabled
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID LIKE '%;EMAIL;BATCH'
) S
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue X
    WHERE X.AppID='INSPEC' AND X.CommonGroup='EmailApproval' AND X.ID=S.ScopeID+';BATCH;PARAM'
);

/* BATCH / INSPECT: SPV -> CHIEF_SEC -> CHIEF_ENG. */
INSERT dbo.SysWebCommonValue
    (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
SELECT 'INSPEC',S.ScopeID+';BATCH;INSPECT',
       '[SPV]['+CASE WHEN S.Enabled=1 THEN 'TRUE' ELSE 'FALSE' END+'];[CHIEF_SEC]['+
       CASE WHEN S.Enabled=1 THEN 'TRUE' ELSE 'FALSE' END+'];[CHIEF_ENG]['+
       CASE WHEN S.Enabled=1 THEN 'TRUE' ELSE 'FALSE' END+']',
       'EmailApproval','INSPEC Approval Email per Stage',0,0,'SYSTEM',GETDATE(),'SYSTEM',GETDATE()
FROM
(
    SELECT LEFT(C.ID,CHARINDEX(';EMAIL;',C.ID)-1) ScopeID,
           CASE WHEN LTRIM(RTRIM(C.Description))='1' THEN 1 ELSE 0 END Enabled
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID LIKE '%;EMAIL;LIGHTNING'
) S
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue X
    WHERE X.AppID='INSPEC' AND X.CommonGroup='EmailApproval' AND X.ID=S.ScopeID+';BATCH;INSPECT'
);

COMMIT TRANSACTION;
GO
