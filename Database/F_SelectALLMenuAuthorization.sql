-- INSPEC / SysWeb2 authorization function
-- Source: SQL definition supplied by the project owner on 2026-11-04.
-- This function depends on dbo.SysWebUserUserGroup and dbo.SplitStringConvertToTable.
-- The supplied schema for SysWebUserUserGroup was not included in the DDL package.

CREATE FUNCTION [dbo].[F_SelectALLMenuAuthorization]
(
    @p_AppID VARCHAR(20),
    @p_EmployeeID VARCHAR(50),
    @p_ListParam VARCHAR(8000)
)
RETURNS @r_SelectALLMenuAuthorization TABLE
(
    MenuID VARCHAR(50),
    ParentMenuID VARCHAR(50),
    Caption VARCHAR(500),
    URL VARCHAR(500),
    AppID VARCHAR(500),
    IsReport BIT,
    [COUNTER] NUMERIC(18, 2),
    Line BIT,
    ImageUrl VARCHAR(5000),
    [DESCRIPTION] VARCHAR(500),
    isActive BIT,
    HeaderDetail VARCHAR(10)
)
AS
BEGIN
    DECLARE @V_ListMenuIDExcl VARCHAR(8000) = '';

    --SET @V_ListMenuIDNotShow = ISNULL((SELECT x.val FROM dbo.SplitStringConvertToTable(@p_ListParam, ';') x WHERE x.id = 1), '')
    --SET @V_ListMenuIDNotShow = '0,1'
    --SET @V_ListMenuIDNotShow = ''

    IF @p_AppID NOT IN ('PIP', 'CM')
    BEGIN
        SET @V_ListMenuIDExcl = @V_ListMenuIDExcl + ',2200';
    END

    IF @p_AppID IN ('PDR', 'PDR2', 'KPI', 'MyTenant', 'ESS', 'QMS', 'RH')
    BEGIN
        SET @V_ListMenuIDExcl = @V_ListMenuIDExcl + ',113,900';
    END

    IF @p_AppID IN ('GL', 'PDR2', 'KPI', 'MyTenant', 'ANP', 'MTA', 'HRD1', 'FA', 'FILLING', 'RH', 'PERMIT', 'CANVASSING')
    BEGIN
        SET @V_ListMenuIDExcl = @V_ListMenuIDExcl + ',1';
    END

    SET @V_ListMenuIDExcl = STUFF(@V_ListMenuIDExcl, 1, 1, '');

    INSERT INTO @r_SelectALLMenuAuthorization
    SELECT
        m.MenuID,
        m.ParentMenuID,
        m.Caption,
        m.[Url],
        m.AppID,
        m.IsReport,
        m.[Counter],
        m.Line,
        m.ImageUrl,
        m.[Description],
        m.isActive,
        CASE
            WHEN EXISTS
            (
                SELECT swm.MenuID
                FROM SysWebMenu swm
                WHERE swm.ParentMenuID = m.MenuID
                  AND swm.isActive = 1
            ) THEN 'H'
            ELSE 'D'
        END AS HeaderDetail
    FROM SysWebMenu m
    INNER JOIN
    (
        SELECT DISTINCT gm.MenuID
        FROM SysWebUserGroupMenu gm
        INNER JOIN SysWebUserGroup ug ON ug.UserGroupID = gm.UserGroupID
        WHERE EXISTS
        (
            SELECT uug.UserID, uug.UserGroupID
            FROM SysWebUserUserGroup uug
            WHERE uug.UserGroupID = gm.UserGroupID
              AND uug.UserID = @p_EmployeeID
        )
        AND NOT EXISTS
        (
            SELECT x.val
            FROM dbo.SplitStringConvertToTable(@V_ListMenuIDExcl, ',') x
            WHERE x.val <> ''
              AND x.val = gm.MenuID
        )
        AND ug.isActive = 1
    ) x ON x.MenuID = m.MenuID
    WHERE m.AppID IN (@p_AppID, 'ALL')
      AND m.isActive = 1;

    --(CASE WHEN @p_AppID IN ('WebAPP', 'GL') THEN 'ALL_2' ELSE 'ALL' END)

    IF @p_AppID IN ('GL', 'PDR2', 'KPI', 'MyTenant', 'ANP', 'MTA', 'HRD1', 'FA', 'FILLING', 'RH', 'PERMIT', 'CANVASSING')
    BEGIN
        IF @p_AppID IN ('PDR2', 'KPI', 'MyTenant')
        BEGIN
            UPDATE m
            SET m.ImageUrl = '<svg xmlns="http://www.w3.org/2000/svg" style="Margin-bottom:2px;" width="16" height="16" fill="currentColor" class="bi bi-house-fill" viewBox="0 0 16 16"><path d="M8.707 1.5a1 1 0 0 0-1.414 0L.646 8.146a.5.5 0 0 0 .708.708L8 2.207l6.646 6.647a.5.5 0 0 0 .708-.708L13 5.793V2.5a.5.5 0 0 0-.5-.5h-1a.5.5 0 0 0-.5.5v1.293L8.707 1.5Z"/><path d="m8 3.293 6 6V13.5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 13.5V9.293l6-6Z"/></svg>'
            FROM @r_SelectALLMenuAuthorization m
            WHERE m.MenuID = '0';
        END
        ELSE
        BEGIN
            UPDATE m
            SET m.ImageUrl = '<i class="fas fa-home"></i>'
            FROM @r_SelectALLMenuAuthorization m
            WHERE m.MenuID = '0';
        END

        UPDATE m
        SET m.ImageUrl = ''
        --, m.[URL] = 'S_SettingCompany.aspx'
        FROM @r_SelectALLMenuAuthorization m
        WHERE m.MenuID = '113';

        UPDATE m
        SET
            m.Caption = 'Setting',
            m.ImageUrl = '<i class="fas fa-cog"></i>',
            m.[DESCRIPTION] = 'Setting'
        FROM @r_SelectALLMenuAuthorization m
        WHERE m.MenuID = '900';

        --SELECT * FROM SysWebMenu swm WHERE swm.AppID = 'ALL'
        --SELECT * FROM SysWebMenu swm WHERE swm.AppID = 'ALL_2'
    END

    --IF @p_AppID='pip'
    --    UPDATE A SET a.[URL]='javascript:openWindow('''+REPLACE(swa.[Url],@p_AppID,'mytenant')+'?infoid=tr&1='+@p_EmployeeID+'&2='+swu.[Password]+''','''+a.MenuID+''',1000,600,''yes'',''yes'');'
    --    FROM @r_SelectALLMenuAuthorization A CROSS JOIN SysWebUser AS swu
    --    CROSS JOIN SysWebApp AS swa
    --    WHERE a.MenuID='16351' AND swu.employeeid=@p_EmployeeID AND swa.AppID=@p_AppID

    RETURN;
END
GO
