-- INSPEC / INSPEC_User user-section and theme table
-- UserID is identical to the authenticated NIK / EmployeeID.

CREATE TABLE [dbo].[INSPEC_User](
    [UserID] [varchar](50) NULL,
    [Theme] [varchar](1) NULL,
    [IsActive] [bit] NULL,
    [SectionList] [varchar](8000) NULL
) ON [PRIMARY]
GO
