/*
  Standard / BATCH-PARAM workflow:
  STANDARD: Technician -> configured SPV; an inspection owned by that SPV is self-approved at sync.
  STANDARD CHIEF approval is created later as a manually selected batch by the SPV.
  BATCH/PARAM: Technician -> SPV -> Section ProfitCenter-derived Chief role.
  BATCH/INSPECT is handled by LightningInspection_Approval_Workflow.sql.
  SMTP is sent from the outbox dispatcher after the caller commits.
  Requires InspectionEmailApproval_Schema.sql.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_SubmitWorkflow','P') IS NOT NULL DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_SubmitWorkflow;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_SubmitWorkflow','P') IS NULL EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_SubmitWorkflow AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_SubmitWorkflow
 @p_InspectionID BIGINT,@p_ActorEmployeeID VARCHAR(50),@p_ApprovalUrl NVARCHAR(1000)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @C VARCHAR(10),@L VARCHAR(3),@S VARCHAR(10),@Owner VARCHAR(50),@No VARCHAR(10),
         @Mode VARCHAR(10),@ScheduleMode VARCHAR(10),@WorkflowKey VARCHAR(30),@ChiefRole VARCHAR(20),
         @TypeName VARCHAR(100),@DetailName VARCHAR(100),@SPV VARCHAR(4000),@Chief VARCHAR(4000),
         @SPVEmail VARCHAR(4000),@TechEmail VARCHAR(320),@ChiefEmail VARCHAR(4000),
         @SPVName NVARCHAR(4000),@TechName NVARCHAR(200),@ChiefName NVARCHAR(200),
         @ConfigScope VARCHAR(30),@EmailSPV BIT,@EmailChief BIT,@OldStatus VARCHAR(30),
         @Action VARCHAR(20),@EventID BIGINT,@LastActionCode VARCHAR(20),@IsChiefWorkflow BIT,@IsActorSPV BIT=0;
 SELECT @C=I.CompanyID,@L=I.LocationID,@S=I.SectionID,@Owner=I.OwnerEmployeeID,@No=I.InspectionNo,
        @TypeName=I.InspectionTypeName,@DetailName=I.InspectionTypeDetailName,
        @Mode=ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD'),
        @ScheduleMode=ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM')
 FROM dbo.PIP_T_Inspection I
 JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
 WHERE I.InspectionID=@p_InspectionID AND I.Status='DONE'
   AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.IsApproved,0)=0
   AND ISNULL(NULLIF(I.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH')
   AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH')
   AND (ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')='STANDARD'
        OR ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM')<>'INSPECT');
 IF @C IS NULL BEGIN RAISERROR('Inspection is not eligible for submission.',16,1); RETURN; END;
 IF @Owner<>@p_ActorEmployeeID BEGIN RAISERROR('Only the inspection owner can submit this inspection.',16,1); RETURN; END;

 SET @ConfigScope=CONVERT(VARCHAR(30),@C)+CONVERT(VARCHAR(30),@L);
 SET @WorkflowKey=CASE WHEN @Mode='STANDARD' THEN 'STANDARD' ELSE 'BATCH;PARAM' END;
 SET @ChiefRole=CASE WHEN @Mode='BATCH' AND @ScheduleMode='PARAM' THEN dbo.fnINSPEC_ChiefRoleForSection(@S) ELSE '' END;
 SET @IsChiefWorkflow=CASE WHEN @Mode='BATCH' AND @ScheduleMode='PARAM' THEN 1 ELSE 0 END;
 IF @IsChiefWorkflow=1 AND ISNULL(@ChiefRole,'')=''
 BEGIN RAISERROR('BATCH/PARAM Section has no supported ProfitCenterNo mapping (PENG/PSEC/PHKP).',16,1); RETURN; END;
 SET @EmailSPV=dbo.fnINSPEC_ApprovalEmailEnabled(@C,@L,@WorkflowKey,'SPV');
 SET @EmailChief=CASE WHEN @IsChiefWorkflow=1 THEN dbo.fnINSPEC_ApprovalEmailEnabled(@C,@L,@WorkflowKey,'CHIEF') ELSE 0 END;

 SELECT @SPV=NULLIF(LTRIM(RTRIM(C.Description)),'')
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';SPV;'+@S;
 IF ISNULL(@SPV,'')=''
 BEGIN RAISERROR('SPV approver mapping is required for this Company, Location, and Section, regardless of email settings.',16,1); RETURN; END;
 IF @Mode='STANDARD' AND EXISTS
 (
     SELECT 1 FROM dbo.SplitStringConvertToTable(@SPV,';') X
     WHERE LTRIM(RTRIM(X.val))=@Owner
 ) SET @IsActorSPV=1;

 IF EXISTS
 (
  SELECT 1 FROM dbo.SplitStringConvertToTable(@SPV,';') X
  WHERE NOT EXISTS
  (
   SELECT 1 FROM dbo.M_HRD_Employee E
   WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@C
     AND ISNULL(E.TerminationDate,'')=''
     AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
       AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
     AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
       WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@C AND CL.LocationID=@L)
       OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',E.EmployeeID,'') L WHERE L.CompanyID=@C AND L.LocationID=@L))
  )
 )
 BEGIN RAISERROR('One or more SPV approvers are inactive or lack Inspection approval access for this Company, Location, and Section.',16,1); RETURN; END;

 SELECT @Chief=NULLIF(LTRIM(RTRIM(C.Description)),'')
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';'+@ChiefRole;
 IF @IsChiefWorkflow=1 AND ISNULL(@Chief,'')<>''
 AND EXISTS
 (
  SELECT 1 FROM dbo.SplitStringConvertToTable(@Chief,';') X
  WHERE NOT EXISTS
  (
   SELECT 1 FROM dbo.M_HRD_Employee E
   WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@C
     AND ISNULL(E.TerminationDate,'')='' AND E.ProfitCenterNo=(SELECT S.ProfitCenterNo FROM dbo.PIP_M_Section S WHERE S.SectionID=@S)
     AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
       AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
     AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
       WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@C AND CL.LocationID=@L)
       OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',E.EmployeeID,'') L WHERE L.CompanyID=@C AND L.LocationID=@L))
  )
 )
 BEGIN RAISERROR('One or more configured Chief approvers are inactive or lack the matching ProfitCenter approval access for this Company and Location.',16,1); RETURN; END;

 SELECT @SPVName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val)))
   FROM dbo.SplitStringConvertToTable(@SPV,';') X LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val))
   ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@SPV),
        @SPVEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress))
   FROM dbo.SplitStringConvertToTable(@SPV,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val))
   WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');
 SELECT @TechName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@Owner),
        @TechEmail=LTRIM(RTRIM(ISNULL(emailaddress,'')))
 FROM dbo.M_HRD_Employee WHERE EmployeeID=@Owner;
 SELECT @ChiefName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val)))
   FROM dbo.SplitStringConvertToTable(@Chief,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val))
   ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@Chief),
        @ChiefEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress))
   FROM dbo.SplitStringConvertToTable(@Chief,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val))
   WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');

 IF @EmailSPV=1 AND @IsActorSPV=0 AND (ISNULL(@TechEmail,'')='' OR EXISTS
   (SELECT 1 FROM dbo.SplitStringConvertToTable(@SPV,';') X
    WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'')))
 BEGIN RAISERROR('Technician and every configured SPV need email addresses while SPV notification is enabled.',16,1); RETURN; END;
 IF @EmailChief=1 AND ISNULL(@Chief,'')<>'' AND EXISTS
   (SELECT 1 FROM dbo.SplitStringConvertToTable(@Chief,';') X
    WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))
 BEGIN RAISERROR('Every configured Chief approver needs an email address while CHIEF notification is enabled.',16,1); RETURN; END;

 SELECT @OldStatus=CASE WHEN ISNULL(IsSubmitted,0)=1
       THEN CASE WHEN ISNULL(IsApproved,0)=1 AND (@IsChiefWorkflow=0 OR ISNULL(IsApproved1,0)=1) THEN 'APPROVED' ELSE 'SUBMITTED' END
       WHEN Status='DRAFT' AND (ISNULL(ReasonVoid,'')<>'' OR ISNULL(ReasonVoid1,'')<>'') THEN 'VOID' ELSE '' END
 FROM dbo.PIP_T_Inspection WITH (UPDLOCK,HOLDLOCK) WHERE InspectionID=@p_InspectionID;
 IF @OldStatus='SUBMITTED' RETURN;
 IF @OldStatus='APPROVED' BEGIN RAISERROR('Inspection has already been finally approved.',16,1); RETURN; END;
 SELECT TOP 1 @LastActionCode=ActionCode FROM dbo.PIP_T_InspectionApprovalHistory
 WHERE EntityType='INSPECTION' AND EntityID=@p_InspectionID ORDER BY ApprovalEventID DESC;
 SET @Action=CASE WHEN @LastActionCode='VOIDED' THEN 'RESUBMITTED' ELSE 'SUBMITTED' END;

 BEGIN TRY
  UPDATE dbo.PIP_T_Inspection
  SET Status='DONE',IsSubmitted=1,SubmittedBy=@p_ActorEmployeeID,SubmittedDate=GETDATE(),
      IsApproved=CASE WHEN @IsActorSPV=1 THEN 1 ELSE 0 END,
      ApprovedBy=CASE WHEN @IsActorSPV=1 THEN @p_ActorEmployeeID ELSE '' END,
      ApprovedDate=CASE WHEN @IsActorSPV=1 THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
      IsApproved1=0,Approved1By='',Approved1Date=CONVERT(DATETIME,'19000101',112),
      IsApproved2=0,Approved2By='',Approved2Date=CONVERT(DATETIME,'19000101',112),
      ApprovalRemark='',ReasonVoid='',ReasonVoid1='',ReasonVoid2='',
      UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
  WHERE InspectionID=@p_InspectionID;

  INSERT dbo.PIP_T_InspectionApprovalHistory
   (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
  VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,'TECHNICIAN',@Action,@p_ActorEmployeeID,GETDATE(),NULL);
  SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());

  IF @IsActorSPV=1
  BEGIN
   INSERT dbo.PIP_T_InspectionApprovalHistory
    (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
   VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,'SPV','APPROVED',@p_ActorEmployeeID,GETDATE(),
          N'Auto-approved: inspection owner is a configured SPV.');
   SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
  END;

  IF @EmailSPV=1 AND @IsActorSPV=0
  BEGIN
   INSERT dbo.PIP_T_InspectionEmailOutbox
   (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
    EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
   SELECT 'INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':SPV:'+X.EmployeeID,
    @EventID,'INSPECTION',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
    N'Inspection menunggu approval SPV - '+ISNULL(@No,''),
    N'<p>Inspection '+ISNULL(@No,'')+N' ('+ISNULL(@Mode,'')+N') menunggu approval SPV.</p><p>Teknisi: '+ISNULL(@TechName,@Owner)+N' ('+ISNULL(@Owner,'')+N')</p><p>Approver: '+X.EmployeeName+N' ('+X.EmployeeID+N')</p><p>'+ISNULL(@TypeName,'')+N' / '+ISNULL(@DetailName,'')+N'</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'">Buka halaman approval INSPEC</a></p>',
    N'Inspection '+ISNULL(@No,'')+N' menunggu approval SPV '+X.EmployeeName+N' ('+X.EmployeeID+N'). '+ISNULL(@p_ApprovalUrl,N''),
    'PENDING',0,GETDATE()
   FROM (SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress,
                 ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
         FROM dbo.SplitStringConvertToTable(@SPV,';') S
         JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
         WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'') X;
   INSERT dbo.PIP_T_InspectionEmailOutbox
   (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
    EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
   VALUES('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',
    @EventID,'INSPECTION',@p_InspectionID,'TECHNICIAN',@Owner,@TechEmail,
    N'Inspection telah dikirim - '+ISNULL(@No,''),
    N'Halo '+ISNULL(@TechName,@Owner)+N', inspection '+ISNULL(@No,'')+N' telah dikirim dan menunggu approval SPV '+ISNULL(@SPVName,@SPV)+N'.',
    N'Inspection '+ISNULL(@No,'')+N' menunggu approval SPV '+ISNULL(@SPVName,@SPV)+N'.','PENDING',0,GETDATE());
  END;
 END TRY
 BEGIN CATCH
  DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
  SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
  RAISERROR(@Err,@Sev,@State);
 END CATCH
END;
GO

IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow','P') IS NOT NULL DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow','P') IS NULL EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow
 @p_InspectionID BIGINT,@p_ActorEmployeeID VARCHAR(50),@p_Action VARCHAR(10),
 @p_Remark NVARCHAR(1000),@p_CorrectionUrl NVARCHAR(1000)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT OFF;
 SET @p_Action=UPPER(LTRIM(RTRIM(ISNULL(@p_Action,''))));
 SET @p_Remark=LTRIM(RTRIM(ISNULL(@p_Remark,N'')));
 IF @p_Action NOT IN ('APPROVE','VOID') BEGIN RAISERROR('Invalid Inspection approval action.',16,1); RETURN; END;
 IF @p_Action='VOID' AND @p_Remark='' BEGIN RAISERROR('Void reason is required.',16,1); RETURN; END;

 DECLARE @C VARCHAR(10),@L VARCHAR(3),@S VARCHAR(10),@Owner VARCHAR(50),@No VARCHAR(10),
         @SPV VARCHAR(4000),@Chief VARCHAR(4000),@Mode VARCHAR(10),@ScheduleMode VARCHAR(10),
         @WorkflowKey VARCHAR(30),@ChiefRole VARCHAR(20),@IsChiefWorkflow BIT,@IsChiefStage BIT,
         @StageCode VARCHAR(20),@EmailStage BIT,@EmailNext BIT,
         @TechName NVARCHAR(200),@ActorName NVARCHAR(200),@TechEmail VARCHAR(320),
         @SPVEmail VARCHAR(4000),@ChiefEmail VARCHAR(4000),@ConfigScope VARCHAR(30),
         @EventID BIGINT,@NextStatus VARCHAR(30);
 SELECT @C=I.CompanyID,@L=I.LocationID,@S=I.SectionID,@Owner=I.OwnerEmployeeID,@No=I.InspectionNo,
        @Mode=ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD'),
        @ScheduleMode=ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM')
 FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
 JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
 WHERE I.InspectionID=@p_InspectionID
   AND I.ApprovalBatchID IS NULL
   AND NOT (ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')='BATCH'
            AND ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM')='PARAM'
            AND ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0)
   AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH')
   AND ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM')<>'INSPECT'
   AND ISNULL(I.IsSubmitted,0)=1
   AND (ISNULL(I.IsApproved,0)=0 OR
        (ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM' AND ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0));
 IF @C IS NULL BEGIN RAISERROR('Inspection is not waiting for an authorized approval stage.',16,1); RETURN; END;

 SET @ConfigScope=CONVERT(VARCHAR(30),@C)+CONVERT(VARCHAR(30),@L);
 SET @WorkflowKey=CASE WHEN @Mode='STANDARD' THEN 'STANDARD' ELSE 'BATCH;PARAM' END;
 SET @ChiefRole=CASE WHEN @Mode='BATCH' AND @ScheduleMode='PARAM' THEN dbo.fnINSPEC_ChiefRoleForSection(@S) ELSE '' END;
 SET @IsChiefWorkflow=CASE WHEN @Mode='BATCH' AND @ScheduleMode='PARAM' THEN 1 ELSE 0 END;
 IF @IsChiefWorkflow=1 AND ISNULL(@ChiefRole,'')=''
 BEGIN RAISERROR('BATCH/PARAM Section has no supported ProfitCenterNo mapping (PENG/PSEC/PHKP).',16,1); RETURN; END;
 SET @IsChiefStage=CASE WHEN @IsChiefWorkflow=1 AND ISNULL((SELECT I.IsApproved FROM dbo.PIP_T_Inspection I WHERE I.InspectionID=@p_InspectionID),0)=1 THEN 1 ELSE 0 END;
 SET @StageCode=CASE WHEN @IsChiefStage=1 THEN @ChiefRole ELSE 'SPV' END;
 SET @EmailStage=CASE WHEN @IsChiefStage=1 THEN dbo.fnINSPEC_ApprovalEmailEnabled(@C,@L,@WorkflowKey,'CHIEF')
                       ELSE dbo.fnINSPEC_ApprovalEmailEnabled(@C,@L,@WorkflowKey,'SPV') END;
 /* BATCH/PARAM Chief notifications are sent once per Chief batch, not per inspection. */
 SET @EmailNext=0;

 SELECT @SPV=NULLIF(LTRIM(RTRIM(C.Description)),'')
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';SPV;'+@S;
 SELECT @Chief=NULLIF(LTRIM(RTRIM(C.Description)),'')
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';'+@ChiefRole;

 IF @IsChiefStage=1 AND ISNULL(@Chief,'')=''
 BEGIN RAISERROR('configured Chief mapping was removed while this inspection was awaiting approval. Re-submit after confirming the workflow.',16,1); RETURN; END;
 IF NOT EXISTS
 (
  SELECT 1 FROM dbo.SysWebUser SU
  WHERE SU.EmployeeID=@p_ActorEmployeeID AND SU.IsActive=1
    AND (EXISTS (SELECT 1 FROM dbo.SysWebUserUserGroup UG WHERE UG.UserID=SU.UserID AND UG.UserGroupID='administrator')
         OR EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
    AND (EXISTS (SELECT 1 FROM dbo.SysWebUserUserGroup UG WHERE UG.UserID=SU.UserID AND UG.UserGroupID='administrator')
         OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(CASE WHEN @IsChiefStage=1 THEN @Chief ELSE @SPV END,';') X
                    WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
    AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL WHERE CL.UserID=SU.EmployeeID
                 AND CL.AppID='pip' AND CL.CompanyID=@C AND CL.LocationID=@L)
         OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L WHERE L.CompanyID=@C AND L.LocationID=@L))
 )
 BEGIN RAISERROR('You are not configured as an approver for the current Inspection stage or lack company/location access.',16,1); RETURN; END;

 SELECT @TechName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@Owner),
        @TechEmail=LTRIM(RTRIM(ISNULL(emailaddress,'')))
 FROM dbo.M_HRD_Employee WHERE EmployeeID=@Owner;
 SELECT @ActorName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@p_ActorEmployeeID)
 FROM dbo.M_HRD_Employee WHERE EmployeeID=@p_ActorEmployeeID;
 IF @EmailStage=1 AND (ISNULL(@TechEmail,'')='' OR
      (@IsChiefStage=0 AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SPV,';') X
        WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))) OR
      (@IsChiefStage=1 AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@Chief,';') X
        WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))))
 BEGIN RAISERROR('Email address is missing for this approval stage. Complete M_HRD_Employee.emailaddress or switch off its email flag.',16,1); RETURN; END;
 IF @EmailNext=1 AND ISNULL(@Chief,'')<>'' AND EXISTS
    (SELECT 1 FROM dbo.SplitStringConvertToTable(@Chief,';') X
     WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))
 BEGIN RAISERROR('Email address is missing for configured Chief recipients.',16,1); RETURN; END;

 BEGIN TRY
  INSERT dbo.PIP_T_InspectionApprovalHistory
   (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
  VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,@StageCode,
         CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOIDED' END,
         @p_ActorEmployeeID,GETDATE(),NULLIF(@p_Remark,N''));
  SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());

  IF @p_Action='VOID'
  BEGIN
   UPDATE dbo.PIP_T_Inspection
   SET Status='DRAFT',IsSubmitted=0,SubmittedBy='',SubmittedDate=CONVERT(DATETIME,'19000101',112),
       IsApproved=0,ApprovedBy='',ApprovedDate=CASE WHEN @IsChiefStage=0 THEN GETDATE() ELSE ApprovedDate END,
       IsApproved1=0,Approved1By='',Approved1Date=CASE WHEN @IsChiefStage=1 THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
       IsApproved2=0,Approved2By='',Approved2Date=CONVERT(DATETIME,'19000101',112),
       ApprovalRemark='',
       ReasonVoid=CASE WHEN @IsChiefStage=0 THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid END,
       ReasonVoid1=CASE WHEN @IsChiefStage=1 THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid1 END,
       ReasonVoid2='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
   WHERE InspectionID=@p_InspectionID;

   IF @EmailStage=1
    INSERT dbo.PIP_T_InspectionEmailOutbox
    (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
     EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
    VALUES('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',
     @EventID,'INSPECTION',@p_InspectionID,'TECHNICIAN',@Owner,@TechEmail,
     N'Inspection perlu diperbaiki - '+ISNULL(@No,''),
     N'Halo '+ISNULL(@TechName,@Owner)+N', inspection '+ISNULL(@No,'')+N' dikembalikan oleh '+@StageCode+N'. Alasan: '+@p_Remark+
       N' <a href="'+ISNULL(@p_CorrectionUrl,N'')+N'">Buka INSPEC</a>',
     N'Inspection '+ISNULL(@No,'')+N' dikembalikan pada stage '+@StageCode+N'. Alasan: '+@p_Remark+N' '+ISNULL(@p_CorrectionUrl,N''),
     'PENDING',0,GETDATE());
  END
  ELSE
  BEGIN
   IF @IsChiefStage=1
   BEGIN
    UPDATE dbo.PIP_T_Inspection
    SET IsApproved1=1,Approved1By=@p_ActorEmployeeID,Approved1Date=GETDATE(),
        ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid1='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
    WHERE InspectionID=@p_InspectionID;
   END
   ELSE
   BEGIN
    UPDATE dbo.PIP_T_Inspection
    SET IsApproved=1,ApprovedBy=@p_ActorEmployeeID,ApprovedDate=GETDATE(),
        IsApproved1=CASE WHEN @IsChiefWorkflow=1 AND ISNULL(@Chief,'')='' THEN 1 ELSE 0 END,
        Approved1By=CASE WHEN @IsChiefWorkflow=1 AND ISNULL(@Chief,'')='' THEN @p_ActorEmployeeID ELSE '' END,
        Approved1Date=CASE WHEN @IsChiefWorkflow=1 AND ISNULL(@Chief,'')='' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
        ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid='',ReasonVoid1='',
        UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
    WHERE InspectionID=@p_InspectionID;

    IF @IsChiefWorkflow=1 AND ISNULL(@Chief,'')=''
     INSERT dbo.PIP_T_InspectionApprovalHistory
      (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
     VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,@ChiefRole,'SKIPPED',@p_ActorEmployeeID,GETDATE(),
            N'Auto-skipped: no '+@ChiefRole+' mapping; Approved1By is stamped with the actual SPV approver.');
   END;

   IF @EmailStage=1
    INSERT dbo.PIP_T_InspectionEmailOutbox
    (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
     EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
    VALUES('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',
     @EventID,'INSPECTION',@p_InspectionID,'TECHNICIAN',@Owner,@TechEmail,
     N'Inspection approval update - '+ISNULL(@No,''),
     N'Inspection '+ISNULL(@No,'')+N' telah disetujui oleh '+ISNULL(@ActorName,@p_ActorEmployeeID)+N' ('+@StageCode+N').',
     N'Inspection '+ISNULL(@No,'')+N' telah disetujui oleh '+ISNULL(@ActorName,@p_ActorEmployeeID)+N' ('+@StageCode+N').',
     'PENDING',0,GETDATE());

   IF @IsChiefStage=0 AND @EmailNext=1 AND ISNULL(@Chief,'')<>''
   BEGIN
    INSERT dbo.PIP_T_InspectionEmailOutbox
    (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
     EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
    SELECT 'INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':CHIEF:'+X.EmployeeID,
     @EventID,'INSPECTION',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
     N'Inspection menunggu approval '+@ChiefRole+N' - '+ISNULL(@No,''),
     N'Inspection '+ISNULL(@No,'')+N' telah di-approve SPV dan menunggu approval '+@ChiefRole+N' '+X.EmployeeName+N'. <a href="'+REPLACE(ISNULL(@p_CorrectionUrl,N''),N'type=entry',N'type=approval')+N'">Buka approval INSPEC</a>',
     N'Inspection '+ISNULL(@No,'')+N' menunggu approval '+@ChiefRole+N' '+X.EmployeeName+N'.',
     'PENDING',0,GETDATE()
    FROM (SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress,
                 ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
          FROM dbo.SplitStringConvertToTable(@Chief,';') S
          JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
          WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'') X;
   END;
  END;
  SELECT @p_InspectionID InspectionID,@StageCode StageCode,@p_Action ActionCode,@EventID ApprovalEventID;
 END TRY
 BEGIN CATCH
  DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
  SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
  RAISERROR(@Err,@Sev,@State);
 END CATCH;
END;
GO

/*
  Execute the legacy Follow Up WO approval and the common header workflow
  atomically. The nested procedures use nested transactions/savepoints, so
  a failure in either step rolls back both the approval and any generated WO.
*/
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Approval_Execute','P') IS NOT NULL
    DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_Approval_Execute;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Approval_Execute','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_Approval_Execute AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_Approval_Execute
 @p_InspectionID BIGINT,@p_Action VARCHAR(10),@p_EmployeeID VARCHAR(50),
 @p_CompanyID VARCHAR(10),@p_LocationID VARCHAR(3),@p_Remark NVARCHAR(1000),
 @p_CorrectionUrl NVARCHAR(1000)
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT OFF;
 /* CF.EQueryP owns the transaction for this approval operation. */
 BEGIN TRY
  EXEC dbo.spUTL_PIP_T_Inspection_Approval
   @p_InspectionID=@p_InspectionID,@p_Action=@p_Action,@p_EmployeeID=@p_EmployeeID,
   @p_CompanyID=@p_CompanyID,@p_LocationID=@p_LocationID,@p_Remark=@p_Remark;
  EXEC dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow
   @p_InspectionID=@p_InspectionID,@p_ActorEmployeeID=@p_EmployeeID,@p_Action=@p_Action,
   @p_Remark=@p_Remark,@p_CorrectionUrl=@p_CorrectionUrl;
 END TRY
 BEGIN CATCH
  DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
  SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
  RAISERROR(@Err,@Sev,@State);
  RETURN;
 END CATCH;
END;
GO
