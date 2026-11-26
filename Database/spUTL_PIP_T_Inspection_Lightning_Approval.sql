/* LEGACY COPY — DO NOT DEPLOY. The active Lightning approval procedure is deployed from Database/LightningInspection_Approval_Workflow.sql. */

CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_Approval
    @p_InspectionID BIGINT,
    @p_ActorEmployeeID VARCHAR(50),
    @p_Action VARCHAR(10),
    @p_Remark NVARCHAR(1000),
    @p_ApprovalUrl NVARCHAR(1000),
    @p_CorrectionUrl NVARCHAR(1000),
    @p_ApprovalToken UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @p_Action=UPPER(LTRIM(RTRIM(ISNULL(@p_Action,''))));
    SET @p_Remark=LTRIM(RTRIM(ISNULL(@p_Remark,N'')));
    IF @p_Action NOT IN ('APPROVE','VOID')
    BEGIN RAISERROR('Invalid Lightning approval action.',16,1); RETURN; END;
    IF @p_Action='VOID' AND @p_Remark=''
    BEGIN RAISERROR('Void reason is required.',16,1); RETURN; END;

    DECLARE @V_CompanyID VARCHAR(10),@V_LocationID VARCHAR(3),@V_SectionID VARCHAR(10);
    DECLARE @V_OwnerEmployeeID VARCHAR(50),@V_InspectionNo VARCHAR(10),@V_Stage VARCHAR(20);
    DECLARE @V_SPVID VARCHAR(4000),@V_ChiefSecID VARCHAR(4000),@V_ChiefEngID VARCHAR(4000);
    DECLARE @V_TechnicianEmail VARCHAR(320),@V_TechnicianName VARCHAR(200),@V_ActorName VARCHAR(200),@V_ActorEmail VARCHAR(320);
    DECLARE @V_EmailEnabled BIT,@V_ConfigScope VARCHAR(30);
    DECLARE @V_NextEmployeeID VARCHAR(4000),@V_NextEmail VARCHAR(4000),@V_NextName VARCHAR(4000);
    DECLARE @V_EventID BIGINT,@V_NewStatus VARCHAR(30),@V_NextStage VARCHAR(20);

    SELECT @V_CompanyID=I.CompanyID,@V_LocationID=I.LocationID,@V_SectionID=I.SectionID,
           @V_Stage=CASE WHEN ISNULL(I.IsApproved,0)=0 THEN 'SPV' WHEN ISNULL(I.IsApproved1,0)=0 THEN 'CHIEF_SEC' ELSE 'CHIEF_ENG' END,
           @V_OwnerEmployeeID=I.OwnerEmployeeID,@V_InspectionNo=I.InspectionNo
    FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
    JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE I.InspectionID=@p_InspectionID AND ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING'
      AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved2,0)=0
      AND ISNULL(I.Status,'')='DONE';

    IF @V_CompanyID IS NULL
    BEGIN RAISERROR('Lightning inspection is not waiting for approval.',16,1); RETURN; END;

    SET @V_ConfigScope=CONVERT(VARCHAR(30),@V_CompanyID)+CONVERT(VARCHAR(30),@V_LocationID);

    SELECT @V_EmailEnabled=CASE WHEN ISNULL(C.Description,'0')='1' THEN 1 ELSE 0 END
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';EMAIL;LIGHTNING';
    SET @V_EmailEnabled=ISNULL(@V_EmailEnabled,0);

    SELECT @V_SPVID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';SPV;'+@V_SectionID;

    SELECT @V_ChiefSecID=NULLIF(LTRIM(RTRIM(C.Description)),''),
           @V_ChiefEngID=NULL
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_SEC';

    SELECT @V_ChiefEngID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_ENG';

    IF (@V_Stage='SPV' AND NOT EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
       OR (@V_Stage='CHIEF_SEC' AND NOT EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
       OR (@V_Stage='CHIEF_ENG' AND NOT EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
    BEGIN RAISERROR('You are not the configured approver for the current Lightning stage.',16,1); RETURN; END;

    /*
       ApprovalToken is an event-scoped capability, not a permanent inspection token.
       The token must belong to the current approver and to the latest workflow event
       that created the current approval email:
         SPV       -> TECHNICIAN SUBMITTED/RESUBMITTED event
         CHIEF_SEC -> SPV APPROVED event
         CHIEF_ENG -> CHIEF_SEC APPROVED event
       Therefore a token from an earlier stage cannot be replayed after the workflow
       has advanced, even when the old email is delivered later by SMTP retry.
    */
    IF @p_ApprovalToken IS NOT NULL
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.PIP_T_InspectionEmailOutbox O
           JOIN dbo.PIP_T_InspectionApprovalHistory H
             ON H.ApprovalEventID=O.ApprovalEventID
           WHERE O.ApprovalToken=@p_ApprovalToken
             AND O.EntityType='LIGHTNING'
             AND O.EntityID=@p_InspectionID
             AND O.RecipientType='APPROVER'
             AND O.RecipientEmployeeID=@p_ActorEmployeeID
             AND O.ApprovalEventID=
                 (SELECT MAX(H2.ApprovalEventID)
                  FROM dbo.PIP_T_InspectionApprovalHistory H2
                  WHERE H2.EntityType='LIGHTNING' AND H2.EntityID=@p_InspectionID)
             AND H.StageCode=
                 CASE
                     WHEN @V_Stage='SPV' THEN 'TECHNICIAN'
                     WHEN @V_Stage='CHIEF_SEC' THEN 'SPV'
                     WHEN @V_Stage='CHIEF_ENG' THEN 'CHIEF_SEC'
                 END
             AND H.ActionCode IN ('SUBMITTED','RESUBMITTED','APPROVED')
       )
    BEGIN RAISERROR('This approval email link is invalid, expired, or belongs to another approver.',16,1); RETURN; END;

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_TechnicianName=ISNULL(Name,@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    SELECT @V_ActorName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@p_ActorEmployeeID),
           @V_ActorEmail=LTRIM(RTRIM(ISNULL(emailaddress,'')))
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@p_ActorEmployeeID;
    IF @V_EmailEnabled=1 AND ISNULL(@V_TechnicianEmail,'')=''
    BEGIN RAISERROR('Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
    IF @V_EmailEnabled=1 AND @V_Stage IN ('CHIEF_SEC','CHIEF_ENG')
       AND EXISTS
       (
           SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X
           WHERE NOT EXISTS
           (
               SELECT 1 FROM dbo.M_HRD_Employee E
               WHERE E.EmployeeID=LTRIM(RTRIM(X.val))
                 AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
           )
       )
    BEGIN RAISERROR('Email address is missing for one or more configured SPV recipients.',16,1); RETURN; END;

    IF @V_EmailEnabled=1 AND @V_Stage='CHIEF_ENG'
       AND EXISTS
       (
           SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X
           WHERE NOT EXISTS
           (
               SELECT 1 FROM dbo.M_HRD_Employee E
               WHERE E.EmployeeID=LTRIM(RTRIM(X.val))
                 AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
           )
       )
    BEGIN RAISERROR('Email address is missing for one or more configured Chief Security recipients.',16,1); RETURN; END;

    IF @p_Action='APPROVE' AND @V_Stage IN ('SPV','CHIEF_SEC')
    BEGIN
        SELECT @V_NextEmployeeID=CASE WHEN @V_Stage='SPV' THEN @V_ChiefSecID ELSE @V_ChiefEngID END;
        SELECT @V_NextEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress)) FROM dbo.SplitStringConvertToTable(@V_NextEmployeeID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),''),
               @V_NextName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val))) FROM dbo.SplitStringConvertToTable(@V_NextEmployeeID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@V_NextEmployeeID);
        IF @V_EmailEnabled=1 AND ISNULL(@V_NextEmail,'')=''
        BEGIN RAISERROR('Email address is missing for the next Lightning approver stage.',16,1); RETURN; END;
        SET @V_NewStatus=CASE WHEN @V_Stage='SPV' THEN 'VERIFIED' ELSE 'ACKNOWLEDGE 1' END; SET @V_NextStage=CASE WHEN @V_Stage='SPV' THEN 'CHIEF_SEC' ELSE 'CHIEF_ENG' END;
    END
    ELSE IF @p_Action='APPROVE'
    BEGIN
        SET @V_NewStatus='ACKNOWLEDGE 2'; SET @V_NextStage='COMPLETED';
    END
    ELSE
    BEGIN
        SET @V_NewStatus='VOID'; SET @V_NextStage='TECHNICIAN';
    END;

    BEGIN TRY
        -- Transaction lifecycle is owned by WAL.BR.CF for this approval call.
        INSERT dbo.PIP_T_InspectionApprovalHistory
        (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
        VALUES ('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,
                @V_Stage,CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOIDED' END,
                @p_ActorEmployeeID,GETDATE(),NULLIF(@p_Remark,N''));
        SET @V_EventID=CONVERT(BIGINT,SCOPE_IDENTITY());

        /*
           Consume the exact email approval token that was used for this action.
           This makes the token one-time-use even before the workflow state changes.
           If the transaction rolls back, this invalidation rolls back with it.
        */
        IF @p_ApprovalToken IS NOT NULL
        BEGIN
            UPDATE dbo.PIP_T_InspectionEmailOutbox
            SET ApprovalToken=NULL
            WHERE ApprovalToken=@p_ApprovalToken
              AND EntityType='LIGHTNING'
              AND EntityID=@p_InspectionID
              AND RecipientType='APPROVER'
              AND RecipientEmployeeID=@p_ActorEmployeeID;
        END;


        IF @p_Action='VOID'
        BEGIN
            UPDATE dbo.PIP_T_Inspection
            SET Status='DRAFT',
                IsSubmitted=0,SubmittedBy='',SubmittedDate=CONVERT(DATETIME,'19000101',112),
                IsApproved=0,
                ApprovedBy=CASE WHEN @V_Stage='SPV' THEN @p_ActorEmployeeID ELSE '' END,
                ApprovedDate=CASE WHEN @V_Stage='SPV' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
                IsApproved1=0,
                Approved1By=CASE WHEN @V_Stage='CHIEF_SEC' THEN @p_ActorEmployeeID ELSE '' END,
                Approved1Date=CASE WHEN @V_Stage='CHIEF_SEC' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
                IsApproved2=0,
                Approved2By=CASE WHEN @V_Stage='CHIEF_ENG' THEN @p_ActorEmployeeID ELSE '' END,
                Approved2Date=CASE WHEN @V_Stage='CHIEF_ENG' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
                ApprovalRemark='',
                ReasonVoid=CASE WHEN @V_Stage='SPV' THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid END,
                ReasonVoid1=CASE WHEN @V_Stage='CHIEF_SEC' THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid1 END,
                ReasonVoid2=CASE WHEN @V_Stage='CHIEF_ENG' THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid2 END,
                UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
            WHERE InspectionID=@p_InspectionID;

            IF @V_EmailEnabled=1
            BEGIN
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                VALUES
                ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
                 @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
                 N'Lightning Inspection perlu diperbaiki - '+ISNULL(@V_InspectionNo,''),
                 N'<p>Halo '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N'), Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' dikembalikan oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N') untuk koreksi.</p><p>Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+
                 N'</p><p><a href="'+ISNULL(@p_CorrectionUrl,N'')+N'">Buka INSPEC untuk memperbaiki dan submit ulang</a></p>',
                 N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' dikembalikan oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N'). Alasan: '+@p_Remark+N' '+ISNULL(@p_CorrectionUrl,N''),'PENDING',0,GETDATE());
            END;

            /* Notify lower approval levels when a higher level VOIDs the inspection. */
            IF @V_EmailEnabled=1 AND @V_Stage='CHIEF_SEC'
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                SELECT 'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':VOID_NOTIFY:SPV:'+X.EmployeeID,
                       @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
                       N'Lightning Inspection di-VOID oleh Chief Security - '+ISNULL(@V_InspectionNo,''),
                       N'<p>Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah di-VOID oleh Chief Security '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N'.</p><p>Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+N'</p><p>Teknisi akan melakukan koreksi dan submit ulang.</p>',
                       N'Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' di-VOID oleh Chief Security. Alasan: '+@p_Remark,
                       'PENDING',0,GETDATE()
                FROM (SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress
                      FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S
                      JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                      WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'') X;

            IF @V_EmailEnabled=1 AND @V_Stage='CHIEF_ENG'
            BEGIN
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                SELECT 'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':VOID_NOTIFY:CHIEF_SEC:'+X.EmployeeID,
                       @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
                       N'Lightning Inspection di-VOID oleh Chief Engineering - '+ISNULL(@V_InspectionNo,''),
                       N'<p>Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah di-VOID oleh Chief Engineering '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N'.</p><p>Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+N'</p><p>Teknisi akan melakukan koreksi dan submit ulang.</p>',
                       N'Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' di-VOID oleh Chief Engineering. Alasan: '+@p_Remark,
                       'PENDING',0,GETDATE()
                FROM (SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress
                      FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') S
                      JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                      WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'') X;

                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                SELECT 'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':VOID_NOTIFY:SPV:'+X.EmployeeID,
                       @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
                       N'Lightning Inspection di-VOID oleh Chief Engineering - '+ISNULL(@V_InspectionNo,''),
                       N'<p>Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah di-VOID oleh Chief Engineering '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N'.</p><p>Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+N'</p><p>Teknisi akan melakukan koreksi dan submit ulang.</p>',
                       N'Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' di-VOID oleh Chief Engineering. Alasan: '+@p_Remark,
                       'PENDING',0,GETDATE()
                FROM (SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress
                      FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S
                      JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                      WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'') X;
            END;
        END
        ELSE
        BEGIN
            IF @V_Stage='SPV'
                UPDATE dbo.PIP_T_Inspection
                SET IsApproved=1,ApprovedBy=@p_ActorEmployeeID,ApprovedDate=GETDATE(),
                    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),
                    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
                WHERE InspectionID=@p_InspectionID;
            ELSE IF @V_Stage='CHIEF_SEC'
                UPDATE dbo.PIP_T_Inspection SET IsApproved1=1,Approved1By=@p_ActorEmployeeID,Approved1Date=GETDATE(),ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE() WHERE InspectionID=@p_InspectionID;
            ELSE
                UPDATE dbo.PIP_T_Inspection SET IsApproved2=1,Approved2By=@p_ActorEmployeeID,Approved2Date=GETDATE(),ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE() WHERE InspectionID=@p_InspectionID;

            IF @V_EmailEnabled=1
            BEGIN
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                VALUES
                ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
                 @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
                 N'Lightning Inspection approval update - '+ISNULL(@V_InspectionNo,''),
                 N'<p>Halo '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N'), Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah diproses oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N').</p><p>Status: '+@V_NewStatus+
                 N'</p><p>Stage berikutnya: '+@V_NextStage+N'</p>',
                 N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah diproses oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N'). Status: '+@V_NewStatus+N'. Stage: '+@V_NextStage,'PENDING',0,GETDATE());

                IF @V_Stage IN ('SPV','CHIEF_SEC')
                    INSERT dbo.PIP_T_InspectionEmailOutbox
                    (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,ApprovalToken,
                     EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                    SELECT
                    'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+CASE WHEN @V_Stage='SPV' THEN ':CHIEF_SEC:' ELSE ':CHIEF_ENG:' END+X.EmployeeID,
                     @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,T.ApprovalToken,
                     N'Lightning Inspection menunggu approval '+CASE WHEN @V_Stage='SPV' THEN N'Chief Security - ' ELSE N'Chief Engineering - ' END+ISNULL(@V_InspectionNo,''),
                     N'<p>'+CASE WHEN @V_Stage='SPV' THEN N'SPV ' ELSE N'Chief Security ' END+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N') telah approve. Daily Lightning Inspection menunggu review '+CASE WHEN @V_Stage='SPV' THEN N'Chief Security ' ELSE N'Chief Engineering ' END+ISNULL(X.EmployeeName,X.EmployeeID)+N' ('+ISNULL(X.EmployeeID,'')+N').</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID)+N'&approvalToken='+CONVERT(NVARCHAR(36),T.ApprovalToken)+N'">Buka halaman approval INSPEC</a></p>',
                     N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' menunggu approval '+CASE WHEN @V_Stage='SPV' THEN N'Chief Security ' ELSE N'Chief Engineering ' END+ISNULL(X.EmployeeName,X.EmployeeID)+N' ('+ISNULL(X.EmployeeID,'')+N') setelah di-approve '+CASE WHEN @V_Stage='SPV' THEN N'SPV ' ELSE N'Chief Security ' END+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N'). '+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID),'PENDING',0,GETDATE()
                    FROM
                    (
                      SELECT LTRIM(RTRIM(S.val)) EmployeeID,E.emailaddress EmailAddress,ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
                      FROM dbo.SplitStringConvertToTable(@V_NextEmployeeID,';') S
                      JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                      WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
                    ) X
                    CROSS APPLY (SELECT NEWID() ApprovalToken) T;

                /* Notify all lower approval levels after a higher-level approval. */
                IF @V_Stage='CHIEF_SEC'
                    INSERT dbo.PIP_T_InspectionEmailOutbox
                    (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                     EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                    SELECT 'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':APPROVED_NOTIFY:SPV:'+X.EmployeeID,
                           @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
                           N'Lightning Inspection telah di-approve Chief Security - '+ISNULL(@V_InspectionNo,''),
                           N'<p>Chief Security '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' telah approve Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N'.</p><p>Saat ini menunggu approval Chief Engineering.</p>',
                           N'Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah di-approve Chief Security dan menunggu Chief Engineering.',
                           'PENDING',0,GETDATE()
                    FROM (SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress
                          FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S
                          JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                          WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'') X;

                IF @V_Stage='CHIEF_ENG'
                BEGIN
                    INSERT dbo.PIP_T_InspectionEmailOutbox
                    (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                     EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                    SELECT 'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':APPROVED_NOTIFY:CHIEF_SEC:'+X.EmployeeID,
                           @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
                           N'Lightning Inspection telah selesai di-approve Chief Engineering - '+ISNULL(@V_InspectionNo,''),
                           N'<p>Chief Engineering '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' telah menyelesaikan approval Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N'.</p>',
                           N'Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah selesai di-approve Chief Engineering.',
                           'PENDING',0,GETDATE()
                    FROM (SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress
                          FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') S
                          JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                          WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'') X;

                    INSERT dbo.PIP_T_InspectionEmailOutbox
                    (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                     EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                    SELECT 'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':APPROVED_NOTIFY:SPV:'+X.EmployeeID,
                           @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
                           N'Lightning Inspection telah selesai di-approve Chief Engineering - '+ISNULL(@V_InspectionNo,''),
                           N'<p>Chief Engineering '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' telah menyelesaikan approval Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N'.</p>',
                           N'Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah selesai di-approve Chief Engineering.',
                           'PENDING',0,GETDATE()
                    FROM (SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress
                          FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S
                          JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                          WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'') X;
                END;
            END;
        END;

        SELECT @V_NewStatus WorkflowStatus,@V_NextStage CurrentStageCode,@V_EventID ApprovalEventID;
    END TRY
    BEGIN CATCH
        DECLARE @V_Error NVARCHAR(4000),@V_Severity INT,@V_State INT;
        SELECT @V_Error=ERROR_MESSAGE(),@V_Severity=ERROR_SEVERITY(),@V_State=ERROR_STATE();
        RAISERROR(@V_Error,@V_Severity,@V_State);
    END CATCH;
END;
