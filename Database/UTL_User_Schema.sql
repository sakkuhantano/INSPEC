-- INSPEC / UTL1 user-section and legacy flags table
-- Source: DDL supplied by the project owner on 2026-11-04.
-- Per project notes, SysWebUser is the authentication source; UTL_User is
-- retained for Section mapping, Theme, and existing business flags.

CREATE TABLE [dbo].[UTL_User](
    [UserID] [varchar](10) NULL,
    [UserName] [varchar](100) NULL,
    [Password] [nvarchar](255) NULL,
    [IsELC] [bit] NULL,
    [IsWTR] [bit] NULL,
    [IsGAS] [bit] NULL,
    [IsWO] [bit] NULL,
    [EmployeeID] [varchar](10) NULL,
    [IsActive] [bit] NULL,
    [Theme] [varchar](1) NULL,
    [IsSpv] [bit] NULL,
    [Section] [varchar](500) NULL
) ON [PRIMARY]
GO
