/*
    Per-approval-stage email switch lookup.
    Workflow ComVal IDs:
      <CompanyID><LocationID>;STANDARD
      <CompanyID><LocationID>;BATCH;PARAM
      <CompanyID><LocationID>;BATCH;INSPECT
    Description tokens: [LEVEL][TRUE/FALSE]
    Missing ComVal / missing token / malformed value => OFF.
*/
IF OBJECT_ID('dbo.fnINSPEC_ApprovalEmailEnabled','FN') IS NOT NULL
    DROP FUNCTION dbo.fnINSPEC_ApprovalEmailEnabled;
GO
CREATE FUNCTION dbo.fnINSPEC_ApprovalEmailEnabled
(
    @p_CompanyID VARCHAR(10),
    @p_LocationID VARCHAR(3),
    @p_WorkflowKey VARCHAR(30),
    @p_LevelCode VARCHAR(20)
)
RETURNS BIT
AS
BEGIN
    DECLARE @Description VARCHAR(4000);
    DECLARE @ComValID VARCHAR(100);
    DECLARE @Token VARCHAR(100);

    SET @ComValID=LTRIM(RTRIM(ISNULL(@p_CompanyID,'')))+
                  LTRIM(RTRIM(ISNULL(@p_LocationID,'')))+';'+
                  LTRIM(RTRIM(ISNULL(@p_WorkflowKey,'')));
    SET @Token='['+UPPER(LTRIM(RTRIM(ISNULL(@p_LevelCode,'')))+'][TRUE]';

    SELECT TOP 1 @Description=UPPER(ISNULL(C.Description,''))
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC'
      AND C.CommonGroup='EmailApproval'
      AND C.IsDelete=0
      AND C.ID=@ComValID;

    RETURN CASE WHEN CHARINDEX(@Token,ISNULL(@Description,''))>0 THEN 1 ELSE 0 END;
END;
GO
