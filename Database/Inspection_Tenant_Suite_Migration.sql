/*
    INSPEC - Tenant-based Inspection Migration
    -------------------------------------------
    Run after the THD master tables are available in the target database.
    Existing inspections remain non-tenant inspections (TenantID/SuiteNo = '').
    Existing Inspection Type Details remain non-tenant (IsTenantInspection = 0).
*/

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionTypeDetail', 'IsTenantInspection') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionTypeDetail
        ADD IsTenantInspection BIT NOT NULL
            CONSTRAINT DF_PIP_M_InspectionTypeDetail_IsTenantInspection DEFAULT (0) WITH VALUES;
END;
GO

IF COL_LENGTH('dbo.PIP_T_Inspection', 'TenantID') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_T_Inspection
        ADD TenantID VARCHAR(10) NOT NULL
            CONSTRAINT DF_PIP_T_Inspection_TenantID DEFAULT ('') WITH VALUES;
END;
GO

IF COL_LENGTH('dbo.PIP_T_Inspection', 'SuiteNo') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_T_Inspection
        ADD SuiteNo VARCHAR(10) NOT NULL
            CONSTRAINT DF_PIP_T_Inspection_SuiteNo DEFAULT ('') WITH VALUES;
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_Inspection')
      AND name = 'IX_PIP_T_Inspection_TenantDuplicate'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_Inspection_TenantDuplicate
    ON dbo.PIP_T_Inspection
    (
        CompanyID, LocationID, SectionID, InspectionDate,
        InspectionTypeCode, InspectionTypeDetailCode,
        ScheduledTime, IDTemplate, TenantID, SuiteNo
    )
    INCLUDE (ClientInspectionID, InspectionID, IsActive);
END;
GO

/*
    To enable tenant-specific inspection for one detail:
    UPDATE dbo.PIP_M_InspectionTypeDetail
    SET IsTenantInspection = 1
    WHERE InspectionTypeCode = 'PHKP'
      AND InspectionTypeDetailCode = '<DETAIL_CODE>'
      AND CompanyID = '<COMPANY_ID>'
      AND LocationID = '<LOCATION_ID>';

    IsTenantInspection = 1 requires an active THD tenant and an active lease suite.
    For all other details, leave IsTenantInspection = 0.
*/
