/*
    INSPEC - Store technician GPS on each inspection transaction.
    SQL Server 2008 compatible and idempotent.
*/
IF COL_LENGTH('dbo.PIP_T_Inspection','GPSLatitude') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD GPSLatitude DECIMAL(10,7) NULL;
GO
IF COL_LENGTH('dbo.PIP_T_Inspection','GPSLongitude') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD GPSLongitude DECIMAL(10,7) NULL;
GO
IF COL_LENGTH('dbo.PIP_T_Inspection','GPSAccuracy') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD GPSAccuracy DECIMAL(10,2) NULL;
GO
IF COL_LENGTH('dbo.PIP_T_Inspection','GPSCapturedAt') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD GPSCapturedAt DATETIME NULL;
GO
