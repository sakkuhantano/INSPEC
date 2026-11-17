/*
    Fix: PIP inspection sync must accept full InspectionTypeCode values
    such as 'HK.TL' (not truncated to 2 characters).

    Target:
      dbo.spUTL_PIP_T_Inspection_Sync
      @p_InspectionTypeCode VARCHAR(2) -> VARCHAR(50)

    This migration preserves the existing procedure body and only changes
    the parameter declaration.
*/

SET NOCOUNT ON;

DECLARE @ProcedureDefinition NVARCHAR(MAX);

SELECT @ProcedureDefinition = sm.definition
FROM sys.sql_modules sm
JOIN sys.objects o
    ON o.object_id = sm.object_id
WHERE o.schema_id = SCHEMA_ID('dbo')
  AND o.name = 'spUTL_PIP_T_Inspection_Sync'
  AND o.type = 'P';

IF @ProcedureDefinition IS NULL
BEGIN
    RAISERROR('dbo.spUTL_PIP_T_Inspection_Sync was not found.', 16, 1);
    RETURN;
END;

IF CHARINDEX('@p_InspectionTypeCode VARCHAR(2)', @ProcedureDefinition) = 0
BEGIN
    IF CHARINDEX('@p_InspectionTypeCode VARCHAR(50)', @ProcedureDefinition) > 0
    BEGIN
        PRINT 'dbo.spUTL_PIP_T_Inspection_Sync is already fixed.';
        RETURN;
    END;

    RAISERROR('Expected @p_InspectionTypeCode VARCHAR(2) declaration was not found. Procedure was not changed.', 16, 1);
    RETURN;
END;

SET @ProcedureDefinition = REPLACE(
    @ProcedureDefinition,
    '@p_InspectionTypeCode VARCHAR(2)',
    '@p_InspectionTypeCode VARCHAR(50)'
);

EXEC sys.sp_executesql @ProcedureDefinition;

PRINT 'dbo.spUTL_PIP_T_Inspection_Sync fixed: @p_InspectionTypeCode is now VARCHAR(50).';
