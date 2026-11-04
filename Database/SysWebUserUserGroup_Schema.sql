-- SysWeb2 user-to-user-group mapping table
-- DDL supplied by the project owner on 2026-11-04.

CREATE TABLE [dbo].[SysWebUserUserGroup]
(
    [UserID] [varchar](50) NOT NULL,
    [UserGroupID] [varchar](50) NOT NULL,
    [DashBoardGroupID] [varchar](50) NULL,
    CONSTRAINT [PK_SysWebUserUserGroup] PRIMARY KEY CLUSTERED
    (
        [UserID] ASC,
        [UserGroupID] ASC
    ) WITH
    (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        IGNORE_DUP_KEY = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON
    ) ON [PRIMARY]
) ON [PRIMARY]
GO
