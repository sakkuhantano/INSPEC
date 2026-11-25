CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow
 @p_InspectionID BIGINT,@p_ActorEmployeeID VARCHAR(50),@p_Action VARCHAR(10),
 @p_Remark NVARCHAR(1000),@p_CorrectionUrl NVARCHAR(1000)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT OFF;
 SET @p_Action=UPPER(LTRIM(RTRIM(ISNULL(@p_Action,''))));
 SET @p_Remark=LTRIM(RTRIM(ISNULL(@p_Remark,N'')));
 IF @p_Action NOT IN ('APPROVE','VOID') BEGIN RAISERROR('Invalid Inspection approval action.',16,1); RETURN; END;
 IF @p_Action='VOID' AND @p_Remark='' BEGIN RAISERROR('Void reason is required.',16,1); RETURN; END;
 DECLARE @C VARCHAR(10),@L VARCHAR(3),@S VARCHAR(10),@Owner VARCHAR(50),@No VARCHAR(10),@SPV VARCHAR(4000),
         @Mode VARCHAR(10),@WorkflowCode VARCHAR(30),@ChiefEng VARCHAR(4000),@EmailEnabled BIT,@IsChiefEngStage BIT,@StageCode VARCHAR(20),@TechName NVARCHAR(200),@ActorName NVARCHAR(200),@TechEmail VARCHAR(320),@ActorEmail VARCHAR(320),@ConfigScope VARCHAR(30),
         @EventID BIGINT;
 SELECT @C=I.CompanyID,@L=I.LocationID,@S=I.SectionID,@Owner=I.OwnerEmployeeID,@No=I.InspectionNo,
        @Mode=ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD'),
        @WorkflowCode=ISNULL(NULLIF(IT.ApprovalWorkflowCode,''),'STANDARD'),
        @IsChiefEngStage=CASE WHEN ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0 AND ISNULL(IT.ApprovalWorkflowCode,'')='SPV_CHIEF_ENG' THEN 1 ELSE 0 END
 FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
 JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
 WHERE I.InspectionID=@p_InspectionID AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH')
  AND ISNULL(I.IsSubmitted,0)=1 AND (ISNULL(I.IsApproved,0)=0 OR (ISNULL(IT.ApprovalWorkflowCode,'')='SPV_CHIEF_ENG' AND ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0));
 IF @C IS NULL BEGIN RAISERROR('Inspection is not waiting for an authorized approval stage.',16,1); RETURN; END;
 SET @ConfigScope=CONVERT(VARCHAR(30),@C)+CONVERT(VARCHAR(30),@L);
 SET @StageCode=CASE WHEN @IsChiefEngStage=1 THEN 'CHIEF_ENG' ELSE 'SPV' END;
 IF @WorkflowCode='SPV_CHIEF_ENG'
 BEGIN
  SELECT @ChiefEng=NULLIF(LTRIM(RTRIM(C.Description)),'') FROM dbo.SysWebCommonValue C
  WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=@ConfigScope+';CHIEF_ENG';
  IF ISNULL(@ChiefEng,'')='' BEGIN RAISERROR('Chief Engineering approver setup is missing.',16,1); RETURN; END;
 END;
 SELECT @EmailEnabled=CASE WHEN ISNULL(C.Description,'0')='1' THEN 1 ELSE 0 END
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';EMAIL;'+@Mode;
 SET @EmailEnabled=ISNULL(@EmailEnabled,0);
 SELECT @SPV=NULLIF(LTRIM(RTRIM(C.Description)),'')
 FROM dbo.SysWebCommonValue C
 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
   AND C.ID=@ConfigScope+';SPV;'+@S;
 /* Administrator group may approve any Standard/Batch section; workflow state and company/location checks remain enforced by the caller and this procedure. */
 IF NOT EXISTS
 (
  SELECT 1 FROM dbo.SysWebUser SU JOIN dbo.SysWebUserUserGroup UG ON UG.UserID=SU.UserID
  WHERE SU.EmployeeID=@p_ActorEmployeeID AND SU.IsActive=1 AND UG.UserGroupID='administrator'
 )
 AND NOT EXISTS
 (
  SELECT 1 FROM dbo.SplitStringConvertToTable(CASE WHEN @IsChiefEngStage=1 THEN @ChiefEng ELSE @SPV END,';') X
  WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID
 )
 BEGIN RAISERROR('You are not configured as an approver for the current Inspection stage.',16,1); RETURN; END;
 SELECT @TechName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@Owner),@TechEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))) FROM dbo.M_HRD_Employee WHERE EmployeeID=@Owner;
 SELECT @ActorName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@p_ActorEmployeeID),
        @ActorEmail=LTRIM(RTRIM(ISNULL(emailaddress,'')))
 FROM dbo.M_HRD_Employee WHERE EmployeeID=@p_ActorEmployeeID;
 IF @EmailEnabled=1
 BEGIN
  IF ISNULL(@TechEmail,'')='' BEGIN RAISERROR('Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
  IF ISNULL(@ActorEmail,'')='' BEGIN RAISERROR('Approver email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
  IF @WorkflowCode='SPV_CHIEF_ENG' AND @IsChiefEngStage=0 AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@ChiefEng,';') X WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'')) BEGIN RAISERROR('Chief Engineering email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
 END;
 BEGIN TRY
  INSERT dbo.PIP_T_InspectionApprovalHistory(EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
   VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,@StageCode,CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOIDED' END,
    @p_ActorEmployeeID,GETDATE(),NULLIF(@p_Remark,N''));
  SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
  IF @p_Action='VOID'
  BEGIN
   UPDATE dbo.PIP_T_Inspection SET Status='DRAFT',
    IsSubmitted=0,SubmittedBy='',SubmittedDate=CONVERT(DATETIME,'19000101',112),
    IsApproved=0,ApprovedBy='',ApprovedDate=GETDATE(),
    IsApproved1=0,Approved1By='',Approved1Date=CONVERT(DATETIME,'19000101',112),
    ApprovalRemark='',ReasonVoid=CONVERT(VARCHAR(500),@p_Remark),
    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
   WHERE InspectionID=@p_InspectionID;
   IF @EmailEnabled=1
   BEGIN
       INSERT dbo.PIP_T_InspectionEmailOutbox(NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
        EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
       VALUES('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',@EventID,'INSPECTION',@p_InspectionID,
        'TECHNICIAN',@Owner,@TechEmail,CASE WHEN @IsChiefEngStage=1 THEN N'Inspection perlu diperbaiki oleh Chief Engineering - ' ELSE N'Inspection perlu diperbaiki oleh SPV - ' END+ISNULL(@No,''),
        N'<p>Halo '+ISNULL(@TechName,@Owner)+N' ('+ISNULL(@Owner,'')+N'), inspection '+ISNULL(@No,'')+N' dikembalikan oleh '+CASE WHEN @IsChiefEngStage=1 THEN N'Chief Engineering ' ELSE N'SPV ' END+ISNULL(@ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N') untuk koreksi.</p><p>Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+
        N'</p><p><a href="'+ISNULL(@p_CorrectionUrl,N'')+N'">Buka INSPEC untuk memperbaiki dan submit ulang</a></p>',
        N'Inspection '+ISNULL(@No,'')+N' dikembalikan oleh '+CASE WHEN @IsChiefEngStage=1 THEN N'Chief Engineering ' ELSE N'SPV ' END+ISNULL(@ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N'). Alasan: '+@p_Remark+N' '+ISNULL(@p_CorrectionUrl,N''),'PENDING',0,GETDATE());
    
   END
  END
  ELSE
  BEGIN
   IF @IsChiefEngStage=1
    UPDATE dbo.PIP_T_Inspection SET IsApproved1=1,Approved1By=@p_ActorEmployeeID,Approved1Date=GETDATE(),
     ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
    WHERE InspectionID=@p_InspectionID;
   ELSE
    UPDATE dbo.PIP_T_Inspection SET IsApproved=1,ApprovedBy=@p_ActorEmployeeID,ApprovedDate=GETDATE(),
     ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
    WHERE InspectionID=@p_InspectionID;
   IF @EmailEnabled=1
   BEGIN
       INSERT dbo.PIP_T_InspectionEmailOutbox(NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
        EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
       VALUES('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',@EventID,'INSPECTION',@p_InspectionID,
        'TECHNICIAN',@Owner,@TechEmail,CASE WHEN @IsChiefEngStage=1 THEN N'Inspection telah di-acknowledge Chief Engineering - ' WHEN @WorkflowCode='SPV_CHIEF_ENG' THEN N'Inspection telah diverifikasi SPV - ' ELSE N'Inspection telah di-approve - ' END+ISNULL(@No,''),
        N'<p>Halo '+ISNULL(@TechName,@Owner)+N', inspection '+ISNULL(@No,'')+N' telah diproses oleh '+CASE WHEN @IsChiefEngStage=1 THEN N'Chief Engineering ' ELSE N'SPV ' END+ISNULL(@ActorName,@p_ActorEmployeeID)+CASE WHEN @WorkflowCode='SPV_CHIEF_ENG' AND @IsChiefEngStage=0 THEN N' dan menunggu acknowledgement Chief Engineering.</p>' ELSE N'.</p>' END,
         N'Inspection '+ISNULL(@No,'')+N' telah diproses oleh '+CASE WHEN @IsChiefEngStage=1 THEN N'Chief Engineering ' ELSE N'SPV ' END+ISNULL(@ActorName,@p_ActorEmployeeID)+CASE WHEN @WorkflowCode='SPV_CHIEF_ENG' AND @IsChiefEngStage=0 THEN N' dan menunggu acknowledgement Chief Engineering.' ELSE N'.' END,'PENDING',0,GETDATE());

       IF @WorkflowCode='SPV_CHIEF_ENG' AND @IsChiefEngStage=0
       BEGIN
        INSERT dbo.PIP_T_InspectionEmailOutbox(NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
         EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
        SELECT 'INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':CHIEF_ENG:'+X.EmployeeID,
         @EventID,'INSPECTION',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
         N'Inspection menunggu acknowledgement Chief Engineering - '+ISNULL(@No,''),
         N'<p>Inspection '+ISNULL(@No,'')+N' telah diverifikasi oleh SPV '+ISNULL(@ActorName,@p_ActorEmployeeID)+N' dan menunggu acknowledgement Chief Engineering '+X.EmployeeName+N' ('+X.EmployeeID+N').</p><p><a href="'+ISNULL(REPLACE(@p_CorrectionUrl,N'type=entry',N'type=approval'),N'')+N'">Buka halaman approval INSPEC</a></p>',
         N'Inspection '+ISNULL(@No,'')+N' menunggu acknowledgement Chief Engineering '+X.EmployeeName+N' ('+X.EmployeeID+N').',
         'PENDING',0,GETDATE()
        FROM
        (
         SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress,
          ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
         FROM dbo.SplitStringConvertToTable(@ChiefEng,';') S
         JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
         WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
        ) X;
       END;
      END;
    
   END;
 END TRY
 BEGIN CATCH
  /* The caller (BRC/EQueryP) owns the transaction; never roll it back here. */
  DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
  SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
  RAISERROR(@Err,@Sev,@State);
 END CATCH
END;
