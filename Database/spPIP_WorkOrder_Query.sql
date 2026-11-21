IF OBJECT_ID('dbo.spPIP_WorkOrder_Query', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spPIP_WorkOrder_Query AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spPIP_WorkOrder_Query
    @p_Tipe VARCHAR(3),
    @p_Data dbo.Type_N_Tbl_C13 READONLY
AS
BEGIN
    SET NOCOUNT ON;

    /*
      TVP contract: one row per call; all values are NVARCHAR.
      C1-C13 mapping is documented per operation below.
      001: C1=KeyHD, C2=EmployeeID, C3=SectionList
      002: C1=EmployeeID, C2=SessionToken, C3=CompanyLocation (CompanyID;LocationID),
           C4=SectionList, C5=CompanyID, C6=LocationID, C7=LastSync (ISO datetime),
           C8=ApprovalMode (0/1), C9=Status, C10=KeyHD (0=all),
           C11=IsTechnician (0/1), C12=IsSupervisor (0/1)
      003: C1=KeyHD
      004: C1=EmployeeID, C2=SectionList, C3=KeyHD, C4=ActionSPV,
           C5=CompanyID, C6=LocationID
      005: C1=CompanyID, C2=LocationID, C3=SectionList (WO approval dashboard counters)
    */
    DECLARE @C1 NVARCHAR(MAX), @C2 NVARCHAR(MAX), @C3 NVARCHAR(MAX),
            @C4 NVARCHAR(MAX), @C5 NVARCHAR(MAX), @C6 NVARCHAR(MAX),
            @C7 NVARCHAR(MAX), @C8 NVARCHAR(MAX), @C9 NVARCHAR(MAX),
            @C10 NVARCHAR(MAX), @C11 NVARCHAR(MAX), @C12 NVARCHAR(MAX);

    SELECT TOP 1
        @C1=C1, @C2=C2, @C3=C3, @C4=C4, @C5=C5, @C6=C6,
        @C7=C7, @C8=C8, @C9=C9, @C10=C10, @C11=C11, @C12=C12
    FROM @p_Data;

    IF @p_Tipe = '001'
    BEGIN
        SELECT TOP 1 1 AS IsAllowed
        FROM dbo.PIP_T_WO W
        JOIN dbo.SysWebUser SU ON SU.EmployeeID=@C2 AND SU.IsActive=1
        WHERE W.KeyHD=CONVERT(INT,@C1)
          AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @C2, '') AM WHERE AM.MenuID='20012')
          AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@C3,';') S WHERE S.val=W.SectionID)
          AND (
               EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                       WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                         AND C.CompanyID=W.CompanyID AND C.LocationID=W.LocationID)
               OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                          WHERE L.CompanyID=W.CompanyID AND L.LocationID=W.LocationID)
          )
          AND EXISTS (
              SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.TemplateNo=W.TemplateWOPM AND T.SectionID=W.SectionID
                AND ISNULL(T.TemplateType,'W')='W'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + W.CompanyID + W.LocationID + ';%'))
          );
        RETURN;
    END;

    IF @p_Tipe = '002'
    BEGIN
        DECLARE @V_GetDate DATETIME;
        SET @V_GetDate=GETDATE();

        UPDATE UserSession
           SET LastSyncWO=@V_GetDate
         WHERE IsActive=1 AND UserID=@C1 AND Token=@C2 AND ExpireTime>GETDATE();

        SELECT TOP 10
            a.KeyHD,a.WONo,a.WODate,a.EquipmentCode,a.LocationNo,a.[Description],a.SectionID,
            Status=CASE WHEN a.ReasonRespondDC<>'' THEN 'DRAFT' WHEN ISNULL(a.RemarkTechnician,'')<>'' THEN 'SYNCED' ELSE 'PENDING' END,
            ISNULL(a.TemplateWOPM,'') TemplateWOPM,a.ReasonRespondDC ReasonVoid,LastUpdated=@V_GetDate,
            a.CompanyID,a.LocationID,a.RemarkTechnician,a.IsCompleteDC,ISNULL(a.TemplateVersion,'') TemplateVersion,
            TemplateVersionStatus=ISNULL((
                SELECT TOP 1 vv.Status
                FROM dbo.PIP_M_CheckListWOPM_Version vv
                JOIN dbo.PIP_M_CheckListWOPM tt ON tt.IDTemplate=vv.IDTemplate
                WHERE tt.TemplateNo=a.TemplateWOPM AND tt.SectionID=a.SectionID
                  AND ISNULL(tt.TemplateType,'W')='W' AND vv.Version=a.TemplateVersion
                  AND (ISNULL(tt.CompanyScope,'S')='A' OR (';' + ISNULL(tt.CompanyLocationList,'') + ';' LIKE '%;' + a.CompanyID + a.LocationID + ';%'))
                ORDER BY CASE WHEN ISNULL(tt.CompanyScope,'S')='S' THEN 0 ELSE 1 END,tt.IDTemplate
            ),''),
            SummarySampleText=ISNULL((
                SELECT TOP 1 vv.SummarySampleText
                FROM dbo.PIP_M_CheckListWOPM_Version vv
                JOIN dbo.PIP_M_CheckListWOPM tt ON tt.IDTemplate=vv.IDTemplate
                WHERE tt.TemplateNo=a.TemplateWOPM AND ISNULL(tt.TemplateType,'W')='W'
                  AND tt.SectionID=a.SectionID
                  AND (ISNULL(tt.CompanyScope,'S')='A' OR (';' + ISNULL(tt.CompanyLocationList,'') + ';' LIKE '%;' + a.CompanyID + a.LocationID + ';%'))
                  AND vv.Version=a.TemplateVersion
                ORDER BY CASE WHEN ISNULL(tt.CompanyScope,'S')='S' THEN 0 ELSE 1 END,tt.IDTemplate
            ),''),
            FollowUp=CASE WHEN ISNULL(a.isFollowUp,0)=1 THEN 'Recommend Follow Up' ELSE 'No Follow Up' END,
            FollowUpSection=ISNULL(a.FollowUpSection,0),FollowUpRemark=ISNULL(a.FollowUpRemark,''),
            IsSampling=ISNULL(a.IsSampling,0),RemarkSupervisor=ISNULL(a.RemarkSupervisor,''),
            StatusSPV=CASE WHEN ISNULL(a.IsSampling,0)=1 AND (a.ReasonRespondDC<>'' OR a.IsCompleteDC=1) THEN 'SYNCED' ELSE '' END,
            ActionSPV=CASE WHEN ISNULL(a.IsSampling,0)=1 THEN CASE WHEN a.ReasonRespondDC<>'' THEN 'VOID' WHEN a.IsCompleteDC=1 THEN 'APPROVED' END ELSE '' END,
            StartTime=(SELECT TOP 1 NULLIF(AA.StartDate,'') FROM dbo.PIP_T_H_WO_Employee AA WHERE AA.KeyHD=a.KeyHD),
            EndTime=(SELECT TOP 1 NULLIF(AA.EndDate,'') FROM dbo.PIP_T_H_WO_Employee AA WHERE AA.KeyHD=a.KeyHD),
            ISNULL(eqp.ModelCode,'') ModelCode
        FROM dbo.PIP_T_WO a
        JOIN dbo.PIP_M_D_SchedulePM d
        JOIN dbo.PIP_M_H_SchedulePM h ON d.KeyHD=h.KeyHD
          ON h.CompanyID=a.CompanyID AND h.LocationID=a.LocationID
        JOIN dbo.PIP_M_Equipment eqp
          ON eqp.CompanyID=a.CompanyID AND eqp.LocationID=a.LocationID
         AND eqp.EquipmentCode=h.EquipmentCode AND a.WONo=d.WONo
        WHERE a.WOType='p'
          AND a.CompanyID+';'+a.LocationID=@C3
          AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@C4,';') b WHERE b.val=a.SectionID)
          AND EXISTS (
              SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.TemplateNo=a.TemplateWOPM AND T.SectionID=a.SectionID
                AND ISNULL(T.TemplateType,'W')='W'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + @C5 + @C6 + ';%'))
          )
          AND (ISNULL(@C10,'0')='0' OR a.KeyHD=CONVERT(INT,@C10))
          AND (
              (ISNULL(@C8,'0')='1' AND (
                    (ISNULL(@C9,'')='PENDING' AND a.isRespondDC=0 AND ISNULL(a.RemarkTechnician,'')<>'' AND a.CompletedDate='' AND a.ReasonRespondDC='')
                 OR (ISNULL(@C9,'')='APPROVED' AND a.isRespondDC=1 AND ISNULL(a.RemarkTechnician,'')<>'' AND a.CompletedDate<>'')
                 OR (ISNULL(@C9,'')='VOID' AND a.isRespondDC=0 AND a.ReasonRespondDC<>'' AND a.CompletedDate='')
                 OR ISNULL(@C9,'') NOT IN ('PENDING','APPROVED','VOID')
              ))
              OR
              (ISNULL(@C8,'0')<>'1' AND a.TemplateWOPM<>'' AND a.UpdateDate>=CONVERT(DATETIME,@C7,126)
                AND (
                    (ISNULL(@C11,'0')='1' AND a.isRespondDC=0 AND a.CompletedDate='')
                    OR
                    (ISNULL(@C12,'0')='1' AND ISNULL(a.RemarkTechnician,'')<>'' AND ISNULL(a.IsSampling,0)=1
                     AND ((a.ReasonRespondDC='' AND a.isRespondDC=0 AND a.CompletedDate='')
                          OR (a.ReasonRespondDC<>'' OR a.isRespondDC=1)))
                ))
          )
        ORDER BY a.KeyHD;
        RETURN;
    END;

    IF @p_Tipe = '003'
    BEGIN
        SELECT ISNULL(V.IsFollowUpRequired,1) IsFollowUpRequired
        FROM dbo.PIP_T_WO W
        JOIN dbo.PIP_M_CheckListWOPM T ON T.TemplateNo=W.TemplateWOPM AND T.SectionID=W.SectionID
        LEFT JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDTemplate=T.IDTemplate AND V.Version=W.TemplateVersion
        WHERE W.KeyHD=CONVERT(INT,@C1) AND ISNULL(T.TemplateType,'W')='W';
        RETURN;
    END;

    IF @p_Tipe = '004'
    BEGIN
        SELECT TOP 1 1 AS IsAllowed
        FROM dbo.PIP_T_WO W
        JOIN dbo.SysWebUser SU ON SU.EmployeeID=@C1 AND SU.IsActive=1
        WHERE W.KeyHD=CONVERT(INT,@C3)
          AND W.CompanyID=@C5 AND W.LocationID=@C6
          AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@C2,';') S WHERE S.val=W.SectionID)
          AND (
              EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                      WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                        AND C.CompanyID=@C5 AND C.LocationID=@C6)
              OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L
                         WHERE L.CompanyID=@C5 AND L.LocationID=@C6)
          )
          AND EXISTS (
              SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.TemplateNo=W.TemplateWOPM AND T.SectionID=W.SectionID
                AND ISNULL(T.TemplateType,'W')='W'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + W.CompanyID + W.LocationID + ';%'))
          )
          AND (
              (ISNULL(@C4,'')<>'' AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',@C1,'') AM WHERE AM.MenuID='20012') AND ISNULL(W.IsSampling,0)=1)
              OR
              (ISNULL(@C4,'')='' AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',@C1,'') AM WHERE AM.MenuID='20011'))
          );
        RETURN;
    END;

    IF @p_Tipe = '005'
    BEGIN
        SELECT
            Pending=ISNULL(SUM(CASE WHEN W.isRespondDC=0 AND ISNULL(W.RemarkTechnician,'')<>'' AND W.ReasonRespondDC='' THEN 1 ELSE 0 END),0),
            [Void]=ISNULL(SUM(CASE WHEN W.isRespondDC=0 AND W.ReasonRespondDC<>'' THEN 1 ELSE 0 END),0),
            [Approved]=ISNULL(SUM(CASE WHEN ISNULL(W.RemarkTechnician,'')<>'' AND W.isCompleteDC=1
                AND CONVERT(VARCHAR(8),W.ApprovedRespondDCDate,112)=CONVERT(VARCHAR(8),GETDATE(),112) THEN 1 ELSE 0 END),0)
        FROM dbo.PIP_T_WO W
        WHERE W.WOType='p' AND W.CompanyID=@C1 AND W.LocationID=@C2
          AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@C3,';') S WHERE S.val=W.SectionID)
          AND EXISTS (SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.TemplateNo=W.TemplateWOPM AND T.SectionID=W.SectionID
                AND ISNULL(T.TemplateType,'W')='W'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + W.CompanyID + W.LocationID + ';%')));
        RETURN;
    END;

END;
GO
