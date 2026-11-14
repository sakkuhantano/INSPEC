/*
  Standard / Batch workflow:
  Technician -> configured SPV (Company + Location + Section).
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
         @Mode VARCHAR(10),@TypeName VARCHAR(100),@DetailName VARCHAR(100),
         @SPV VARCHAR(50),@SPVEmail VARCHAR(320),@TechEmail VARCHAR(320),
         @OldStatus VARCHAR(30),@Action VARCHAR(20),@EventID BIGINT,@TranCount INT;
 SELECT @C=I.CompanyID,@L=I.LocationID,@S=I.SectionID,@Owner=I.OwnerEmployeeID,@No=I.InspectionNo,
        @TypeName=I.InspectionTypeName,@DetailName=I.InspectionTypeDetailName,
        @Mode=ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')
 FROM dbo.PIP_T_Inspection I JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
 WHERE I.InspectionID=@p_InspectionID AND I.Status='DONE' AND ISNULL(I.IsApprove,0)=0
   AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH');
 IF @C IS NULL BEGIN RAISERROR('Inspection is not eligible for SPV workflow.',16,1); RETURN; END;
 IF @Owner<>@p_ActorEmployeeID BEGIN RAISERROR('Only the inspection owner can submit this inspection.',16,1); RETURN; END;
 SELECT @SPV=SPVEmployeeID FROM dbo.PIP_M_InspectionEmailSetupSection
 WHERE CompanyID=@C AND LocationID=@L AND SectionID=@S AND IsActive=1;
 IF ISNULL(@SPV,'')='' BEGIN RAISERROR('SPV routing is not configured for this Company, Location, and Section.',16,1); RETURN; END;
 IF NOT EXISTS
 (
  SELECT 1 FROM dbo.M_HRD_Employee E
  WHERE E.EmployeeID=@SPV AND E.CompanyID=@C AND E.SectionID=@S
    AND ISNULL(E.TerminationDate,'')=''
    AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
      AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
    AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
      WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@C AND CL.LocationID=@L)
 )
 BEGIN RAISERROR('Configured SPV is not active or lacks approval access for this Company, Location, and Section.',16,1); RETURN; END;
 SELECT @SPVEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))) FROM dbo.M_HRD_Employee WHERE EmployeeID=@SPV;
 SELECT @TechEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))) FROM dbo.M_HRD_Employee WHERE EmployeeID=@Owner;
 IF ISNULL(@SPVEmail,'')='' OR ISNULL(@TechEmail,'')='' BEGIN RAISERROR('SPV or Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
 SELECT @OldStatus=WorkflowStatus FROM dbo.PIP_T_InspectionWorkflow WITH (UPDLOCK,HOLDLOCK)
 WHERE EntityType='INSPECTION' AND EntityID=@p_InspectionID;
 IF @OldStatus='SUBMITTED' RETURN;
 IF @OldStatus='APPROVED' BEGIN RAISERROR('Inspection has already been finally approved.',16,1); RETURN; END;
 SET @Action=CASE WHEN @OldStatus='VOID' THEN 'RESUBMITTED' ELSE 'SUBMITTED' END;
 SET @TranCount=@@TRANCOUNT;
 BEGIN TRY
  IF @TranCount=0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION InspectionWorkflowSubmitSave;
  IF EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionWorkflow WHERE EntityType='INSPECTION' AND EntityID=@p_InspectionID)
   UPDATE dbo.PIP_T_InspectionWorkflow SET CompanyID=@C,LocationID=@L,SectionID=@S,
    WorkflowStatus='SUBMITTED',CurrentStageCode='SPV',SubmittedBy=@p_ActorEmployeeID,SubmittedDate=GETDATE(),
    LastActorEmployeeID=@p_ActorEmployeeID,LastActionDate=GETDATE(),LastRemark=NULL
   WHERE EntityType='INSPECTION' AND EntityID=@p_InspectionID;
  ELSE
   INSERT dbo.PIP_T_InspectionWorkflow(EntityType,EntityID,CompanyID,LocationID,SectionID,WorkflowStatus,CurrentStageCode,
    SubmittedBy,SubmittedDate,LastActorEmployeeID,LastActionDate,LastRemark)
   VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,'SUBMITTED','SPV',@p_ActorEmployeeID,GETDATE(),@p_ActorEmployeeID,GETDATE(),NULL);
  UPDATE dbo.PIP_T_Inspection
  SET Status='DONE',IsApprove=0,ApprovedBy='',
      ApprovedDate=CONVERT(DATETIME,'19000101',112),ApprovalRemark='',ReasonVoid='',
      UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
  WHERE InspectionID=@p_InspectionID;

  INSERT dbo.PIP_T_InspectionApprovalHistory(EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
   VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,'TECHNICIAN',@Action,@p_ActorEmployeeID,GETDATE(),NULL);
  SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
  INSERT dbo.PIP_T_InspectionEmailOutbox(NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
   EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
  VALUES
   ('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':SPV',@EventID,'INSPECTION',@p_InspectionID,
    'APPROVER',@SPV,@SPVEmail,N'Inspection menunggu approval SPV - '+ISNULL(@No,''),
    N'<p>Inspection '+ISNULL(@No,'')+N' ('+ISNULL(@Mode,'')+N') menunggu approval SPV.</p><p>'+ISNULL(@TypeName,'')+N' / '+ISNULL(@DetailName,'')+
    N'</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'">Buka halaman approval INSPEC</a></p>',
    N'Inspection menunggu approval SPV. '+ISNULL(@p_ApprovalUrl,N''),'PENDING',0,GETDATE()),
   ('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',@EventID,'INSPECTION',@p_InspectionID,
    'TECHNICIAN',@Owner,@TechEmail,N'Inspection telah dikirim - '+ISNULL(@No,''),
    N'<p>Inspection Anda telah dikirim dan menunggu approval SPV.</p>',
    N'Inspection Anda telah dikirim dan menunggu approval SPV.','PENDING',0,GETDATE());
  IF @TranCount=0 COMMIT TRANSACTION;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()=1 BEGIN IF @TranCount=0 ROLLBACK TRANSACTION; ELSE ROLLBACK TRANSACTION InspectionWorkflowSubmitSave; END
  ELSE IF XACT_STATE()=-1 AND @TranCount=0 ROLLBACK TRANSACTION;
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
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET @p_Action=UPPER(LTRIM(RTRIM(ISNULL(@p_Action,''))));
 SET @p_Remark=LTRIM(RTRIM(ISNULL(@p_Remark,N'')));
 IF @p_Action NOT IN ('APPROVE','VOID') BEGIN RAISERROR('Invalid SPV approval action.',16,1); RETURN; END;
 IF @p_Action='VOID' AND @p_Remark='' BEGIN RAISERROR('Void reason is required.',16,1); RETURN; END;
 DECLARE @C VARCHAR(10),@L VARCHAR(3),@S VARCHAR(10),@Owner VARCHAR(50),@No VARCHAR(10),@SPV VARCHAR(50),
         @TechEmail VARCHAR(320),@EventID BIGINT,@TranCount INT,@NewStatus VARCHAR(30),@NextStage VARCHAR(20);
 SELECT @C=I.CompanyID,@L=I.LocationID,@S=I.SectionID,@Owner=I.OwnerEmployeeID,@No=I.InspectionNo
 FROM dbo.PIP_T_Inspection I JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
 JOIN dbo.PIP_T_InspectionWorkflow W WITH (UPDLOCK,HOLDLOCK) ON W.EntityType='INSPECTION' AND W.EntityID=I.InspectionID
 WHERE I.InspectionID=@p_InspectionID AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH')
  AND W.WorkflowStatus='SUBMITTED' AND W.CurrentStageCode='SPV';
 IF @C IS NULL BEGIN RAISERROR('Inspection is not waiting for SPV approval.',16,1); RETURN; END;
 SELECT @SPV=SPVEmployeeID FROM dbo.PIP_M_InspectionEmailSetupSection
 WHERE CompanyID=@C AND LocationID=@L AND SectionID=@S AND IsActive=1;
 IF @SPV<>@p_ActorEmployeeID BEGIN RAISERROR('You are not the configured SPV for this Section.',16,1); RETURN; END;
 SELECT @TechEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))) FROM dbo.M_HRD_Employee WHERE EmployeeID=@Owner;
 IF ISNULL(@TechEmail,'')='' BEGIN RAISERROR('Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
 SET @NewStatus=CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOID' END;
 SET @NextStage=CASE WHEN @p_Action='APPROVE' THEN 'COMPLETED' ELSE 'TECHNICIAN' END;
 SET @TranCount=@@TRANCOUNT;
 BEGIN TRY
  IF @TranCount=0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION InspectionApprovalWorkflowSave;
  INSERT dbo.PIP_T_InspectionApprovalHistory(EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
   VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,'SPV',CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOIDED' END,
    @p_ActorEmployeeID,GETDATE(),NULLIF(@p_Remark,N''));
  SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
  UPDATE dbo.PIP_T_InspectionWorkflow SET WorkflowStatus=@NewStatus,CurrentStageCode=@NextStage,
   LastActorEmployeeID=@p_ActorEmployeeID,LastActionDate=GETDATE(),LastRemark=NULLIF(@p_Remark,N'')
   WHERE EntityType='INSPECTION' AND EntityID=@p_InspectionID;
  IF @p_Action='VOID'
  BEGIN
   UPDATE dbo.PIP_T_Inspection SET Status='DRAFT',IsApprove=0,ApprovedBy='',
    ApprovedDate=CONVERT(DATETIME,'19000101',112),ApprovalRemark='',
    ReasonVoid=CONVERT(VARCHAR(500),@p_Remark),UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
   WHERE InspectionID=@p_InspectionID;
   INSERT dbo.PIP_T_InspectionEmailOutbox(NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
    EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
   VALUES('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',@EventID,'INSPECTION',@p_InspectionID,
    'TECHNICIAN',@Owner,@TechEmail,N'Inspection perlu diperbaiki - '+ISNULL(@No,''),
    N'<p>Inspection dikembalikan untuk koreksi.</p><p>Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+
    N'</p><p><a href="'+ISNULL(@p_CorrectionUrl,N'')+N'">Buka INSPEC untuk memperbaiki dan submit ulang</a></p>',
    N'Inspection dikembalikan. Alasan: '+@p_Remark+N' '+ISNULL(@p_CorrectionUrl,N''),'PENDING',0,GETDATE());
  END
  ELSE
  BEGIN
   UPDATE dbo.PIP_T_Inspection SET IsApprove=1,ApprovedBy=@p_ActorEmployeeID,ApprovedDate=GETDATE(),
    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
   WHERE InspectionID=@p_InspectionID;
   INSERT dbo.PIP_T_InspectionEmailOutbox(NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
    EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
   VALUES('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',@EventID,'INSPECTION',@p_InspectionID,
    'TECHNICIAN',@Owner,@TechEmail,N'Inspection telah di-approve - '+ISNULL(@No,''),
    N'<p>Inspection Anda telah di-approve oleh SPV.</p>',N'Inspection Anda telah di-approve oleh SPV.','PENDING',0,GETDATE());
  END;
  IF @TranCount=0 COMMIT TRANSACTION;
  SELECT @NewStatus WorkflowStatus,@NextStage CurrentStageCode,@EventID ApprovalEventID;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()=1 BEGIN IF @TranCount=0 ROLLBACK TRANSACTION; ELSE ROLLBACK TRANSACTION InspectionApprovalWorkflowSave; END
  ELSE IF XACT_STATE()=-1 AND @TranCount=0 ROLLBACK TRANSACTION;
  DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
  SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
  RAISERROR(@Err,@Sev,@State);
 END CATCH
END;
GO
