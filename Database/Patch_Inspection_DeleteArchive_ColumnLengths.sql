/* INSPEC - fix Inspection delete archive column lengths
   Required because SEC.MP is 6 characters while older archive schema may still use VARCHAR(2).
   SQL Server 2008 compatible.
*/
IF OBJECT_ID('dbo.PIP_T_Inspection_Delete','U') IS NOT NULL
BEGIN
    IF COL_LENGTH('dbo.PIP_T_Inspection_Delete','InspectionTypeCode') IS NOT NULL
       AND COL_LENGTH('dbo.PIP_T_Inspection_Delete','InspectionTypeCode') < 10
    BEGIN
        ALTER TABLE dbo.PIP_T_Inspection_Delete
            ALTER COLUMN InspectionTypeCode VARCHAR(10) NULL;
    END;

    IF COL_LENGTH('dbo.PIP_T_Inspection_Delete','ReasonCancel') IS NOT NULL
       AND COL_LENGTH('dbo.PIP_T_Inspection_Delete','ReasonCancel') < 1000
    BEGIN
        ALTER TABLE dbo.PIP_T_Inspection_Delete
            ALTER COLUMN ReasonCancel VARCHAR(1000) NULL;
    END;

    IF COL_LENGTH('dbo.PIP_T_Inspection_Delete','OriginalStatus') IS NOT NULL
       AND COL_LENGTH('dbo.PIP_T_Inspection_Delete','OriginalStatus') < 10
    BEGIN
        ALTER TABLE dbo.PIP_T_Inspection_Delete
            ALTER COLUMN OriginalStatus VARCHAR(10) NULL;
    END;

    IF COL_LENGTH('dbo.PIP_T_Inspection_Delete','OriginalSyncStatus') IS NOT NULL
       AND COL_LENGTH('dbo.PIP_T_Inspection_Delete','OriginalSyncStatus') < 20
    BEGIN
        ALTER TABLE dbo.PIP_T_Inspection_Delete
            ALTER COLUMN OriginalSyncStatus VARCHAR(20) NULL;
    END;
END;
