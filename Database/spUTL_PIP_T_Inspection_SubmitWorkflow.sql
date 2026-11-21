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
         @EmailEnabled BIT,@SPV VARCHAR(4000),@SPVEmail VARCHAR(4000),@TechEmail VARCHAR(320),
          @SPVName NVARCHAR(4000),@TechName NVARCHAR(200),@ActorName NVARCHAR(200),
         @ConfigScope VARCHAR(30),@OldStatus VARCHAR(30),@Action VARCHAR(20),@EventID BIGINT,@LastActionCode VARCHAR(20);
 SELECT @C=I.CompanyID,@L=I.LocationID,@S=I.SectionID,@Owner=I.OwnerEmployeeID,@No=I.InspectionNo,
        @TypeName=I.InspectionTypeName,@DetailName=I.InspectionTypeDetailName,
        @Mode=ISNULL(NULLIF(I.InspectionMode,''),'STANDARD')
 FROM dbo.PIP_T_Inspection I JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
 WHERE I.InspectionID=@p_InspectionID AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.IsApproved,0)=0
   AND ISNULL(NULLIF(I.InspectionMode,''),'STANDARD') IN ('STANDARD','BATCH')
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
 /* SPV routing is mandatory only when approval email notification is enabled.
    With notification disabled (missing config or Description='0'), sync and workflow
    submission must still succeed; the SPV can be configured later for approval access. */
 IF @EmailEnabled=1
 BEGIN
  IF ISNULL(@SPV,'')=''
  BEGIN
   DECLARE @MissingSPVKey VARCHAR(100);
   SET @MissingSPVKey=@ConfigScope+';SPV;'+@S;
   RAISERROR('SPV approver setup is missing. Required SysWebCommonValue.ID: %s',16,1,@MissingSPVKey);
   RETURN;
  END;
  IF EXISTS
  (
   SELECT 1 FROM dbo.SplitStringConvertToTable(@SPV,';') X
   WHERE NOT EXISTS
   (
    SELECT 1 FROM dbo.M_HRD_Employee E
    WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@C AND E.SectionID=@S
      AND ISNULL(E.TerminationDate,'')=''
      AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
        AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
      AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
        WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@C AND CL.LocationID=@L)
   )
  )
  BEGIN RAISERROR('One or more configured SPV approvers are not active or lack approval access for this Company, Location, and Section.',16,1); RETURN; END;
 END;
 SELECT @SPVName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val)))
 FROM dbo.SplitStringConvertToTable(@SPV,';') X
 LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val))
 ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@SPV),
 @SPVEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress))
 FROM dbo.SplitStringConvertToTable(@SPV,';') X
 JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val))
 WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
 ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');
 SELECT @TechName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@Owner),@TechEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))) FROM dbo.M_HRD_Employee WHERE EmployeeID=@Owner;
 IF @EmailEnabled=1
 BEGIN
  IF EXISTS
  (
   SELECT 1
   FROM dbo.SplitStringConvertToTable(@SPV,';') X
   WHERE NOT EXISTS
   (
    SELECT 1 FROM dbo.M_HRD_Employee E
    WHERE E.EmployeeID=LTRIM(RTRIM(X.val))
      AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
   )
  ) OR ISNULL(@TechEmail,'')=''
  BEGIN RAISERROR('SPV or Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
 END;
 SELECT @OldStatus=CASE WHEN ISNULL(IsSubmitted,0)=1 THEN CASE WHEN ISNULL(IsApproved,0)=1 THEN 'APPROVED' ELSE 'SUBMITTED' END
  WHEN Status='DRAFT' AND ISNULL(ReasonVoid,'')<>'' THEN 'VOID' ELSE '' END
 FROM dbo.PIP_T_Inspection WITH (UPDLOCK,HOLDLOCK) WHERE InspectionID=@p_InspectionID;
 IF @OldStatus='SUBMITTED' RETURN;
 IF @OldStatus='APPROVED' BEGIN RAISERROR('Inspection has already been finally approved.',16,1); RETURN; END;
 SELECT TOP 1 @LastActionCode=ActionCode
 FROM dbo.PIP_T_InspectionApprovalHistory
 WHERE EntityType='INSPECTION' AND EntityID=@p_InspectionID
 ORDER BY ApprovalEventID DESC;
 SET @Action=CASE WHEN @LastActionCode='VOIDED' THEN 'RESUBMITTED' ELSE 'SUBMITTED' END;
 BEGIN TRY
  -- Transaction lifecycle is owned by BRC.PIP_T_WO.SyncInspection().
  UPDATE dbo.PIP_T_Inspection
  SET Status='DONE',IsSubmitted=1,SubmittedBy=@p_ActorEmployeeID,SubmittedDate=GETDATE(),
      IsApproved=0,ApprovedBy='',ApprovedDate=CONVERT(DATETIME,'19000101',112),
      ApprovalRemark='',ReasonVoid='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
  WHERE InspectionID=@p_InspectionID;

  INSERT dbo.PIP_T_InspectionApprovalHistory(EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
   VALUES('INSPECTION',@p_InspectionID,@C,@L,@S,'TECHNICIAN',@Action,@p_ActorEmployeeID,GETDATE(),NULL);
  SET @EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
  IF @EmailEnabled=1
  BEGIN
   /* One outbox row per SPV approver. */
   INSERT dbo.PIP_T_InspectionEmailOutbox
   (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
    EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
   SELECT
    'INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':SPV:'+X.EmployeeID,
    @EventID,'INSPECTION',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
    N'Inspection menunggu approval SPV - '+ISNULL(@No,''),
    N'<p>Inspection '+ISNULL(@No,'')+N' ('+ISNULL(@Mode,'')+N') menunggu approval SPV.</p><p>Teknisi: '+ISNULL(@TechName,@Owner)+N' ('+ISNULL(@Owner,'')+N')</p><p>Approver: '+X.EmployeeName+N' ('+X.EmployeeID+N')</p><p>'+ISNULL(@TypeName,'')+N' / '+ISNULL(@DetailName,'')+
    N'</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'">Buka halaman approval INSPEC</a></p>',
    N'Inspection '+ISNULL(@No,'')+N' milik '+ISNULL(@TechName,@Owner)+N' ('+ISNULL(@Owner,'')+N') menunggu approval SPV '+X.EmployeeName+N' ('+X.EmployeeID+N'). '+ISNULL(@p_ApprovalUrl,N''),
    'PENDING',0,GETDATE()
   FROM
   (
    SELECT LTRIM(RTRIM(S.val)) EmployeeID,
           LTRIM(RTRIM(E.emailaddress)) EmailAddress,
           ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
    FROM dbo.SplitStringConvertToTable(@SPV,';') S
    JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
    WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
   ) X;

   INSERT dbo.PIP_T_InspectionEmailOutbox
   (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
    EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
   VALUES
   ('INSPECTION:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@EventID)+':TECHNICIAN',
    @EventID,'INSPECTION',@p_InspectionID,'TECHNICIAN',@Owner,@TechEmail,
    N'Inspection telah dikirim - '+ISNULL(@No,''),
    N'<p>Halo '+ISNULL(@TechName,@Owner)+N' ('+ISNULL(@Owner,'')+N'), inspection '+ISNULL(@No,'')+N' telah dikirim dan menunggu approval SPV '+ISNULL(@SPVName,@SPV)+N'.</p>',
    N'Inspection '+ISNULL(@No,'')+N' milik '+ISNULL(@TechName,@Owner)+N' ('+ISNULL(@Owner,'')+N') telah dikirim dan menunggu approval SPV '+ISNULL(@SPVName,@SPV)+N'.',
    'PENDING',0,GETDATE());
  END;
  END TRY
 BEGIN CATCH
  DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
  SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
  RAISERROR(@Err,@Sev,@State);
 END CATCH
END;
GO
