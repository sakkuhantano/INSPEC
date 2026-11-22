/*
    Remove the ShapeType CHECK constraint from dbo.PIP_M_InspectionPoint.

    Reason:
      Inspection Master supports CIRCLE, RECTANGLE and PATH geometry.
      ShapeType values are validated and normalized by the application;
      the database CHECK constraint is stale and rejects valid geometry
      values used by the current editor.

    SQL Server 2008 compatible and safe to execute more than once.
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.PIP_M_InspectionPoint', N'U') IS NOT NULL
   AND EXISTS
   (
       SELECT 1
       FROM sys.check_constraints
       WHERE name = N'CK_PIP_M_InspectionPoint_ShapeType'
         AND parent_object_id = OBJECT_ID(N'dbo.PIP_M_InspectionPoint')
   )
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionPoint
        DROP CONSTRAINT CK_PIP_M_InspectionPoint_ShapeType;
END;
GO

-- Verify that the obsolete constraint is no longer present.
SELECT name
FROM sys.check_constraints
WHERE name = N'CK_PIP_M_InspectionPoint_ShapeType'
  AND parent_object_id = OBJECT_ID(N'dbo.PIP_M_InspectionPoint');
GO
