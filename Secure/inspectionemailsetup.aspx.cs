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
    public partial class inspectionemailsetup : WAL.PB, WAL.I_ToolBar_2
    {
        private const string MenuID = "10014";
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
            InitToolbar();
            pnlSmtpWarning.Visible = String.IsNullOrWhiteSpace(
                ConfigurationManager.AppSettings["smtpHost"]
            );
            PrepareEmployeeSearch();
            if (!IsPostBack)
            {
                BindSections();
                LoadHeader();
                LoadEmailModeSettings();
                BindSPVGrid();
                ClearSPVEditor();
            }
        }
        private void InitToolbar()
        {
            Master.TB_VisibleToolbar(true);
            Master.TB_VisibleButton(ToolbarItem_2.New, false);
            Master.TB_VisibleButton(ToolbarItem_2.Save, true);
            Master.TB_VisibleButton(ToolbarItem_2.Delete, false);
            Master.TB_VisibleButton(ToolbarItem_2.Previous, false);
            Master.TB_VisibleButton(ToolbarItem_2.Next, false);
        }
        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            if (e.ToolbarItem == ToolbarItem_2.Save)
                SaveAllSettings();
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
            return FindEmployeeName(id, "", "");
        }

        private string NormalizeEmployeeList(string value)
        {
            string[] parts = (value ?? "").Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries);
            var seen = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var result = new System.Collections.Generic.List<string>();
            foreach (string part in parts)
            {
                string id = part.Trim();
                if (id == "")
                    continue;
                if (!seen.Add(id))
                    throw new InvalidOperationException("NIK approval tidak boleh duplikat: " + id);
                result.Add(id);
            }
            return String.Join(";", result.ToArray());
        }

        private string GetEmployeeNames(string ids, string employeeFilter, string sectionId)
        {
            string normalized = NormalizeEmployeeList(ids);
            if (normalized == "")
                return "";
            var names = new System.Collections.Generic.List<string>();
            foreach (string id in normalized.Split(';'))
            {
                string name = FindEmployeeName(id, employeeFilter, sectionId);
                if (String.IsNullOrWhiteSpace(name))
                    return "";
                names.Add(id + " - " + name);
            }
            return String.Join("; ", names.ToArray());
        }

        private void ValidateEmployeeList(TextBox input, Label nameLabel, string employeeFilter, string sectionId, bool required)
        {
            string normalized = NormalizeEmployeeList(input.Text);
            input.Text = normalized;
            nameLabel.Text = "";
            if (normalized == "")
            {
                if (required)
                    throw new InvalidOperationException("NIK approval wajib diisi.");
                return;
            }

            string display = GetEmployeeNames(normalized, employeeFilter, sectionId);
            if (display == "")
                throw new InvalidOperationException("Salah satu NIK approval tidak ditemukan atau tidak memenuhi mapping.");
            nameLabel.Text = "Approver: " + display;
        }
        private string FindEmployeeName(string id, string employeeFilter, string sectionId)
        {
            id = (id ?? "").Trim();
            if (id == "")
                return "";
            using (var br = new WAL.BR.CF())
            {
                DataTable d = br.EQueryP(
                    @"SELECT TOP 1 Name FROM dbo.M_HRD_Employee WHERE EmployeeID=@ID AND CompanyID=@C AND ISNULL(TerminationDate,'')='' AND " + employeeFilter,
                    new SqlParameter[]
                    {
                        new SqlParameter("@ID", id),
                        new SqlParameter("@C", Master.Mn_CompanyID),
                        new SqlParameter("@S", sectionId ?? "")
                    }
                );
                return d.Rows.Count == 0 ? "" : Convert.ToString(d.Rows[0]["Name"]);
            }
        }
        private void ValidateEmployeeText(TextBox input, Label nameLabel, string employeeFilter, string sectionId)
        {
            string id = (input.Text ?? "").Trim();
            input.Text = id;
            nameLabel.Text = "";
            if (id == "")
                return;
            string name = FindEmployeeName(id, employeeFilter, sectionId);
            if (String.IsNullOrWhiteSpace(name))
            {
                GF.MsgBox(this, "Employee not found", "BS-5.3.0");
                return;
            }
            nameLabel.Text = "Name: " + name;
        }
        protected void txtChiefEng_TextChanged(object sender, EventArgs e)
        {
            try { ValidateEmployeeList(txtChiefEng, lblChiefEngName, "ProfitCenterNo='PENG'", "", true); }
            catch (Exception ex) { GF.MsgBox(this, ex.Message, "BS-5.3.0"); }
            PrepareEmployeeSearch();
        }
        protected void txtChiefSec_TextChanged(object sender, EventArgs e)
        {
            try { ValidateEmployeeList(txtChiefSec, lblChiefSecName, "ProfitCenterNo='PSEC'", "", true); }
            catch (Exception ex) { GF.MsgBox(this, ex.Message, "BS-5.3.0"); }
            PrepareEmployeeSearch();
        }
        protected void txtSPV_TextChanged(object sender, EventArgs e)
        {
            try { ValidateEmployeeList(txtSPV, lblSPVName, "SectionID=@S", ddlSection.SelectedValue, true); }
            catch (Exception ex) { GF.MsgBox(this, ex.Message, "BS-5.3.0"); }
            PrepareEmployeeSearch();
        }
        private void LoadHeader()
        {
            txtChiefEng.Text = GetCommonValue(Scope + ";CHIEF_ENG");
            txtChiefSec.Text = GetCommonValue(Scope + ";CHIEF_SEC");
            string chiefEngName = GetEmployeeNames(txtChiefEng.Text, "ProfitCenterNo='PENG'", "");
            string chiefSecName = GetEmployeeNames(txtChiefSec.Text, "ProfitCenterNo='PSEC'", "");
            lblChiefEngName.Text = String.IsNullOrWhiteSpace(chiefEngName) ? "" : "Approver: " + chiefEngName;
            lblChiefSecName.Text = String.IsNullOrWhiteSpace(chiefSecName) ? "" : "Approver: " + chiefSecName;
        }
        private void LoadEmailModeSettings()
        {
            chkEmailStandard.Checked = GetCommonValue(Scope + ";EMAIL;STANDARD") == "1";
            chkEmailBatch.Checked = GetCommonValue(Scope + ";EMAIL;BATCH") == "1";
            string v = GetCommonValue(Scope + ";EMAIL;LIGHTNING");
            chkEmailLightning.Checked = v == "" || v == "1";
            chkEmailWO.Checked = GetCommonValue(Scope + ";EMAIL;WO") == "1";
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
        private void SaveAllSettings()
        {
            try
            {
                EnsureAdministrator();
                string ce = NormalizeEmployeeList(txtChiefEng.Text);
                string chiefSec = NormalizeEmployeeList(txtChiefSec.Text);
                if (ce == "" || chiefSec == "")
                    throw new InvalidOperationException("Pilih minimal satu NIK Chief Engineering dan Chief Security.");

                var ceSet = new System.Collections.Generic.HashSet<string>(ce.Split(';'), StringComparer.OrdinalIgnoreCase);
                foreach (string id in chiefSec.Split(';'))
                    if (ceSet.Contains(id))
                        throw new InvalidOperationException("NIK tidak boleh terdaftar sebagai Chief Engineering dan Chief Security sekaligus: " + id);

                using (var br = new WAL.BR.CF())
                {
                    br.EQueryP(
                        @"IF EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@E,';') X WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee WHERE EmployeeID=X.val AND CompanyID=@C AND ISNULL(TerminationDate,'')='' AND ProfitCenterNo='PENG')) RAISERROR('Chief Engineering wajib seluruhnya employee aktif Company ini dengan ProfitCenterNo PENG.',16,1); IF EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@S,';') X WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee WHERE EmployeeID=X.val AND CompanyID=@C AND ISNULL(TerminationDate,'')='' AND ProfitCenterNo='PSEC')) RAISERROR('Chief Security wajib seluruhnya employee aktif Company ini dengan ProfitCenterNo PSEC.',16,1);",
                        new SqlParameter[] {
                            new SqlParameter("@E", ce),
                            new SqlParameter("@S", chiefSec),
                            new SqlParameter("@C", Master.Mn_CompanyID)
                        }
                    );
                }

                string section = "";
                string spv = "";
                string oldSection = "";
                if (pnlSPVEditor.Visible)
                {
                    section = ddlSection.SelectedValue;
                    spv = NormalizeEmployeeList(txtSPV.Text);
                    oldSection = hidSPVOriginalSection.Value;
                    if (section == "" || spv == "")
                        throw new InvalidOperationException("Lengkapi Section dan minimal satu NIK SPV pada form Add New Record.");
                    if (oldSection == "" && GetCommonValue(Scope + ";SPV;" + section) != "")
                        throw new InvalidOperationException("Section tersebut sudah memiliki mapping SPV. Gunakan Edit pada baris yang ada.");
                    using (var br = new WAL.BR.CF())
                    {
                        DataTable d = br.EQueryP(
                            @"SELECT COUNT(DISTINCT X.val) Cnt FROM dbo.SplitStringConvertToTable(@E,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=X.val AND E.CompanyID=@C AND E.SectionID=@S AND ISNULL(E.TerminationDate,'')=''",
                            new SqlParameter[] {
                                new SqlParameter("@E", spv),
                                new SqlParameter("@C", Master.Mn_CompanyID),
                                new SqlParameter("@S", section)
                            }
                        );
                        if (d.Rows.Count == 0 || Convert.ToInt32(d.Rows[0]["Cnt"]) != spv.Split(';').Length)
                            throw new InvalidOperationException("Seluruh NIK SPV harus employee aktif pada Company dan Section terpilih.");
                    }
                }

                SaveCommonValue(Scope + ";CHIEF_ENG", ce);
                SaveCommonValue(Scope + ";CHIEF_SEC", chiefSec);
                SaveCommonValue(Scope + ";EMAIL;STANDARD", chkEmailStandard.Checked ? "1" : "0");
                SaveCommonValue(Scope + ";EMAIL;BATCH", chkEmailBatch.Checked ? "1" : "0");
                SaveCommonValue(Scope + ";EMAIL;LIGHTNING", chkEmailLightning.Checked ? "1" : "0");
                SaveCommonValue(Scope + ";EMAIL;WO", chkEmailWO.Checked ? "1" : "0");

                if (pnlSPVEditor.Visible)
                {
                    if (oldSection != "" && oldSection != section)
                    {
                        using (var br = new WAL.BR.CF())
                            br.EQueryP(
                                @"UPDATE dbo.SysWebCommonValue SET IsDelete=1,UpdateUser=LEFT(@U,10),UpdateDate=GETDATE() WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID=@ID",
                                new SqlParameter[] {
                                    new SqlParameter("@U", Master.Mn_EmployeeID),
                                    new SqlParameter("@ID", Scope + ";SPV;" + oldSection)
                                }
                            );
                    }
                    SaveCommonValue(Scope + ";SPV;" + section, spv);
                }

                LoadHeader();
                LoadEmailModeSettings();
                ClearSPVEditor();
                pnlSPVEditor.Visible = false;
                btnNewSPV.Visible = true;
                BindSPVGrid();
                GF.MsgBox(this, "Seluruh pengaturan Inspection berhasil disimpan.", "BS-5.3.0");
            }
            catch (Exception ex)
            {
                GF.MsgBox(this, ex.Message, "BS-5.3.0");
            }
        }
        private void BindSPVGrid()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable d = br.EQueryP(
                    @"SELECT SUBSTRING(C.ID,LEN(@P)+6,100) SectionID,C.Description EmployeeID,
                             STUFF((SELECT '; '+X.val+' - '+ISNULL(E2.Name,X.val)
                                    FROM dbo.SplitStringConvertToTable(C.Description,';') X
                                    LEFT JOIN dbo.M_HRD_Employee E2 ON E2.EmployeeID=X.val AND E2.CompanyID=@C AND ISNULL(E2.TerminationDate,'')=''
                                    ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,'') EmployeeName
                       FROM dbo.SysWebCommonValue C
                       WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID LIKE @P+';SPV;%'
                       ORDER BY C.ID",
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
                    string spvName = GetEmployeeNames(txtSPV.Text, "SectionID=@S", sec);
                    lblSPVName.Text = String.IsNullOrWhiteSpace(spvName) ? "" : "Approver: " + spvName;
                    hidSPVOriginalSection.Value = sec;
                    pnlSPVEditor.Visible = true;
                    btnNewSPV.Visible = false;
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
                    pnlSPVEditor.Visible = false;
                    btnNewSPV.Visible = true;
                    BindSPVGrid();
                    GF.MsgBox(this, "Mapping SPV dihapus.", "BS-5.3.0");
                }
            }
            catch (Exception ex)
            {
                GF.MsgBox(this, ex.Message, "BS-5.3.0");
            }
            PrepareEmployeeSearch();
        }
        protected void btnNewSPV_Click(object sender, EventArgs e)
        {
            ClearSPVEditor();
            pnlSPVEditor.Visible = true;
            btnNewSPV.Visible = false;
            PrepareEmployeeSearch();
        }
        protected void btnCancelSPV_Click(object sender, EventArgs e)
        {
            ClearSPVEditor();
            pnlSPVEditor.Visible = false;
            btnNewSPV.Visible = true;
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
            if (ddlSection.Items.Count > 0)
                ddlSection.SelectedIndex = 0;
            PrepareEmployeeSearch();
        }

    }
}
