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
            if (
                Context.User != null
                && Context.User.Identity != null
                && Context.User.Identity.IsAuthenticated
            )
                ViewStateUserKey = Context.User.Identity.Name;
            base.OnInit(e);
        }
        protected void Page_Load(object sender, EventArgs e)
        {
            if (base.AllowRead(MenuID) == 2)
                throw new HttpException(403, WAL.GF.MSG_ACCESS_DENIED);
            GFC.RequireCompanyLocation(
                Master.Mn_EmployeeID,
                Master.Mn_CompanyID,
                Master.Mn_LocationID
            );
            EnsureAdministrator();
            pnlSmtpWarning.Visible = String.IsNullOrWhiteSpace(
                ConfigurationManager.AppSettings["smtpHost"]
            );
            PrepareEmployeeSearch();
            if (IsPostBack)
            {
                lblChiefEngName.Text = GetEmployeeName(txtChiefEng.Text.Trim());
                lblChiefSecName.Text = GetEmployeeName(txtChiefSec.Text.Trim());
                lblSPVName.Text = GetEmployeeName(txtSPV.Text.Trim());
            }
            if (!IsPostBack)
            {
                Master.Mn_lit_Title = WAL.PB.AppID + " -> Inspection Email & Approval Routing";
                BindSections();
                LoadHeader();
                LoadEmailModeSettings();
                BindSPVGrid();
                ClearSPVEditor();
            }
        }
        private bool IsAdministrator()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable d = br.EQueryP(
                    @"SELECT CASE WHEN EXISTS(SELECT 1 FROM dbo.SysWebUserUserGroup WHERE UserID=@U AND UserGroupID='administrator') THEN 1 ELSE 0 END AS IsAdmin",
                    new SqlParameter[] { new SqlParameter("@U", Master.Mn_EmployeeID) }
                );
                return d.Rows.Count > 0 && Convert.ToInt32(d.Rows[0]["IsAdmin"]) == 1;
            }
        }
        private void EnsureAdministrator()
        {
            if (!IsAdministrator())
                throw new HttpException(
                    403,
                    "Only INSPEC administrators can change approval routing."
                );
        }
        private string Scope
        {
            get
            {
                return Convert.ToString(Master.Mn_CompanyID)
                    + Convert.ToString(Master.Mn_LocationID);
            }
        }
        private void PrepareEmployeeSearch()
        {
            string c = Master.Mn_CompanyID + GF.Str;
            lBtnChiefEng.Attributes["onclick"] = GF.JSOpenSearchList_2(
                "330",
                "Chief Engineering",
                txtChiefEng.ClientID,
                false,
                c + ";PENG" + GF.Str + ";" + GF.Str 
            );
            txtChiefEng.Attributes["onkeydown"] = GF.JSOpenSearchList_2(
                "330",
                "Chief Engineering",
                txtChiefEng.ClientID,
                true,
                c + ";PENG" + GF.Str + ";" + GF.Str 
            );
            lBtnChiefSec.Attributes["onclick"] = GF.JSOpenSearchList_2(
                "330",
                "Chief Security",
                txtChiefSec.ClientID,
                false,
                c + ";PSEC" + GF.Str + ";" + GF.Str 
            );
            txtChiefSec.Attributes["onkeydown"] = GF.JSOpenSearchList_2(
                "330",
                "Chief Security",
                txtChiefSec.ClientID,
                true,
                c + ";PSEC" + GF.Str + ";" + GF.Str 
            );
            lBtnSPV.Enabled = !String.IsNullOrWhiteSpace(ddlSection.SelectedValue);
            lBtnSPV.Attributes["onclick"] = GF.JSOpenSearchList_2(
                "330",
                "SPV per Section",
                txtSPV.ClientID,
                false,
                c + ";" + GF.Str + ";" + ddlSection.ClientID
            );
            txtSPV.Attributes["onkeydown"] = GF.JSOpenSearchList_2(
                "330",
                "SPV per Section",
                txtSPV.ClientID,
                true,
                c + ";" + GF.Str + ";" + ddlSection.ClientID
            );
        }
        private void BindSections()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable d = br.EQueryP(
                    @"SELECT DISTINCT S.SectionID FROM dbo.PIP_M_Section S WHERE EXISTS(SELECT 1 FROM dbo.PIP_M_InspectionType T WHERE T.SectionID=S.SectionID) AND EXISTS(SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.SectionID=S.SectionID AND E.CompanyID=@C AND ISNULL(E.TerminationDate,'')='') ORDER BY S.SectionID",
                    new SqlParameter[] { new SqlParameter("@C", Master.Mn_CompanyID) }
                );
                ddlSection.Items.Clear();
                ddlSection.Items.Add(new ListItem("-- Pilih Section --", ""));
                foreach (DataRow r in d.Rows)
                {
                    string v = Convert.ToString(r["SectionID"]);
                    ddlSection.Items.Add(new ListItem(v, v));
                }
            }
        }
        private string GetCommonValue(string id)
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable d = br.EQueryP(
                    @"SELECT TOP 1 Description FROM dbo.SysWebCommonValue WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ID AND IsDelete=0",
                    new SqlParameter[] { new SqlParameter("@ID", id) }
                );
                return d.Rows.Count == 0 ? "" : Convert.ToString(d.Rows[0]["Description"]).Trim();
            }
        }
        private string GetEmployeeName(string id)
        {
            if (id == "")
                return "";
            using (var br = new WAL.BR.CF())
            {
                DataTable d = br.EQueryP(
                    @"SELECT TOP 1 Name FROM dbo.M_HRD_Employee WHERE EmployeeID=@ID AND CompanyID=@C AND ISNULL(TerminationDate,'')=''",
                    new SqlParameter[]
                    {
                        new SqlParameter("@ID", id),
                        new SqlParameter("@C", Master.Mn_CompanyID)
                    }
                );
                return d.Rows.Count == 0 ? "" : Convert.ToString(d.Rows[0]["Name"]);
            }
        }
        private void LoadHeader()
        {
            txtChiefEng.Text = GetCommonValue(Scope + ";CHIEF_ENG");
            txtChiefSec.Text = GetCommonValue(Scope + ";CHIEF_SEC");
            lblChiefEngName.Text = GetEmployeeName(txtChiefEng.Text);
            lblChiefSecName.Text = GetEmployeeName(txtChiefSec.Text);
        }
        private void LoadEmailModeSettings()
        {
            chkEmailStandard.Checked = GetCommonValue(Scope + ";EMAIL;STANDARD") == "1";
            chkEmailBatch.Checked = GetCommonValue(Scope + ";EMAIL;BATCH") == "1";
            string v = GetCommonValue(Scope + ";EMAIL;LIGHTNING");
            chkEmailLightning.Checked = v == "" || v == "1";
        }
        private void SaveCommonValue(string id, string val)
        {
            using (var br = new WAL.BR.CF())
            {
                br.EQueryP(
                    @"IF EXISTS(SELECT 1 FROM dbo.SysWebCommonValue WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ID) UPDATE dbo.SysWebCommonValue SET Description=@V,IsDelete=0,IsSystem=0,GroupDescription='INSPEC Inspection Email Approval',UpdateUser=LEFT(@U,10),UpdateDate=GETDATE() WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ID; ELSE INSERT dbo.SysWebCommonValue(AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate) VALUES('INSPEC',@ID,@V,'EmailApproval','INSPEC Inspection Email Approval',0,0,LEFT(@U,10),GETDATE(),LEFT(@U,10),GETDATE());",
                    new SqlParameter[]
                    {
                        new SqlParameter("@ID", id),
                        new SqlParameter("@V", val ?? ""),
                        new SqlParameter("@U", Master.Mn_EmployeeID)
                    }
                );
            }
        }
        protected void btnSaveHeader_Click(object sender, EventArgs e)
        {
            try
            {
                EnsureAdministrator();
                string ce = txtChiefEng.Text.Trim(),
                    cs = txtChiefSec.Text.Trim();
                if (ce == "" || cs == "")
                    throw new InvalidOperationException(
                        "Pilih NIK Chief Engineering dan Chief Security."
                    );
                if (ce == cs)
                    throw new InvalidOperationException("Chief Approver harus employee berbeda.");
                using (var br = new WAL.BR.CF())
                {
                    br.EQueryP(
                        @"IF NOT EXISTS(SELECT 1 FROM dbo.M_HRD_Employee WHERE EmployeeID=@E AND CompanyID=@C AND ISNULL(TerminationDate,'')='' AND ProfitCenterNo='PENG') RAISERROR('Chief Engineering wajib employee aktif Company ini dengan ProfitCenterNo PENG.',16,1); IF NOT EXISTS(SELECT 1 FROM dbo.M_HRD_Employee WHERE EmployeeID=@S AND CompanyID=@C AND ISNULL(TerminationDate,'')='' AND ProfitCenterNo='PSEC') RAISERROR('Chief Security wajib employee aktif Company ini dengan ProfitCenterNo PSEC.',16,1);",
                        new SqlParameter[]
                        {
                            new SqlParameter("@E", ce),
                            new SqlParameter("@S", cs),
                            new SqlParameter("@C", Master.Mn_CompanyID)
                        }
                    );
                }
                SaveCommonValue(Scope + ";CHIEF_ENG", ce);
                SaveCommonValue(Scope + ";CHIEF_SEC", cs);
                LoadHeader();
                ShowMessage("Chief approver berhasil disimpan.", false);
            }
            catch (Exception ex)
            {
                ShowMessage(ex.Message, true);
            }
        }
        protected void btnSaveEmailMode_Click(object sender, EventArgs e)
        {
            try
            {
                EnsureAdministrator();
                SaveCommonValue(Scope + ";EMAIL;STANDARD", chkEmailStandard.Checked ? "1" : "0");
                SaveCommonValue(Scope + ";EMAIL;BATCH", chkEmailBatch.Checked ? "1" : "0");
                SaveCommonValue(Scope + ";EMAIL;LIGHTNING", chkEmailLightning.Checked ? "1" : "0");
                ShowMessage("Email settings berhasil disimpan.", false);
            }
            catch (Exception ex)
            {
                ShowMessage(ex.Message, true);
            }
        }
        private void BindSPVGrid()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable d = br.EQueryP(
                    @"SELECT SUBSTRING(C.ID,LEN(@P)+6,100) SectionID,C.Description EmployeeID,E.Name EmployeeName FROM dbo.SysWebCommonValue C INNER JOIN dbo.M_HRD_Employee E ON E.EmployeeID=C.Description AND E.CompanyID=@C AND ISNULL(E.TerminationDate,'')='' AND E.SectionID=SUBSTRING(C.ID,LEN(@P)+6,100) WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID LIKE @P+';SPV;%' ORDER BY C.ID",
                    new SqlParameter[]
                    {
                        new SqlParameter("@P", Scope),
                        new SqlParameter("@C", Master.Mn_CompanyID)
                    }
                );
                gvSPV.DataSource = d;
                gvSPV.DataBind();
            }
        }
        protected void btnSaveSPV_Click(object sender, EventArgs e)
        {
            try
            {
                EnsureAdministrator();
                string sec = ddlSection.SelectedValue,
                    spv = txtSPV.Text.Trim(),
                    old = hidSPVOriginalSection.Value;
                if (sec == "" || spv == "")
                    throw new InvalidOperationException("Pilih Section dan NIK SPV.");
                using (var br = new WAL.BR.CF())
                {
                    DataTable d = br.EQueryP(
                        @"SELECT COUNT(1) Cnt FROM dbo.M_HRD_Employee WHERE EmployeeID=@E AND CompanyID=@C AND SectionID=@S AND ISNULL(TerminationDate,'')=''",
                        new SqlParameter[]
                        {
                            new SqlParameter("@E", spv),
                            new SqlParameter("@C", Master.Mn_CompanyID),
                            new SqlParameter("@S", sec)
                        }
                    );
                    if (d.Rows.Count == 0 || Convert.ToInt32(d.Rows[0]["Cnt"]) != 1)
                        throw new InvalidOperationException(
                            "SPV harus employee aktif pada Company dan Section terpilih."
                        );
                    if (old != "" && old != sec)
                        br.EQueryP(
                            @"UPDATE dbo.SysWebCommonValue SET IsDelete=1,UpdateUser=LEFT(@U,10),UpdateDate=GETDATE() WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ID",
                            new SqlParameter[]
                            {
                                new SqlParameter("@U", Master.Mn_EmployeeID),
                                new SqlParameter("@ID", Scope + ";SPV;" + old)
                            }
                        );
                }
                SaveCommonValue(Scope + ";SPV;" + sec, spv);
                ClearSPVEditor();
                BindSPVGrid();
                ShowMessage("Mapping SPV tersimpan.", false);
            }
            catch (Exception ex)
            {
                ShowMessage(ex.Message, true);
            }
        }
        protected void gvSPV_RowCommand(object sender, GridViewCommandEventArgs e)
        {
            try
            {
                EnsureAdministrator();
                string sec = Convert.ToString(e.CommandArgument);
                if (e.CommandName == "EditMapping")
                {
                    ddlSection.SelectedValue = sec;
                    txtSPV.Text = GetCommonValue(Scope + ";SPV;" + sec);
                    lblSPVName.Text = GetEmployeeName(txtSPV.Text);
                    hidSPVOriginalSection.Value = sec;
                    btnSaveSPV.Text = "Update Mapping";
                }
                else if (e.CommandName == "DeleteMapping")
                {
                    using (var br = new WAL.BR.CF())
                        br.EQueryP(
                            @"UPDATE dbo.SysWebCommonValue SET IsDelete=1,UpdateUser=LEFT(@U,10),UpdateDate=GETDATE() WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ID",
                            new SqlParameter[]
                            {
                                new SqlParameter("@U", Master.Mn_EmployeeID),
                                new SqlParameter("@ID", Scope + ";SPV;" + sec)
                            }
                        );
                    ClearSPVEditor();
                    BindSPVGrid();
                    ShowMessage("Mapping SPV dihapus.", false);
                }
            }
            catch (Exception ex)
            {
                ShowMessage(ex.Message, true);
            }
            PrepareEmployeeSearch();
        }
        protected void btnNewSPV_Click(object sender, EventArgs e)
        {
            ClearSPVEditor();
            PrepareEmployeeSearch();
        }
        protected void btnCancelSPV_Click(object sender, EventArgs e)
        {
            ClearSPVEditor();
            PrepareEmployeeSearch();
        }
        protected void ddlSection_SelectedIndexChanged(object sender, EventArgs e)
        {
            txtSPV.Text = "";
            lblSPVName.Text = "";
            hidSPVOriginalSection.Value = "";
            PrepareEmployeeSearch();
        }
        private void ClearSPVEditor()
        {
            hidSPVOriginalSection.Value = "";
            txtSPV.Text = "";
            lblSPVName.Text = "";
            btnSaveSPV.Text = "Save Mapping";
            if (ddlSection.Items.Count > 0)
                ddlSection.SelectedIndex = 0;
            PrepareEmployeeSearch();
        }
        private void ShowMessage(string m, bool err)
        {
            pnlMessage.Visible = true;
            pnlMessage.CssClass = err ? "alert alert-danger mb-3" : "alert alert-success mb-3";
            litMessage.Text = Server.HtmlEncode(m ?? "");
        }
    }
}
