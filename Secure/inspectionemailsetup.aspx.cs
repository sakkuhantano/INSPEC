using System;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    public partial class inspectionemailsetup : WAL.PB
    {
        private const string MenuID = "10013";

        protected override void OnInit(EventArgs e)
        {
            if (Context.User != null && Context.User.Identity != null && Context.User.Identity.IsAuthenticated)
                ViewStateUserKey = Context.User.Identity.Name;
            base.OnInit(e);
        }

        protected void Page_Load(object sender, EventArgs e)
        {
            if (base.AllowRead(MenuID) == 2)
                throw new HttpException(403, WAL.GF.MSG_ACCESS_DENIED);
            GFC.RequireCompanyLocation(Master.Mn_EmployeeID, Master.Mn_CompanyID, Master.Mn_LocationID);
            if (!IsAdministrator())
                throw new HttpException(403, "Only INSPEC administrators can change inspection email routing.");

            pnlSmtpWarning.Visible =
                String.IsNullOrWhiteSpace(ConfigurationManager.AppSettings["smtpHost"]) ||
                String.IsNullOrWhiteSpace(ConfigurationManager.AppSettings["smtpFrom"]);

            if (!IsPostBack)
            {
                Master.Mn_lit_Title = WAL.PB.AppID + " -> Inspection Email & Approval Routing";
                BindPage();
            }
        }

        private bool IsAdministrator()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT CASE WHEN EXISTS
(
    SELECT 1 FROM dbo.SysWebUserUserGroup
    WHERE UserID=@UserID AND UserGroupID='administrator'
) THEN 1 ELSE 0 END AS IsAdmin",
                    new SqlParameter[] { new SqlParameter("@UserID", Master.Mn_EmployeeID) });
                return dt.Rows.Count > 0 && Convert.ToInt32(dt.Rows[0]["IsAdmin"]) == 1;
            }
        }

        private void BindPage()
        {
            BindSections();
            BindChiefSections();
            LoadHeader();
            LoadEmailModeSettings();
            BindSPVEmployees();
            LoadSectionSPV();
        }

        private void BindSections()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT DISTINCT S.SectionID
FROM dbo.PIP_M_Section S
WHERE EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionType IT WHERE IT.SectionID=S.SectionID)
  AND EXISTS (
      SELECT 1 FROM dbo.M_HRD_Employee E
      WHERE E.SectionID=S.SectionID AND E.CompanyID=@CompanyID AND ISNULL(E.TerminationDate,'')=''
        AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
                    WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@CompanyID
                      AND CL.LocationID=@LocationID)
  )
ORDER BY S.SectionID",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });
                ddlSection.Items.Clear();
                ddlSection.Items.Add(new ListItem("-- Pilih Section --", ""));
                foreach (DataRow row in dt.Rows)
                    ddlSection.Items.Add(new ListItem(Convert.ToString(row["SectionID"]), Convert.ToString(row["SectionID"])));
            }
        }

        private void BindChiefSections()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT DISTINCT S.SectionID,S.Description
FROM dbo.PIP_M_Section S
INNER JOIN dbo.M_HRD_Employee E ON E.SectionID=S.SectionID
WHERE E.CompanyID=@CompanyID AND ISNULL(E.TerminationDate,'')=''
  AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
              WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@CompanyID
                AND CL.LocationID=@LocationID)
  AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU
              WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
ORDER BY S.SectionID",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });
                foreach (DropDownList list in new[] { ddlChiefEngSection, ddlChiefSecSection })
                {
                    list.Items.Clear();
                    list.Items.Add(new ListItem("-- Pilih Section --", ""));
                    foreach (DataRow row in dt.Rows)
                        list.Items.Add(new ListItem(Convert.ToString(row["SectionID"]) + " - " +
                            Convert.ToString(row["Description"]), Convert.ToString(row["SectionID"])));
                }
            }
        }

        private void BindChiefEmployees()
        {
            BindEmployees(ddlChiefEng, ddlChiefEngSection.SelectedValue);
            BindEmployees(ddlChiefSec, ddlChiefSecSection.SelectedValue);
        }

        private void BindSPVEmployees()
        {
            BindEmployees(ddlSPV, ddlSection.SelectedValue);
        }

        private void BindEmployees(DropDownList target, string sectionID)
        {
            target.Items.Clear();
            target.Items.Add(new ListItem("-- Pilih Employee --", ""));
            if (String.IsNullOrWhiteSpace(sectionID)) return;
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT E.EmployeeID,E.Name,ISNULL(E.emailaddress,'') AS EmailAddress
FROM dbo.M_HRD_Employee E
WHERE E.CompanyID=@CompanyID AND E.SectionID=@SectionID
  AND ISNULL(E.TerminationDate,'')=''
  AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
              WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@CompanyID
                AND CL.LocationID=@LocationID)
  AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU
              WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
