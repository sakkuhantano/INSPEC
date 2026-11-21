IF OBJECT_ID('dbo.spPIP_Inspection_Query', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spPIP_Inspection_Query AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spPIP_Inspection_Query
    @p_Tipe VARCHAR(3),
    @p_IDTemplate INT = NULL,
    @p_IDVersion INT = NULL,
    @p_CompanyID VARCHAR(50) = NULL,
    @p_LocationID VARCHAR(50) = NULL,
    @p_UserID VARCHAR(50) = NULL,
    @p_EmployeeID VARCHAR(50) = NULL,
    @p_SectionID VARCHAR(50) = NULL,
    @p_InspectionTypeCode VARCHAR(10) = NULL,
    @IDTemplate INT = NULL,
    @IDVersion INT = NULL,
    @TemplateVersion VARCHAR(10) = NULL,
    @SectionID VARCHAR(50) = NULL,
    @CompanyID VARCHAR(50) = NULL,
    @LocationID VARCHAR(50) = NULL,
    @EmployeeID VARCHAR(50) = NULL,
    @InspectionMode VARCHAR(10) = NULL,
    @InspectionTypeDetailCode VARCHAR(20) = NULL,
    @InspectionDate DATETIME = NULL,
    @ClientInspectionID VARCHAR(36) = NULL,
    @InspectionID BIGINT = NULL,
    @SectionList VARCHAR(MAX) = NULL,
    @InspectionNo VARCHAR(20) = NULL,
    @ScheduledTime VARCHAR(5) = NULL,
    @DateFrom DATETIME = NULL,
    @DateThru DATETIME = NULL,
    @IsAdministrator BIT = NULL,
    @TypeCode VARCHAR(50) = NULL,
    @DetailCode VARCHAR(50) = NULL,
    @BatchSize INT = NULL,
    @E VARCHAR(50) = NULL,
    @C VARCHAR(50) = NULL,
    @ID BIGINT = NULL,
    @Error VARCHAR(2000) = NULL,
    @TemplateId VARCHAR(20) = NULL,
    @ScheduleTime VARCHAR(5) = NULL,
    @ApprovalTab VARCHAR(20) = NULL,
    @InspectionTypeCode VARCHAR(10) = NULL,
    @TechnicianView BIT = NULL,
    @InspectionIDs VARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    /*
      Central read/query dispatcher for INSPEC.
      001 = Template access / return SectionID
      002 = Version access / return IDTemplate
      003 = Template Versions
      004 = Version Structure (7 result sets)
    */

    IF @p_Tipe = '001'
    BEGIN
        SELECT TOP 1 SectionID
        FROM dbo.PIP_M_CheckListWOPM
        WHERE IDTemplate = @p_IDTemplate
          AND (
              ISNULL(CompanyScope, 'S') = 'A'
              OR (';' + ISNULL(CompanyLocationList, '') + ';'
                  LIKE '%;' + ISNULL(@p_CompanyID, '') + ISNULL(@p_LocationID, '') + ';%')
          );
        RETURN;
    END;

    IF @p_Tipe = '002'
    BEGIN
        SELECT TOP 1 IDTemplate
        FROM dbo.PIP_M_CheckListWOPM_Version
        WHERE IDVersion = @p_IDVersion;
        RETURN;
    END;

    IF @p_Tipe = '003'
    BEGIN
        SELECT
            a.IDVersion,
            a.Version,
            a.[Status],
            a.EffectiveDate,
            a.StatusOption,
            a.Remark,
            RuntimeVersionID = a.IDVersion,
            a.GroupEquipment,
            a.RemarkRequiredOptions,
            a.SummarySampleText,
            a.IsRemark1Required,
            a.Remark1Text,
            a.IsRemark2Required,
            a.Remark2Text,
            ISNULL(a.PhotoRequirement,'NONE') PhotoRequirement,
            ISNULL(a.IsSummaryRequired,1) IsSummaryRequired,
            ISNULL(a.IsFollowUpRequired,1) IsFollowUpRequired
        FROM dbo.PIP_M_CheckListWOPM_Version a
        WHERE a.IDTemplate = @p_IDTemplate;
        RETURN;
    END;

    IF @p_Tipe = '005'
    BEGIN
        SELECT
            aa.val SectionID,
            TotalTemplate = ISNULL((
                SELECT COUNT(*)
                FROM dbo.PIP_M_CheckListWOPM bb
                WHERE bb.SectionID = aa.val
                  AND (
                      ISNULL(bb.CompanyScope, 'S') = 'A'
                      OR (';' + ISNULL(bb.CompanyLocationList, '') + ';'
                          LIKE '%;' + ISNULL(@p_CompanyID, '') + ISNULL(@p_LocationID, '') + ';%')
                  )
            ), 0)
        FROM dbo.SplitStringConvertToTable(@p_SectionID, ';') aa
        WHERE (
            EXISTS (
                SELECT 1
                FROM dbo.SysWebUserCompanyLocation perm
                WHERE perm.AppID = 'INSPEC'
                  AND perm.UserID = @p_UserID
                  AND perm.CompanyID = @p_CompanyID
                  AND perm.LocationID = @p_LocationID
            )
            OR EXISTS (
                SELECT 1
                FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') loginCompany
                WHERE loginCompany.CompanyID = @p_CompanyID
                  AND loginCompany.LocationID = @p_LocationID
            )
        );
        RETURN;
    END;

    IF @p_Tipe = '006'
    BEGIN
        SELECT InspectionTypeCode, InspectionTypeName, SectionID, IsActive
        FROM dbo.PIP_M_InspectionType
        WHERE SectionID=@p_SectionID AND IsActive=1
        ORDER BY InspectionTypeName;
        RETURN;
    END;

    IF @p_Tipe = '007'
    BEGIN
        SELECT
            T.SectionID,
            D.InspectionTypeDetailCode,
            D.InspectionTypeDetailName
        FROM dbo.PIP_M_InspectionType T
        JOIN dbo.PIP_M_InspectionTypeDetail D
          ON D.InspectionTypeCode=T.InspectionTypeCode
         AND D.IsActive=1
        WHERE T.InspectionTypeCode=@p_InspectionTypeCode
          AND T.IsActive=1
        ORDER BY D.InspectionTypeDetailName, D.InspectionTypeDetailCode;
        RETURN;
    END;

    IF @p_Tipe = '008'
    BEGIN
        SELECT
            a.IDTemplate,
            a.TemplateNo,
            a.TemplateName,
            a.IsActive,
            a.SectionID,
            a.TemplateType,
            a.InspectionTypeCode,
            ISNULL(a.InspectionTypeDetailCode,'') InspectionTypeDetailCode,
            a.CompanyScope,
            HasActiveVersion = CAST(CASE WHEN EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Version aa
                WHERE aa.IDTemplate=a.IDTemplate AND aa.Status='Active'
            ) THEN 1 ELSE 0 END AS BIT),
            CanDeleted = CAST(CASE WHEN NOT EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Version aa
                WHERE aa.IDTemplate=a.IDTemplate AND aa.Status='Active'
            ) THEN 1 ELSE 0 END AS BIT),
            RuntimeTemplateID=a.IDTemplate
        FROM dbo.PIP_M_CheckListWOPM a
        WHERE a.SectionID=@p_SectionID
          AND (
              EXISTS (
                  SELECT 1 FROM dbo.SysWebUserCompanyLocation perm
                  WHERE perm.AppID='INSPEC' AND perm.UserID=@p_UserID
                    AND perm.CompanyID=@p_CompanyID AND perm.LocationID=@p_LocationID
              )
              OR EXISTS (
                  SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') loginCompany
                  WHERE loginCompany.CompanyID=@p_CompanyID AND loginCompany.LocationID=@p_LocationID
              )
          )
          AND (
              ISNULL(a.CompanyScope,'S')='A'
              OR (';' + ISNULL(a.CompanyLocationList,'') + ';'
                  LIKE '%;' + @p_CompanyID + @p_LocationID + ';%')
          );
        RETURN;
    END;

    IF @p_Tipe = '009'
    BEGIN
        SELECT
            L.CompanyID, L.LocationID, L.CompanyName, L.LocationName,
            IsAssigned=CAST(CASE
                WHEN T.IDTemplate IS NOT NULL
                 AND (';' + ISNULL(T.CompanyLocationList,'') + ';'
                      LIKE '%;' + L.CompanyID + L.LocationID + ';%') THEN 1
                WHEN @p_IDTemplate<=0
                 AND L.CompanyID=@p_CompanyID AND L.LocationID=@p_LocationID THEN 1
                ELSE 0 END AS BIT)
        FROM (
            SELECT swc.CompanyID, swl.LocationID, swc.CompanyName, swl.LocationName
            FROM dbo.SysWebLocation swl
            JOIN dbo.SysWebCompany swc ON swc.CompanyID=swl.CompanyID
            WHERE swc.IsActive=1 AND swl.IsActive=1
              AND (
                  EXISTS (
                      SELECT 1 FROM dbo.SysWebUserCompanyLocation perm
                      WHERE perm.CompanyID=swl.CompanyID AND perm.LocationID=swl.LocationID
                        AND perm.UserID=@p_UserID AND perm.AppID='INSPEC'
                  )
                  OR EXISTS (
                      SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') LoginCompany
                      WHERE LoginCompany.CompanyID=swl.CompanyID
                        AND LoginCompany.LocationID=swl.LocationID
                  )
              )
        ) L
        LEFT JOIN dbo.PIP_M_CheckListWOPM T ON T.IDTemplate=@p_IDTemplate
        WHERE (
            EXISTS (
                SELECT 1 FROM dbo.SysWebUserCompanyLocation CurrentPermission
                WHERE CurrentPermission.AppID='INSPEC' AND CurrentPermission.UserID=@p_UserID
                  AND CurrentPermission.CompanyID=@p_CompanyID
                  AND CurrentPermission.LocationID=@p_LocationID
            )
            OR EXISTS (
                SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') LoginCompany
                WHERE LoginCompany.CompanyID=@p_CompanyID AND LoginCompany.LocationID=@p_LocationID
            )
        )
        AND (
            @p_IDTemplate<=0
            OR EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
                WHERE T.IDTemplate=@p_IDTemplate
                  AND (ISNULL(T.CompanyScope,'S')='A'
                       OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                           LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))
            )
        )
        ORDER BY L.CompanyID, L.LocationID;
        RETURN;
    END;

    IF @p_Tipe = '010'
    BEGIN
        SELECT SectionID
        FROM dbo.PIP_M_CheckListWOPM
        WHERE IDTemplate=@p_IDTemplate;
        RETURN;
    END;

    IF @p_Tipe = '011'
    BEGIN
        SELECT
            E.EmployeeID, E.Name, E.CompanyID, E.LocationID,
            IsAssigned=CAST(CASE
                WHEN ISNULL(T.EmployeeList,'')=''
                  OR (';' + REPLACE(ISNULL(T.EmployeeList,''),':',';') + ';'
                      LIKE '%;' + E.EmployeeID + ';%')
                THEN 1 ELSE 0 END AS BIT),
            swc.BuildingName
        FROM dbo.M_HRD_Employee E
        JOIN dbo.SysWebCompany swc ON swc.CompanyID=E.CompanyID
        JOIN dbo.PIP_M_CheckListWOPM T ON T.IDTemplate=@p_IDTemplate
        WHERE E.SectionID=T.SectionID
          AND E.SectionID=@p_SectionID
          AND T.TemplateType='I'
          AND ISNULL(E.TerminationDate,'')=''
          AND (
              EXISTS (
                  SELECT 1 FROM dbo.SysWebUserCompanyLocation CurrentPermission
                  WHERE CurrentPermission.AppID='INSPEC'
                    AND CurrentPermission.UserID=(SELECT TOP 1 SU.UserID FROM dbo.SysWebUser SU WHERE SU.employeeid=E.EmployeeID)
                    AND CurrentPermission.CompanyID=@p_CompanyID
                    AND CurrentPermission.LocationID=@p_LocationID
              )
              OR EXISTS (
                  SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', E.EmployeeID, '') LoginCompany
                  WHERE LoginCompany.CompanyID=@p_CompanyID
                    AND LoginCompany.LocationID=@p_LocationID
              )
          )
          AND (
              ISNULL(T.CompanyScope,'S')='A'
              OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                  LIKE '%;' + @p_CompanyID + @p_LocationID + ';%')
          )
        ORDER BY E.CompanyID, E.LocationID, E.EmployeeID;
        RETURN;
    END;

    IF @p_Tipe = '012'
    BEGIN
        SELECT GroupEquipment, Description
        FROM dbo.PIP_M_GroupEquipment B
        WHERE B.CompanyID=@p_CompanyID
          AND B.LocationID=@p_LocationID
          AND B.SectionID=@p_SectionID;
        RETURN;
    END;

    IF @p_Tipe = '013'
    BEGIN
        SELECT
            B.SectionID,
            A.ModelCode,
            A.Remark
        FROM dbo.PIP_M_GroupEquipment_Model A
        JOIN dbo.PIP_M_GroupEquipment B ON A.ID=B.ID
        WHERE B.CompanyID=@p_CompanyID
          AND B.LocationID=@p_LocationID
          AND B.GroupEquipment=@p_InspectionTypeCode;
        RETURN;
    END;

    IF @p_Tipe = '004'
    BEGIN
        SELECT
            IDVersion,
            A.IDTemplate,
            B.TemplateNo,
            B.TemplateName,
            A.Version,
            A.Status,
            A.EffectiveDate,
            A.Remark,
            A.StatusOption StatusOptionRaw,
            A.GroupEquipment,
            A.RemarkRequiredOptions RemarkRequiredOptionsRaw,
            A.SummarySampleText,
            A.IsRemark1Required,
            A.Remark1Text,
            A.IsRemark2Required,
            A.Remark2Text,
            ISNULL(A.PhotoRequirement,'NONE') PhotoRequirement,
            ISNULL(A.IsSummaryRequired,1) IsSummaryRequired,
            ISNULL(A.IsFollowUpRequired,1) IsFollowUpRequired
        FROM dbo.PIP_M_CheckListWOPM_Version A
        JOIN dbo.PIP_M_CheckListWOPM B ON B.IDTemplate = A.IDTemplate
        WHERE IDVersion = @p_IDVersion;

        SELECT IDSection, SectionName, DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_Section
        WHERE IDVersion = @p_IDVersion
        ORDER BY DisplayOrder;

        SELECT
            A.IDItem,
            A.IDSection,
            A.IDSubSection,
            A.ItemLabel,
            A.ItemType,
            A.DisplayOrder,
            A.Unit,
            A.IsRemark1Required,
            A.IsRemark2Required,
            A.IsRemark1Mandatory,
            A.IsRemark2Mandatory,
            A.Remark1Text,
            A.Remark2Text,
            A.IsUseDefaultRemark1,
            A.IsUseDefaultRemark2,
            A.IsValueRequired,
            A.ShowUnitInRange,
            UseDefaultOption = CAST(
                CASE WHEN A.ItemType='OPTION' AND ISNULL(A.OptionList,'')='' THEN 1 ELSE 0 END
                AS BIT),
            A.OptionList OptionListRaw,
            A.RemarkRequiredOptions RemarkRequiredOptionsRaw,
            A.MinValue,
            A.MaxValue,
            A.MinTolerance,
            A.MaxTolerance,
            A.ModelCode,
            A.IsToleranceRequired
        FROM dbo.PIP_M_CheckListWOPM_Item A
        JOIN dbo.PIP_M_CheckListWOPM_Section B ON B.IDSection = A.IDSection
        WHERE B.IDVersion = @p_IDVersion
        ORDER BY A.DisplayOrder;

        SELECT
            A.IDGroup,
            A.IDItem,
            A.GroupName,
            FieldListRaw = A.FieldList,
            A.Unit,
            A.DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_ItemGroup A
        JOIN dbo.PIP_M_CheckListWOPM_Item B ON B.IDItem = A.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section C ON C.IDSection = B.IDSection
        WHERE C.IDVersion = @p_IDVersion
        ORDER BY A.DisplayOrder;

        SELECT
            SS.IDSubSection,
            SS.IDSection,
            SS.SubSectionName,
            SS.DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_SubSection SS
        JOIN dbo.PIP_M_CheckListWOPM_Section SEC ON SEC.IDSection = SS.IDSection
        WHERE SEC.IDVersion = @p_IDVersion
        ORDER BY SS.DisplayOrder;

        SELECT
            R.IDItem,
            R.RepeatMode,
            R.ColumnCount,
            R.ObjectLabel,
            R.CountMode,
            R.FixedCount,
            R.MinCount,
            R.MaxCount
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem = R.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection = I.IDSection
        WHERE S.IDVersion = @p_IDVersion;

        SELECT
            F.IDItem,
            F.IDRepeat,
            F.FieldLabel,
            F.FieldType,
            F.OptionList,
            F.Unit,
            F.MinValue,
            F.MaxValue,
            F.IsRequired,
            F.GroupName,
            F.DisplayOrder,
            F.MinInclusive,
            F.MaxInclusive
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem = F.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection = I.IDSection
        WHERE S.IDVersion = @p_IDVersion
        ORDER BY F.IDItem, F.DisplayOrder, F.IDRepeat;

        RETURN;
    END;

    IF @p_Tipe = '023'
    BEGIN
        
        SELECT TOP 1 1
        FROM dbo.SysWebUser SU
        JOIN dbo.SysWebUserUserGroup UG ON UG.UserID=SU.UserID
        WHERE SU.EmployeeID=@UserID
          AND SU.IsActive=1
          AND UG.UserGroupID='administrator'
        RETURN;
    END;

    IF @p_Tipe = '014'
    BEGIN
        
        SELECT T.IDTemplate
        FROM dbo.PIP_M_CheckListWOPM T
        WHERE T.IDTemplate=@IDTemplate
          AND T.SectionID=@SectionID
          AND T.TemplateType='I'
          
          AND (ISNULL(T.CompanyScope,'S')='A'
               OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + @CompanyID + @LocationID + ';%'))
          AND (ISNULL(T.EmployeeList,'')=''
               OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + @EmployeeID + ';%'))
          AND EXISTS (
               SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Version V
               WHERE V.IDTemplate=T.IDTemplate
                 AND V.IDVersion=@IDVersion
                 AND V.Version=@TemplateVersion
                 AND V.Status IN ('Active','Archieved')
          )
          AND T.InspectionTypeCode=@InspectionTypeCode
          AND EXISTS (
               SELECT 1 FROM dbo.PIP_M_InspectionType IT
               WHERE IT.InspectionTypeCode=@InspectionTypeCode
                 AND IT.SectionID=@SectionID
                 AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')=@InspectionMode
          )
          AND (
               ISNULL(T.InspectionTypeDetailCode,'')=''
               OR EXISTS (
                   SELECT 1
                   FROM dbo.SplitStringConvertToTable(T.InspectionTypeDetailCode, ';') AllowedDetail
                   WHERE LTRIM(RTRIM(AllowedDetail.val))=@InspectionTypeDetailCode
               )
          )
        RETURN;
    END;

    IF @p_Tipe = '015'
    BEGIN
        
        SELECT ISNULL(V.PhotoRequirement,'NONE') PhotoRequirement,
               ISNULL(V.IsSummaryRequired,1) IsSummaryRequired,
               ISNULL(V.IsFollowUpRequired,1) IsFollowUpRequired,
               ISNULL(V.IsRemark1Required,0) IsRemark1Required,
               ISNULL(V.IsRemark2Required,0) IsRemark2Required,
               ISNULL(V.StatusOption,'') StatusOption,
               ISNULL(V.RemarkRequiredOptions,'') RemarkRequiredOptions
        FROM dbo.PIP_M_CheckListWOPM_Version V
        WHERE V.IDTemplate=@IDTemplate AND V.IDVersion=@IDVersion
        RETURN;
    END;

    IF @p_Tipe = '016'
    BEGIN
        
        SELECT I.IDItem, I.ItemLabel, I.ItemType, ISNULL(I.OptionList,'') OptionList,
               ISNULL(I.IsValueRequired,0) IsValueRequired,
               ISNULL(I.IsRemark1Required,0) IsRemark1Required,
               ISNULL(I.IsRemark2Required,0) IsRemark2Required,
               ISNULL(I.IsRemark1Mandatory,0) IsRemark1Mandatory,
               ISNULL(I.IsRemark2Mandatory,0) IsRemark2Mandatory,
               ISNULL(I.IsUseDefaultRemark1,0) IsUseDefaultRemark1,
               ISNULL(I.IsUseDefaultRemark2,0) IsUseDefaultRemark2,
               ISNULL(I.IsToleranceRequired,0) IsToleranceRequired,
               I.MinValue, I.MaxValue, I.MinTolerance, I.MaxTolerance,
               ISNULL(I.RemarkRequiredOptions,'') RemarkRequiredOptions
        FROM dbo.PIP_M_CheckListWOPM_Item I
        INNER JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY S.DisplayOrder, I.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '017'
    BEGIN
        
        SELECT G.IDItem, G.GroupName, G.FieldList
        FROM dbo.PIP_M_CheckListWOPM_ItemGroup G
        INNER JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=G.IDItem
        INNER JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY G.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '018'
    BEGIN
        
        SELECT R.IDItem,R.RepeatMode,R.CountMode,R.FixedCount,R.MinCount,R.MaxCount
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=R.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        RETURN;
    END;

    IF @p_Tipe = '019'
    BEGIN
        
        SELECT F.IDItem,F.IDRepeat,F.FieldLabel,F.FieldType,F.OptionList,F.MinValue,F.MaxValue,F.MinInclusive,F.MaxInclusive,F.IsRequired
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=F.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY F.IDItem,F.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '020'
    BEGIN
        
        SELECT P.InspectionPointID, ISNULL(M.RequireAllPoints,1) AS RequireAllPoints,
               ISNULL(P.IsNormalAbnormalRequired,0) AS IsNormalAbnormalRequired, P.PointCode
        FROM dbo.PIP_M_InspectionPoint P
        INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
        LEFT JOIN dbo.PIP_M_InspectionMapGroup G ON G.MapGroupID=M.MapGroupID AND G.CompanyID=M.CompanyID AND G.LocationID=M.LocationID
        WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID
          AND M.InspectionTypeCode=@InspectionTypeCode
          AND M.InspectionTypeDetailCode=@InspectionTypeDetailCode
          AND P.IsActive=1 AND M.IsCurrentVersion=1 AND M.IsActive=1
        RETURN;
    END;

    IF @p_Tipe = '021'
    BEGIN
        
        SELECT InspectionID, InspectionNo, InspectionDate, CompanyID, LocationID,
               StartDateTime, EndDateTime, ReasonVoid, IsSubmitted
        FROM dbo.PIP_T_Inspection
        WHERE ClientInspectionID=@ClientInspectionID
        RETURN;
    END;

    IF @p_Tipe = '022'
    BEGIN
        
        SELECT FileName, FileType, PhotoType, SeqNo
        FROM dbo.PIP_T_InspectionPhoto
        WHERE InspectionID=@InspectionID
        RETURN;
    END;
    IF @p_Tipe = '024'
    BEGIN
        SELECT I.CompanyID,I.LocationID,I.InspectionDate,I.InspectionNo,I.InspectionTypeName,I.InspectionTypeDetailName,
               I.OwnerEmployeeID,I.ScheduledTime,I.Summary,ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') InspectionMode
        FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        WHERE I.InspectionID=@InspectionID
        RETURN;
    END;

    IF @p_Tipe = '025'
    BEGIN
        SELECT DISTINCT D.ScheduleTime FROM dbo.PIP_T_Inspection I
        JOIN dbo.PIP_M_InspectionTypeDetail D ON D.InspectionTypeCode=I.InspectionTypeCode
         AND D.InspectionTypeDetailCode=I.InspectionTypeDetailCode
        WHERE I.InspectionID=@InspectionID ORDER BY D.ScheduleTime
        RETURN;
    END;

    IF @p_Tipe = '026'
    BEGIN
        SELECT TP.ScheduleTime,TP.InspectionPointTransactionID,TP.Status,TP.AbnormalRemark,
               P.PointCode,P.PointName,P.MapID,P.MapX,P.MapY,P.DisplayOrder,
               M.MapCode,M.MapName,M.ImagePath,M.MapGroupID,G.GroupName,G.Sequence GroupSequence
        FROM dbo.PIP_T_InspectionPoint TP
        JOIN dbo.PIP_M_InspectionPoint P ON P.InspectionPointID=TP.InspectionPointID
        LEFT JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
        LEFT JOIN dbo.PIP_M_InspectionMapGroup G ON G.MapGroupID=M.MapGroupID
        WHERE TP.InspectionID=@InspectionID
        ORDER BY TP.ScheduleTime,ISNULL(G.Sequence,0),M.MapGroupID,M.MapID,P.DisplayOrder,P.PointCode
        RETURN;
    END;

    IF @p_Tipe = '027'
    BEGIN
        SELECT R.InspectionResultID,R.InspectionPointTransactionID,R.ItemLabel,R.Value,R.Remark1,R.Remark2,R.IsAnomali,R.DisplayOrder
        FROM dbo.PIP_T_InspectionResult R
        WHERE R.InspectionID=@InspectionID
        ORDER BY R.InspectionPointTransactionID,R.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '028'
    BEGIN
        SELECT R.InspectionResultID,R.InspectionPointTransactionID,R.ItemLabel,
               V.ObjectIndex,V.FieldName,ISNULL(F.FieldLabel,V.FieldName) FieldLabel,V.Value FieldValue
        FROM dbo.PIP_T_InspectionResult R
        JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
        LEFT JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F
          ON F.IDItem=R.IDItem
         AND F.IDRepeat=CASE WHEN V.FieldName<>'' AND LEN(V.FieldName)<=10 AND V.FieldName NOT LIKE '%[^0-9]%'
                             THEN CAST(V.FieldName AS INT) ELSE 0 END
        WHERE R.InspectionID=@InspectionID
        ORDER BY R.InspectionResultID,V.ObjectIndex,V.FieldName
        RETURN;
    END;

    IF @p_Tipe = '029'
    BEGIN
        SELECT InspectionPointTransactionID,PhotoType,FileName,FileType,SeqNo
        FROM dbo.PIP_T_InspectionPhoto
        WHERE InspectionID=@InspectionID
        ORDER BY InspectionPointTransactionID,PhotoType,SeqNo
        RETURN;
    END;
    IF @p_Tipe = '030'
    BEGIN
        SELECT @SectionList Section, CASE WHEN EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021') THEN 1 ELSE 0 END IsWO
        FROM dbo.SysWebUser SU
        
        WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
          AND (
              EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                      WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                        AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
              OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                         WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID)
          )
        RETURN;
    END;

    IF @p_Tipe = '031'
    BEGIN
        SELECT TOP 1 InspectionNo, OwnerEmployeeID, Status
        FROM dbo.PIP_T_Inspection
        WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID
          AND InspectionTypeCode=@InspectionTypeCode
          AND InspectionTypeDetailCode=@InspectionTypeDetailCode
          AND ISNULL(ScheduledTime,'')=ISNULL(@ScheduledTime,'')
          AND IDTemplate=@IDTemplate
          AND InspectionDate >= CONVERT(DATETIME, CONVERT(VARCHAR(10), @InspectionDate, 120), 120)
          AND InspectionDate < DATEADD(DAY, 1, CONVERT(DATETIME, CONVERT(VARCHAR(10), @InspectionDate, 120), 120))
        ORDER BY InspectionID DESC
        RETURN;
    END;

    IF @p_Tipe = '032'
    BEGIN
        SELECT @SectionList Section, CASE WHEN EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021') THEN 1 ELSE 0 END IsWO
        FROM dbo.SysWebUser SU
        
        WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
          AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                       WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                         AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
               OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                          WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID))
        RETURN;
    END;

    IF @p_Tipe = '033'
    BEGIN
        SELECT @SectionList Section, CASE WHEN EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021') THEN 1 ELSE 0 END IsWO
        FROM dbo.SysWebUser SU
        
        WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
          AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                       WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                         AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
               OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                          WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID))
        RETURN;
    END;

    IF @p_Tipe = '034'
    BEGIN
        SET XACT_ABORT ON;
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM dbo.PIP_T_Inspection_Delete WITH (UPDLOCK, HOLDLOCK) WHERE ClientInspectionID=@ClientInspectionID)
        BEGIN
            DECLARE @NextDeleteArchiveID BIGINT;
            SELECT @NextDeleteArchiveID=ISNULL(MAX(DeleteArchiveID),0)+1 FROM dbo.PIP_T_Inspection_Delete WITH (UPDLOCK, HOLDLOCK);
            INSERT dbo.PIP_T_Inspection_Delete
            (DeleteArchiveID, ClientInspectionID, CompanyID, LocationID, SectionID,
             InspectionTypeCode, InspectionTypeDetailCode, IDTemplate, InspectionDate,
             OriginalStatus, OriginalSyncStatus, ReasonCancel, DeletedBy, OriginalTransactionJson)
            VALUES
            (@NextDeleteArchiveID, @ClientInspectionID, @CompanyID, @LocationID, @SectionID,
             @InspectionTypeCode, @InspectionTypeDetailCode, @IDTemplate, @InspectionDate,
             @OriginalStatus, @OriginalSyncStatus, @ReasonCancel, @DeletedBy, @OriginalTransactionJson);
        END;
        COMMIT TRANSACTION;
        RETURN;
    END;

    IF @p_Tipe = '035'
    BEGIN
        SET XACT_ABORT ON;
        BEGIN TRANSACTION;
        IF EXISTS
        (
            SELECT 1 FROM dbo.PIP_T_Inspection WITH (UPDLOCK, HOLDLOCK)
            WHERE InspectionID=@InspectionID AND ClientInspectionID=@ClientInspectionID
              AND CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID
              AND OwnerEmployeeID=@EmployeeID AND ISNULL(IsActive,1)=0
        )
        BEGIN
            UPDATE dbo.PIP_T_Inspection SET ReasonCancel=CASE WHEN ISNULL(ReasonCancel,'')='' THEN @ReasonCancel ELSE ReasonCancel END
            WHERE InspectionID=@InspectionID AND ClientInspectionID=@ClientInspectionID
              AND CompanyID=@CompanyID AND LocationID=@LocationID AND OwnerEmployeeID=@EmployeeID;
        END
        ELSE
        BEGIN
            UPDATE dbo.PIP_T_Inspection
            SET IsActive=0, ReasonCancel=@ReasonCancel, UpdateUser=@EmployeeID, UpdateDate=GETDATE(), SyncDate=GETDATE()
            WHERE InspectionID=@InspectionID AND ClientInspectionID=@ClientInspectionID
              AND CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID
              AND OwnerEmployeeID=@EmployeeID AND ISNULL(IsActive,1)=1
              AND Status='DRAFT' AND ISNULL(IsSubmitted,0)=0
              AND ISNULL(ReasonVoid,'')<>'';
            IF @@ROWCOUNT=0
            BEGIN
                ROLLBACK TRANSACTION;
                RAISERROR('The server inspection is not eligible for technician deletion.',16,1);
                RETURN;
            END;
        END;
        COMMIT TRANSACTION;
        RETURN;
    END;

    IF @p_Tipe = '036'
    BEGIN
        SELECT COUNT(1) AS SavedCount FROM dbo.PIP_T_Inspection
        WHERE InspectionID=@InspectionID AND ClientInspectionID=@ClientInspectionID
          AND CompanyID=@CompanyID AND LocationID=@LocationID AND OwnerEmployeeID=@EmployeeID AND IsActive=0
        RETURN;
    END;

    IF @p_Tipe = '037'
    BEGIN
        SELECT IT.InspectionTypeCode, IT.InspectionTypeName, IT.SectionID
        FROM dbo.PIP_M_InspectionType IT
        WHERE IT.InspectionTypeCode=@TypeCode AND IT.IsActive=1
          AND ISNULL(IT.InspectionMode,'STANDARD') IN ('BATCH','LIGHTNING')
          AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=IT.SectionID)
        RETURN;
    END;

    IF @p_Tipe = '038'
    BEGIN
        SELECT InspectionTypeDetailCode, InspectionTypeDetailName, ScheduleTime
        FROM dbo.PIP_M_InspectionTypeDetail
        WHERE InspectionTypeCode=@TypeCode AND InspectionTypeDetailCode=@DetailCode
          AND CompanyID=@CompanyID AND LocationID=@LocationID AND IsActive=1
        RETURN;
    END;

    IF @p_Tipe = '039'
    BEGIN
        SELECT P.InspectionPointID, P.PointCode, P.PointName, P.PointObjectType,
               P.PointDescription, P.ObjectReferenceType, P.ObjectReferenceID,
               P.ObjectReferenceCode, M.MapID AS MapID, P.MapX, P.MapY,
               ISNULL(P.ShapeType,'CIRCLE') AS ShapeType,P.SvgPathData,P.ShapeAttributes,P.StrokeWidth,P.DisplayOrder,
               M.MapCode, M.MapName, M.Description, M.ImagePath AS MapUrl, M.MapVersion,
               M.MapGroupID, ISNULL(G.GroupCode,'') AS GroupCode, ISNULL(G.GroupName,'') AS GroupName,
               ISNULL(G.Description,'') AS GroupDescription,
               ISNULL(M.RequireAllPoints,1) AS RequireAllPoints,
               ISNULL(P.IsNormalAbnormalRequired,0) AS IsNormalAbnormalRequired
        FROM dbo.PIP_M_InspectionMap M
        LEFT JOIN dbo.PIP_M_InspectionPoint P ON P.MapID=M.MapID AND P.IsActive=1
        LEFT JOIN dbo.PIP_M_InspectionMapGroup G ON G.MapGroupID=M.MapGroupID AND G.CompanyID=M.CompanyID AND G.LocationID=M.LocationID
        WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID
          AND M.InspectionTypeCode=@TypeCode
          AND M.InspectionTypeDetailCode=@DetailCode
          AND M.IsCurrentVersion=1 AND M.IsActive=1
        ORDER BY ISNULL(M.MapCode,''), P.DisplayOrder, P.PointCode
        RETURN;
    END;

    IF @p_Tipe = '040'
    BEGIN
        SELECT @SectionList Section, CASE WHEN EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021') THEN 1 ELSE 0 END IsWO,
               ISNULL(E.Name, SU.EmployeeID) TechnicianName
        FROM dbo.SysWebUser SU
        
        LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=SU.EmployeeID
        WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
          AND (
              EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                      WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                        AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
              OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                         WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID)
          )
        RETURN;
    END;

    IF @p_Tipe = '041'
    BEGIN
        SELECT P.PhotoType, P.FileName, P.FileType, P.SeqNo, TP.ClientPointID,
               I.InspectionID, I.InspectionNo, I.CompanyID, I.LocationID, I.InspectionDate
        FROM dbo.PIP_T_InspectionPhoto P
        JOIN dbo.PIP_T_Inspection I ON I.InspectionID=P.InspectionID
        LEFT JOIN dbo.PIP_T_InspectionPoint TP ON TP.InspectionPointTransactionID=P.InspectionPointTransactionID
        WHERE I.ClientInspectionID=@ClientInspectionID
          AND I.OwnerEmployeeID=@EmployeeID AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
          AND I.Status='DRAFT' AND I.IsApproved=0
          AND EXISTS (
              SELECT 1 FROM dbo.SysWebUser SU
        
        WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1 AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021')
                AND EXISTS (
              SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S
              WHERE S.val=I.SectionID
          )
                AND (
                    EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                            WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                              AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
                    OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                               WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
                )
          )
        ORDER BY P.SeqNo
        RETURN;
    END;

    IF @p_Tipe = '042'
    BEGIN
        SELECT R.IDItem, R.ItemLabel, R.ItemType, R.Value, R.Remark1, R.Remark2, R.IsAnomali,
               V.ObjectIndex, V.FieldName, V.Value AS FieldValue, R.DisplayOrder
        FROM dbo.PIP_T_InspectionResult R
        JOIN dbo.PIP_T_Inspection I ON I.InspectionID=R.InspectionID
        LEFT JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
        WHERE I.InspectionID=@InspectionID AND R.InspectionPointTransactionID IS NULL
        ORDER BY R.DisplayOrder, V.FieldName
        RETURN;
    END;

    IF @p_Tipe = '043'
    BEGIN
        SELECT TP.InspectionPointTransactionID, TP.ClientPointID, TP.InspectionPointID,
               TP.ScheduleTime, TP.InspectionDateTime, TP.Status, TP.AbnormalRemark, P.IsNormalAbnormalRequired,
               P.PointCode, P.PointName, P.PointObjectType,
               P.PointDescription, P.MapID, P.MapX, P.MapY,
               P.ShapeType,P.SvgPathData,P.ShapeAttributes,P.StrokeWidth,
               M.MapCode,M.MapName,M.ImagePath AS MapUrl,M.MapVersion,M.MapGroupID,
               MG.GroupCode,MG.GroupName,MG.Sequence MapGroupSequence
        FROM dbo.PIP_T_InspectionPoint TP
        JOIN dbo.PIP_M_InspectionPoint P ON P.InspectionPointID=TP.InspectionPointID
        LEFT JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
        LEFT JOIN dbo.PIP_M_InspectionMapGroup MG ON MG.MapGroupID=M.MapGroupID
        WHERE TP.InspectionID=@InspectionID
        ORDER BY P.DisplayOrder,P.PointCode
        RETURN;
    END;

    IF @p_Tipe = '044'
    BEGIN
        SELECT R.InspectionPointTransactionID,R.IDItem,R.ItemLabel,R.ItemType,R.Value,
               R.Remark1,R.Remark2,R.IsAnomali,R.DisplayOrder,V.ObjectIndex,V.FieldName,V.Value AS FieldValue
        FROM dbo.PIP_T_InspectionResult R
        LEFT JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
        WHERE R.InspectionID=@InspectionID
        ORDER BY R.InspectionPointTransactionID,R.DisplayOrder,V.FieldName
        RETURN;
    END;

    IF @p_Tipe = '045'
    BEGIN
        SELECT DISTINCT D.ScheduleTime,'SUBMITTED' ScheduleStatus,I.SubmittedDate
        FROM dbo.PIP_T_Inspection I
        JOIN dbo.PIP_M_InspectionTypeDetail D
          ON D.InspectionTypeCode=I.InspectionTypeCode
         AND D.InspectionTypeDetailCode=I.InspectionTypeDetailCode
        WHERE I.InspectionID=@InspectionID
        ORDER BY D.ScheduleTime
        RETURN;
    END;

    IF @p_Tipe = '046'
    BEGIN
        SELECT T.IDTemplate, T.TemplateNo, T.TemplateName, T.SectionID, T.InspectionTypeCode,
           V.IDVersion, V.Version, V.StatusOption, ISNULL(V.PhotoRequirement,'NONE') PhotoRequirement, ISNULL(V.SummarySampleText,'') SummarySampleText, ISNULL(V.IsSummaryRequired,1) VersionIsSummaryRequired, ISNULL(V.IsFollowUpRequired,1) VersionIsFollowUpRequired, V.IsRemark1Required VersionIsRemark1Required, V.Remark1Text VersionRemark1Text, V.IsRemark2Required VersionIsRemark2Required, V.Remark2Text VersionRemark2Text, V.RemarkRequiredOptions VersionRemarkRequiredOptions
        FROM dbo.PIP_M_CheckListWOPM T
        JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDTemplate=T.IDTemplate
        WHERE T.IDTemplate=@IDTemplate AND V.IDVersion=@IDVersion AND ISNULL(T.TemplateType,'W')='I'
        RETURN;
    END;

    IF @p_Tipe = '047'
    BEGIN
        SELECT S.IDSection, S.SectionName, S.DisplayOrder AS SectionOrder,
           I.IDItem, I.IDSubSection, ISNULL(SS.SubSectionName,'') AS SubSectionName,
           ISNULL(SS.DisplayOrder,0) AS SubSectionOrder,
           I.ItemLabel, I.ItemType, ISNULL(I.OptionList,'') OptionList,
           I.MinValue, I.MaxValue, ISNULL(I.Unit,'') Unit, ISNULL(I.ShowUnitInRange,0) ShowUnitInRange, I.IsValueRequired,
           I.IsRemark1Required, I.IsRemark2Required, I.IsRemark1Mandatory, I.IsRemark2Mandatory, I.Remark1Text, I.Remark2Text, I.IsUseDefaultRemark1, I.IsUseDefaultRemark2, ISNULL(I.RemarkRequiredOptions,'') RemarkRequiredOptions, I.DisplayOrder AS ItemOrder, V.StatusOption,
           I.ModelCode, I.MinTolerance, I.MaxTolerance, I.IsToleranceRequired
        FROM dbo.PIP_M_CheckListWOPM_Section S
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDSection=S.IDSection
        LEFT JOIN dbo.PIP_M_CheckListWOPM_SubSection SS ON SS.IDSubSection=I.IDSubSection
        JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
        WHERE V.IDVersion=@IDVersion
        ORDER BY S.DisplayOrder,
             CASE WHEN ISNULL(I.IDSubSection,0)=0 THEN I.DisplayOrder ELSE SS.DisplayOrder END,
             I.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '048'
    BEGIN
        SELECT G.IDItem, G.GroupName, G.FieldList, G.Unit, G.DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_ItemGroup G
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=G.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY G.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '049'
    BEGIN
        SELECT R.IDItem,R.RepeatMode,R.ColumnCount,R.ObjectLabel,R.CountMode,R.FixedCount,R.MinCount,R.MaxCount
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=R.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        RETURN;
    END;

    IF @p_Tipe = '050'
    BEGIN
        SELECT F.IDItem,F.IDRepeat,F.FieldLabel,F.FieldType,F.OptionList,F.Unit,F.MinValue,F.MaxValue,
               F.MinInclusive,F.MaxInclusive,F.IsRequired,F.GroupName,F.DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=F.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY F.IDItem,F.DisplayOrder,F.IDRepeat
        RETURN;
    END;

    IF @p_Tipe = '051'
    BEGIN
        SELECT P.PhotoType, P.FileName, P.FileType, P.SeqNo, P.InspectionPointTransactionID
        FROM dbo.PIP_T_InspectionPhoto P
        WHERE P.InspectionID=@InspectionID
        ORDER BY P.SeqNo
        RETURN;
    END;

    IF @p_Tipe = '052'
    BEGIN
        SELECT I.InspectionID, I.ClientInspectionID, I.InspectionNo, I.CompanyID, I.LocationID, I.SectionID,
               I.InspectionTypeCode, I.InspectionTypeName, I.InspectionTypeDetailCode,
               I.InspectionTypeDetailName, I.ScheduledTime, I.IDTemplate, I.IDVersion,
               I.TemplateNo, I.TemplateName, I.TemplateVersion,
               CONVERT(VARCHAR(10),I.InspectionDate,120) InspectionDate,
               CONVERT(VARCHAR(23),I.StartDateTime,126) StartDateTime,
               CONVERT(VARCHAR(23),I.EndDateTime,126) EndDateTime,
               I.Status, I.Summary, I.OwnerEmployeeID,
               I.FollowUp,I.FollowUpSection,I.FollowUpRemark,I.FollowUpWONo,
               I.ReasonVoid, I.UpdateDate,
               ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') AS InspectionMode
        FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        WHERE I.OwnerEmployeeID=@EmployeeID AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
          AND ISNULL(I.IsActive,1)=1
          AND I.Status='DRAFT' AND I.IsApproved=0
          AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.ReasonVoid,'')<>''
          AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU
        
        WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1 AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021')
                      AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
                      AND (
                          EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                                  WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                                    AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
                          OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                                     WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
                      ))
        ORDER BY I.UpdateDate DESC
        RETURN;
    END;

    IF @p_Tipe = '053'
    BEGIN
        SELECT R.IDItem, R.ItemLabel, R.ItemType, R.Value, R.Remark1, R.Remark2, R.IsAnomali, R.DisplayOrder,
               V.ObjectIndex,V.FieldName, V.Value AS FieldValue
        FROM dbo.PIP_T_InspectionResult R
        LEFT JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
        WHERE R.InspectionID=@InspectionID
        ORDER BY R.DisplayOrder, V.FieldName
        RETURN;
    END;

    IF @p_Tipe = '054'
    BEGIN
        SELECT TP.InspectionPointTransactionID,TP.ClientPointID,TP.InspectionPointID,
               TP.ScheduleTime,TP.InspectionDateTime,TP.Status,TP.AbnormalRemark,P.IsNormalAbnormalRequired,
               P.PointCode,P.PointName,P.PointObjectType,
               P.PointDescription,P.MapID,P.MapX,P.MapY,
               P.ShapeType,P.SvgPathData,P.ShapeAttributes,P.StrokeWidth
        FROM dbo.PIP_T_InspectionPoint TP
        JOIN dbo.PIP_M_InspectionPoint P ON P.InspectionPointID=TP.InspectionPointID
        WHERE TP.InspectionID=@InspectionID
        ORDER BY P.DisplayOrder,P.PointCode
        RETURN;
    END;

    IF @p_Tipe = '055'
    BEGIN
        SELECT R.InspectionPointTransactionID,R.IDItem,R.ItemLabel,R.ItemType,R.Value,
               R.Remark1,R.Remark2,R.IsAnomali,R.DisplayOrder,V.ObjectIndex,V.FieldName,V.Value AS FieldValue
        FROM dbo.PIP_T_InspectionResult R
        LEFT JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
        WHERE R.InspectionID=@InspectionID AND R.InspectionPointTransactionID IS NOT NULL
        ORDER BY R.InspectionPointTransactionID,R.DisplayOrder,V.FieldName
        RETURN;
    END;

    IF @p_Tipe = '056'
    BEGIN
        SELECT DISTINCT D.ScheduleTime,'SUBMITTED' ScheduleStatus,I.SubmittedDate
        FROM dbo.PIP_T_Inspection I
        JOIN dbo.PIP_M_InspectionTypeDetail D
          ON D.InspectionTypeCode=I.InspectionTypeCode
         AND D.InspectionTypeDetailCode=I.InspectionTypeDetailCode
        WHERE I.InspectionID=@InspectionID
        ORDER BY D.ScheduleTime
        RETURN;
    END;

    IF @p_Tipe = '057'
    BEGIN
        SELECT T.IDTemplate, T.TemplateNo, T.TemplateName, T.SectionID, T.InspectionTypeCode,
               V.IDVersion, V.Version, V.StatusOption, ISNULL(V.PhotoRequirement,'NONE') PhotoRequirement, ISNULL(V.SummarySampleText,'') SummarySampleText, ISNULL(V.IsSummaryRequired,1) VersionIsSummaryRequired, ISNULL(V.IsFollowUpRequired,1) VersionIsFollowUpRequired, V.IsRemark1Required VersionIsRemark1Required, V.Remark1Text VersionRemark1Text, V.IsRemark2Required VersionIsRemark2Required, V.Remark2Text VersionRemark2Text, V.RemarkRequiredOptions VersionRemarkRequiredOptions
        FROM dbo.PIP_M_CheckListWOPM T
        JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDTemplate=T.IDTemplate
        WHERE T.IDTemplate=@IDTemplate AND V.IDVersion=@IDVersion AND ISNULL(T.TemplateType,'W')='I'
        RETURN;
    END;

    IF @p_Tipe = '058'
    BEGIN
        SELECT S.IDSection, S.SectionName, S.DisplayOrder AS SectionOrder,
               I.IDItem, I.IDSubSection, ISNULL(SS.SubSectionName,'') AS SubSectionName,
               ISNULL(SS.DisplayOrder,0) AS SubSectionOrder,
               I.ItemLabel, I.ItemType, ISNULL(I.OptionList,'') OptionList,
               I.MinValue, I.MaxValue, ISNULL(I.Unit,'') Unit, ISNULL(I.ShowUnitInRange,0) ShowUnitInRange, I.IsValueRequired,
               I.IsRemark1Required, I.IsRemark2Required, I.IsRemark1Mandatory, I.IsRemark2Mandatory, I.Remark1Text, I.Remark2Text, I.IsUseDefaultRemark1, I.IsUseDefaultRemark2, ISNULL(I.RemarkRequiredOptions,'') RemarkRequiredOptions, I.DisplayOrder AS ItemOrder, V.StatusOption,
               I.ModelCode, I.MinTolerance, I.MaxTolerance, I.IsToleranceRequired
        FROM dbo.PIP_M_CheckListWOPM_Section S
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDSection=S.IDSection
        LEFT JOIN dbo.PIP_M_CheckListWOPM_SubSection SS ON SS.IDSubSection=I.IDSubSection
        JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
        WHERE V.IDVersion=@IDVersion
        ORDER BY S.DisplayOrder,
                 CASE WHEN ISNULL(I.IDSubSection,0)=0 THEN I.DisplayOrder ELSE SS.DisplayOrder END,
                 I.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '059'
    BEGIN
        SELECT G.IDItem, G.GroupName, G.FieldList, G.Unit, G.DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_ItemGroup G
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=G.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY G.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '060'
    BEGIN
        SELECT R.IDItem,R.RepeatMode,R.ColumnCount,R.ObjectLabel,R.CountMode,R.FixedCount,R.MinCount,R.MaxCount
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=R.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        RETURN;
    END;

    IF @p_Tipe = '061'
    BEGIN
        SELECT F.IDItem,F.IDRepeat,F.FieldLabel,F.FieldType,F.OptionList,F.Unit,F.MinValue,F.MaxValue,
               F.MinInclusive,F.MaxInclusive,F.IsRequired,F.GroupName,F.DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=F.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY F.IDItem,F.DisplayOrder,F.IDRepeat
        RETURN;
    END;

    IF @p_Tipe = '062'
    BEGIN
        SELECT TOP 1 ISNULL(LTRIM(RTRIM(emailaddress)),'') AS EmailAddress, ISNULL(LTRIM(RTRIM(Name)),'') AS EmployeeName
        FROM dbo.M_HRD_Employee
        WHERE EmployeeID=@E AND CompanyID=@C AND ISNULL(TerminationDate,'')=''
          AND ISNULL(LTRIM(RTRIM(emailaddress)),'')<>''
        RETURN;
    END;

    IF @p_Tipe = '063'
    BEGIN
        ;WITH EmailQueue AS
        (
            SELECT TOP (@BatchSize) *
            FROM dbo.PIP_T_InspectionEmailOutbox O WITH (UPDLOCK,READPAST,ROWLOCK)
            WHERE O.DeliveryStatus IN ('PENDING','FAILED')
              AND O.NextAttemptDate<=GETDATE()
              AND O.AttemptCount<5
              /* Fail closed: never dispatch queued mail unless the matching
                 inspection email switch is explicitly enabled for its scope. */
              AND EXISTS
              (
                  SELECT 1
                  FROM dbo.PIP_T_Inspection I
                  JOIN dbo.SysWebCommonValue C
                    ON C.AppID='INSPEC'
                   AND C.CommonGroup='EmailApproval'
                   AND C.IsDelete=0
                   AND C.Description='1'
                   AND
                   (
                       (O.EntityType='LIGHTNING'
                        AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';EMAIL;LIGHTNING')
                       OR
                       (O.EntityType='INSPECTION'
                        AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';EMAIL;'+ISNULL(NULLIF(I.InspectionMode,''),'STANDARD'))
                   )
                  WHERE I.InspectionID=O.EntityID
              )
            ORDER BY EmailOutboxID
        )
        UPDATE EmailQueue
        SET DeliveryStatus='SENDING',AttemptCount=AttemptCount+1,LastAttemptDate=GETDATE()
        OUTPUT inserted.EmailOutboxID,inserted.EntityType,inserted.EntityID,
               inserted.RecipientEmail,inserted.EmailSubject,inserted.HtmlBody,inserted.PlainBody,inserted.AttemptCount;
        RETURN;
    END;

    IF @p_Tipe = '064'
    BEGIN
        UPDATE dbo.PIP_T_InspectionEmailOutbox
        SET DeliveryStatus='SENT',SentDate=GETDATE(),LastError=NULL
        WHERE EmailOutboxID=@ID AND DeliveryStatus='SENDING'
        RETURN;
    END;

    IF @p_Tipe = '065'
    BEGIN
        UPDATE dbo.PIP_T_InspectionEmailOutbox
        SET DeliveryStatus='FAILED',LastError=@Error,
            NextAttemptDate=DATEADD(MINUTE,
                CASE WHEN AttemptCount=1 THEN 5 WHEN AttemptCount=2 THEN 10
                     WHEN AttemptCount=3 THEN 20 WHEN AttemptCount=4 THEN 40 ELSE 60 END,GETDATE())
        WHERE EmailOutboxID=@ID AND DeliveryStatus='SENDING'
        RETURN;
    END;

    IF @p_Tipe = '066'
    BEGIN
        SELECT 1
        FROM dbo.PIP_M_CheckListWOPM T
        WHERE T.IDTemplate=@IDTemplate
          AND T.SectionID=@SectionID
          AND ISNULL(T.TemplateType,'W')='I'
          AND (ISNULL(T.CompanyScope,'S')='A'
               OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + @CompanyID + @LocationID + ';%'))
          AND (ISNULL(T.EmployeeList,'')=''
               OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + @EmployeeID + ';%'))
        RETURN;
    END;

    IF @p_Tipe = '067'
    BEGIN
        SELECT I.InspectionID, I.ClientInspectionID, I.InspectionNo,
               I.CompanyID, I.LocationID, I.SectionID, I.InspectionTypeCode,
               I.InspectionTypeName, I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
               I.ScheduledTime, I.IDTemplate, I.IDVersion, I.TemplateNo, I.TemplateName,
               I.TemplateVersion, I.InspectionDate, I.StartDateTime, I.EndDateTime,
               I.OwnerEmployeeID, ISNULL(E.Name, I.OwnerEmployeeID) TechnicianName,
               I.Status, I.IsApproved, I.ReasonVoid
        FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
        WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID
          AND ISNULL(I.IsActive,1)=1
          AND I.InspectionDate >= CONVERT(DATETIME, CONVERT(VARCHAR(10), GETDATE(), 120), 120)
          AND I.InspectionDate < DATEADD(DAY, 1, CONVERT(DATETIME, CONVERT(VARCHAR(10), GETDATE(), 120), 120))
          AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
          AND EXISTS (
              SELECT 1
              FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.IDTemplate=I.IDTemplate
                AND T.SectionID=I.SectionID
                AND ISNULL(T.TemplateType,'W')='I'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
                AND (ISNULL(T.EmployeeList,'')=''
                     OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
          )
        ORDER BY I.InspectionDate, I.ScheduledTime, I.InspectionID
        RETURN;
    END;

    IF @p_Tipe = '068'
    BEGIN
        SELECT 1
        FROM dbo.PIP_M_CheckListWOPM T
        WHERE T.IDTemplate=@IDTemplate
          AND T.SectionID=@SectionID
          AND ISNULL(T.TemplateType,'W')='I'
          AND (ISNULL(T.CompanyScope,'S')='A'
               OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + @CompanyID + @LocationID + ';%'))
          AND (ISNULL(T.EmployeeList,'')=''
               OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + @EmployeeID + ';%'))
        RETURN;
    END;

    IF @p_Tipe = '069'
    BEGIN
        SELECT I.InspectionID, I.ClientInspectionID, I.InspectionNo,
               I.CompanyID, I.LocationID, I.SectionID, I.InspectionTypeCode,
               I.InspectionTypeName, I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
               I.ScheduledTime, I.IDTemplate, I.IDVersion, I.TemplateNo, I.TemplateName,
               I.TemplateVersion, I.InspectionDate, I.StartDateTime, I.EndDateTime,
               I.OwnerEmployeeID, ISNULL(E.Name, I.OwnerEmployeeID) TechnicianName, I.Status,
               I.IsSubmitted, I.IsApproved, I.IsApproved1, I.IsApproved2,
               I.ApprovedDate, I.SyncDate, I.ReasonVoid, I.ReasonVoid1, I.ReasonVoid2,
               ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') AS InspectionMode
        FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
        LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
        LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
        WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID
          AND I.OwnerEmployeeID=@EmployeeID
          AND ISNULL(I.IsActive,1)=1
          AND EXISTS (
              SELECT 1
              FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.IDTemplate=I.IDTemplate
                AND T.SectionID=I.SectionID
                AND ISNULL(T.TemplateType,'W')='I'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
                AND (ISNULL(T.EmployeeList,'')=''
                     OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
          )
          AND I.SyncDate >= @FromDate AND I.SyncDate < DATEADD(DAY, 1, @ThruDate)
          -- A supervisor-voided transaction is surfaced in Draft for technician handling,
          -- not again in Submitted just because its SyncDate falls in the selected range.
          AND NOT (
              I.Status='DRAFT'
              AND ISNULL(I.IsSubmitted,0)=0
              AND ISNULL(I.ReasonVoid,'')<>''
          )
          AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
        ORDER BY I.ApprovedDate DESC, I.EndDateTime DESC, I.StartDateTime DESC, I.InspectionID DESC
        RETURN;
    END;

    IF @p_Tipe = '070'
    BEGIN
        ;WITH InspectionData AS
                        (
                            SELECT
                                I.Status,
                                I.IsSubmitted,
                                I.IsApproved,
                                I.IsApproved1,
                                I.IsApproved2,
                                I.ApprovedDate,
                                I.ReasonVoid,
                                I.CompanyID,
                                I.LocationID,
                                I.SectionID,
                                ISNULL(NULLIF(IT.InspectionMode, ''), 'STANDARD')
                                    AS InspectionMode
                            FROM dbo.PIP_T_Inspection I
                            LEFT JOIN dbo.PIP_M_InspectionType IT
                                ON IT.InspectionTypeCode = I.InspectionTypeCode
                            WHERE I.CompanyID = @CompanyID
                              AND I.LocationID = @LocationID
                              AND ISNULL(I.IsActive, 1) = 1
        
                              AND EXISTS
                              (
                                  SELECT 1
                                  FROM dbo.PIP_M_CheckListWOPM T
                                  WHERE T.IDTemplate = I.IDTemplate
                                    AND T.SectionID = I.SectionID
                                    AND ISNULL(T.TemplateType, 'W') = 'I'
                                    AND
                                    (
                                        ISNULL(T.CompanyScope, 'S') = 'A'
                                        OR
                                        (
                                            ';' + ISNULL(T.CompanyLocationList, '') + ';'
                                            LIKE '%;' + I.CompanyID + I.LocationID + ';%'
                                        )
                                    )
                                    AND
                                    (
                                        ISNULL(T.EmployeeList, '') = ''
                                        OR
                                        (
                                            ';' + ISNULL(T.EmployeeList, '') + ';'
                                            LIKE '%;' + I.OwnerEmployeeID + ';%'
                                        )
                                    )
                              )
        
                              AND EXISTS
                              (
                                  SELECT 1
                                  FROM dbo.SysWebUser SU
                                  WHERE SU.EmployeeID = @EmployeeID
                                    AND SU.IsActive = 1
        
                                    AND (
                                        @IsAdministrator=1
                                        OR EXISTS
                                        (
                                            SELECT 1
                                            FROM dbo.F_SelectALLMenuAuthorization(
                                                'inspecfo', @EmployeeID, ''
                                            ) AM
                                            WHERE AM.MenuID = '20022'
                                        )
                                    )
        
                                    AND
                                    (
                                        @IsAdministrator=1
                                        OR (
                                        EXISTS
                                        (
                                            SELECT 1
                                            FROM dbo.SysWebCommonValue C
                                            WHERE C.AppID = 'INSPEC'
                                              AND C.CommonGroup = 'EmailApproval'
                                              AND C.IsDelete = 0
                                              AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description, ';') X WHERE LTRIM(RTRIM(X.val)) = @EmployeeID)
                                              AND C.ID =
                                                  CONVERT(VARCHAR(30), I.CompanyID) +
                                                  CONVERT(VARCHAR(30), I.LocationID) +
                                                  ';SPV;' + I.SectionID
                                        )
                                        OR EXISTS
                                        (
                                            SELECT 1
                                            FROM dbo.SysWebCommonValue C
                                            WHERE C.AppID = 'INSPEC'
                                              AND C.CommonGroup = 'EmailApproval'
                                              AND C.IsDelete = 0
                                              AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description, ';') X WHERE LTRIM(RTRIM(X.val)) = @EmployeeID)
                                              AND C.ID =
                                                  CONVERT(VARCHAR(30), I.CompanyID) +
                                                  CONVERT(VARCHAR(30), I.LocationID) +
                                                  ';CHIEF_ENG'
                                        )
                                        OR EXISTS
                                        (
                                            SELECT 1
                                            FROM dbo.SysWebCommonValue C
                                            WHERE C.AppID = 'INSPEC'
                                              AND C.CommonGroup = 'EmailApproval'
                                              AND C.IsDelete = 0
                                              AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description, ';') X WHERE LTRIM(RTRIM(X.val)) = @EmployeeID)
                                              AND C.ID =
                                                  CONVERT(VARCHAR(30), I.CompanyID) +
                                                  CONVERT(VARCHAR(30), I.LocationID) +
                                                  ';CHIEF_SEC'
                                        )
                                    ))
        
                                    AND
                                    (
                                        EXISTS
                                        (
                                            SELECT 1
                                            FROM dbo.SysWebUserCompanyLocation C
                                            WHERE C.UserID = SU.EmployeeID
                                              AND C.AppID = 'pip'
                                              AND C.CompanyID = I.CompanyID
                                              AND C.LocationID = I.LocationID
                                        )
                                        OR EXISTS
                                        (
                                            SELECT 1
                                            FROM dbo.F_SelectOneLogin(
                                                'pip', SU.EmployeeID, ''
                                            ) L
                                            WHERE L.CompanyID = I.CompanyID
                                              AND L.LocationID = I.LocationID
                                        )
                                    )
                              )
                        ),
                        ApprovalFlags AS
                        (
                            SELECT
                                I.*,
                                CASE
                                    WHEN @IsAdministrator=1
                                         AND I.InspectionMode<>'LIGHTNING'
                                         AND ISNULL(I.IsSubmitted,0)=1
                                         AND ISNULL(I.IsApproved,0)=0
                                    THEN 1
        
                                    WHEN I.InspectionMode = 'LIGHTNING'
                                         AND ISNULL(I.IsSubmitted, 0) = 1
                                         AND ISNULL(I.IsApproved, 0) = 0
                                         AND EXISTS
                                         (
                                             SELECT 1 FROM dbo.SysWebCommonValue C
                                             WHERE C.AppID = 'INSPEC' AND C.CommonGroup = 'EmailApproval' AND C.IsDelete = 0
                                               AND C.ID = CONVERT(VARCHAR(30), I.CompanyID) + CONVERT(VARCHAR(30), I.LocationID) + ';SPV;' + I.SectionID
                                               AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description, ';') X WHERE LTRIM(RTRIM(X.val)) = @EmployeeID)
                                         )
                                    THEN 1
        
                                    WHEN I.InspectionMode = 'LIGHTNING'
                                         AND ISNULL(I.IsSubmitted, 0) = 1
                                         AND ISNULL(I.IsApproved, 0) = 1
                                         AND ISNULL(I.IsApproved1, 0) = 0
                                         AND EXISTS
                                         (
                                             SELECT 1 FROM dbo.SysWebCommonValue C
                                             WHERE C.AppID = 'INSPEC' AND C.CommonGroup = 'EmailApproval' AND C.IsDelete = 0
                                               AND C.ID = CONVERT(VARCHAR(30), I.CompanyID) + CONVERT(VARCHAR(30), I.LocationID) + ';CHIEF_ENG'
                                               AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description, ';') X WHERE LTRIM(RTRIM(X.val)) = @EmployeeID)
                                         )
                                    THEN 1
        
                                    WHEN I.InspectionMode = 'LIGHTNING'
                                         AND ISNULL(I.IsSubmitted, 0) = 1
                                         AND ISNULL(I.IsApproved1, 0) = 1
                                         AND ISNULL(I.IsApproved2, 0) = 0
                                         AND EXISTS
                                         (
                                             SELECT 1 FROM dbo.SysWebCommonValue C
                                             WHERE C.AppID = 'INSPEC' AND C.CommonGroup = 'EmailApproval' AND C.IsDelete = 0
                                               AND C.ID = CONVERT(VARCHAR(30), I.CompanyID) + CONVERT(VARCHAR(30), I.LocationID) + ';CHIEF_SEC'
                                               AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description, ';') X WHERE LTRIM(RTRIM(X.val)) = @EmployeeID)
                                         )
                                    THEN 1
        
                                    WHEN I.InspectionMode <> 'LIGHTNING'
                                         AND ISNULL(I.IsSubmitted, 0) = 1
                                         AND ISNULL(I.IsApproved, 0) = 0
                                         AND EXISTS
                                         (
                                             SELECT 1 FROM dbo.SysWebCommonValue C
                                             WHERE C.AppID = 'INSPEC' AND C.CommonGroup = 'EmailApproval' AND C.IsDelete = 0
                                               AND C.ID = CONVERT(VARCHAR(30), I.CompanyID) + CONVERT(VARCHAR(30), I.LocationID) + ';SPV;' + I.SectionID
                                               AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description, ';') X WHERE LTRIM(RTRIM(X.val)) = @EmployeeID)
                                         )
                                    THEN 1
        
                                    ELSE 0
                                END AS CanApprove
                            FROM InspectionData I
                        )
                        SELECT
                            ISNULL(SUM(
                                CASE
                                    WHEN Status = 'DONE'
                                     AND IsSubmitted = 1
                                     AND CanApprove = 1
                                     AND (InspectionMode = 'LIGHTNING' OR IsApproved = 0)
                                    THEN 1 ELSE 0
                                END
                            ), 0) AS PendingApproval,
        
                            ISNULL(SUM(
                                CASE
                                    WHEN IsApproved = 1
                                     AND ApprovedDate >=
                                         CONVERT(DATETIME,
                                             CONVERT(VARCHAR(10), GETDATE(), 120),
                                             120)
                                    THEN 1 ELSE 0
                                END
                            ), 0) AS ApprovedToday,
        
                            ISNULL(SUM(
                                CASE
                                    WHEN Status = 'DRAFT'
                                     AND IsSubmitted = 0
                                     AND ISNULL(ReasonVoid, '') <> ''
                                    THEN 1 ELSE 0
                                END
                            ), 0) AS VoidCount
                        FROM ApprovalFlags;
        RETURN;
    END;

    IF @p_Tipe = '071'
    BEGIN
        SELECT I.InspectionID, I.InspectionNo, I.CompanyID, I.LocationID, I.SectionID, I.Status, I.InspectionTypeName,
               I.InspectionTypeDetailName, ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') AS InspectionMode,
               CASE WHEN I.Status='DRAFT' AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'') THEN 'VOID'
                    WHEN ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING' THEN CASE WHEN I.IsApproved2=1 THEN 'ACKNOWLEDGE 2' WHEN I.IsApproved1=1 THEN 'ACKNOWLEDGE 1' WHEN I.IsApproved=1 THEN 'VERIFIED' ELSE 'CHECKED' END
                    WHEN I.IsApproved=1 THEN 'APPROVED' ELSE 'SUBMITTED' END WorkflowStatus,
               CASE WHEN ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING' THEN CASE WHEN I.IsApproved=0 THEN 'SPV' WHEN I.IsApproved1=0 THEN 'CHIEF_ENG' WHEN I.IsApproved2=0 THEN 'CHIEF_SEC' ELSE 'COMPLETED' END
                    WHEN I.IsApproved=0 THEN 'SPV' ELSE 'COMPLETED' END CurrentStageCode,
               I.InspectionTypeCode, I.InspectionTypeDetailCode, I.ScheduledTime, I.IDTemplate, I.IDVersion, I.TemplateNo, I.TemplateVersion,
               I.InspectionDate, CONVERT(VARCHAR(23), I.StartDateTime, 126) AS StartDateTime, CONVERT(VARCHAR(23), I.EndDateTime, 126) AS EndDateTime, I.Summary, I.OwnerEmployeeID,
               ISNULL(ET.Name,I.OwnerEmployeeID) AS TechnicianName,
               I.IsSubmitted,I.SubmittedBy,ISNULL(ES.Name,I.SubmittedBy) AS SubmittedByName,I.SubmittedDate,
               I.IsApproved,I.ApprovedBy,ISNULL(EA.Name,I.ApprovedBy) AS ApprovedByName,I.ApprovedDate,
               I.ApprovalRemark,I.ReasonVoid,I.ReasonVoid1,I.ReasonVoid2,
               I.IsApproved1,I.Approved1By,I.Approved1Date,I.IsApproved2,I.Approved2By,I.Approved2Date,
               I.FollowUp, I.FollowUpSection, I.FollowUpRemark, I.FollowUpWONo,
               I.GPSLatitude,I.GPSLongitude,I.GPSAccuracy,I.GPSCapturedAt
        FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        LEFT JOIN dbo.M_HRD_Employee ET ON ET.EmployeeID=I.OwnerEmployeeID
        LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
        LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
        WHERE I.InspectionID=@InspectionID
          AND EXISTS (
              SELECT 1
              FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.IDTemplate=I.IDTemplate
                AND T.SectionID=I.SectionID
                AND ISNULL(T.TemplateType,'W')='I'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
                AND (ISNULL(T.EmployeeList,'')=''
                     OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
          )
          AND (
               ((I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1)
                OR (I.Status='DRAFT' AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.ReasonVoid,'')<>''))
          )
          AND (
              (@TechnicianView=1
               AND I.OwnerEmployeeID=@EmployeeID
               AND I.Status='DONE'
               AND ISNULL(I.IsSubmitted,0)=1
               AND EXISTS (
                   SELECT 1
                   FROM dbo.SysWebUser SU
                   WHERE SU.EmployeeID=@EmployeeID
                     AND SU.IsActive=1
                     AND (
                         EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                                 WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                                   AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
                         OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                                    WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
                     )
               )
              )
              OR
              (@TechnicianView=0
               AND EXISTS (
                   SELECT 1 FROM dbo.SysWebUser SU
                   WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
                     AND (@IsAdministrator=1 OR EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20022'))
                     AND (@IsAdministrator=1 OR (
                       (ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')<>'LIGHTNING' AND EXISTS (
                           SELECT 1 FROM dbo.SysWebCommonValue C
                           WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                             AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
                             AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                       ))
                       OR (ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')='LIGHTNING' AND (
                           EXISTS (
                               SELECT 1 FROM dbo.SysWebCommonValue C
                               WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                                 AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                                 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
                           )
                           OR EXISTS (
                               SELECT 1 FROM dbo.SysWebCommonValue C
                               WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                                 AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                                 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_ENG'
                           )
                           OR EXISTS (
                               SELECT 1 FROM dbo.SysWebCommonValue C
                               WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                                 AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                                 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_SEC'
                           )
                       ))
                     ))
                     AND (
                         EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                                 WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                                   AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
                         OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                                    WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
                     )
               )
              )
          )
        RETURN;
    END;

    IF @p_Tipe = '072'
    BEGIN
        SELECT TOP 1 1
        FROM dbo.PIP_T_Inspection I
        JOIN dbo.SysWebUser SU ON SU.EmployeeID=@EmployeeID AND SU.IsActive=1
        LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        JOIN dbo.PIP_M_CheckListWOPM T ON T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
        WHERE I.InspectionID=@InspectionID
          AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
          AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')<>'LIGHTNING'
          AND ISNULL(T.TemplateType,'W')='I' 
          AND (ISNULL(T.CompanyScope,'S')='A'
               OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
          AND (ISNULL(T.EmployeeList,'')=''
               OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
          AND (@IsAdministrator=1 OR EXISTS (
              SELECT 1 FROM dbo.SysWebCommonValue C
              WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
                AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
          ))
          AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved,0)=0
          AND (@IsAdministrator=1 OR EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') M WHERE M.MenuID='20022'))
        RETURN;
    END;

    IF @p_Tipe = '073'
    BEGIN
        SELECT TOP 1 1 AS IsEnabled
        FROM dbo.PIP_T_Inspection I
        JOIN dbo.SysWebCommonValue C
          ON C.AppID='INSPEC'
         AND C.CommonGroup='EmailApproval'
         AND C.IsDelete=0
         AND C.Description='1'
         AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)
                  +';EMAIL;'+ISNULL(NULLIF(I.InspectionMode,''),'STANDARD')
        WHERE I.CompanyID=@C
        RETURN;
    END;
    IF @p_Tipe = '075'
    BEGIN
        SELECT DISTINCT I.InspectionTypeCode, I.InspectionTypeName,
               I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
               I.IDTemplate, I.TemplateNo, I.ScheduledTime
        FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
        LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
        LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
        WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID
          AND ISNULL(I.IsActive,1)=1
          AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')<>'LIGHTNING'
          AND EXISTS (
              SELECT 1
              FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.IDTemplate=I.IDTemplate
                AND T.SectionID=I.SectionID
                AND ISNULL(T.TemplateType,'W')='I'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
                AND (ISNULL(T.EmployeeList,'')=''
                     OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
          )
          AND (
               (I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1
                AND ISNULL(I.IsApproved,0)=0)
               OR
               (I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1
                AND ISNULL(I.IsApproved,0)=1
                AND I.ApprovedDate>=@DateFrom AND I.ApprovedDate<DATEADD(DAY,1,@DateThru))
               OR
               (I.Status='DRAFT' AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.ReasonVoid,'')<>'')
          )
          AND EXISTS (
              SELECT 1
              FROM dbo.SysWebUser SU
              WHERE SU.EmployeeID=@EmployeeID
                AND SU.IsActive=1
                AND (
                     EXISTS (
                         SELECT 1
                         FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM
                         WHERE AM.MenuID='20022'
                     )
                     OR @IsAdministrator=1
                     OR (
                         EXISTS (
                             SELECT 1
                             FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM
                             WHERE AM.MenuID='20021'
                         )
                         AND I.OwnerEmployeeID=SU.EmployeeID
                     )
                )
                AND (@IsAdministrator=1 OR EXISTS (
                    SELECT 1 FROM dbo.SysWebCommonValue C
                    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                      AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
                      AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                ))
                AND (ISNULL(I.IsSubmitted,0)=1 OR (I.Status='DRAFT' AND ISNULL(I.ReasonVoid,'')<>''))
                AND (
                    EXISTS (
                        SELECT 1
                        FROM dbo.SysWebUserCompanyLocation C
                        WHERE C.UserID=SU.EmployeeID
                          AND C.AppID='pip'
                          AND C.CompanyID=I.CompanyID
                          AND C.LocationID=I.LocationID
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                        WHERE L.CompanyID=I.CompanyID
                          AND L.LocationID=I.LocationID
                    )
                )
          )
        ORDER BY I.InspectionTypeName, I.InspectionTypeDetailName, I.TemplateNo, I.ScheduledTime
        RETURN;
    END;

    IF @p_Tipe = '076'
    BEGIN
        SELECT I.InspectionID, I.ClientInspectionID, I.InspectionNo, I.CompanyID, I.LocationID, I.SectionID,
               I.InspectionTypeCode, I.InspectionTypeName, I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
               I.IDTemplate, I.IDVersion, I.ScheduledTime, I.TemplateNo, I.TemplateName, I.TemplateVersion,
               I.InspectionDate, CONVERT(VARCHAR(23), I.StartDateTime, 126) AS StartDateTime, CONVERT(VARCHAR(23), I.EndDateTime, 126) AS EndDateTime, I.Summary, I.OwnerEmployeeID,
               ISNULL(E.Name, I.OwnerEmployeeID) AS TechnicianName, I.Status,
               I.IsSubmitted,I.SubmittedBy,ISNULL(ES.Name,I.SubmittedBy) AS SubmittedByName,I.SubmittedDate,
               I.IsApproved,I.ApprovedBy,ISNULL(EA.Name,I.ApprovedBy) AS ApprovedByName,I.ApprovedDate,
               I.ApprovalRemark,I.ReasonVoid,I.FollowUp, I.FollowUpSection, I.FollowUpRemark, I.FollowUpWONo,
               ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') AS InspectionMode,
               CASE WHEN I.Status='DRAFT' AND ISNULL(I.ReasonVoid,'')<>'' THEN 'VOID'
                    WHEN ISNULL(I.IsApproved,0)=1 THEN 'SPV APPROVED'
                    WHEN ISNULL(I.IsSubmitted,0)=1 THEN 'PENDING SPV' ELSE I.Status END AS WorkflowStatus
        FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
        LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
        LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
        WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID
          AND ISNULL(I.IsActive,1)=1
          AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')<>'LIGHTNING'
          AND EXISTS (
              SELECT 1
              FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.IDTemplate=I.IDTemplate
                AND T.SectionID=I.SectionID
                AND ISNULL(T.TemplateType,'W')='I'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
                AND (ISNULL(T.EmployeeList,'')=''
                     OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
          )
          AND (
               (I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1
                AND ISNULL(I.IsApproved,0)=0)
               OR
               (I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1
                AND ISNULL(I.IsApproved,0)=1
                AND I.ApprovedDate>=@DateFrom AND I.ApprovedDate<DATEADD(DAY,1,@DateThru))
               OR
               (I.Status='DRAFT' AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.ReasonVoid,'')<>'')
          )
          AND EXISTS (
              SELECT 1
              FROM dbo.SysWebUser SU
              WHERE SU.EmployeeID=@EmployeeID
                AND SU.IsActive=1
                AND (
                     EXISTS (
                         SELECT 1
                         FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM
                         WHERE AM.MenuID='20022'
                     )
                     OR @IsAdministrator=1
                     OR (
                         EXISTS (
                             SELECT 1
                             FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM
                             WHERE AM.MenuID='20021'
                         )
                         AND I.OwnerEmployeeID=SU.EmployeeID
                     )
                )
                AND (@IsAdministrator=1 OR EXISTS (
                    SELECT 1 FROM dbo.SysWebCommonValue C
                    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                      AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
                      AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                ))
                AND (ISNULL(I.IsSubmitted,0)=1 OR (I.Status='DRAFT' AND ISNULL(I.ReasonVoid,'')<>''))
                AND (
                    EXISTS (
                        SELECT 1
                        FROM dbo.SysWebUserCompanyLocation C
                        WHERE C.UserID=SU.EmployeeID
                          AND C.AppID='pip'
                          AND C.CompanyID=I.CompanyID
                          AND C.LocationID=I.LocationID
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                        WHERE L.CompanyID=I.CompanyID
                          AND L.LocationID=I.LocationID
                    )
                )
          )
          AND (@InspectionTypeCode='' OR I.InspectionTypeCode=@InspectionTypeCode)
          AND (@InspectionTypeDetailCode='' OR I.InspectionTypeDetailCode=@InspectionTypeDetailCode)
          AND (@TemplateId='' OR CONVERT(VARCHAR(20),I.IDTemplate)=@TemplateId)
          AND (@ScheduleTime='' OR ISNULL(I.ScheduledTime,'')=@ScheduleTime)
        ORDER BY I.InspectionDate DESC, I.InspectionID DESC
        RETURN;
    END;

    IF @p_Tipe = '077'
    BEGIN
        SELECT DISTINCT I.InspectionTypeCode,I.InspectionTypeName,I.InspectionTypeDetailCode,I.InspectionTypeDetailName,I.IDTemplate,I.TemplateNo,I.ScheduledTime
        FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
        LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
        LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
        WHERE ISNULL(I.InspectionMode,'')='LIGHTNING'
          AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
          AND ISNULL(I.IsActive,1)=1
          AND (
              (@ApprovalTab='OUTSTANDING' AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved2,0)=0
               AND ((@IsAdministrator=1 AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved2,0)=0)
                 OR (ISNULL(I.IsApproved,0)=0 AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
                 OR (ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0 AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_ENG' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
                 OR (ISNULL(I.IsApproved1,0)=1 AND ISNULL(I.IsApproved2,0)=0 AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_SEC' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))))
              OR (@ApprovalTab='APPROVED' AND ISNULL(I.IsSubmitted,0)=1
               AND (
                    @IsAdministrator=1
                    OR (ISNULL(I.IsApproved,0)=1
                     AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
                 OR (ISNULL(I.IsApproved1,0)=1
                     AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_ENG' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
                 OR (ISNULL(I.IsApproved2,0)=1
                     AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_SEC' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
               ))
              OR (@ApprovalTab='VOID' AND I.Status='DRAFT' AND ISNULL(I.IsSubmitted,0)=0 AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'')
               AND (EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID))
                 OR EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_ENG' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID))
                 OR EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_SEC' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)) OR @IsAdministrator=1)
          )
          )
          AND (@ApprovalTab='OUTSTANDING' OR
               (I.InspectionDate>=@DateFrom AND I.InspectionDate<DATEADD(DAY,1,@DateThru)))
          AND (@InspectionTypeCode='' OR I.InspectionTypeCode=@InspectionTypeCode)
          AND (@InspectionTypeDetailCode='' OR I.InspectionTypeDetailCode=@InspectionTypeDetailCode)
          AND (@TemplateId='' OR CONVERT(VARCHAR(20),I.IDTemplate)=@TemplateId)
          AND (@ScheduleTime='' OR ISNULL(I.ScheduledTime,'')=@ScheduleTime)
          AND EXISTS (
              SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
                AND ISNULL(T.TemplateType,'W')='I'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
                AND (ISNULL(T.EmployeeList,'')='' OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
          )
        ORDER BY I.InspectionTypeName,I.InspectionTypeDetailName,I.TemplateNo,I.ScheduledTime
        RETURN;
    END;

    IF @p_Tipe = '078'
    BEGIN
        SELECT I.InspectionID,I.ClientInspectionID,I.InspectionNo,I.CompanyID,I.LocationID,I.SectionID,
               I.InspectionTypeCode,I.InspectionTypeName,I.InspectionTypeDetailCode,I.InspectionTypeDetailName,
               I.IDTemplate,I.IDVersion,I.ScheduledTime,I.TemplateNo,I.TemplateName,I.TemplateVersion,
               I.InspectionDate,CONVERT(VARCHAR(23),I.StartDateTime,126) StartDateTime,CONVERT(VARCHAR(23),I.EndDateTime,126) EndDateTime,I.Summary,I.OwnerEmployeeID,
               ISNULL(E.Name,I.OwnerEmployeeID) TechnicianName,I.Status,I.IsSubmitted,I.SubmittedBy,ISNULL(ES.Name,I.SubmittedBy) SubmittedByName,I.SubmittedDate,
               I.IsApproved,I.ApprovedBy,ISNULL(EA.Name,I.ApprovedBy) ApprovedByName,I.ApprovedDate,
               I.IsApproved1,I.Approved1By,I.Approved1Date,I.IsApproved2,I.Approved2By,I.Approved2Date,I.ApprovalRemark,I.ReasonVoid,I.ReasonVoid1,I.ReasonVoid2,
               I.FollowUp,I.FollowUpSection,I.FollowUpRemark,I.FollowUpWONo,'LIGHTNING' InspectionMode,
               CASE WHEN I.Status='DRAFT' AND ISNULL(I.ReasonVoid,'')<>'' THEN 'VOID'
                    WHEN I.IsApproved2=1 THEN 'ACKNOWLEDGE 2' WHEN I.IsApproved1=1 THEN 'ACKNOWLEDGE 1' WHEN I.IsApproved=1 THEN 'VERIFIED' ELSE 'CHECKED' END WorkflowStatus,
               CASE WHEN I.IsApproved=0 THEN 'SPV' WHEN I.IsApproved1=0 THEN 'CHIEF_ENG' WHEN I.IsApproved2=0 THEN 'CHIEF_SEC' ELSE 'COMPLETED' END CurrentStageCode
        FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
        LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
        LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
        WHERE ISNULL(I.InspectionMode,'')='LIGHTNING'
          AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
          AND ISNULL(I.IsActive,1)=1
          AND (
              (@ApprovalTab='OUTSTANDING' AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved2,0)=0
               AND ((@IsAdministrator=1 AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved2,0)=0)
                 OR (ISNULL(I.IsApproved,0)=0 AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
                 OR (ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0 AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_ENG' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
                 OR (ISNULL(I.IsApproved1,0)=1 AND ISNULL(I.IsApproved2,0)=0 AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_SEC' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))))
              OR (@ApprovalTab='APPROVED' AND ISNULL(I.IsSubmitted,0)=1
               AND (
                    @IsAdministrator=1
                    OR (ISNULL(I.IsApproved,0)=1
                     AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
                 OR (ISNULL(I.IsApproved1,0)=1
                     AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_ENG' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
                 OR (ISNULL(I.IsApproved2,0)=1
                     AND EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_SEC' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)))
               ))
              OR (@ApprovalTab='VOID' AND I.Status='DRAFT' AND ISNULL(I.IsSubmitted,0)=0 AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'')
               AND (EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID))
                 OR EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_ENG' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID))
                 OR EXISTS (SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_SEC' AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)) OR @IsAdministrator=1)
          )
          )
          AND (@ApprovalTab='OUTSTANDING' OR
               (I.InspectionDate>=@DateFrom AND I.InspectionDate<DATEADD(DAY,1,@DateThru)))
          AND (@InspectionTypeCode='' OR I.InspectionTypeCode=@InspectionTypeCode)
          AND (@InspectionTypeDetailCode='' OR I.InspectionTypeDetailCode=@InspectionTypeDetailCode)
          AND (@TemplateId='' OR CONVERT(VARCHAR(20),I.IDTemplate)=@TemplateId)
          AND (@ScheduleTime='' OR ISNULL(I.ScheduledTime,'')=@ScheduleTime)
          AND EXISTS (
              SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
              WHERE T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
                AND ISNULL(T.TemplateType,'W')='I'
                AND (ISNULL(T.CompanyScope,'S')='A'
                     OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
                AND (ISNULL(T.EmployeeList,'')='' OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
          )
        ORDER BY I.InspectionDate DESC,I.InspectionID DESC
        RETURN;
    END;

    IF @p_Tipe = '079'
    BEGIN
        SELECT I.InspectionID,I.InspectionNo,I.CompanyID,I.LocationID,I.InspectionTypeCode,I.InspectionTypeName,I.InspectionTypeDetailCode,I.InspectionTypeDetailName,I.InspectionDate,I.TemplateNo,I.TemplateName,I.OwnerEmployeeID,I.Status,I.IsApproved
        FROM dbo.PIP_T_Inspection I
        JOIN dbo.SysWebUser SU ON SU.EmployeeID=@EmployeeID AND SU.IsActive=1
        JOIN dbo.PIP_M_CheckListWOPM T ON T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
        WHERE I.InspectionID IN (SELECT CONVERT(BIGINT,LTRIM(RTRIM(val))) FROM dbo.SplitStringConvertToTable(@InspectionIDs,','))
        AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID AND ISNULL(I.IsActive,1)=1 AND ISNULL(T.TemplateType,'W')='I'
        AND (ISNULL(T.CompanyScope,'S')='A' OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
        AND (ISNULL(T.EmployeeList,'')='' OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
        AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
        AND (@IsAdministrator=1 OR EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') M WHERE M.MenuID='20022'))
        AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C WHERE C.UserID=SU.EmployeeID AND C.AppID='pip' AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
        OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID))
        ORDER BY I.InspectionID
        RETURN;
    END;

    IF @p_Tipe = '080'
    BEGIN
        SELECT COUNT(1) PendingCount FROM dbo.PIP_T_InspectionEmailOutbox O
        WHERE O.DeliveryStatus IN ('PENDING','FAILED','SENDING')
        AND EXISTS (SELECT 1 FROM dbo.PIP_T_Inspection I JOIN dbo.SysWebCommonValue C ON C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.Description='1'
        AND ((O.EntityType='LIGHTNING' AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';EMAIL;LIGHTNING')
        OR (O.EntityType='INSPECTION' AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';EMAIL;'+ISNULL(NULLIF(I.InspectionMode,''),'STANDARD')))
        WHERE I.InspectionID=O.EntityID)
        RETURN;
    END;

    RAISERROR('Invalid @p_Tipe for spPIP_Inspection_Query.', 16, 1);
END;
GO
