/*
    InspectionMode on PIP_M_InspectionType.
    STANDARD = existing checklist workflow.
    BATCH    = map / Inspection Point batch workflow.
    SQL Server 2008 compatible.
*/
SET NOCOUNT ON;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionType','InspectionMode') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionType
        ADD InspectionMode VARCHAR(10) NOT NULL
            CONSTRAINT DF_PIP_M_InspectionType_InspectionMode DEFAULT ('STANDARD');
END
ELSE
BEGIN
    UPDATE dbo.PIP_M_InspectionType
    SET InspectionMode=CASE
        WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,''))))='BATCH' THEN 'BATCH'
        ELSE 'STANDARD'
    END
    ;

    IF EXISTS
    (
        SELECT 1 FROM sys.columns
        WHERE object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
          AND name='InspectionMode' AND is_nullable=1
    )
        ALTER TABLE dbo.PIP_M_InspectionType ALTER COLUMN InspectionMode VARCHAR(10) NOT NULL;

    IF NOT EXISTS
    (
        SELECT 1 FROM sys.default_constraints
        WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
          AND parent_column_id=COLUMNPROPERTY(OBJECT_ID('dbo.PIP_M_InspectionType'),'InspectionMode','ColumnId')
    )
        ALTER TABLE dbo.PIP_M_InspectionType
            ADD CONSTRAINT DF_PIP_M_InspectionType_InspectionMode DEFAULT ('STANDARD') FOR InspectionMode;
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name='CK_PIP_M_InspectionType_InspectionMode'
)
    ALTER TABLE dbo.PIP_M_InspectionType
        ADD CONSTRAINT CK_PIP_M_InspectionType_InspectionMode
        CHECK (InspectionMode IN ('STANDARD','BATCH'));
GO
