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
         @EmailEnabled BIT,@SPV VARCHAR(50),@SPVEmail VARCHAR(320),@TechEmail VARCHAR(320),
          @SPVName NVARCHAR(200),@TechName NVARCHAR(200),@ActorName NVARCHAR(200),
         @ConfigScope VARCHAR(30),@OldStatus VARCHAR(30),@Action VARCHAR(20),@EventID BIGINT,@TranCount INT;
 SELECT @C=I.CompanyID,@L=I.LocationID,@S=I.SectionID,@Owner=I.OwnerEmployeeID,@No=I.InspectionNo,
        @TypeName=I.InspectionTypeName,@DetailName=I.InspectionTypeDetailName,
        @Mode=ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')
 FROM dbo.PIP_T_Inspection I JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
 WHERE I.InspectionID=@p_InspectionID AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.IsApprovedFinal,0)=0
   AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH');
 IF @C IS NULL BEGIN RAISERROR('Inspection is not eligible for SPV workflow.',16,1); RETURN; END;
 SET @ConfigScope=CONVERT(VARCHAR(30),@C)+CONVERT(VARCHAR(30),@L);
 SELECT @EmailEnabled=CASE WHEN ISNULL(C.Description,'0')='1' THEN 1 ELSE 0 END
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';EMAIL;'+@Mode;
 SET @EmailEnabled=ISNULL(@EmailEnabled,0);
 IF @Owner<>@p_ActorEmployeeID BEGIN RAISERROR('Only the inspection owner can submit this inspection.',16,1); RETURN; END;
 SELECT @SPV=NULLIF(LTRIM(RTRIM(C.Description)),'')
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';SPV;'+@S;
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
 IF @EmailEnabled=1
 BEGIN
  SELECT @SPVEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))) FROM dbo.M_HRD_Employee WHERE EmployeeID=@SPV;
  SELECT @TechEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))) FROM dbo.M_HRD_Employee WHERE EmployeeID=@Owner;
  IF ISNULL(@SPVEmail,'')='' OR ISNULL(@TechEmail,'')=''
  BEGIN RAISERROR('SPV or Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
 END;
 SELECT @OldStatus=CASE WHEN ISNULL(IsSubmitted,0)=1 THEN CASE WHEN ISNULL(IsApprovedFinal,0)=1 THEN 'APPROVED' ELSE 'SUBMITTED' END
  WHEN Status='DRAFT' AND ISNULL(ReasonVoid,'')<>'' THEN 'VOID' ELSE '' END
 FROM dbo.PIP_T_Inspection WITH (UPDLOCK,HOLDLOCK) WHERE InspectionID=@p_InspectionID;
 IF @OldStatus='SUBMITTED' RETURN;
 IF @OldStatus='APPROVED' BEGIN RAISERROR('Inspection has already been finally approved.',16,1); RETURN; END;
 SELECT TOP 1 @LastActionCode=ActionCode
 FROM dbo.PIP_T_InspectionApprovalHistory
 WHERE EntityType='INSPECTION' AND EntityID=@p_InspectionID
 ORDER BY ApprovalEventID DESC;
 SET @Action=CASE WHEN @LastActionCode='VOIDED' THEN 'RESUBMITTED' ELSE 'SUBMITTED' END;
 SET @TranCount=@@TRANCOUNT;
 BEGIN TRY
  IF @TranCount=0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION InspectionWorkflowSubmitSave;
  UPDATE dbo.PIP_T_Inspection
  SET Status='DONE',IsSubmitted=1,SubmittedBy=@p_ActorEmployeeID,SubmittedDate=GETDATE(),
      IsApproved=0,ApprovedBy='',ApprovedDate=CONVERT(DATETIME,'19000101',112),
      IsApprovedFinal=0,ApprovedFinalBy='',ApprovedFinalDate=CONVERT(DATETIME,'19000101',112),
      ApprovalRemark='',ReasonVoid='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
  WHERE InspectionID=@p_InspectionID;

  INSERT dbo.PIP_T_InspectionApprovalHistory(EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
   VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,'TECHNICIAN',@Action,@p_ActorEmployeeID,GETDATE(),NULL);
  SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
  IF @EmailEnabled=1
  BEGIN
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
   
  END;
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
         @Mode VARCHAR(10),@EmailEnabled BIT,@TechEmail VARCHAR(320),@ConfigScope VARCHAR(30),
         @EventID BIGINT,@TranCount INT,@NewStatus VARCHAR(30),@NextStage VARCHAR(20);
 SELECT @C=I.CompanyID,@L=I.LocationID,@S=I.SectionID,@Owner=I.OwnerEmployeeID,@No=I.InspectionNo,
        @Mode=ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')
 FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
 JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
 WHERE I.InspectionID=@p_InspectionID AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH')
  AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApprovedFinal,0)=0;
 IF @C IS NULL BEGIN RAISERROR('Inspection is not waiting for SPV approval.',16,1); RETURN; END;
 SET @ConfigScope=CONVERT(VARCHAR(30),@C)+CONVERT(VARCHAR(30),@L);
 SELECT @EmailEnabled=CASE WHEN ISNULL(C.Description,'0')='1' THEN 1 ELSE 0 END
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';EMAIL;'+@Mode;
 SET @EmailEnabled=ISNULL(@EmailEnabled,0);
 SELECT @SPV=NULLIF(LTRIM(RTRIM(C.Description)),'')
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';SPV;'+@S;
 IF @SPV<>@p_ActorEmployeeID BEGIN RAISERROR('You are not the configured SPV for this Section.',16,1); RETURN; END;
 IF @EmailEnabled=1
 BEGIN
  SELECT @TechEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))) FROM dbo.M_HRD_Employee WHERE EmployeeID=@Owner;
  IF ISNULL(@TechEmail,'')='' BEGIN RAISERROR('Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
 END;
 SET @NewStatus=CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOID' END;
 SET @NextStage=CASE WHEN @p_Action='APPROVE' THEN 'COMPLETED' ELSE 'TECHNICIAN' END;
 SET @TranCount=@@TRANCOUNT;
 BEGIN TRY
  IF @TranCount=0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION InspectionApprovalWorkflowSave;
  INSERT dbo.PIP_T_InspectionApprovalHistory(EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
   VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,'SPV',CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOIDED' END,
    @p_ActorEmployeeID,GETDATE(),NULLIF(@p_Remark,N''));
  SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
  IF @p_Action='VOID'
  BEGIN
   UPDATE dbo.PIP_T_Inspection SET Status='DRAFT',
    IsSubmitted=0,SubmittedBy='',SubmittedDate=CONVERT(DATETIME,'19000101',112),
    IsApproved=0,ApprovedBy='',ApprovedDate=CONVERT(DATETIME,'19000101',112),
    IsApprovedFinal=0,ApprovedFinalBy='',ApprovedFinalDate=CONVERT(DATETIME,'19000101',112),
    ApprovalRemark='',ReasonVoid=CONVERT(VARCHAR(500),@p_Remark),
    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
   WHERE InspectionID=@p_InspectionID;
   IF @EmailEnabled=1
   BEGIN
       INSERT dbo.PIP_T_InspectionEmailOutbox(NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
        EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
       VALUES('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',@EventID,'INSPECTION',@p_InspectionID,
        'TECHNICIAN',@Owner,@TechEmail,N'Inspection perlu diperbaiki - '+ISNULL(@No,''),
        N'<p>Halo '+ISNULL(@TechName,@Owner)+N' ('+ISNULL(@Owner,'')+N'), inspection '+ISNULL(@No,'')+N' dikembalikan oleh SPV '+ISNULL(@ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N') untuk koreksi.</p><p>Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+
        N'</p><p><a href="'+ISNULL(@p_CorrectionUrl,N'')+N'">Buka INSPEC untuk memperbaiki dan submit ulang</a></p>',
        N'Inspection '+ISNULL(@No,'')+N' dikembalikan oleh SPV '+ISNULL(@ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N'). Alasan: '+@p_Remark+N' '+ISNULL(@p_CorrectionUrl,N''),'PENDING',0,GETDATE());
    
   END
  END
  ELSE
  BEGIN
   UPDATE dbo.PIP_T_Inspection SET IsApproved=1,ApprovedBy=@p_ActorEmployeeID,ApprovedDate=GETDATE(),
    IsApprovedFinal=1,ApprovedFinalBy=@p_ActorEmployeeID,ApprovedFinalDate=GETDATE(),
    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
   WHERE InspectionID=@p_InspectionID;
   IF @EmailEnabled=1
   BEGIN
       INSERT dbo.PIP_T_InspectionEmailOutbox(NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
        EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
       VALUES('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',@EventID,'INSPECTION',@p_InspectionID,
        'TECHNICIAN',@Owner,@TechEmail,N'Inspection telah di-approve - '+ISNULL(@No,''),
        N'<p>Halo '+ISNULL(@TechName,@Owner)+N' ('+ISNULL(@Owner,'')+N'), inspection '+ISNULL(@No,'')+N' telah di-approve oleh SPV '+ISNULL(@ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N').</p>',
         N'Inspection '+ISNULL(@No,'')+N' telah di-approve oleh SPV '+ISNULL(@ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N').','PENDING',0,GETDATE());
      END;
    
   END;
  IF @TranCount=0 COMMIT TRANSACTION;
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
 @p_InspectionID BIGINT,
 @p_Action VARCHAR(10),
 @p_EmployeeID VARCHAR(50),
 @p_CompanyID VARCHAR(10),
 @p_LocationID VARCHAR(3),
 @p_Remark NVARCHAR(1000),
 @p_CorrectionUrl NVARCHAR(1000)
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.spUTL_PIP_T_Inspection_Approval
   @p_InspectionID=@p_InspectionID,@p_Action=@p_Action,@p_EmployeeID=@p_EmployeeID,
   @p_CompanyID=@p_CompanyID,@p_LocationID=@p_LocationID,@p_Remark=@p_Remark;
  EXEC dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow
   @p_InspectionID=@p_InspectionID,@p_ActorEmployeeID=@p_EmployeeID,@p_Action=@p_Action,
   @p_Remark=@p_Remark,@p_CorrectionUrl=@p_CorrectionUrl;
  COMMIT TRANSACTION;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  DECLARE @V_ExecuteError NVARCHAR(4000),@V_ExecuteSeverity INT,@V_ExecuteState INT;
  SELECT @V_ExecuteError=ERROR_MESSAGE(),@V_ExecuteSeverity=ERROR_SEVERITY(),@V_ExecuteState=ERROR_STATE();
  RAISERROR(@V_ExecuteError,@V_ExecuteSeverity,@V_ExecuteState);
 END CATCH;
END;
GO
