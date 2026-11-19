CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow
 @p_InspectionID BIGINT,@p_ActorEmployeeID VARCHAR(50),@p_Action VARCHAR(10),
 @p_Remark NVARCHAR(1000),@p_CorrectionUrl NVARCHAR(1000)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT OFF;
 SET @p_Action=UPPER(LTRIM(RTRIM(ISNULL(@p_Action,''))));
 SET @p_Remark=LTRIM(RTRIM(ISNULL(@p_Remark,N'')));
 IF @p_Action NOT IN ('APPROVE','VOID') BEGIN RAISERROR('Invalid SPV approval action.',16,1); RETURN; END;
 IF @p_Action='VOID' AND @p_Remark='' BEGIN RAISERROR('Void reason is required.',16,1); RETURN; END;
 DECLARE @C VARCHAR(10),@L VARCHAR(3),@S VARCHAR(10),@Owner VARCHAR(50),@No VARCHAR(10),@SPV VARCHAR(4000),
         @Mode VARCHAR(10),@EmailEnabled BIT,@TechName NVARCHAR(200),@ActorName NVARCHAR(200),@TechEmail VARCHAR(320),@ActorEmail VARCHAR(320),@ConfigScope VARCHAR(30),
         @EventID BIGINT;
 SELECT @C=I.CompanyID,@L=I.LocationID,@S=I.SectionID,@Owner=I.OwnerEmployeeID,@No=I.InspectionNo,
        @Mode=ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')
 FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
 JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
 WHERE I.InspectionID=@p_InspectionID AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH')
  AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved,0)=0;
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
 /* Administrator group may approve any Standard/Batch section; workflow state and company/location checks remain enforced by the caller and this procedure. */
 IF NOT EXISTS
 (
  SELECT 1
  FROM dbo.SysWebUser SU
  JOIN dbo.SysWebUserUserGroup UG ON UG.UserID=SU.UserID
  WHERE SU.EmployeeID=@p_ActorEmployeeID
    AND SU.IsActive=1
    AND UG.UserGroupID='administrator'
 )
 AND NOT EXISTS
 (
  SELECT 1 FROM dbo.SplitStringConvertToTable(@SPV,';') X
  WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID
 )
 BEGIN RAISERROR('You are not a configured SPV for this Section.',16,1); RETURN; END;
 SELECT @TechName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@Owner),@TechEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))) FROM dbo.M_HRD_Employee WHERE EmployeeID=@Owner;
 SELECT @ActorName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@p_ActorEmployeeID),
        @ActorEmail=LTRIM(RTRIM(ISNULL(emailaddress,'')))
 FROM dbo.M_HRD_Employee WHERE EmployeeID=@p_ActorEmployeeID;
 IF @EmailEnabled=1
 BEGIN
  IF ISNULL(@TechEmail,'')='' BEGIN RAISERROR('Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
  IF ISNULL(@ActorEmail,'')='' BEGIN RAISERROR('SPV email is missing from M_HRD_Employee.emailaddress; it is used as the outbox sender address.',16,1); RETURN; END;
 END;
 BEGIN TRY
  INSERT dbo.PIP_T_InspectionApprovalHistory(EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
   VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,'SPV',CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOIDED' END,
    @p_ActorEmployeeID,GETDATE(),NULLIF(@p_Remark,N''));
  SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
  IF @p_Action='VOID'
  BEGIN
   UPDATE dbo.PIP_T_Inspection SET Status='DRAFT',
    IsSubmitted=0,SubmittedBy='',SubmittedDate=CONVERT(DATETIME,'19000101',112),
    IsApproved=0,ApprovedBy='',ApprovedDate=CONVERT(DATETIME,'19000101',112),
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
 END TRY
 BEGIN CATCH
  /* The caller (BRC/EQueryP) owns the transaction; never roll it back here. */
  DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
  SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
  RAISERROR(@Err,@Sev,@State);
 END CATCH
END;
