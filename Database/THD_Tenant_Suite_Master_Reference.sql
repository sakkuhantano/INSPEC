/*
    INSPEC - THD Tenant / Suite Master Reference
    --------------------------------------------
    Source master tables used by tenant-based inspections.

    These tables are maintained by the THD application/database.
    This file documents their structure and the lookup contract for INSPEC.
    Do not deploy duplicate copies if the tables already exist in the target database.
*/

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   dbo.THD_M_AgreementInformation
   Master suite / lease agreement.
   Primary key: CompanyID + LocationID + TenantID + SuiteNo
   ============================================================ */

IF OBJECT_ID(N'dbo.THD_M_AgreementInformation', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[THD_M_AgreementInformation]
    (
        [CompanyID]          varchar(10) NOT NULL,
        [LocationID]         varchar(3) NOT NULL,
        [TenantID]           varchar(10) NOT NULL,
        [SuiteNo]            varchar(10) NOT NULL,
        [LeaseCommDate]      datetime NOT NULL,
        [RentCommDate]       datetime NOT NULL,
        [LeaseTermDate]      datetime NOT NULL,
        [TermOfLeaseMonth]   int NOT NULL,
        [TermOfLeaseDay]     int NOT NULL,
        [PartialLeaseFrom]   datetime NOT NULL,
        [PartialLeaseThru]   datetime NOT NULL,
        [PartialDay]         int NOT NULL,
        [FitOutTerm]         int NOT NULL,
        [FitOutDate]         datetime NOT NULL,
        [UpdateUser]         varchar(50) NOT NULL,
        [UpdateDate]         datetime NOT NULL,
        CONSTRAINT [PK_THD_M_AgreementInformation_1] PRIMARY KEY CLUSTERED
        (
            [CompanyID] ASC,
            [LocationID] ASC,
            [TenantID] ASC,
            [SuiteNo] ASC
        )
    );
END;
GO

/* ============================================================
   dbo.THD_M_GeneralInformation
   Master tenant.
   Primary key: CompanyID + LocationID + TenantID
   ============================================================ */

IF OBJECT_ID(N'dbo.THD_M_GeneralInformation', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[THD_M_GeneralInformation]
    (
        [CompanyID] varchar(10) NOT NULL,
        [LocationID] varchar(3) NOT NULL,
        [TenantID] varchar(10) NOT NULL,
        [TenantName] varchar(200) NOT NULL,
        [TradeName] varchar(200) NOT NULL,
        [MailingAddress] varchar(1000) NOT NULL,
        [MailingCity] varchar(30) NOT NULL,
        [MailingPostCode] varchar(10) NOT NULL,
        [MailingProvince] varchar(25) NOT NULL,
        [MailingCountry] varchar(30) NOT NULL,
        [BillingAddress] varchar(1000) NOT NULL,
        [BillingCity] varchar(30) NOT NULL,
        [BillingPostCode] varchar(10) NOT NULL,
        [BillingProvince] varchar(25) NOT NULL,
        [BillingCountry] varchar(30) NOT NULL,
        [Telephone] varchar(50) NOT NULL,
        [Fax] varchar(50) NOT NULL,
        [NPWP] varchar(30) NOT NULL,
        [NITKU] varchar(50) NOT NULL,
        [NPWPName] varchar(200) NOT NULL,
        [NPWPAddress] varchar(1000) NOT NULL,
        [NPWPNIK] varchar(100) NOT NULL,
        [NPWPCity] varchar(30) NOT NULL,
        [NPWPPostCode] varchar(10) NOT NULL,
        [NPWPProvince] varchar(25) NOT NULL,
        [IsPSC] bit NOT NULL,
        [Limit] money NOT NULL,
        [BusinessType] varchar(20) NOT NULL,
        [UseOfPremises] varchar(20) NOT NULL,
        [InterestType] varchar(1) NOT NULL,
        [InterestRate] smallint NOT NULL,
        [Days] smallint NOT NULL,
        [IsProforma] bit NOT NULL,
        [TerminationDate] datetime NOT NULL,
        [GroupIDIDR] varchar(2) NOT NULL,
        [BankIDIDR] varchar(3) NOT NULL,
        [GroupIDUSD] varchar(2) NOT NULL,
        [BankIDUSD] varchar(3) NOT NULL,
        [GroupRate] varchar(1) NOT NULL,
        [InstallmentNo] smallint NOT NULL,
        [DownPaymentNo] smallint NOT NULL,
        [IsExhibition] bit NOT NULL,
        [IsStoreClosed] bit NOT NULL,
        [DateClosed] datetime NOT NULL,
        [Description] text NOT NULL,
        [MarketingExecutive] varchar(50) NOT NULL,
        [IsVAT] bit NOT NULL,
        [IsLocalCompany] bit NOT NULL,
        [CompanyRegistrationNo] varchar(30) NOT NULL,
        [SSTNo] varchar(30) NOT NULL,
        [IncomeTaxRegNo] varchar(30) NOT NULL,
        [BankID] varchar(3) NOT NULL,
        [SwiftCode] varchar(50) NOT NULL,
        [BankAccount] varchar(50) NOT NULL,
        [BeneficiaryName] varchar(50) NOT NULL,
        [IsInternationalOrganisation] bit NOT NULL,
        [EntryUser] varchar(50) NOT NULL,
        [EntryDate] datetime NOT NULL,
        [UpdateUser] varchar(50) NOT NULL,
        [UpdateDate] datetime NOT NULL,
        [IsJOTenant] bit NOT NULL,
        CONSTRAINT [PK_THD_M_GeneralInformation] PRIMARY KEY CLUSTERED
        (
            [CompanyID] ASC,
            [LocationID] ASC,
            [TenantID] ASC
        )
    ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
END;
GO

/* Defaults supplied by the source master schema. */
IF OBJECT_ID(N'dbo.THD_M_GeneralInformation', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_NITKU')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_NITKU] DEFAULT ('') FOR [NITKU];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_NPWPNIK')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_NPWPNIK] DEFAULT ('') FOR [NPWPNIK];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_IsLocalCompany')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_IsLocalCompany] DEFAULT ((1)) FOR [IsLocalCompany];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_CompanyRegistrationNo')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_CompanyRegistrationNo] DEFAULT ('') FOR [CompanyRegistrationNo];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_SSTNo')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_SSTNo] DEFAULT ('') FOR [SSTNo];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_IncomeTaxRegNo')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_IncomeTaxRegNo] DEFAULT ('') FOR [IncomeTaxRegNo];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_BankID')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_BankID] DEFAULT ('') FOR [BankID];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_SwiftCode')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_SwiftCode] DEFAULT ('') FOR [SwiftCode];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_BankAccount')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_BankAccount] DEFAULT ('') FOR [BankAccount];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_BeneficiaryName')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_BeneficiaryName] DEFAULT ('') FOR [BeneficiaryName];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_IsInternationalOrganisation')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_IsInternationalOrganisation] DEFAULT ((0)) FOR [IsInternationalOrganisation];

    IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_THD_M_GeneralInformation_IsJOTenant')
        ALTER TABLE [dbo].[THD_M_GeneralInformation] ADD CONSTRAINT [DF_THD_M_GeneralInformation_IsJOTenant] DEFAULT ((1)) FOR [IsJOTenant];
