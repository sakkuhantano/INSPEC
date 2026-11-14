using System;
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
            BindChiefEmployees();
            LoadHeader();
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
ORDER BY S.SectionID");
                ddlSection.Items.Clear();
                ddlSection.Items.Add(new ListItem("-- Pilih Section --", ""));
                foreach (DataRow row in dt.Rows)
                    ddlSection.Items.Add(new ListItem(Convert.ToString(row["SectionID"]), Convert.ToString(row["SectionID"])));
            }
        }

        private void BindChiefEmployees()
        {
            BindEmployees(ddlChiefEng, "peng", null);
            BindEmployees(ddlChiefSec, "psec", null);
        }

        private void BindSPVEmployees()
        {
            BindEmployees(ddlSPV, null, ddlSection.SelectedValue);
        }

        private void BindEmployees(DropDownList target, string profitCenterNo, string sectionID)
        {
            target.Items.Clear();
            target.Items.Add(new ListItem("-- Pilih Employee --", ""));
            using (var br = new WAL.BR.CF())
            {
                DataTable dt;
                if (!String.IsNullOrWhiteSpace(profitCenterNo))
                {
                    dt = br.EQueryP(@"
SELECT DISTINCT E.EmployeeID, E.Name, ISNULL(E.emailaddress,'') AS EmailAddress
FROM dbo.M_HRD_Employee E
INNER JOIN dbo.PIP_M_Section S ON S.SectionID=E.SectionID
WHERE E.CompanyID=@CompanyID
  AND S.ProfitCenterNo=@ProfitCenterNo
  AND ISNULL(E.TerminationDate,'')=''
ORDER BY E.Name, E.EmployeeID",
                        new SqlParameter[] {
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@ProfitCenterNo", profitCenterNo)
                        });
                }
                else
                {
                    if (String.IsNullOrWhiteSpace(sectionID)) return;
                    dt = br.EQueryP(@"
SELECT E.EmployeeID, E.Name, ISNULL(E.emailaddress,'') AS EmailAddress
FROM dbo.M_HRD_Employee E
WHERE E.CompanyID=@CompanyID
  AND E.SectionID=@SectionID
  AND ISNULL(E.TerminationDate,'')=''
ORDER BY E.Name, E.EmployeeID",
                        new SqlParameter[] {
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@SectionID", sectionID)
                        });
                }

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

        private void LoadHeader()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT ChiefEngEmployeeID, ChiefSecEmployeeID
FROM dbo.PIP_M_InspectionEmailSetup
WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND IsActive=1",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });
                if (dt.Rows.Count > 0)
                {
                    SelectIfPresent(ddlChiefEng, Convert.ToString(dt.Rows[0]["ChiefEngEmployeeID"]));
                    SelectIfPresent(ddlChiefSec, Convert.ToString(dt.Rows[0]["ChiefSecEmployeeID"]));
                }
            }
        }

        private void LoadSectionSPV()
        {
            if (String.IsNullOrWhiteSpace(ddlSection.SelectedValue)) return;
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT SPVEmployeeID
FROM dbo.PIP_M_InspectionEmailSetupSection
WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID AND IsActive=1",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@SectionID", ddlSection.SelectedValue)
                    });
                if (dt.Rows.Count > 0)
                    SelectIfPresent(ddlSPV, Convert.ToString(dt.Rows[0]["SPVEmployeeID"]));
            }
        }

        private static void SelectIfPresent(DropDownList list, string value)
        {
            ListItem item = list.Items.FindByValue(value);
            if (item != null) list.SelectedValue = value;
        }

        protected void ddlSection_SelectedIndexChanged(object sender, EventArgs e)
        {
            BindSPVEmployees();
            LoadSectionSPV();
        }

        protected void btnSaveHeader_Click(object sender, EventArgs e)
        {
            try
            {
                EnsureAdministrator();
                if (String.IsNullOrWhiteSpace(ddlChiefEng.SelectedValue) ||
                    String.IsNullOrWhiteSpace(ddlChiefSec.SelectedValue))
                    throw new InvalidOperationException("Pilih Chief Engineering dan Chief Security.");

                using (var br = new WAL.BR.CF())
                {
                    br.EQueryP(@"
IF NOT EXISTS
(
    SELECT 1 FROM dbo.M_HRD_Employee E
    INNER JOIN dbo.PIP_M_Section S ON S.SectionID=E.SectionID
    WHERE E.EmployeeID=@ChiefEng AND E.CompanyID=@CompanyID
      AND S.ProfitCenterNo='peng' AND ISNULL(E.TerminationDate,'')=''
      AND LTRIM(RTRIM(ISNULL(E.emailaddress,'')))<>''
)
BEGIN
    RAISERROR('Chief Engineering harus employee aktif pada section Engineering dan memiliki email.',16,1);
    RETURN;
END;
IF NOT EXISTS
(
    SELECT 1 FROM dbo.M_HRD_Employee E
    INNER JOIN dbo.PIP_M_Section S ON S.SectionID=E.SectionID
    WHERE E.EmployeeID=@ChiefSec AND E.CompanyID=@CompanyID
      AND S.ProfitCenterNo='psec' AND ISNULL(E.TerminationDate,'')=''
      AND LTRIM(RTRIM(ISNULL(E.emailaddress,'')))<>''
)
BEGIN
    RAISERROR('Chief Security harus employee aktif pada section Security dan memiliki email.',16,1);
    RETURN;
END;

BEGIN TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionEmailSetup WHERE CompanyID=@CompanyID AND LocationID=@LocationID)
    UPDATE dbo.PIP_M_InspectionEmailSetup
    SET ChiefEngEmployeeID=@ChiefEng, ChiefSecEmployeeID=@ChiefSec,
        IsActive=1, UpdateUser=@UserID, UpdateDate=GETDATE()
    WHERE CompanyID=@CompanyID AND LocationID=@LocationID;
ELSE
    INSERT dbo.PIP_M_InspectionEmailSetup
    (CompanyID,LocationID,ChiefEngEmployeeID,ChiefSecEmployeeID,IsActive,EntryUser,UpdateUser)
    VALUES
    (@CompanyID,@LocationID,@ChiefEng,@ChiefSec,1,@UserID,@UserID);
COMMIT TRANSACTION",
                        new SqlParameter[] {
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@LocationID", Master.Mn_LocationID),
                            new SqlParameter("@ChiefEng", ddlChiefEng.SelectedValue),
                            new SqlParameter("@ChiefSec", ddlChiefSec.SelectedValue),
                            new SqlParameter("@UserID", Master.Mn_EmployeeID)
                        });
                }
                ShowMessage("Penerima Chief Engineering dan Chief Security berhasil disimpan.", false);
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
      AND LTRIM(RTRIM(ISNULL(E.emailaddress,'')))<>''
)
BEGIN
    RAISERROR('SPV harus employee aktif pada Company dan Section terpilih serta memiliki email.',16,1);
    RETURN;
