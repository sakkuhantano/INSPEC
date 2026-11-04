using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.HtmlControls;
using System.Web.UI.WebControls;
using WAL;
using INSPECFO;

namespace INSPEC.Secure
{
    public partial class T_DailyLogEmployee : WAL.PB, WAL.I_ToolBar_2
    {
        private const string _MenuID = "20031";

        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            switch (e.ToolbarItem)
            {
                case ToolbarItem_2.Refresh:
                    break;
            }
        }
        private void InitToolbar()
        {
            // Daily Log uses the Site1 application toolbar instead of the legacy WAL toolbar.
        }

        private string _loginEmployeeID;
        private string LoginEmployeeID
        {
            get
            {
                if (String.IsNullOrEmpty(_loginEmployeeID))
                    _loginEmployeeID = AppAuthorization.RequireMenuEmployee(_MenuID);
                return _loginEmployeeID;
            }
        }

        private const string IsoFormat = "yyyy-MM-dd";
        private string SelectedLogType
        {
            get { return NormalizeLogType(ddlLogType.SelectedValue); }
        }

        // Jenis log sepenuhnya berasal dari master dbo.inspec_m_logtype.
        // Code disimpan ke Table_Dt.LogType; Name hanya untuk tampilan.
        private void BindLogTypeDropdown()
        {
            DataTable types;
            using (WAL.BR.CF br = new WAL.BR.CF())
            {
                types = br.EQuery(
                    "SELECT Code, Name " +
                    "FROM dbo.inspec_m_logtype " +
                    "WHERE IsActive = 1 " +
                    "  AND NULLIF(LTRIM(RTRIM(Code)), '') IS NOT NULL " +
                    "  AND NULLIF(LTRIM(RTRIM(Name)), '') IS NOT NULL " +
                    "ORDER BY ID;");
            }

            if (types == null || types.Rows.Count == 0)
                throw new InvalidOperationException("Master Jenis Log aktif belum tersedia.");

            foreach (DataRow row in types.Rows)
            {
                string code = Convert.ToString(row["Code"]).Trim();
                if (code.Length == 0 || code.Length > 10)
                    throw new InvalidOperationException("Code pada master Jenis Log tidak valid.");
            }

            ddlLogType.DataSource = types;
            ddlLogType.DataValueField = "Code";
            ddlLogType.DataTextField = "Name";
            ddlLogType.DataBind();
        }

        private string NormalizeLogType(string value)
        {
            value = (value ?? "").Trim();
            if (value.Length == 0 || value.Length > 10 || ddlLogType.Items.FindByValue(value) == null)
                throw new InvalidOperationException("Jenis log tidak valid atau sudah tidak aktif.");
            return value;
        }

        private string LogTypeLabel(string value)
        {
            value = (value ?? "").Trim();
            ListItem item = ddlLogType.Items.FindByValue(value);
            return item == null ? value : item.Text;
        }

        private string SelectedLogTypeName
        {
            get
            {
                string code = SelectedLogType;
                ListItem item = ddlLogType.Items.FindByValue(code);
                return item == null ? code : item.Text;
            }
        }
        private bool SummaryOpen { get { return (bool)(ViewState["SummaryOpen"] ?? false); } set { ViewState["SummaryOpen"] = value; } }
        private const int SummaryPageSize = 10;
        private string SummarySearch
        {
            get { return (txtSummarySearch.Text ?? "").Trim(); }
            set { txtSummarySearch.Text = value ?? ""; }
        }
        private int SummaryPage
        {
            get { return Convert.ToInt32(ViewState["SummaryPage"] ?? 1, CultureInfo.InvariantCulture); }
            set { ViewState["SummaryPage"] = Math.Max(1, value); }
        }
        private string SelectedIso
        {
            get
            {
                // Datepicker menampilkan dd-MM-yyyy; tanggal tidak disimpan dalam ViewState.
                string raw = (txtPeriod.Text ?? "").Trim();
                if (raw.Length == 0 && !IsPostBack) return TodayIso;
                DateTime date;
                if (!DateTime.TryParseExact(raw, "dd-MM-yyyy", CultureInfo.InvariantCulture,
                    DateTimeStyles.None, out date))
                    throw new InvalidOperationException("Tanggal aktivitas tidak valid. Gunakan dd-MM-yyyy.");
                return AsIso(date);
            }
            set { txtPeriod.Text = ParseIso(value).ToString("dd-MM-yyyy", CultureInfo.InvariantCulture); }
        }
        private string ExpandedMemberId
        {
            get { return Convert.ToString(ViewState["ExpandedMemberId"] ?? ""); }
            set { ViewState["ExpandedMemberId"] = value; }
        }
        private int CurrentPage
        {
            get { return Convert.ToInt32(ViewState["CurrentPage"] ?? 1); }
            set { ViewState["CurrentPage"] = Math.Max(1, value); }
        }
        private string DetailMode
        {
            get { return Convert.ToString(ViewState["DetailMode"] ?? "view"); }
            set { ViewState["DetailMode"] = value; }
        }
        private int SelectedEntryId
        {
            get { return Convert.ToInt32(ViewState["SelectedEntryId"] ?? 0); }
            set { ViewState["SelectedEntryId"] = value; }
        }
        // Snapshot catatan saat Edit/Hapus dibuka; untuk mendeteksi update bersamaan.
        private DateTime OriginalStart { get { return (DateTime)(ViewState["OriginalStart"] ?? DateTime.MinValue); } set { ViewState["OriginalStart"] = value; } }
        private DateTime OriginalEnd { get { return (DateTime)(ViewState["OriginalEnd"] ?? DateTime.MinValue); } set { ViewState["OriginalEnd"] = value; } }
        private string OriginalActivity { get { return Convert.ToString(ViewState["OriginalActivity"] ?? ""); } set { ViewState["OriginalActivity"] = value; } }
        private string OriginalStatus { get { return Convert.ToString(ViewState["OriginalStatus"] ?? ""); } set { ViewState["OriginalStatus"] = value; } }
        private string OriginalLogType { get { return Convert.ToString(ViewState["OriginalLogType"] ?? ""); } set { ViewState["OriginalLogType"] = value; } }
        