END;
GO

/* ============================================================
   INSPEC lookup contract
   ============================================================ */

-- 1. Tenant list for the logged-in CompanyID + LocationID.
SELECT
    a.TenantID,
    a.TenantName
FROM dbo.THD_M_GeneralInformation AS a
WHERE
    (a.IsStoreClosed = 0 OR a.DateClosed > GETDATE())
    AND a.CompanyID = @CompanyID
    AND a.LocationID = @LocationID
ORDER BY
    a.TenantName,
    a.TenantID;
GO

-- 2. Suite list for the selected tenant.
--    TenantID must be included; otherwise suites belonging to other tenants
--    will also appear in the dropdown.
SELECT
    a.TenantID,
    a.SuiteNo
FROM dbo.THD_M_AgreementInformation AS a
WHERE
    a.CompanyID = @CompanyID
    AND a.LocationID = @LocationID
    AND a.TenantID = @TenantID
    AND a.LeaseTermDate >= GETDATE()
ORDER BY
    a.SuiteNo;
GO

/*
    INSPEC implementation notes:
    - PIP_M_InspectionTypeDetail.IsTenantInspection = 1 means TenantID and SuiteNo
      are mandatory when creating an inspection for that detail.
    - Validate the selected pair against THD_M_AgreementInformation using
      CompanyID + LocationID + TenantID + SuiteNo.
    - Duplicate-inspection identity must include TenantID + SuiteNo when
      IsTenantInspection = 1. Non-tenant inspection duplicate behavior stays unchanged.
    - Keep TenantID and SuiteNo as transaction snapshot values so historical
      inspections remain identifiable if master tenant/agreement data changes.
*/