END;
IF NOT EXISTS
(
    SELECT 1 FROM dbo.PIP_M_InspectionEmailSetup
    WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND IsActive=1
)
BEGIN
    RAISERROR('Simpan penerima Chief Engineering dan Chief Security terlebih dahulu.',16,1);
    RETURN;
END;

BEGIN TRANSACTION;
IF EXISTS
(
    SELECT 1 FROM dbo.PIP_M_InspectionEmailSetupSection
    WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID
)
    UPDATE dbo.PIP_M_InspectionEmailSetupSection
    SET SPVEmployeeID=@SPV, IsActive=1, UpdateUser=@UserID, UpdateDate=GETDATE()
    WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID;
ELSE
    INSERT dbo.PIP_M_InspectionEmailSetupSection
    (CompanyID,LocationID,SectionID,SPVEmployeeID,IsActive,EntryUser,UpdateUser)
    VALUES
    (@CompanyID,@LocationID,@SectionID,@SPV,1,@UserID,@UserID);
COMMIT TRANSACTION",
                        new SqlParameter[] {
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@LocationID", Master.Mn_LocationID),
                            new SqlParameter("@SectionID", ddlSection.SelectedValue),
                            new SqlParameter("@SPV", ddlSPV.SelectedValue),
                            new SqlParameter("@UserID", Master.Mn_EmployeeID)
                        });
                }
                ShowMessage("Pemetaan SPV untuk Section berhasil disimpan.", false);
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
