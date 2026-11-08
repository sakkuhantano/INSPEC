/*
    Inspection Map coverage rule.
    Default = 1 preserves existing behavior: all active points are required.
    Set RequireAllPoints = 0 for partial-coverage maps such as car parks.
*/
IF COL_LENGTH('dbo.PIP_M_InspectionMap', 'RequireAllPoints') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionMap
        ADD RequireAllPoints BIT NOT NULL
            CONSTRAINT DF_PIP_M_InspectionMap_RequireAllPoints DEFAULT (1) WITH VALUES;
END;
GO

-- Example configuration:
-- UPDATE dbo.PIP_M_InspectionMap
-- SET RequireAllPoints = 0
-- WHERE MapCode = 'CARPARK' AND IsCurrentVersion = 1;
--
-- UPDATE dbo.PIP_M_InspectionMap
-- SET RequireAllPoints = 1
-- WHERE MapCode = 'LIGHTING' AND IsCurrentVersion = 1;