        // TextBox saat Save, atau dari SQL saat membuka Edit. Tidak masuk ViewState.
        private bool draftInitialized;
        private string DraftStartDate = "";
        private string DraftEndDate = "";
        private string DraftStartTime = "";
        private string DraftEndTime = "";
        private string DraftActivity = "";
        private string DraftStatus = "";
        private static DateTime TodayDate
        {
            get
            {
                try
                {
                    TimeZoneInfo zone = TimeZoneInfo.FindSystemTimeZoneById("SE Asia Standard Time");
                    return TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, zone).Date;
                }
                catch (TimeZoneNotFoundException) { return DateTime.UtcNow.AddHours(7).Date; }
                catch (InvalidTimeZoneException) { return DateTime.UtcNow.AddHours(7).Date; }
            }
        }
        private string TodayIso { get { return AsIso(TodayDate); } }
        private string TomorrowIso { get { return AsIso(TodayDate.AddDays(1)); } }
        private static string AsIso(DateTime date) { return date.ToString(IsoFormat, CultureInfo.InvariantCulture); }
        private static DateTime ParseIso(string text) { return DateTime.ParseExact(text, IsoFormat, CultureInfo.InvariantCulture); }

        protected override void OnInit(EventArgs e)
        {
            if (Context.User != null && Context.User.Identity != null && Context.User.Identity.IsAuthenticated)
                ViewStateUserKey = Context.User.Identity.Name;
            base.OnInit(e);
            BindLogTypeDropdown();
        }

        protected void Page_Load(object sender, EventArgs e)
        {
            string authenticatedEmployeeID = LoginEmployeeID;
            if (!IsPostBack)
            {
                using (WAL.BR.SysWebMenu sw = new WAL.BR.SysWebMenu())
                {
                    sw.AppID = "inspecfo";
                    sw.MenuID = _MenuID;
                    if (sw.SelectOneByMenuID().Rows.Count > 0)
                    {
                        Page.Title = sw.Description;
                    }
                }
                SelectedIso = TodayIso;
                CurrentPage = 1;
                ddlStatus.SelectedValue = "all";
                ddlPageSize.SelectedValue = "10";
                if (ddlLogType.Items.Count == 0)
                    throw new InvalidOperationException("Master Jenis Log aktif belum tersedia.");
                ddlLogType.SelectedIndex = 0;
                SafeBind();
            }
        }

        protected string FormatDate(string iso)
        {
            DateTime result;
            return DateTime.TryParseExact(iso, IsoFormat, CultureInfo.InvariantCulture,
                DateTimeStyles.None, out result)
                ? result.ToString("dd-MM-yyyy", CultureInfo.InvariantCulture) : "";
        }
        protected bool CanEditEntry(string startDate)
        {
            return SelectedIso == TodayIso && startDate == TodayIso;
        }
        protected bool CanEditDetailEntry(object startDate, object isCurrentMember)
        {
            if (startDate == null || startDate == DBNull.Value ||
                isCurrentMember == null || isCurrentMember == DBNull.Value)
                return false;

            bool memberAllowed = Convert.ToBoolean(isCurrentMember, CultureInfo.InvariantCulture);
            return memberAllowed && CanEditEntry(Convert.ToString(startDate));
        }
        private void ShowNotice(string title, string message, bool error)
        {
            // Satu sumber notifikasi: Panel server ini sendiri menjadi floating card.
            // Tidak ada toast kedua di luar UpdatePanel, sehingga tidak terjadi style/posisi ganda.
            pnlNotice.Visible = true;
            pnlNotice.CssClass = error
                ? "la-float-notice la-float-notice-error"
                : "la-float-notice la-float-notice-success";

            if (String.IsNullOrWhiteSpace(title))
                title = error ? "Tidak dapat diproses" : "Berhasil";

            lblNoticeTitle.Text = title;
            litNotice.Text = message ?? "";

            // Error sedikit lebih lama agar mudah dibaca. Tanpa JS, card tetap terlihat dan bisa ditutup.
            ScriptManager.RegisterStartupScript(
                upLogAktivitas, upLogAktivitas.GetType(),
                "laNotice_" + Guid.NewGuid().ToString("N"),
                "if(window.laScheduleNoticeHide){laScheduleNoticeHide(" +
                (error ? "6000" : "3500") + ");}",
                true);
        }
        private void ClearNotice()
        {
            pnlNotice.Visible = false;
            lblNoticeTitle.Text = "";
            litNotice.Text = "";
        }
        protected void btnDismissNotice_Click(object sender, EventArgs e) { ClearNotice(); }

        private void SafeBind()
        {
            try 
            { 
                BindDashboard(); 
            }
            catch (Exception ex)
            {
                Trace.Warn("LogAktivitas", "Bind gagal", ex);
                ShowNotice("Data belum dapat dimuat", ex is InvalidOperationException ? ex.Message : "Terjadi kendala saat mengambil data. Silakan coba lagi.", true);
                rptMembers.DataSource = new DataTable();
                rptMembers.DataBind();
                rptPages.DataSource = new DataTable();
                rptPages.DataBind();
            }
        }
        private void RunAndBind(Action action)
        {
            ClearNotice();
            try { action(); }
            catch (Exception ex)
            {
                Trace.Warn("LogAktivitas", "Aksi gagal", ex);
                // Jika input tanggal rusak / dimanipulasi, pulihkan tanggal valid
                // sebelum bind ulang (tanpa bergantung pada ViewState tanggal).
                if (ex is InvalidOperationException &&
                    ex.Message.StartsWith("Tanggal aktivitas tidak valid", StringComparison.Ordinal))
                    SelectedIso = TodayIso;
                ShowNotice("Tindakan gagal", ex is InvalidOperationException ? ex.Message :
                            "Tidak dapat memproses aktivitas. Periksa data dan koneksi, lalu coba lagi.", true);
            }
            SafeBind();
        }

        // --------------------------------------------------------------
        // BIND TABEL: langsung DataTable, tidak ada ActivityDashboard.
        // --------------------------------------------------------------

        private void BindLoginHeader()
        {
            DataTable employee;
            using (WAL.BR.CF br = new WAL.BR.CF())
            {
                employee = br.EQuery(
                    "SELECT TOP (1) mhe.ProfitCenterNo, mhe.SectionID " +
                    "FROM dbo.M_HRD_Employee AS mhe " +
                    "WHERE mhe.EmployeeID = '" + LoginEmployeeID + "'");
            }

            if (employee == null || employee.Rows.Count == 0)
                throw new InvalidOperationException("Profit Center dan Section untuk EmployeeID login tidak ditemukan.");

            // asp:Literal Mode=Encode di ASPX menghindari injeksi markup dari data HRD.
            litProfitCenterNo.Text = HeaderText(employee.Rows[0]["ProfitCenterNo"]);
            litSectionID.Text = HeaderText(employee.Rows[0]["SectionID"]);
        }

        private static string HeaderText(object value)
        {
            string text = Convert.ToString(value).Trim();
            return text.Length == 0 ? "—" : text;
        }

        protected void btnSummary_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate
            {
                SummaryPage = 1;
                SummarySearch = "";
                txtSummarySearch.Text = "";
                SummaryOpen = true;
                ResetDetail();
            });
        }
        protected void btnCloseSummary_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate { SummaryOpen = false; SummaryPage = 1; });
        }
        protected void btnSummarySearch_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate
            {
                SummarySearch = (txtSummarySearch.Text ?? "").Trim();
                if (SummarySearch.Length > 100) SummarySearch = SummarySearch.Substring(0, 100);
                SummaryPage = 1;
                SummaryOpen = true;
            });
        }
        protected void ddlLogType_SelectedIndexChanged(object sender, EventArgs e)
        {
            RunAndBind(delegate
            {
                // Nilai dropdown dipulihkan dari request oleh Web Forms.
                SummaryPage = 1;
                SummarySearch = "";
                CurrentPage = 1;
                ResetDetail();
            });
        }
        protected void btnSummaryPrev_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate
            {
                SummaryOpen = true;
                SummaryPage = Math.Max(1, SummaryPage - 1);
            });
        }
        protected void btnSummaryNext_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate
            {
                SummaryOpen = true;
                SummaryPage = SummaryPage + 1;
            });
        }
        private void BindSummary()
        {
            pnlSummary.Visible = SummaryOpen;
            if (!SummaryOpen) return;

            string period = ParseIso(SelectedIso).ToString("yyyyMMdd", CultureInfo.InvariantCulture);
            string keyword = (SummarySearch ?? "").Trim();
            if (keyword.Length > 100) keyword = keyword.Substring(0, 100);
                txtSummarySearch.Text = keyword;
            string selectedTypeSql = SafeSqlLiteral(SelectedLogType, 10, "Jenis log");
            string criteria =
                " FROM dbo.Inspec_T_DailyLog_Hd h " +
                " INNER JOIN dbo.Inspec_T_DailyLog_Dt d ON d.Idhd = h.Id " +
                " LEFT JOIN m_hrd_employee m ON m.EmployeeID = d.EmployeeID " +
                " WHERE h.EmployeeID = '" + LoginEmployeeID + "' " +
                " AND h.PeriodDate = CONVERT(date, '" + period + "', 112) " +
                " AND d.LogType = '" + selectedTypeSql + "' ";
            if (keyword.Length > 0)
            {
                string k = SafeSqlLiteral(keyword, 100, "Pencarian aktivitas");
                // CHARINDEX bukan LIKE: karakter % dan _ ditafsir secara literal.
                criteria +=
                    " AND (CHARINDEX(N'" + k + "', ISNULL(m.Name, '')) > 0 " +
                    " OR CHARINDEX(N'" + k + "', ISNULL(d.Activity, '')) > 0 " +
                    " OR CHARINDEX(N'" + k + "', ISNULL(d.Status, N'')) > 0) ";
            }
            // Jumlah seluruh aktivitas pada periode yang sama, tanpa membatasi 10 baris.
            DataTable countTable;
            using (WAL.BR.CF br = new WAL.BR.CF())
                countTable = br.EQuery("SELECT COUNT(1) AS TotalRows " + criteria);
            int total = countTable != null && countTable.Rows.Count > 0 &&
                        countTable.Rows[0]["TotalRows"] != DBNull.Value
                ? Convert.ToInt32(countTable.Rows[0]["TotalRows"], CultureInfo.InvariantCulture) : 0;
            int maxPage = Math.Max(1, (int)Math.Ceiling(total / (double)SummaryPageSize));
            SummaryPage = Math.Min(Math.Max(1, SummaryPage), maxPage);
            int start = (SummaryPage - 1) * SummaryPageSize + 1;
            int end = Math.Min(total, SummaryPage * SummaryPageSize);

            // Pagination di SQL: hanya mengambil baris untuk halaman modal saat ini.
            string sql =
               "WITH Numbered AS ( " +
               " SELECT d.StartDateTime, d.EndDateTime, ISNULL(m.Name, d.EmployeeID) AS FullName, " +
               " d.Activity, d.Status, ROW_NUMBER() OVER (ORDER BY d.StartDateTime, d.Id) AS RowNum " +
               criteria +
               ") SELECT StartDateTime, EndDateTime, FullName, Activity, Status " +
               " FROM Numbered WHERE RowNum BETWEEN " + start + " AND " + end +
               " ORDER BY RowNum;";
            DataTable rows;
            if (total == 0)
            {
                rows = new DataTable();
                rows.Columns.Add("StartDateTime", typeof(DateTime));
                rows.Columns.Add("EndDateTime", typeof(DateTime));
                rows.Columns.Add("FullName", typeof(string));
                rows.Columns.Add("Activity", typeof(string));
                rows.Columns.Add("Status", typeof(string));
            }
            else
            {
                using (WAL.BR.CF br = new WAL.BR.CF()) rows = br.EQuery(sql);
            }
            if (rows == null)
                throw new InvalidOperationException("Tidak dapat memuat ringkasan aktivitas.");

            DataTable summary = new DataTable("SummaryActivities");
            summary.Columns.Add("ReportText", typeof(string));
            summary.Columns.Add("StartText", typeof(string));
            summary.Columns.Add("EndText", typeof(string));
            summary.Columns.Add("FullName", typeof(string));
            summary.Columns.Add("Activity", typeof(string));
            summary.Columns.Add("StatusText", typeof(string));
            foreach (DataRow r in rows.Rows)
            {
                summary.Rows.Add(
                    FormatDate(SelectedIso),
                    Convert.ToDateTime(r["StartDateTime"]).ToString("HH:mm", CultureInfo.InvariantCulture),
                    Convert.ToDateTime(r["EndDateTime"]).ToString("HH:mm", CultureInfo.InvariantCulture),
                    Convert.ToString(r["FullName"]),
                    Convert.ToString(r["Activity"]), Convert.ToString(r["Status"]));
            }
            lblSummaryTitle.Text = "Detail " + SelectedLogTypeName;
            lblSummaryDate.Text = "Tanggal " + FormatDate(SelectedIso);
            lblSummaryRange.Text = total == 0 ? "0 aktivitas ditemukan" : String.Format(
                CultureInfo.GetCultureInfo("id-ID"), "Menampilkan {0}–{1} dari {2} aktivitas", start, end, total);
            lblSummaryPage.Text = String.Format(CultureInfo.InvariantCulture,  "{0} / {1}", SummaryPage, maxPage);
            btnSummaryPrev.Enabled = SummaryPage > 1;
            btnSummaryNext.Enabled = SummaryPage < maxPage;
            rptSummary.DataSource = summary;
            rptSummary.DataBind();
            lblSummaryEmpty.Visible = total == 0;
            lblSummaryEmpty.Text = keyword.Length > 0 ? "Tidak ditemukan aktivitas yang cocok." : "Belum ada aktivitas " + SelectedLogTypeName + " pada tanggal ini.";
        }

        private void BindDashboard()
        {
            BindLoginHeader();
            NormalizeLogType(ddlLogType.SelectedValue);
            if (String.IsNullOrEmpty(SelectedIso)) SelectedIso = TodayIso;
            if (ParseIso(SelectedIso).Date > TodayDate.AddDays(1))
                throw new InvalidOperationException("Tanggal aktivitas maksimal besok.");

            int size = Convert.ToInt32(ddlPageSize.SelectedValue, CultureInfo.InvariantCulture);
            if (size != 10 && size != 20 && size != 50) size = 10;
            int total, completed, filtered;
            int selectedPage = CurrentPage;
            DataTable members = GetMembersPage(SelectedIso, txtSearch.Text, ddlStatus.SelectedValue, size, ref selectedPage, out total, out completed, out filtered);
            CurrentPage = selectedPage;

            DateTime chosen = ParseIso(SelectedIso);
            // txtPeriod adalah satu-satunya sumber tampilan tanggal; dipulihkan saat semua partial postback.
            txtPeriod.Text = FormatDate(SelectedIso);
            txtPeriod.Attributes["data-server-date"] = txtPeriod.Text;
            // Dibaca bootstrap-datepicker tanpa mengekspose properti private C# ke template ASPX.
            txtPeriod.Attributes["data-end-date"] = FormatDate(TomorrowIso);
            lblDateCaption.Text = chosen.ToString("dddd, dd MMMM yyyy", new CultureInfo("id-ID")) +
                                (SelectedIso == TodayIso ? " · Hari Ini" : SelectedIso == TomorrowIso ? " · Besok" : " · Riwayat");
            btnNext.Enabled = SelectedIso.CompareTo(TomorrowIso) < 0;

            // Total, Sudah, dan Belum diisi berasal dari SQL Server per PeriodDate.
            // Nilai memakai semua anak buah untuk tanggal terpilih (bukan hanya halaman/filter).
            lblTotalMembers.Text = total.ToString("N0", CultureInfo.GetCultureInfo("id-ID"));
            lblCompletedMembers.Text = completed.ToString("N0", CultureInfo.GetCultureInfo("id-ID"));
            lblPendingMembers.Text = (total - completed).ToString("N0", CultureInfo.GetCultureInfo("id-ID"));
            int first = filtered == 0 ? 0 : (CurrentPage - 1) * size + 1;
            int last = Math.Min(filtered, CurrentPage * size);
            lblRange.Text = String.Format(CultureInfo.InvariantCulture, "Menampilkan {0}–{1} dari {2} anggota", first, last, filtered);

            BindSummary();
            rptMembers.DataSource = members;
            rptMembers.DataBind();

            int maxPage = Math.Max(1, (int)Math.Ceiling(filtered / (double)size));
            btnPagePrevious.Enabled = CurrentPage > 1;
            btnPageNext.Enabled = CurrentPage < maxPage;
            DataTable pages = new DataTable("Halaman");
            pages.Columns.Add("Number", typeof(int));
            pages.Columns.Add("Current", typeof(bool));
            for (int p = 1; p <= maxPage; p++)
                if (p == 1 || p == maxPage || Math.Abs(p - CurrentPage) <= 2)
                    pages.Rows.Add(p, p == CurrentPage);
            rptPages.DataSource = pages;
            rptPages.DataBind();
        }

        // Ambil anak buah yang ParentEmployeeID-nya sama dengan login, beserta status laporan per tanggal.
        private DataTable GetMembersPage(string selectedDate, string search, string status, int pageSize,
            ref int pageNumber, out int totalMembers, out int completedMembers, out int filteredCount)
        {
            using (WAL.BR.CF br = new WAL.BR.CF())
            {
                DateTime date = ParseIso(selectedDate).Date;
                if (date > TodayDate.AddDays(1))
                    throw new InvalidOperationException("Tanggal aktivitas maksimal besok.");
                string periodSql = date.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
                string typeSql = SafeSqlLiteral(NormalizeLogType(SelectedLogType), 10, "Jenis log");
                DataTable V_dt = br.EQuery(
                    "SELECT member.EmployeeID AS MemberId, member.EmployeeID AS StaffCode, " +
                    "       member.Name AS FullName, " +
                    "       ISNULL(t.ActivityCount, 0) AS ActivityCount, " +
                    "       ISNULL(CONVERT(varchar(5), f.StartDateTime, 108), '') AS FirstStart, " +
                    "       ISNULL(CONVERT(varchar(5), f.EndDateTime, 108), '') AS FirstEnd, " +
                    "       CAST(1 AS bit) AS IsCurrentMember, " +
                    "       CAST(CASE WHEN f.StartDateTime IS NOT NULL " +
                    "                 AND CONVERT(date, f.StartDateTime) <> CONVERT(date, f.EndDateTime) " +
                    "                 THEN 1 ELSE 0 END AS bit) AS CrossDay " +
                    "FROM m_hrd_employee AS loginEmp " +
                    "INNER JOIN m_hrd_employee AS member " +
                    "    ON (member.EmployeeID = loginEmp.EmployeeID OR ( " +
                    "         member.CompanyID = loginEmp.CompanyID " +
                    "         AND member.LocationID = loginEmp.LocationID " +
                    "         AND member.ProfitCenterNo = loginEmp.ProfitCenterNo " +
                    "         AND member.SectionID = loginEmp.SectionID)) " +
                    "OUTER APPLY ( " +
                    "    SELECT COUNT(1) AS ActivityCount " +
                    "    FROM dbo.Inspec_T_DailyLog_Hd h " +
                    "    INNER JOIN dbo.Inspec_T_DailyLog_Dt d ON d.Idhd = h.Id AND d.EmployeeID = member.EmployeeID AND d.IsActive = 1 AND d.LogType = '" + typeSql + "' " +
                    "    WHERE h.EmployeeID = loginEmp.EmployeeID " +
                    "      AND h.PeriodDate = CONVERT(date, '" + periodSql + "', 112) " +
                    ") t " +
                    "OUTER APPLY ( " +
                    "    SELECT TOP (1) d.StartDateTime, d.EndDateTime " +
                    "    FROM dbo.Inspec_T_DailyLog_Hd h " +
                    "    INNER JOIN dbo.Inspec_T_DailyLog_Dt d ON d.Idhd = h.Id AND d.EmployeeID = member.EmployeeID AND d.IsActive = 1 AND d.LogType = '" + typeSql + "' " +
                    "    WHERE h.EmployeeID = loginEmp.EmployeeID " +
                    "      AND h.PeriodDate = CONVERT(date, '" + periodSql + "', 112) " +
                    "    ORDER BY d.StartDateTime, d.Id " +
                    ") f " +
                    "WHERE loginEmp.EmployeeID = '" + LoginEmployeeID + "' AND member.TerminationDate = '' " +
                    "ORDER BY member.Name, member.EmployeeID;");

                totalMembers = 0;
                completedMembers = 0;
                foreach (DataRow row in V_dt.Rows)
                {
                    totalMembers++;
                    if (Convert.ToInt32(row["ActivityCount"], CultureInfo.InvariantCulture) > 0)
                        completedMembers++;
                }

                search = (search ?? "").Trim();
                if (search.Length > 100) search = search.Substring(0, 100);
                DataTable visible = V_dt.Clone();
                foreach (DataRow row in V_dt.Rows)
                {
                    bool found = Convert.ToString(row["FullName"]).IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0
                        || Convert.ToString(row["StaffCode"]).IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0;
                    int count = Convert.ToInt32(row["ActivityCount"], CultureInfo.InvariantCulture);
                    bool passed = status == "done" ? count > 0 : status == "empty" ? count == 0 : true;
                    if (found && passed) visible.ImportRow(row);
                }
                filteredCount = visible.Rows.Count;
                int maxPage = Math.Max(1, (int)Math.Ceiling(filteredCount / (double)pageSize));
                pageNumber = Math.Max(1, Math.Min(maxPage, pageNumber));
                DataTable result = visible.Clone();
                int start = (pageNumber - 1) * pageSize;
                for (int i = start; i < Math.Min(start + pageSize, visible.Rows.Count); i++)
                    result.ImportRow(visible.Rows[i]);
                return result;
            }
            
        }

        protected void rptMembers_ItemDataBound(object sender, RepeaterItemEventArgs e)
        {
            if (e.Item.ItemType != ListItemType.Item && e.Item.ItemType != ListItemType.AlternatingItem) return;
            DataRowView row = (DataRowView)e.Item.DataItem;
            string memberId = Convert.ToString(row["MemberId"]);
            int count = (int)row["ActivityCount"];
            ((Literal)e.Item.FindControl("litNumber")).Text =
                ((CurrentPage - 1) * Int32.Parse(ddlPageSize.SelectedValue, CultureInfo.InvariantCulture) + e.Item.ItemIndex + 1)
                .ToString(CultureInfo.InvariantCulture);
            Literal shift = (Literal)e.Item.FindControl("litShift");
            Literal status = (Literal)e.Item.FindControl("litStatus");
            if (count == 0)
            {
                shift.Text = "<span class=\"la-secondary\">Belum ada shift</span>";
                status.Text = "<span class=\"la-status\">Belum Diisi</span>";
            }
            else
            {
                shift.Text = "<span class=\"la-shift\">" +
                    HttpUtility.HtmlEncode(Convert.ToString(row["FirstStart"]) + " – " + row["FirstEnd"]) + "</span>" +
                    "<div class=\"la-secondary\">" + ((bool)row["CrossDay"] ? "+1 hari" : FormatDate(SelectedIso)) +
                    (count > 1 ? " · " + count.ToString(CultureInfo.InvariantCulture) + " catatan" : "") + "</div>";
                status.Text = "<span class=\"la-status la-filled\">Sudah Diisi</span>";
            }
            LinkButton toggle = (LinkButton)e.Item.FindControl("btnMember");
            bool opened = String.Equals(ExpandedMemberId, memberId, StringComparison.OrdinalIgnoreCase);
            bool inputDate = SelectedIso == TodayIso;
            toggle.Text = opened ? "Tutup" : count == 0 && inputDate ? "Isi" : "Lihat";
            toggle.CssClass = "la-row-button" + (opened ? " la-close" : count == 0 && inputDate ? " la-fill" : "");
            HtmlTableRow parent = (HtmlTableRow)e.Item.FindControl("trMember");
            HtmlTableRow detail = (HtmlTableRow)e.Item.FindControl("trDetail");
            detail.Visible = opened;
            if (!opened) return;
            parent.Attributes["class"] = "la-member-row la-active-parent";

            DataTable entries = GetActivitiesTable(SelectedIso, memberId);
            Panel view = (Panel)e.Item.FindControl("pnlView");
            Panel editor = (Panel)e.Item.FindControl("pnlEditor");
            Panel confirm = (Panel)e.Item.FindControl("pnlConfirm");
            view.Visible = DetailMode == "view";
            editor.Visible = DetailMode == "add" || DetailMode == "edit";
            confirm.Visible = DetailMode == "delete";
            ((LinkButton)e.Item.FindControl("btnAdd")).Visible = DetailMode == "view" && inputDate;
            if (view.Visible)
            {
                ((Label)e.Item.FindControl("lblEmpty")).Visible = entries.Rows.Count == 0;
                Repeater nested = (Repeater)e.Item.FindControl("rptEntries");
                nested.DataSource = entries.DefaultView;
                nested.DataBind();
            }
            if (editor.Visible) PopulateEditor(e.Item, entries);
            if (confirm.Visible)
            {
                DataRow item = FindDetailRow(entries, SelectedEntryId);
                if (item == null) throw new InvalidOperationException("Catatan tidak ditemukan. Buka ulang detail.");
                ((Literal)e.Item.FindControl("litDeleteStaff")).Text =
                    Convert.ToString(row["FullName"]) + " (" + row["StaffCode"] + ")";
                ((Literal)e.Item.FindControl("litDeleteWhen")).Text =
                    FormatDate(Convert.ToString(item["StartDate"])) + " " + item["StartTime"] + " – " +
                    FormatDate(Convert.ToString(item["EndDate"])) + " " + item["EndTime"] +
                    (Convert.ToString(item["StartDate"]) == Convert.ToString(item["EndDate"]) ? "" : " (+1 hari)");
                ((Literal)e.Item.FindControl("litDeletePreview")).Text = Convert.ToString(item["ActivityText"]);
                ((Literal)e.Item.FindControl("litDeleteStatus")).Text = Convert.ToString(item["StatusText"]);
            }
        }

        private void PopulateEditor(RepeaterItem item, DataTable entries)
        {
            bool editing = DetailMode == "edit";
            if (!draftInitialized)
            {
                if (editing)
                {
                    // Setelah postback lain, sumber data Edit tetap SQL, bukan ViewState.
                    DataRow row = FindDetailRow(entries, SelectedEntryId);
                    if (row == null)
                        throw new InvalidOperationException("Aktivitas sudah berubah. Buka ulang detail.");
                    LoadDraftFromRow(row);
                }
                else
                {
                    InitializeNewDraft();
                }
            }
            ((Label)item.FindControl("lblFormTitle")).Text = editing ? "Edit Aktivitas" : "Isi Aktivitas Baru";
            ((LinkButton)item.FindControl("btnSave")).Text = editing ? "Simpan Perubahan" : "Simpan Aktivitas";
            ((TextBox)item.FindControl("txtStartTime")).Text = DraftStartTime;
            ((TextBox)item.FindControl("txtEndTime")).Text = DraftEndTime;
            ((TextBox)item.FindControl("txtActivity")).Text = DraftActivity;
            ((TextBox)item.FindControl("txtWorkStatus")).Text = DraftStatus;
        }

        private void LoadDraftFromRow(DataRow row)
        {
            DraftStartDate = Convert.ToString(row["StartDate"]);
            DraftEndDate = Convert.ToString(row["EndDate"]);
            DraftStartTime = Convert.ToString(row["StartTime"]);
            DraftEndTime = Convert.ToString(row["EndTime"]);
            DraftActivity = Convert.ToString(row["ActivityText"]);
            DraftStatus = Convert.ToString(row["StatusText"]);
            draftInitialized = true;
        }

        //private void PopulateEditor(RepeaterItem item)
        //{
        //    bool editing = DetailMode == "edit";
        //    ((Label)item.FindControl("lblFormTitle")).Text = editing ? "Edit Aktivitas" : "Isi Aktivitas Baru";
        //    ((LinkButton)item.FindControl("btnSave")).Text = editing ? "Simpan Perubahan" : "Simpan Aktivitas";
        //    // Tanggal mulai/selesai ditentukan di server, tanpa dropdown.
        //    ((TextBox)item.FindControl("txtStartTime")).Text = DraftStartTime;
        //    ((TextBox)item.FindControl("txtEndTime")).Text = DraftEndTime;
        //    ((TextBox)item.FindControl("txtActivity")).Text = DraftActivity;
        //}

        private static DataRow FindDetailRow(DataTable table, int activityId)
        {
            foreach (DataRow row in table.Rows) if ((int)row["ActivityId"] == activityId) return row;
            return null;
        }

        private DataTable GetActivitiesTable(string dateText, string memberId)
        {
            DateTime date = ParseIso(dateText).Date;
            if (date > TodayDate.AddDays(1))
                throw new InvalidOperationException("Tanggal aktivitas maksimal besok.");

            string periodSql = date.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
            string memberSql = SafeSqlLiteral(memberId, 10, "EmployeeID");
            string typeSql = SafeSqlLiteral(NormalizeLogType(SelectedLogType), 10, "Jenis log");
            string sql =
                "SELECT d.Id AS ActivityId, d.StartDateTime, d.EndDateTime, d.Activity, " +
                "       CAST(CASE WHEN EXISTS ( " +
                "          SELECT 1 FROM m_hrd_Employee AS loginEmp " +
                "          INNER JOIN m_hrd_Employee AS member " +
                "            ON member.EmployeeID = d.EmployeeID " +
                "          WHERE loginEmp.EmployeeID = '" + LoginEmployeeID + "' " +
                "            AND (member.EmployeeID = loginEmp.EmployeeID OR ( " +
                "                 member.CompanyID = loginEmp.CompanyID " +
                "                 AND member.LocationID = loginEmp.LocationID " +
                "                 AND member.ProfitCenterNo = loginEmp.ProfitCenterNo " +
                "                 AND member.SectionID = loginEmp.SectionID)) " +
                "       ) THEN 1 ELSE 0 END AS bit) AS IsCurrentMember " +
                "FROM dbo.Inspec_T_DailyLog_Hd h " +
                "INNER JOIN dbo.Inspec_T_DailyLog_Dt d ON d.Idhd = h.Id AND d.IsActive = 1 " +
                "WHERE h.EmployeeID = '" + LoginEmployeeID + "' " +
                "AND d.EmployeeID = '" + memberSql + "' " +
                "AND d.LogType = '" + typeSql + "' " +
                "AND h.PeriodDate = CONVERT(date, '" + periodSql + "', 112) " +
                "ORDER BY d.StartDateTime, d.Id;";

            DataTable raw;
            using (WAL.BR.CF br = new WAL.BR.CF())
            {
                raw = br.EQuery(sql);
            }
            if (raw == null)
                throw new InvalidOperationException("Query aktivitas tidak mengembalikan DataTable.");

            DataTable details = NewActivityTable();
            foreach (DataRow row in raw.Rows)
            {
                DateTime started = Convert.ToDateTime(row["StartDateTime"]);
                DateTime finished = Convert.ToDateTime(row["EndDateTime"]);
                details.Rows.Add(
                    Convert.ToInt32(row["ActivityId"], CultureInfo.InvariantCulture),
                    AsIso(started), AsIso(finished),
                    started.ToString("HH:mm", CultureInfo.InvariantCulture),
                    finished.ToString("HH:mm", CultureInfo.InvariantCulture),
                    Convert.ToString(row["Activity"]),
                    Convert.ToString(row["Status"]), Convert.ToString(row["LogType"]),
                    LogTypeLabel(Convert.ToString(row["LogType"])),
                    started,
                    row["IsCurrentMember"] != DBNull.Value &&
                    Convert.ToBoolean(row["IsCurrentMember"], CultureInfo.InvariantCulture));
            }
            return details;
        }

        private static DataTable NewActivityTable()
        {
            DataTable table = new DataTable("DetailAktivitas");
            table.Columns.Add("ActivityId", typeof(int));
            table.Columns.Add("StartDate", typeof(string));
            table.Columns.Add("EndDate", typeof(string));
            table.Columns.Add("StartTime", typeof(string));
            table.Columns.Add("EndTime", typeof(string));
            table.Columns.Add("ActivityText", typeof(string));
            table.Columns.Add("StatusText", typeof(string));
            table.Columns.Add("LogType", typeof(string));
            table.Columns.Add("LogTypeLabel", typeof(string));
            table.Columns.Add("SortAt", typeof(DateTime));
            DataColumn currentMemberColumn = table.Columns.Add("IsCurrentMember", typeof(bool));
            currentMemberColumn.DefaultValue = false;
            return table;
        }

        // --------------------------------------------------------------
        // WEB FORMS EVENTS: semua aksi di code-behind (UpdatePanel).
        // --------------------------------------------------------------
        private void ClearOriginalSnapshot()
        {
            // Buang snapshot dari __VIEWSTATE saat tidak sedang Edit/Hapus.
            // SP tetap menerima snapshot asli untuk memeriksa konflik saat diperlukan.
            ViewState.Remove("OriginalStart");
            ViewState.Remove("OriginalEnd");
            ViewState.Remove("OriginalActivity");
            ViewState.Remove("OriginalStatus");
            ViewState.Remove("OriginalLogType");
        }
        private void ResetDetail()
        {
            draftInitialized = false;
            ExpandedMemberId = "";
            DetailMode = "view";
            SelectedEntryId = 0;
            ClearOriginalSnapshot();
        }
        private void SelectDay(string newDate)
        {
            DateTime date;
            if (!DateTime.TryParseExact(newDate, IsoFormat, CultureInfo.InvariantCulture,
                DateTimeStyles.None, out date) || date.Date > TodayDate.AddDays(1))
                throw new InvalidOperationException("Tanggal aktivitas maksimal besok.");
            SelectedIso = AsIso(date);
            CurrentPage = 1;
            SummaryPage = 1;
            SummarySearch = "";
            ResetDetail();
        }
        protected void btnPeriodChanged_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate
            {
                DateTime parsed;
                string raw = (txtPeriod.Text ?? "").Trim();
                // Bootstrap Datepicker memakai dd-MM-yyyy. Parse ketat agar 12-03 tidak ambigu.
                if (!DateTime.TryParseExact(raw, "dd-MM-yyyy", CultureInfo.InvariantCulture,
                    DateTimeStyles.None, out parsed))
                {
                    SelectedIso = TodayIso; // pulihkan tanggal valid sebelum SafeBind
                    throw new InvalidOperationException("Tanggal aktivitas tidak valid. Gunakan dd-MM-yyyy.");
                }
                SelectDay(AsIso(parsed)); // reset detail & halaman, lalu BindDashboard memuat ulang Repeater.
            });
        }
        protected void btnToday_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate { SelectDay(TodayIso); });
        }
        protected void btnPrevious_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate { SelectDay(AsIso(ParseIso(SelectedIso).AddDays(-1))); });
        }
        protected void btnNext_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate { SelectDay(AsIso(ParseIso(SelectedIso).AddDays(1))); });
        }
        protected void btnSearch_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate { CurrentPage = 1; ResetDetail(); });
        }
        protected void ddlStatus_SelectedIndexChanged(object sender, EventArgs e)
        {
            RunAndBind(delegate { CurrentPage = 1; ResetDetail(); });
        }
        protected void ddlPageSize_SelectedIndexChanged(object sender, EventArgs e)
        {
            RunAndBind(delegate { CurrentPage = 1; ResetDetail(); });
        }
        protected void btnPagePrevious_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate { CurrentPage = Math.Max(1, CurrentPage - 1); ResetDetail(); });
        }
        protected void btnPageNext_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate { CurrentPage++; ResetDetail(); });
        }
        protected void rptPages_ItemCommand(object source, RepeaterCommandEventArgs e)
        {
            if (e.CommandName != "GoPage") return;
            RunAndBind(delegate
            {
                CurrentPage = Convert.ToInt32(e.CommandArgument, CultureInfo.InvariantCulture);
                ResetDetail();
            });
        }
        protected void rptMembers_ItemCommand(object source, RepeaterCommandEventArgs e)
        {
            if (e.CommandName != "ToggleMember") return;
            RunAndBind(delegate
            {
                string memberId = Convert.ToString(e.CommandArgument);
                if (String.Equals(ExpandedMemberId, memberId, StringComparison.OrdinalIgnoreCase))
                {
                    ResetDetail();
                    return;
                }
                DataTable details = GetActivitiesTable(SelectedIso, memberId);
                ExpandedMemberId = memberId;
                DetailMode = details.Rows.Count == 0 && SelectedIso == TodayIso
                    ? "add" : "view";
                if (DetailMode == "add") InitializeNewDraft();
            });
        }
        private void InitializeNewDraft()
        {
            // Isi jam sekarang WIB secara otomatis; pengguna tetap boleh mengganti jam.
            DateTime nowWib = DateTime.UtcNow.AddHours(7);
            DraftStartDate = TodayIso;
            DraftStartTime = nowWib.ToString("HH:mm", CultureInfo.InvariantCulture);
            DraftEndTime = nowWib.AddHours(1).ToString("HH:mm", CultureInfo.InvariantCulture);
            DraftEndDate = nowWib.AddHours(1).Date > nowWib.Date ? TomorrowIso : TodayIso;
            DraftActivity = "";
            DraftStatus = "";
            draftInitialized = true;
            SelectedEntryId = 0;
            ClearOriginalSnapshot();
        }
        protected void btnAdd_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate
            {
                if (SelectedIso != TodayIso)
                    throw new InvalidOperationException("Hanya hari ini yang dapat ditambahkan. Riwayat tetap dapat dilihat.");
                InitializeNewDraft();
                DetailMode = "add";
            });
        }
        protected void btnClose_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate { ResetDetail(); });
        }
        protected void rptEntries_ItemCommand(object source, RepeaterCommandEventArgs e)
        {
            if (e.CommandName != "EditEntry" && e.CommandName != "DeleteEntry") return;
            RunAndBind(delegate
            {
                int entryId = Convert.ToInt32(e.CommandArgument, CultureInfo.InvariantCulture);
                DataRow row = FindDetailRow(GetActivitiesTable(SelectedIso, ExpandedMemberId), entryId);
                if (row == null || !CanEditDetailEntry(row["StartDate"], row["IsCurrentMember"]))
                    throw new InvalidOperationException("Catatan ini tidak dapat diubah.");
                SelectedEntryId = entryId;
                OriginalStart = ParseIso(Convert.ToString(row["StartDate"])).Add(TimeSpan.ParseExact(Convert.ToString(row["StartTime"]), @"hh\:mm", CultureInfo.InvariantCulture));
                OriginalEnd = ParseIso(Convert.ToString(row["EndDate"])).Add(TimeSpan.ParseExact(Convert.ToString(row["EndTime"]), @"hh\:mm", CultureInfo.InvariantCulture));
                OriginalActivity = Convert.ToString(row["ActivityText"]);
                OriginalStatus = Convert.ToString(row["StatusText"]);
                OriginalLogType = NormalizeLogType(Convert.ToString(row["LogType"]));
                if (e.CommandName == "DeleteEntry")
                {
                    DetailMode = "delete";
                    return;
                }
                DetailMode = "edit";
                LoadDraftFromRow(row);
            });
        }
        // Tetap menerima 830 / 0800 / 8:00 ketika JS input-mask tidak berjalan.
        private static string NormalizeClock(string raw)
        {
            string input = (raw ?? "").Trim();
            int hour, minute;
            if (input.IndexOf(':') >= 0)
            {
                string[] parts = input.Split(':');
                if (parts.Length != 2 ||
                    !Int32.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out hour) ||
                    !Int32.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out minute))
                    throw new InvalidOperationException("Jam tidak valid. Gunakan HH:mm, contohnya 08:30.");
            }
            else
            {
                if (input.Length < 1 || input.Length > 4)
                    throw new InvalidOperationException("Jam tidak valid. Ketik 0800 atau 08:00.");
                if (input.Length <= 2)
                {
                    if (!Int32.TryParse(input, NumberStyles.None, CultureInfo.InvariantCulture, out hour))
                        throw new InvalidOperationException("Jam harus berupa angka.");
                    minute = 0;
                }
                else
                {
                    if (!Int32.TryParse(input.Substring(0, input.Length - 2), NumberStyles.None, CultureInfo.InvariantCulture, out hour) ||
                        !Int32.TryParse(input.Substring(input.Length - 2), NumberStyles.None, CultureInfo.InvariantCulture, out minute))
                        throw new InvalidOperationException("Jam harus berupa angka.");
                }
            }
            if (hour < 0 || hour > 23 || minute < 0 || minute > 59)
                throw new InvalidOperationException("Jam tidak valid. Jam 00–23, menit 00–59.");
            return hour.ToString("00", CultureInfo.InvariantCulture) + ":" +
                minute.ToString("00", CultureInfo.InvariantCulture);
        }

        private static RepeaterItem FindParentItem(Control child)
        {
            Control cursor = child;
            while (cursor != null && !(cursor is RepeaterItem)) cursor = cursor.Parent;
            return cursor as RepeaterItem;
        }
        protected void btnSave_Click(object sender, EventArgs e)
        {
            RepeaterItem repeaterRow = FindParentItem((Control)sender);
            RunAndBind(delegate
            {
                if (repeaterRow == null || String.IsNullOrEmpty(ExpandedMemberId) ||
                    (DetailMode != "add" && DetailMode != "edit"))
                    throw new InvalidOperationException("Form tidak tersedia. Buka ulang detail.");
                bool editing = DetailMode == "edit";
                // Baca input POST langsung dari TextBox, lalu simpan dalam field request-local
                // agar jika validasi gagal, form dan toast tetap menampilkan nilai pengguna.
                DraftStartTime = ((TextBox)repeaterRow.FindControl("txtStartTime")).Text;
                DraftEndTime = ((TextBox)repeaterRow.FindControl("txtEndTime")).Text;
                DraftActivity = ((TextBox)repeaterRow.FindControl("txtActivity")).Text;
                DraftStatus = ((TextBox)repeaterRow.FindControl("txtWorkStatus")).Text;
                draftInitialized = true;
                DraftStartTime = NormalizeClock(DraftStartTime);
                DraftEndTime = NormalizeClock(DraftEndTime);
                // Jam input sudah otomatis dirapikan oleh JS; server tetap memvalidasi.
                TimeSpan startClock, endClock;
                if (!TimeSpan.TryParseExact(DraftStartTime, @"hh\:mm", CultureInfo.InvariantCulture, out startClock) ||
                    !TimeSpan.TryParseExact(DraftEndTime, @"hh\:mm", CultureInfo.InvariantCulture, out endClock))
                    throw new InvalidOperationException("Jam harus HH:mm, contohnya 08:00 atau ketik 0800.");
                DraftStartDate = TodayIso;
                DraftEndDate = endClock <= startClock ? TomorrowIso : TodayIso;
                SaveToSql(editing);
                SelectedIso = DraftStartDate;
                DetailMode = "view";
                SelectedEntryId = 0;
                ClearOriginalSnapshot();
                ShowNotice(editing ? "Aktivitas diperbarui" : "Aktivitas tersimpan", editing ? "Perubahan aktivitas berhasil disimpan." : "Aktivitas berhasil disimpan.", false);
            });
        }
        protected void btnConfirmDelete_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate
            {
                if (DetailMode != "delete" || SelectedEntryId <= 0 || String.IsNullOrEmpty(ExpandedMemberId))
                    throw new InvalidOperationException("Konfirmasi tidak tersedia.");
                DeleteFromSql();
                DetailMode = "view";
                SelectedEntryId = 0;
                ClearOriginalSnapshot();
                ShowNotice("Aktivitas dihapus", "Aktivitas berhasil dihapus.", false);
            });
        }
        protected void btnCancel_Click(object sender, EventArgs e)
        {
            RunAndBind(delegate
            {
                DetailMode = "view";
                SelectedEntryId = 0;
                ClearOriginalSnapshot();
            });
        }

        private static string SafeSqlLiteral(string input, int maxLength, string fieldName)
        {
            if (String.IsNullOrWhiteSpace(input) || input.Length > maxLength)
                throw new InvalidOperationException(fieldName + " tidak valid.");
            return input.Replace("'", "''");
        }

        private void SaveToSql(bool editing)
        {
            if (String.IsNullOrWhiteSpace(ExpandedMemberId) || ExpandedMemberId.Length > 10)
                throw new InvalidOperationException("EmployeeID tidak valid.");

            DateTime startDate, endDate, startAt, endAt;
            if (!DateTime.TryParseExact(DraftStartDate, IsoFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out startDate) ||
                !DateTime.TryParseExact(DraftEndDate, IsoFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out endDate))
                throw new InvalidOperationException("Tanggal tidak valid.");

            DateTime today = TodayDate;
            if (startDate.Date < today || startDate.Date > today.AddDays(1) ||
                endDate.Date < startDate.Date || endDate.Date > today.AddDays(1))
                throw new InvalidOperationException("Tanggal mulai/selesai hanya boleh hari ini hingga besok.");

            if (!DateTime.TryParseExact(DraftStartDate + " " + DraftStartTime, "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture,
                    DateTimeStyles.None, out startAt) || !DateTime.TryParseExact(DraftEndDate + " " + DraftEndTime,
                    "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out endAt))
                throw new InvalidOperationException("Jam harus HH:mm, misalnya 08:00.");

            if (endAt <= startAt || endAt - startAt > TimeSpan.FromHours(24))
                throw new InvalidOperationException("Durasi harus lebih dari 0 dan maksimal 24 jam.");

            string activity = (DraftActivity ?? "").Trim();
            if (activity.Length == 0 || activity.Length > 1000)
                throw new InvalidOperationException("Aktivitas wajib diisi, maksimal 1000 karakter.");

            if (SelectedIso != AsIso(startDate) || (editing && SelectedIso != TodayIso))
                throw new InvalidOperationException("Tanggal tidak sesuai dengan periode laporan.");

            using (BRC.T_DailyLogEmployee br = new BRC.T_DailyLogEmployee())
            {
                if (editing)
                {
                    if (SelectedEntryId <= 0 || OriginalStart == DateTime.MinValue)
                        throw new InvalidOperationException("Catatan tidak tersedia. Buka ulang detail.");
                    if (startAt.Date != OriginalStart.Date)
                        throw new InvalidOperationException("Tanggal mulai tidak boleh berubah saat Edit.");
                }

                br.InsertUpdateData(editing, ExpandedMemberId, LoginEmployeeID, startAt, endAt, activity, 
                                    SelectedEntryId, OriginalStart, OriginalEnd, OriginalActivity, startDate.Date);
            }
        }

        private void DeleteFromSql()
        {
            using (BRC.T_DailyLogEmployee br = new BRC.T_DailyLogEmployee())
            {
                if (SelectedIso != TodayIso)
                    throw new InvalidOperationException("Riwayat hanya boleh dilihat.");
                if (String.IsNullOrWhiteSpace(ExpandedMemberId) || ExpandedMemberId.Length > 10 ||
                    SelectedEntryId <= 0 || OriginalStart == DateTime.MinValue)
                    throw new InvalidOperationException("Aktivitas tidak valid. Buka ulang detail.");
                br.DeleteData(SelectedEntryId, ExpandedMemberId, LoginEmployeeID, OriginalStart, OriginalEnd, OriginalActivity);
            }
        }

    }
}