ORDER BY E.Name,E.EmployeeID",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@SectionID", sectionID)
                    });
                foreach (DataRow row in dt.Rows)
                {
                    string employeeID = Convert.ToString(row["EmployeeID"]);
                    string name = Convert.ToString(row["Name"]);
                    string email = Convert.ToString(row["EmailAddress"]).Trim();
                    string label = name + " (" + employeeID + ") - " +
                        (email == "" ? "EMAIL BELUM DIISI" : email);
                    target.Items.Add(new ListItem(label, employeeID));
                }
            }
        }

        private string GetConfigScope()
        {
            return Convert.ToString(Master.Mn_CompanyID) + Convert.ToString(Master.Mn_LocationID);
        }

        private string GetCommonValue(string id)
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT TOP 1 Description
FROM dbo.SysWebCommonValue
WHERE AppID='INSPEC' AND CommonGroup='EmailApproval'
  AND ID=@ID AND IsDelete=0",
                    new SqlParameter[] { new SqlParameter("@ID", id) });
                return dt.Rows.Count == 0 ? "" : Convert.ToString(dt.Rows[0]["Description"]).Trim();
            }
        }

        private void LoadHeader()
        {
            string scope = GetConfigScope();
            string chiefEng = GetCommonValue(scope + ";CHIEF_ENG");
            string chiefSec = GetCommonValue(scope + ";CHIEF_SEC");

            string chiefEngSection = "";
            string chiefSecSection = "";
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT EmployeeID,SectionID
FROM dbo.M_HRD_Employee
WHERE EmployeeID IN (@ChiefEng,@ChiefSec) AND CompanyID=@CompanyID",
                    new SqlParameter[] {
                        new SqlParameter("@ChiefEng", chiefEng),
                        new SqlParameter("@ChiefSec", chiefSec),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID)
                    });
                foreach (DataRow row in dt.Rows)
                {
                    if (String.Equals(Convert.ToString(row["EmployeeID"]), chiefEng, StringComparison.OrdinalIgnoreCase))
                        chiefEngSection = Convert.ToString(row["SectionID"]);
                    if (String.Equals(Convert.ToString(row["EmployeeID"]), chiefSec, StringComparison.OrdinalIgnoreCase))
                        chiefSecSection = Convert.ToString(row["SectionID"]);
                }
            }

            SelectIfPresent(ddlChiefEngSection, chiefEngSection);
            SelectIfPresent(ddlChiefSecSection, chiefSecSection);
            BindChiefEmployees();
            SelectIfPresent(ddlChiefEng, chiefEng);
            SelectIfPresent(ddlChiefSec, chiefSec);
        }

        private void LoadEmailModeSettings()
        {
            string scope = GetConfigScope();
            chkEmailStandard.Checked = GetCommonValue(scope + ";EMAIL;STANDARD") == "1";
            chkEmailBatch.Checked = GetCommonValue(scope + ";EMAIL;BATCH") == "1";
            string lightning = GetCommonValue(scope + ";EMAIL;LIGHTNING");
            chkEmailLightning.Checked = lightning == "" || lightning == "1";
        }

        private void LoadSectionSPV()
        {
            if (String.IsNullOrWhiteSpace(ddlSection.SelectedValue)) return;
            string employeeID = GetCommonValue(GetConfigScope() + ";SPV;" + ddlSection.SelectedValue);
            SelectIfPresent(ddlSPV, employeeID);
        }

        private static void SelectIfPresent(DropDownList list, string value)
        {
            ListItem item = list.Items.FindByValue(value);
            if (item != null) list.SelectedValue = value;
        }

        protected void ddlChiefEngSection_SelectedIndexChanged(object sender, EventArgs e)
        {
            BindEmployees(ddlChiefEng, ddlChiefEngSection.SelectedValue);
        }

        protected void ddlChiefSecSection_SelectedIndexChanged(object sender, EventArgs e)
        {
            BindEmployees(ddlChiefSec, ddlChiefSecSection.SelectedValue);
        }

        protected void ddlSection_SelectedIndexChanged(object sender, EventArgs e)
        {
            BindSPVEmployees();
            LoadSectionSPV();
        }

        private void SaveCommonValue(string id, string description)
        {
            using (var br = new WAL.BR.CF())
            {
                br.EQueryP(@"
IF EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ID
)
    UPDATE dbo.SysWebCommonValue
    SET Description=@Description,IsDelete=0,IsSystem=0,
        GroupDescription='INSPEC Inspection Email Approval',
        UpdateUser=LEFT(@UserID,10),UpdateDate=GETDATE()
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ID;
ELSE
    INSERT dbo.SysWebCommonValue
    (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    VALUES
    ('INSPEC',@ID,@Description,'EmailApproval','INSPEC Inspection Email Approval',0,0,
     LEFT(@UserID,10),GETDATE(),LEFT(@UserID,10),GETDATE());",
                    new SqlParameter[] {
                        new SqlParameter("@ID", id),
                        new SqlParameter("@Description", description ?? ""),
                        new SqlParameter("@UserID", Master.Mn_EmployeeID)
                    });
            }
        }

        protected void btnSaveHeader_Click(object sender, EventArgs e)
        {
            try
            {
                EnsureAdministrator();
                if (String.IsNullOrWhiteSpace(ddlChiefEngSection.SelectedValue) ||
                    String.IsNullOrWhiteSpace(ddlChiefSecSection.SelectedValue) ||
                    String.IsNullOrWhiteSpace(ddlChiefEng.SelectedValue) ||
                    String.IsNullOrWhiteSpace(ddlChiefSec.SelectedValue))
                    throw new InvalidOperationException("Pilih section dan employee Chief Engineering serta Chief Security.");
                if (String.Equals(ddlChiefEng.SelectedValue, ddlChiefSec.SelectedValue, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Chief Engineering dan Chief Security harus dua employee yang berbeda.");

                using (var br = new WAL.BR.CF())
                {
                    br.EQueryP(@"
IF NOT EXISTS
(
    SELECT 1 FROM dbo.M_HRD_Employee E
    WHERE E.EmployeeID=@ChiefEng AND E.CompanyID=@CompanyID
      AND E.SectionID=@ChiefEngSectionID AND ISNULL(E.TerminationDate,'')=''
      AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
                  WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@CompanyID
                    AND CL.LocationID=@LocationID)
      AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU
                  WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                    AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
)
    RAISERROR('Chief Engineering harus employee aktif pada section terpilih dan memiliki akses approval.',16,1);

IF NOT EXISTS
(
    SELECT 1 FROM dbo.M_HRD_Employee E
    WHERE E.EmployeeID=@ChiefSec AND E.CompanyID=@CompanyID
      AND E.SectionID=@ChiefSecSectionID AND ISNULL(E.TerminationDate,'')=''
      AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
                  WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@CompanyID
                    AND CL.LocationID=@LocationID)
      AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU
                  WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                    AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
)
    RAISERROR('Chief Security harus employee aktif pada section terpilih dan memiliki akses approval.',16,1);

BEGIN TRANSACTION;
IF EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ChiefEngKey
)
    UPDATE dbo.SysWebCommonValue
    SET Description=@ChiefEng,IsDelete=0,UpdateUser=LEFT(@UserID,10),UpdateDate=GETDATE()
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ChiefEngKey;
ELSE
    INSERT dbo.SysWebCommonValue
    (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    VALUES ('INSPEC',@ChiefEngKey,@ChiefEng,'EmailApproval','INSPEC Inspection Email Approval',0,0,
            LEFT(@UserID,10),GETDATE(),LEFT(@UserID,10),GETDATE());

IF EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ChiefSecKey
)
    UPDATE dbo.SysWebCommonValue
    SET Description=@ChiefSec,IsDelete=0,UpdateUser=LEFT(@UserID,10),UpdateDate=GETDATE()
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ChiefSecKey;
ELSE
    INSERT dbo.SysWebCommonValue
    (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    VALUES ('INSPEC',@ChiefSecKey,@ChiefSec,'EmailApproval','INSPEC Inspection Email Approval',0,0,
            LEFT(@UserID,10),GETDATE(),LEFT(@UserID,10),GETDATE());
COMMIT TRANSACTION;",
                        new SqlParameter[] {
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@LocationID", Master.Mn_LocationID),
                            new SqlParameter("@ChiefEngSectionID", ddlChiefEngSection.SelectedValue),
                            new SqlParameter("@ChiefEng", ddlChiefEng.SelectedValue),
                            new SqlParameter("@ChiefSecSectionID", ddlChiefSecSection.SelectedValue),
                            new SqlParameter("@ChiefSec", ddlChiefSec.SelectedValue),
                            new SqlParameter("@ChiefEngKey", GetConfigScope() + ";CHIEF_ENG"),
                            new SqlParameter("@ChiefSecKey", GetConfigScope() + ";CHIEF_SEC"),
                            new SqlParameter("@UserID", Master.Mn_EmployeeID)
                        });
                }
                ShowMessage("Routing Chief Engineering dan Chief Security berhasil disimpan ke SysWebCommonValue.", false);
                BindPage();
            }
            catch (Exception ex) { ShowMessage(ex.Message, true); }
        }

        protected void btnSaveEmailMode_Click(object sender, EventArgs e)
        {
            try
            {
                EnsureAdministrator();
                SaveCommonValue(GetConfigScope() + ";EMAIL;STANDARD", chkEmailStandard.Checked ? "1" : "0");
                SaveCommonValue(GetConfigScope() + ";EMAIL;BATCH", chkEmailBatch.Checked ? "1" : "0");
                SaveCommonValue(GetConfigScope() + ";EMAIL;LIGHTNING", chkEmailLightning.Checked ? "1" : "0");
                ShowMessage("Pengaturan email berhasil disimpan. Approval tetap online.", false);
                BindPage();
            }
            catch (Exception ex) { ShowMessage(ex.Message, true); }
        }

        protected void btnSaveSPV_Click(object sender, EventArgs e)
        {
            try
            {
                EnsureAdministrator();
                if (String.IsNullOrWhiteSpace(ddlSection.SelectedValue) ||
                    String.IsNullOrWhiteSpace(ddlSPV.SelectedValue))
                    throw new InvalidOperationException("Pilih Section dan SPV Employee.");

                using (var br = new WAL.BR.CF())
                {
                    br.EQueryP(@"
IF NOT EXISTS
(
    SELECT 1 FROM dbo.M_HRD_Employee E
    WHERE E.EmployeeID=@SPV AND E.CompanyID=@CompanyID
      AND E.SectionID=@SectionID AND ISNULL(E.TerminationDate,'')=''
      AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
                  WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@CompanyID
                    AND CL.LocationID=@LocationID)
      AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                  AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
)
    RAISERROR('SPV harus employee aktif pada Company, Location, Section dan memiliki akses approval.',16,1);

IF EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@SPVKey
)
    UPDATE dbo.SysWebCommonValue
    SET Description=@SPV,IsDelete=0,UpdateUser=LEFT(@UserID,10),UpdateDate=GETDATE()
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@SPVKey;
ELSE
    INSERT dbo.SysWebCommonValue
    (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    VALUES ('INSPEC',@SPVKey,@SPV,'EmailApproval','INSPEC Inspection Email Approval',0,0,
            LEFT(@UserID,10),GETDATE(),LEFT(@UserID,10),GETDATE());",
                        new SqlParameter[] {
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@LocationID", Master.Mn_LocationID),
                            new SqlParameter("@SectionID", ddlSection.SelectedValue),
                            new SqlParameter("@SPV", ddlSPV.SelectedValue),
                            new SqlParameter("@SPVKey", GetConfigScope() + ";SPV;" + ddlSection.SelectedValue),
                            new SqlParameter("@UserID", Master.Mn_EmployeeID)
                        });
                }
                ShowMessage("Pemetaan SPV untuk Section berhasil disimpan ke SysWebCommonValue.", false);
                string selectedSection = ddlSection.SelectedValue;
                BindPage();
                SelectIfPresent(ddlSection, selectedSection);
                BindSPVEmployees();
                LoadSectionSPV();
            }
            catch (Exception ex) { ShowMessage(ex.Message, true); }
        }

        private void EnsureAdministrator()
        {
            GFC.RequireCompanyLocation(Master.Mn_EmployeeID, Master.Mn_CompanyID, Master.Mn_LocationID);
            if (!IsAdministrator())
                throw new HttpException(403, "Only INSPEC administrators can change inspection email routing.");
        }

        private void ShowMessage(string message, bool isError)
        {
            pnlMessage.Visible = true;
            pnlMessage.CssClass = isError ? "alert alert-danger mb-3" : "alert alert-success mb-3";
            litMessage.Text = Server.HtmlEncode(message ?? "");
        }
    }
}
