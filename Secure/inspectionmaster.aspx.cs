using System;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    public partial class inspectionmaster : WAL.PB, WAL.I_ToolBar_2
    {
        // Reuse the Inspection Type master permission while the dedicated
        // Inspection Setup menu entry is registered in the menu master.
        private const string _MenuID = "10013";
        private const int _MaxPdfBytes = 50 * 1024 * 1024;

        private string DraftMapFileKey
        {
            get
            {
                return "INSPEC_InspectionMapDraft_" +
                    SafePathPart(Master.Mn_CompanyID) + "_" +
                    SafePathPart(Master.Mn_LocationID) + "_" +
                    SafePathPart(Master.Mn_EmployeeID);
            }
        }

        protected void Page_Load(object sender, EventArgs e)
        {
            if (Page.Form != null) Page.Form.Enctype = "multipart/form-data";
            if (!IsPostBack)
            {
                if (base.AllowRead(_MenuID) == 2)
                    throw new Exception(WAL.GF.MSG_ACCESS_DENIED);

                Master.Mn_lit_Title = WAL.PB.AppID + " -> Inspection Setup";
                InitToolbar();
                BindAll();
                PrepareMap();
                PreparePoint();
            }
            PrepareScreen();
        }

        private void PrepareScreen()
        {
            string mapSearchArgs = Master.Mn_CompanyID + GF.Str + ";" +
                Master.Mn_LocationID + GF.Str + ";" +
                Master.Mn_ProfitCenterNo + GF.Str + ";" +
                Master.Mn_EmployeeID + GF.Str;

            lBtnMapCode.Attributes["onclick"] = GF.JSOpenSearchList_2(
                "155", "Master Inspection Map", txtMapCode.ClientID, false, mapSearchArgs);
            txtMapCode.Attributes["onkeydown"] = GF.JSOpenSearchList_2(
                "155", "Master Inspection Map", txtMapCode.ClientID, true, mapSearchArgs);
            //txtMapCode.Attributes["ondblclick"] = GF.JSOpenSearchList_2(
            //    "155", "Master Inspection Map", txtMapCode.ClientID, false, mapSearchArgs);
            btnClearMapFile.Visible = String.IsNullOrWhiteSpace(hidMapID.Value);
            fuMapPdf.Attributes["data-inspection-draft-key"] = DraftMapFileKey;
        }

        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            switch (e.ToolbarItem)
            {
                case ToolbarItem_2.New:
                    btnNewMap_Click(sender, EventArgs.Empty);
                    break;
                case ToolbarItem_2.Save:
                    btnSaveMap_Click(sender, EventArgs.Empty);
                    break;
                case ToolbarItem_2.Previous:
                    NavigateMap(-1);
                    break;
                case ToolbarItem_2.Next:
                    NavigateMap(1);
                    break;
            }
        }

        private void InitToolbar()
        {
            Master.TB_VisibleToolbar(true);
            Master.TB_VisibleButton(ToolbarItem_2.New, true);
            Master.TB_VisibleButton(ToolbarItem_2.Save, true);
            Master.TB_VisibleButton(ToolbarItem_2.Delete, false);
            Master.TB_VisibleButton(ToolbarItem_2.Previous, false);
            Master.TB_VisibleButton(ToolbarItem_2.Next, false);
            Master.TB_IsConfirmMessage(ToolbarItem_2.Delete, false);
        }

        private void NavigateMap(int direction)
        {
            string currentCode = txtMapCode.Text.Trim();
            using (var br = new WAL.BR.CF())
            {
                string order = direction < 0 ? "DESC" : "ASC";
                DataTable dt = br.EQueryP(@"
SELECT TOP 1 M.MapCode
FROM dbo.PIP_M_InspectionMap M
WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID
  AND M.IsCurrentVersion=1
  AND (@IsAdmin=1 OR M.EntryUser=@EmployeeID OR EXISTS (
      SELECT 1
      FROM dbo.PIP_M_InspectionType IT
      INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
      WHERE IT.InspectionTypeCode=M.InspectionTypeCode
        AND S.ProfitCenterNo=@ProfitCenterNo))
  AND ((@Direction=-1 AND M.MapCode < @CurrentCode)
       OR (@Direction=1 AND M.MapCode > @CurrentCode))
ORDER BY M.MapCode " + order,
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@EmployeeID", Master.Mn_EmployeeID),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo),
                        new SqlParameter("@Direction", direction),
                        new SqlParameter("@CurrentCode", currentCode)
                    });
                if (dt.Rows.Count == 0)
                {
                    GF.MsgBox(this, direction < 0 ? "Sudah di Map pertama." : "Sudah di Map terakhir.", "BS-5.3.0");
                    return;
                }
                txtMapCode.Text = Convert.ToString(dt.Rows[0]["MapCode"]);
            }
            txtMapCode_TextChanged(null, EventArgs.Empty);
        }

        protected void lbtn_PreRender(object sender, EventArgs e)
        {
            GF.AddAttdisabled_2(sender);
        }

        private void BindAll()
        {
            BindMaps();
            BindPointLookups();
            BindPoints();
            BindEditorMaps();
        }

        private void ShowMessage(string message, bool isError)
        {
            pnlMessage.Visible = true;
            pnlMessage.CssClass = "alert " + (isError ? "alert-danger" : "alert-success") + " alert-dismissible fade show mb-3";
            litMessage.Text = HttpUtility.HtmlEncode(message);
        }

        private void SetTab(string tab)
        {
            hidActiveTab.Value = tab;
        }

        private bool IsAdministrator()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"SELECT CASE WHEN EXISTS
(SELECT 1 FROM dbo.syswebuserusergroup WHERE usergroupid='administrator' AND userid=@UserID)
THEN 1 ELSE 0 END AS IsAdmin",
                    new SqlParameter[] { new SqlParameter("@UserID", Master.Mn_EmployeeID) });
                return dt.Rows.Count > 0 && Convert.ToInt32(dt.Rows[0]["IsAdmin"]) == 1;
            }
        }

        private void BindMaps()
        {
            // Registered Map grid is intentionally not displayed.
            // Map is opened directly by Map Code / SearchList.
        }

        private void BindPointLookups()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable types = br.EQueryP(@"
SELECT IT.InspectionTypeCode, IT.InspectionTypeName
FROM dbo.PIP_M_InspectionType IT
INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
WHERE IT.IsActive=1
  AND ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
  AND (@IsAdmin=1 OR S.ProfitCenterNo=@ProfitCenterNo)
ORDER BY IT.InspectionTypeCode",
                    new SqlParameter[] {
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
                ddlInspectionType.Items.Clear();
                ddlInspectionType.Items.Add(new ListItem("-- Select Inspection Type --", ""));
                if (types != null)
                {
                    foreach (DataRow row in types.Rows)
                        ddlInspectionType.Items.Add(new ListItem(
                            Convert.ToString(row["InspectionTypeCode"]) + " - " + Convert.ToString(row["InspectionTypeName"]),
                            Convert.ToString(row["InspectionTypeCode"])));
                }

                DataTable maps = br.EQueryP(@"
SELECT MapID, MapCode, MapName, MapVersion
FROM dbo.PIP_M_InspectionMap
WHERE CompanyID=@CompanyID AND LocationID=@LocationID
  AND IsCurrentVersion=1 AND IsActive=1
ORDER BY MapCode",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });
                ddlPointMap.Items.Clear();
                ddlPointMap.Items.Add(new ListItem("-- No Map (Optional) --", ""));
                ddlEditorMap.Items.Clear();
                ddlEditorMap.Items.Add(new ListItem("-- Select Map --", ""));
                if (maps != null)
                {
                    foreach (DataRow row in maps.Rows)
                    {
                        string value = Convert.ToString(row["MapID"]);
                        string label = Convert.ToString(row["MapCode"]) + " - " +
                            Convert.ToString(row["MapName"]) + " (v" + Convert.ToString(row["MapVersion"]) + ")";
                        ddlPointMap.Items.Add(new ListItem(label, value));
                        ddlEditorMap.Items.Add(new ListItem(label, value));
                    }
                }
            }
            BindInspectionDetails();
        }

        private void BindInspectionDetails()
        {
            string selected = ddlInspectionType.SelectedValue;
            ddlInspectionDetail.Items.Clear();
            ddlInspectionDetail.Items.Add(new ListItem("-- Select Inspection Detail --", ""));
            if (String.IsNullOrWhiteSpace(selected)) return;

            using (var br = new WAL.BR.CF())
            {
                DataTable details = br.EQueryP(@"
SELECT InspectionTypeDetailCode, InspectionTypeDetailName
FROM dbo.PIP_M_InspectionTypeDetail
WHERE InspectionTypeCode=@TypeCode
  AND CompanyID=@CompanyID AND LocationID=@LocationID AND IsActive=1
  AND EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionType IT
              INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
              WHERE IT.InspectionTypeCode=@TypeCode
                AND ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
                AND (@IsAdmin=1 OR S.ProfitCenterNo=@ProfitCenterNo))
ORDER BY InspectionTypeDetailCode",
                    new SqlParameter[] {
                        new SqlParameter("@TypeCode", selected),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
                if (details != null)
                {
                    foreach (DataRow row in details.Rows)
                        ddlInspectionDetail.Items.Add(new ListItem(
                            Convert.ToString(row["InspectionTypeDetailCode"]) + " - " +
                            Convert.ToString(row["InspectionTypeDetailName"]),
                            Convert.ToString(row["InspectionTypeDetailCode"])));
                }
            }
        }

        private int PointPageIndex
        {
            get { return ViewState["PointPageIndex"] == null ? 0 : Convert.ToInt32(ViewState["PointPageIndex"]); }
            set { ViewState["PointPageIndex"] = Math.Max(0, value); }
        }

        private int PointPageSize
        {
            get
            {
                int size;
                return Int32.TryParse(ddlPointPageSize.SelectedValue, out size)
                    ? Math.Max(10, Math.Min(100, size)) : 20;
            }
        }

        private void BindPoints()
        {
            int totalRecords = 0;
            string keyword = txtPointSearch.Text.Trim();
            int pageSize = PointPageSize;

            using (var br = new WAL.BR.CF())
            {
                DataTable count = br.EQueryP(@"
SELECT COUNT(1) AS TotalRecords
FROM dbo.PIP_M_InspectionPoint P
INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID AND P.MapID=@MapID
  AND P.IsActive=1
  AND (@Keyword='' OR P.PointCode LIKE '%' + @Keyword + '%')
  AND (@IsAdmin=1 OR EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionType IT
      INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
      WHERE IT.InspectionTypeCode=M.InspectionTypeCode AND S.ProfitCenterNo=@ProfitCenterNo))",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@Keyword", keyword),
                        new SqlParameter("@MapID", String.IsNullOrEmpty(hidMapID.Value) ? 0 : Convert.ToInt64(hidMapID.Value)),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
                if (count != null && count.Rows.Count > 0)
                    totalRecords = Convert.ToInt32(count.Rows[0]["TotalRecords"]);

                int totalPages = Math.Max(1, (int)Math.Ceiling((double)totalRecords / pageSize));
                if (PointPageIndex >= totalPages) PointPageIndex = totalPages - 1;
                int startRow = PointPageIndex * pageSize + 1;
                int endRow = startRow + pageSize - 1;

                DataTable page = br.EQueryP(@"
WITH PointRows AS
(
    SELECT P.InspectionPointID, P.PointCode, P.PointName,
           P.ObjectReferenceCode, P.IsNormalAbnormalRequired,
           P.DisplayOrder,
           ISNULL(M.MapCode,'') AS MapCode,
           ROW_NUMBER() OVER
           (
               ORDER BY M.InspectionTypeCode,
                        M.InspectionTypeDetailCode,
                        P.DisplayOrder,
                        P.PointCode,
                        P.InspectionPointID
           ) AS RowNum
    FROM dbo.PIP_M_InspectionPoint P
    INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
    WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID AND P.MapID=@MapID
      AND P.IsActive=1
      AND (@Keyword='' OR P.PointCode LIKE '%' + @Keyword + '%')
      AND (@IsAdmin=1 OR EXISTS
      (
          SELECT 1
          FROM dbo.PIP_M_InspectionType IT
          INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
          WHERE IT.InspectionTypeCode=M.InspectionTypeCode
            AND S.ProfitCenterNo=@ProfitCenterNo
      ))
)
SELECT InspectionPointID, PointCode, PointName,
       ObjectReferenceCode, IsNormalAbnormalRequired, DisplayOrder, MapCode
FROM PointRows
WHERE RowNum BETWEEN @StartRow AND @EndRow
ORDER BY RowNum",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@Keyword", keyword),
                        new SqlParameter("@MapID", String.IsNullOrEmpty(hidMapID.Value) ? 0 : Convert.ToInt64(hidMapID.Value)),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo),
                        new SqlParameter("@StartRow", startRow),
                        new SqlParameter("@EndRow", endRow)
                    });

                gvPoints.DataSource = page;
                gvPoints.DataBind();

                int firstRecord = totalRecords == 0 ? 0 : startRow;
                int lastRecord = Math.Min(endRow, totalRecords);
                lblPointPageInfo.Text = "Showing " + firstRecord + "–" + lastRecord + " of " + totalRecords + " points";
                lblPointPageTotal.Text = "of " + totalPages;
                txtPointGoToPage.Text = (PointPageIndex + 1).ToString(CultureInfo.InvariantCulture);

                bool hasPrevious = PointPageIndex > 0;
                bool hasNext = PointPageIndex < totalPages - 1;
                pnlPointPager.Visible = totalPages > 1;
                btnPointFirst.Enabled = btnPointPrevious.Enabled = hasPrevious;
                btnPointNext.Enabled = btnPointLast.Enabled = hasNext;
            }
        }

        protected void btnSearchPoint_Click(object sender, EventArgs e)
        {
            PointPageIndex = 0;
            BindPoints();
            SetTab("#tab-point");
        }

        protected void ddlPointPageSize_SelectedIndexChanged(object sender, EventArgs e)
        {
            PointPageIndex = 0;
            BindPoints();
            SetTab("#tab-point");
        }

        protected void btnPointFirst_Click(object sender, EventArgs e)
        {
            PointPageIndex = 0;
            BindPoints();
            SetTab("#tab-point");
        }

        protected void btnPointPrevious_Click(object sender, EventArgs e)
        {
            PointPageIndex = Math.Max(0, PointPageIndex - 1);
            BindPoints();
            SetTab("#tab-point");
        }

        protected void btnPointNext_Click(object sender, EventArgs e)
        {
            PointPageIndex++;
            BindPoints();
            SetTab("#tab-point");
        }

        protected void btnPointLast_Click(object sender, EventArgs e)
        {
            int totalRecords;
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT COUNT(1) AS TotalRecords
FROM dbo.PIP_M_InspectionPoint P
INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID AND P.MapID=@MapID
  AND P.IsActive=1
  AND (@Keyword='' OR P.PointCode LIKE '%' + @Keyword + '%')
  AND (@IsAdmin=1 OR EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionType IT
      INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
      WHERE IT.InspectionTypeCode=M.InspectionTypeCode AND S.ProfitCenterNo=@ProfitCenterNo))",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@Keyword", txtPointSearch.Text.Trim()),
                        new SqlParameter("@MapID", String.IsNullOrEmpty(hidMapID.Value) ? 0 : Convert.ToInt64(hidMapID.Value)),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
                totalRecords = Convert.ToInt32(dt.Rows[0]["TotalRecords"]);
            }
            PointPageIndex = Math.Max(0, (int)Math.Ceiling((double)totalRecords / PointPageSize) - 1);
            BindPoints();
            SetTab("#tab-point");
        }

        protected void btnPointGoToPage_Click(object sender, EventArgs e)
        {
            int page;
            if (!Int32.TryParse(txtPointGoToPage.Text.Trim(), out page) || page < 1)
            {
                //ShowMessage("Nomor halaman tidak valid.", true);
                GF.MsgBox(this, "Nomor halaman tidak valid.", "BS-5.3.0");
                BindPoints();
                SetTab("#tab-point");
                return;
            }
            PointPageIndex = page - 1;
            BindPoints();
            SetTab("#tab-point");
        }
        private void BindEditorMaps()
        {
            ddlEditorMap.Items.Clear();
            ddlEditorMap.Items.Add(new ListItem("", ""));
            if (!String.IsNullOrWhiteSpace(hidMapID.Value))
            {
                DataTable map = GetMap(Convert.ToInt64(hidMapID.Value));
                if (map.Rows.Count > 0)
                {
                    ddlEditorMap.Items.Add(new ListItem(Convert.ToString(map.Rows[0]["MapCode"]), hidMapID.Value));
                    ddlEditorMap.SelectedValue = hidMapID.Value;
                }
            }
        }

        private void PrepareMap()
        {
            hidMapID.Value = "";
            hidMapIsDraft.Value = "0";
            txtMapCode.Text = "";
            Master.TB_VisibleButton(ToolbarItem_2.Previous, false);
            Master.TB_VisibleButton(ToolbarItem_2.Next, false);
            txtMapName.Text = "";
            txtMapDescription.Text = "";
            txtMapGroupCode.Text = "";
            txtMapGroupName.Text = "";
            txtMapGroupDescription.Text = "";
            if (ddlInspectionType.Items.Count > 0) ddlInspectionType.SelectedIndex = 0;
            BindInspectionDetails();
            chkRequireAllPoints.Checked = true;
            lblMapVersion.Text = "New map · version will start at 1";
            pnlMapPreview.Visible = false;
        }

        private void PreparePoint()
        {
            hidPointID.Value = "";
            txtPointCode.Text = "";
            txtPointName.Text = "";
            txtObjectReferenceCode.Text = "";
            txtPointDescription.Text = "";
            txtPointOrder.Text = "0";
            chkNormalAbnormalRequired.Checked = false;
            if (ddlPointMap.Items.Count > 0) ddlPointMap.SelectedIndex = 0;
            if (!String.IsNullOrWhiteSpace(hidMapID.Value)) BindEditorMaps();
            txtMarkerX.Text = "";
            txtMarkerY.Text = "";
            hidSwapPointID.Value = "";
            btnSwapPosition.Visible = false;
            pnlEditor.Visible = false;
            pnlPointEditor.Visible = false;
        }

        protected void btnNewMap_Click(object sender, EventArgs e)
        {
            PrepareMap();
            PreparePoint();
            BindEditorMaps();
            pnlEditor.Visible = false;
            litEditorPdfBackground.Text = "";
            lnkEditorPdf.Visible = false;
            BindPoints();
            ScriptManager.RegisterStartupScript(this, GetType(), "clearInspectionMapDraft", "inspectionMasterClearDraft();", true);
            SetTab("#tab-map");
        }

        protected void btnEditMapRow_Command(object sender, CommandEventArgs e)
        {
            ProcessMapRowCommand("EditMap", e.CommandArgument);
        }

        protected void btnOpenMapRow_Command(object sender, CommandEventArgs e)
        {
            ProcessMapRowCommand("PreviewMap", e.CommandArgument);
        }

        private void ProcessMapRowCommand(string commandName, object commandArgument)
        {
            long mapID;
            if (!Int64.TryParse(Convert.ToString(commandArgument), out mapID) || mapID <= 0)
            {
                //ShowMessage("Map ID tidak valid. Silakan refresh daftar map.", true);
                GF.MsgBox(this, "Map ID tidak valid. Silakan refresh daftar map.", "BS-5.3.0");
                SetTab("#tab-map");
                return;
            }

            try
            {
                DataTable dt = GetMap(mapID);
                if (dt == null || dt.Rows.Count == 0)
                {
                    //ShowMessage("Data map tidak ditemukan untuk Map ID " +
                    //    mapID.ToString(CultureInfo.InvariantCulture) +
                    //    ". Periksa CompanyID/LocationID atau refresh daftar map.", true);
                    GF.MsgBox(this, "Data map tidak ditemukan untuk Map ID " +
                        mapID.ToString(CultureInfo.InvariantCulture) +
                        ". Periksa CompanyID/LocationID atau refresh daftar map.", "BS-5.3.0");
                    SetTab("#tab-map");
                    return;
                }

                DataRow row = dt.Rows[0];
                if (commandName == "EditMap")
                {
                    hidMapID.Value = mapID.ToString(CultureInfo.InvariantCulture);
                    hidMapIsDraft.Value = "0";
                    txtMapCode.Text = Convert.ToString(row["MapCode"]);
                    Master.TB_VisibleButton(ToolbarItem_2.Previous, true);
                    Master.TB_VisibleButton(ToolbarItem_2.Next, true);
                    txtMapName.Text = Convert.ToString(row["MapName"]);
                    txtMapDescription.Text = Convert.ToString(row["Description"]);
                    ddlInspectionType.SelectedValue = Convert.ToString(row["InspectionTypeCode"]);
                    BindInspectionDetails();
                    if (ddlInspectionDetail.Items.FindByValue(Convert.ToString(row["InspectionTypeDetailCode"])) != null)
                        ddlInspectionDetail.SelectedValue = Convert.ToString(row["InspectionTypeDetailCode"]);
                    chkRequireAllPoints.Checked = row["RequireAllPoints"] == DBNull.Value || Convert.ToBoolean(row["RequireAllPoints"]);
                    lblMapVersion.Text = "Current version: " + Convert.ToString(row["MapVersion"]) +
                        " · Upload PDF/JPG baru untuk membuat versi berikutnya.";
                }

                ShowMapPreview(row);
                SetTab("#tab-map");
            }
            catch (Exception ex)
            {
                //ShowMessage("Gagal membuka map: " + ex.Message, true);
                GF.MsgBox(this, "Gagal membuka map: " + ex.Message, "BS-5.3.0");
                SetTab("#tab-map");
            }
        }

        private DataTable GetMap(long mapID)
        {
            using (var br = new WAL.BR.CF())
                return br.EQueryP(@"
SELECT M.MapID, M.MapCode, M.MapName, M.ImagePath, M.MapVersion, M.IsActive, M.Description,
       M.InspectionTypeCode, M.InspectionTypeDetailCode, M.MapGroupID,
       ISNULL(G.GroupCode,'') AS GroupCode, ISNULL(G.GroupName,'') AS GroupName,
       ISNULL(G.Description,'') AS GroupDescription,
       ISNULL(M.RequireAllPoints,1) AS RequireAllPoints
FROM dbo.PIP_M_InspectionMap M
LEFT JOIN dbo.PIP_M_InspectionMapGroup G ON G.MapGroupID=M.MapGroupID AND G.CompanyID=M.CompanyID AND G.LocationID=M.LocationID
WHERE M.MapID=@MapID AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID
  AND (@IsAdmin=1 OR M.EntryUser=@EmployeeID OR EXISTS
      (SELECT 1 FROM dbo.PIP_M_InspectionType IT
       INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
       WHERE IT.InspectionTypeCode=M.InspectionTypeCode
         AND S.ProfitCenterNo=@ProfitCenterNo))",
                    new SqlParameter[] {
                        new SqlParameter("@MapID", mapID),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@EmployeeID", Master.Mn_EmployeeID),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
        }

        private string GetCurrentMapImagePath()
        {
            long mapID;
            if (!Int64.TryParse(hidMapID.Value, out mapID) || mapID <= 0)
                return "";

            DataTable map = GetMap(mapID);
            if (map == null || map.Rows.Count == 0)
                return "";

            return Convert.ToString(map.Rows[0]["ImagePath"]).Trim();
        }

        private string ResolveMapPdfUrl(string storedPath)
        {
            string path = (storedPath ?? "").Trim();
            if (path == "") return "";

            // New records store only the generated filename. Older records may
            // still contain an absolute URL or a relative path, so normalize
            // all formats to the same environment-specific ToolsLib location.
            Uri oldUrl;
            if (Uri.TryCreate(path, UriKind.Absolute, out oldUrl) &&
                (oldUrl.Scheme == Uri.UriSchemeHttp || oldUrl.Scheme == Uri.UriSchemeHttps))
                path = oldUrl.AbsolutePath;

            path = path.Replace("\\", "/");
            int slash = path.LastIndexOf('/');
            string fileName = slash >= 0 ? path.Substring(slash + 1) : path;
            fileName = fileName.Split('?')[0].Split('#')[0];
            if (fileName == "") return "";

            string companyLocation = SafePathPart(Master.Mn_CompanyID) + "_" +
                SafePathPart(Master.Mn_LocationID);
            string relativeUrl = "/ToolsLib/" + GetInspectionMapRoot() +
                "/PIP_M_InspectionMap/" + companyLocation + "/" +
                HttpUtility.UrlPathEncode(fileName);
            return Request.Url.GetLeftPart(UriPartial.Authority) + relativeUrl;
        }

        private void ShowMapPreview(DataRow row)
        {
            string url = ResolveMapPdfUrl(Convert.ToString(row["ImagePath"]));
            string extension = Path.GetExtension(url).ToLowerInvariant();
            bool isJpeg = extension == ".jpg" || extension == ".jpeg";
            bool hasFloorPlan = !String.IsNullOrWhiteSpace(url);
            lblMapPreviewTitle.Text = Convert.ToString(row["MapCode"]) + " - " + Convert.ToString(row["MapName"]) + " (v" + Convert.ToString(row["MapVersion"]) + ")";
            lnkMapPdf.NavigateUrl = url;
            lnkMapPdf.Visible = hasFloorPlan;
            string markers = BuildMapPreviewMarkers(Convert.ToInt64(row["MapID"]));
            string media = !hasFloorPlan
                ? "<div class='alert alert-light border small mb-0'>Floor Plan belum diupload. Inspection Point tetap dapat digunakan tanpa denah.</div>"
                : (isJpeg
                    ? "<img class='inspection-image-preview' alt='Inspection floor plan' src='" + HttpUtility.HtmlAttributeEncode(url) + "' />"
                    : "<canvas id='inspectionMapPreviewCanvas' class='inspection-map-preview-canvas' data-map-url='" + HttpUtility.HtmlAttributeEncode(url) + "' aria-label='Inspection floor plan'></canvas><div id='inspectionMapPreviewStatus' class='inspection-pdf-status'>Memuat denah...</div>");
            litMapPreview.Text = "<div class='inspection-map-preview-toolbar d-flex align-items-center gap-1 mb-2'>" +
                "<button type='button' class='btn btn-sm btn-outline-secondary' id='btnMapPreviewZoomOut' title='Zoom out'><i class='bi bi-zoom-out'></i></button>" +
                "<button type='button' class='btn btn-sm btn-outline-secondary' id='btnMapPreviewZoomIn' title='Zoom in'><i class='bi bi-zoom-in'></i></button>" +
                "<button type='button' class='btn btn-sm btn-outline-secondary' id='btnMapPreviewZoomFit'>Fit</button>" +
                "<span class='small text-muted ms-1' id='lblMapPreviewZoom'>100%</span>" +
                "<span class='small text-muted ms-auto'>Titik = master point sudah memiliki koordinat</span></div>" +
                "<div class='inspection-map-preview-stage' id='inspectionMapPreviewStage'><div class='inspection-map-preview-media' id='inspectionMapPreviewMedia'>" + media +
                "<div class='inspection-map-preview-markers'>" + markers + "</div></div></div>";
            pnlMapPreview.Visible = true;
        }

        private string BuildMapPreviewMarkers(long mapID)
        {
            DataTable points;
            using (var br = new WAL.BR.CF())
                points = br.EQueryP(@"
SELECT P.MapX, P.MapY, P.PointCode, P.PointName
FROM dbo.PIP_M_InspectionPoint P
INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID
  AND P.MapID=@MapID AND P.IsActive=1
  AND P.MapX IS NOT NULL AND P.MapY IS NOT NULL
ORDER BY P.DisplayOrder, P.PointCode",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@MapID", mapID)
                    });

            System.Text.StringBuilder html = new System.Text.StringBuilder();
            foreach (DataRow point in points.Rows)
            {
                string pointLabel = Convert.ToString(point["PointCode"]) + " - " + Convert.ToString(point["PointName"]);
                html.Append("<span class='inspection-map-preview-marker' data-bs-toggle='tooltip' data-bs-placement='top' title='");
                html.Append(HttpUtility.HtmlAttributeEncode(pointLabel));
                html.Append("' style='left:");
                html.Append(Convert.ToDecimal(point["MapX"]).ToString("0.####", CultureInfo.InvariantCulture));
                html.Append("%;top:");
                html.Append(Convert.ToDecimal(point["MapY"]).ToString("0.####", CultureInfo.InvariantCulture));
                html.Append("%'></span>");
            }
            return html.ToString();
        }

        private void LoadEditorMapPdf()
        {
            string url = "";
            string mapLabel = "";

            if (!String.IsNullOrWhiteSpace(ddlEditorMap.SelectedValue))
            {
                DataTable selectedMap = GetMap(Convert.ToInt64(ddlEditorMap.SelectedValue));
                if (selectedMap == null || selectedMap.Rows.Count == 0)
                    throw new Exception("Map yang dipilih tidak ditemukan.");

                url = ResolveMapPdfUrl(Convert.ToString(selectedMap.Rows[0]["ImagePath"]));
                mapLabel = Convert.ToString(selectedMap.Rows[0]["MapCode"]);
            }
            else
            {
                // A new Map's floor-plan draft stays in browser IndexedDB.
                // inspectionmaster.js restores the Blob and supplies its object URL.
                mapLabel = "New Map (not saved)";
            }

            if (String.IsNullOrWhiteSpace(url))
            {
                // Floor plan is optional. Keep the point editor usable without
                // a background map; MapX/MapY remain optional as well.
                if (String.IsNullOrWhiteSpace(ddlEditorMap.SelectedValue))
                {
                    // New Map draft: the browser restores its IndexedDB Blob here.
                    litEditorPdfBackground.Text = "<canvas id='inspectionPdfCanvas' class='inspection-coordinate-pdf' data-map-url='' aria-label='Inspection floor plan'></canvas><div id='inspectionPdfStatus' class='inspection-pdf-status'>Pilih PDF/JPG denah untuk menampilkan background.</div>";
                }
                else
                {
                    litEditorPdfBackground.Text = "";
                }
                lnkEditorPdf.Visible = false;
                lblPointMapCode.Text = "· " + mapLabel + " (tanpa denah)";
                return;
            }

            string extension = Path.GetExtension(url).ToLowerInvariant();
            bool isJpeg = extension == ".jpg" || extension == ".jpeg";
            string media = isJpeg
                ? "<img id='inspectionPdfCanvas' class='inspection-coordinate-pdf' data-map-url='" + HttpUtility.HtmlAttributeEncode(url) + "' alt='Inspection floor plan' />"
                : "<canvas id='inspectionPdfCanvas' class='inspection-coordinate-pdf' data-map-url='" + HttpUtility.HtmlAttributeEncode(url) + "' aria-label='Inspection floor plan'></canvas>";
            litEditorPdfBackground.Text = media + "<div id='inspectionPdfStatus' class='inspection-pdf-status'>Memuat denah...</div>";
            lnkEditorPdf.NavigateUrl = url;
            lnkEditorPdf.Visible = true;
            lblPointMapCode.Text = "· " + mapLabel;
        }
        protected void btnSaveMap_Click(object sender, EventArgs e)
        {
            string code = txtMapCode.Text.Trim().ToUpperInvariant();
            string name = txtMapName.Text.Trim();
            string typeCode = ddlInspectionType.SelectedValue;
            string detailCode = ddlInspectionDetail.SelectedValue;
            if (code == "" || name == "" || typeCode == "" || detailCode == "")
            {
                //ShowMessage("Map Code, Map Name, Inspection Type, dan Inspection Detail wajib diisi.", true);
                GF.MsgBox(this, "Map Code, Map Name, Inspection Type, dan Inspection Detail wajib diisi.", "BS-5.3.0");
                SetTab("#tab-map");
                return;
            }

            if (!IsValidMapTypeDetail(typeCode, detailCode))
            {
                //ShowMessage("Inspection Type atau Detail tidak aktif, bukan mode BATCH, atau tidak termasuk Profit Center Anda.", true);
                GF.MsgBox(this, "Inspection Type atau Detail tidak aktif, bukan mode BATCH, atau tidak termasuk Profit Center Anda.", "BS-5.3.0");
                SetTab("#tab-map");
                return;
            }

            string savedPath = "";
            bool databaseSaved = false;
            bool uploadedThisRequest = false;
            try
            {
                long? mapGroupID = SaveOrGetMapGroup();
                if (fuMapPdf.HasFile)
                {
                    savedPath = SaveMapFile(fuMapPdf);
                    uploadedThisRequest = true;
                }
                // A selected draft file is restored into fuMapPdf from browser IndexedDB
                // before postback. No temporary server-side file or Session path is used.

                using (var br = new WAL.BR.CF())
                {
                    long oldID;
                    bool editing = Int64.TryParse(hidMapID.Value, out oldID) && oldID > 0;
                    if (editing)
                    {
                        DataTable old = GetMap(oldID);
                        if (old.Rows.Count == 0) throw new Exception("Map yang dipilih tidak ditemukan.");
                        if (savedPath == "")
                        {
                            br.EQueryP(@"
UPDATE dbo.PIP_M_InspectionMap
SET MapCode=@MapCode, MapName=@MapName, Description=@Description, MapGroupID=@MapGroupID,
    InspectionTypeCode=@TypeCode, InspectionTypeDetailCode=@DetailCode,
    RequireAllPoints=@RequireAllPoints, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@MapID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                                MapParameters(oldID, code, name, Convert.ToString(old.Rows[0]["ImagePath"]), mapGroupID));
                        }
                        else if (hidMapIsDraft.Value == "1")
                        {
                            string imagePath = savedPath == "" ? Convert.ToString(old.Rows[0]["ImagePath"]) : savedPath;
                            br.EQueryP(@"
UPDATE dbo.PIP_M_InspectionMap
SET MapCode=@MapCode, MapName=@MapName, ImagePath=@ImagePath, Description=@Description, MapGroupID=@MapGroupID,
    InspectionTypeCode=@TypeCode, InspectionTypeDetailCode=@DetailCode,
    RequireAllPoints=@RequireAllPoints, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@MapID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                                MapParameters(oldID, code, name, imagePath, mapGroupID));
                        }
                        else
                        {
                            int version;
                            using (var brVersion = new WAL.BR.CF())
                            {
                                DataTable next = brVersion.EQueryP(@"
SELECT ISNULL(MAX(MapVersion),0)+1 AS NextVersion
FROM dbo.PIP_M_InspectionMap
WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND MapCode=@MapCode",
                                    new SqlParameter[] {
                                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                                        new SqlParameter("@MapCode", code)
                                    });
                                version = Convert.ToInt32(next.Rows[0]["NextVersion"]);
                            }
                            long newID = NextId("dbo.PIP_M_InspectionMap", "MapID");
                            br.EQueryP(@"
UPDATE dbo.PIP_M_InspectionMap
SET IsCurrentVersion=0, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@OldMapID AND CompanyID=@CompanyID AND LocationID=@LocationID;
INSERT INTO dbo.PIP_M_InspectionMap
(MapID,CompanyID,LocationID,MapCode,MapName,ImagePath,ViewBoxX,ViewBoxY,ViewBoxWidth,ViewBoxHeight,
 MapGroupID,MapVersion,InspectionTypeCode,InspectionTypeDetailCode,RequireAllPoints,IsCurrentVersion,IsActive,Description,EntryUser,UpdateUser)
VALUES
(@NewMapID,@CompanyID,@LocationID,@MapCode,@MapName,@ImagePath,0,0,100,100,@MapGroupID,
 @MapVersion,@TypeCode,@DetailCode,@RequireAllPoints,1,1,@Description,@UpdateUser,@UpdateUser);
UPDATE dbo.PIP_M_InspectionPoint SET MapID=@NewMapID, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@OldMapID;
",
                                new SqlParameter[] {
                                    new SqlParameter("@OldMapID", oldID), new SqlParameter("@NewMapID", newID), new SqlParameter("@MapGroupID", (object)mapGroupID ?? DBNull.Value),
                                    new SqlParameter("@CompanyID", Master.Mn_CompanyID), new SqlParameter("@LocationID", Master.Mn_LocationID),
                                    new SqlParameter("@MapCode", code), new SqlParameter("@MapName", name),
                                    new SqlParameter("@ImagePath", savedPath), new SqlParameter("@MapVersion", version),
                                    new SqlParameter("@Description", txtMapDescription.Text.Trim()),
                                    new SqlParameter("@TypeCode", typeCode),
                                    new SqlParameter("@DetailCode", detailCode),
                                    new SqlParameter("@RequireAllPoints", chkRequireAllPoints.Checked),
                                    new SqlParameter("@UpdateUser", Master.Mn_EmployeeID)
                                });
                            hidMapID.Value = newID.ToString(CultureInfo.InvariantCulture);
                        }
                    }
                    else
                    {
                        // Floor plan is optional for a Map master. An empty
                        // ImagePath means this Map is intentionally configured
                        // without a background denah.
                        int version;
                        using (var brVersion = new WAL.BR.CF())
                        {
                            DataTable next = brVersion.EQueryP(@"
SELECT ISNULL(MAX(MapVersion),0)+1 AS NextVersion
FROM dbo.PIP_M_InspectionMap
WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND MapCode=@MapCode",
                                new SqlParameter[] {
                                    new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                                    new SqlParameter("@LocationID", Master.Mn_LocationID),
                                    new SqlParameter("@MapCode", code)
                                });
                            version = Convert.ToInt32(next.Rows[0]["NextVersion"]);
                        }
                        long newID = NextId("dbo.PIP_M_InspectionMap", "MapID");
                        br.EQueryP(@"
INSERT INTO dbo.PIP_M_InspectionMap
(MapID,CompanyID,LocationID,MapCode,MapName,ImagePath,ViewBoxX,ViewBoxY,ViewBoxWidth,ViewBoxHeight,
 MapGroupID,MapVersion,InspectionTypeCode,InspectionTypeDetailCode,RequireAllPoints,IsCurrentVersion,IsActive,Description,EntryUser,UpdateUser)
VALUES
(@MapID,@CompanyID,@LocationID,@MapCode,@MapName,@ImagePath,0,0,100,100,@MapGroupID,
 @MapVersion,@TypeCode,@DetailCode,@RequireAllPoints,1,1,@Description,@UpdateUser,@UpdateUser)",
                            new SqlParameter[] {
                                new SqlParameter("@MapID", newID), new SqlParameter("@MapGroupID", (object)mapGroupID ?? DBNull.Value), new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                                new SqlParameter("@LocationID", Master.Mn_LocationID), new SqlParameter("@MapCode", code),
                                new SqlParameter("@MapName", name), new SqlParameter("@ImagePath", savedPath),
                                new SqlParameter("@MapVersion", version), new SqlParameter("@Description", txtMapDescription.Text.Trim()),
                                new SqlParameter("@TypeCode", typeCode),
                                new SqlParameter("@DetailCode", detailCode),
                                new SqlParameter("@RequireAllPoints", chkRequireAllPoints.Checked),
                                new SqlParameter("@UpdateUser", Master.Mn_EmployeeID)
                            });
                        hidMapID.Value = newID.ToString(CultureInfo.InvariantCulture);
                    }
                }

                databaseSaved = true;
                hidMapIsDraft.Value = "0";

                // After the first successful save of a new Map Code, the
                // Previous/Next toolbar becomes available for this Map.
                Master.TB_VisibleButton(ToolbarItem_2.Previous, true);
                Master.TB_VisibleButton(ToolbarItem_2.Next, true);

                BindMaps();
                BindEditorMaps();
                PointPageIndex = 0;
                txtPointSearch.Text = "";
                BindPoints();
                DataTable current = GetMap(Convert.ToInt64(hidMapID.Value));
                if (current.Rows.Count > 0) ShowMapPreview(current.Rows[0]);
                lblMapVersion.Text = "Map tersimpan. PDF dan versi map sudah tercatat.";
                //ShowMessage("Map berhasil disimpan.", false);
                GF.MsgBox(this, "Map berhasil disimpan.", "BS-5.3.0");
                ScriptManager.RegisterStartupScript(this, GetType(), "clearInspectionMapDraft", "inspectionMasterClearDraft();", true);
            }
            catch (Exception ex)
            {
                if (!databaseSaved && uploadedThisRequest && savedPath != "") TryDeleteFile(savedPath);
                //ShowMessage("Gagal menyimpan map: " + ex.Message, true);
                GF.MsgBox(this, "Gagal menyimpan map: " + ex.Message, "BS-5.3.0");
            }
            SetTab("#tab-map");
        }

        private bool IsValidMapTypeDetail(string typeCode, string detailCode)
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT COUNT(1) AS TotalRows
FROM dbo.PIP_M_InspectionType IT
INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
INNER JOIN dbo.PIP_M_InspectionTypeDetail D ON D.InspectionTypeCode=IT.InspectionTypeCode
WHERE IT.InspectionTypeCode=@TypeCode
  AND D.InspectionTypeDetailCode=@DetailCode
  AND D.CompanyID=@CompanyID AND D.LocationID=@LocationID
  AND IT.IsActive=1 AND D.IsActive=1
  AND ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
  AND (@IsAdmin=1 OR S.ProfitCenterNo=@ProfitCenterNo)",
                    new SqlParameter[] {
                        new SqlParameter("@TypeCode", typeCode),
                        new SqlParameter("@DetailCode", detailCode),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
                return dt != null && dt.Rows.Count > 0 && Convert.ToInt32(dt.Rows[0]["TotalRows"]) > 0;
            }
        }

        private long? SaveOrGetMapGroup()
        {
            string groupCode = (txtMapGroupCode.Text ?? "").Trim().ToUpperInvariant();
            string groupName = (txtMapGroupName.Text ?? "").Trim();
            string groupDescription = (txtMapGroupDescription.Text ?? "").Trim();
            if (groupCode == "" && groupName == "" && groupDescription == "") return null;
            if (groupCode == "" || groupName == "")
                throw new Exception("Map Group Code dan Map Group Name harus diisi bersama-sama.");

            long newID = NextId("dbo.PIP_M_InspectionMapGroup", "MapGroupID");
            using (var br = new WAL.BR.CF())
            {
                DataTable saved = br.EQueryP(@"
DECLARE @MapGroupID BIGINT;
SELECT @MapGroupID=MapGroupID
FROM dbo.PIP_M_InspectionMapGroup
WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND GroupCode=@GroupCode;
IF @MapGroupID IS NULL
BEGIN
    SET @MapGroupID=@NewMapGroupID;
    INSERT INTO dbo.PIP_M_InspectionMapGroup
    (MapGroupID,CompanyID,LocationID,GroupCode,GroupName,Description,DisplayOrder,IsActive,EntryUser,UpdateUser)
    VALUES
    (@MapGroupID,@CompanyID,@LocationID,@GroupCode,@GroupName,@Description,0,1,@UpdateUser,@UpdateUser);
END
ELSE
BEGIN
    UPDATE dbo.PIP_M_InspectionMapGroup
    SET GroupName=@GroupName, Description=@Description, IsActive=1,
        UpdateUser=@UpdateUser, UpdateDate=GETDATE()
    WHERE MapGroupID=@MapGroupID AND CompanyID=@CompanyID AND LocationID=@LocationID;
END
SELECT @MapGroupID AS MapGroupID;",
                    new SqlParameter[] {
                        new SqlParameter("@NewMapGroupID", newID),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@GroupCode", groupCode),
                        new SqlParameter("@GroupName", groupName),
                        new SqlParameter("@Description", groupDescription),
                        new SqlParameter("@UpdateUser", Master.Mn_EmployeeID)
                    });
                if (saved == null || saved.Rows.Count == 0) throw new Exception("Map Group gagal disimpan.");
                return Convert.ToInt64(saved.Rows[0]["MapGroupID"]);
            }
        }

        private SqlParameter[] MapParameters(long mapID, string code, string name, string imagePath, long? mapGroupID)
        {
            return new SqlParameter[] {
                new SqlParameter("@MapID", mapID), new SqlParameter("@MapCode", code),
                new SqlParameter("@MapName", name), new SqlParameter("@ImagePath", imagePath),
                new SqlParameter("@Description", txtMapDescription.Text.Trim()),
                new SqlParameter("@MapGroupID", (object)mapGroupID ?? DBNull.Value),
                new SqlParameter("@TypeCode", ddlInspectionType.SelectedValue),
                new SqlParameter("@DetailCode", ddlInspectionDetail.SelectedValue),
                new SqlParameter("@RequireAllPoints", chkRequireAllPoints.Checked),
                new SqlParameter("@UpdateUser", Master.Mn_EmployeeID),
                new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                new SqlParameter("@LocationID", Master.Mn_LocationID)
            };
        }

        private string SaveMapFile(FileUpload upload)
        {
            if (upload == null || !upload.HasFile) throw new Exception("Silakan pilih file PDF atau JPG/JPEG denah.");
            if (upload.PostedFile.ContentLength <= 0 || upload.PostedFile.ContentLength > _MaxPdfBytes)
                throw new Exception("Ukuran file denah harus lebih dari 0 dan maksimal 50 MB.");
            string extension = Path.GetExtension(upload.FileName).ToLowerInvariant();
            byte[] signature = new byte[8];
            upload.PostedFile.InputStream.Position = 0;
            int read = upload.PostedFile.InputStream.Read(signature, 0, signature.Length);
            bool pdf = extension == ".pdf" && read >= 5 && System.Text.Encoding.ASCII.GetString(signature, 0, 5) == "%PDF-";
            bool jpg = (extension == ".jpg" || extension == ".jpeg") && read >= 3 && signature[0] == 0xFF && signature[1] == 0xD8 && signature[2] == 0xFF;
            if (!pdf && !jpg) throw new Exception("Format denah tidak valid. Gunakan PDF atau JPG/JPEG yang valid.");
            string webFolder = PB.Path_WebFolder1;
            if (String.IsNullOrWhiteSpace(webFolder)) throw new Exception("PB.Path_WebFolder1 is empty; Inspection map storage root is not configured.");
            string relativeFolder = Path.Combine(GetInspectionMapRoot(), "PIP_M_InspectionMap", SafePathPart(Master.Mn_CompanyID) + "_" + SafePathPart(Master.Mn_LocationID));
            string physicalFolder = Path.Combine(webFolder, relativeFolder);
            if (!Directory.Exists(physicalFolder)) Directory.CreateDirectory(physicalFolder);
            string fileName = Guid.NewGuid().ToString("N") + extension;
            upload.PostedFile.InputStream.Position = 0;
            upload.SaveAs(Path.Combine(physicalFolder, fileName));
            // ImagePath is deliberately environment-independent. The URL is
            // reconstructed from the current request when the map is displayed.
            return fileName;
        }
        private string GetInspectionMapRoot()
        {
            string appPath = Request.ApplicationPath ?? "";
            string root = appPath.Trim('/').ToUpperInvariant();
            root = root.Replace("INSPEC", "PIP");
            return String.IsNullOrEmpty(root) ? "PIP" : root;
        }

        private string SafePathPart(string value)
        {
            string result = new string((value ?? "").Where(
                c => Char.IsLetterOrDigit(c) || c == '-' || c == '_').ToArray());

            return result == "" ? "_" : result;
        }

        private void TryDeleteFile(string storedPath)
        {
            try
            {
                if (String.IsNullOrWhiteSpace(storedPath)) return;

                // ImagePath stores a filename (legacy full URLs are also accepted).
                // Only delete GUID-named PDF/JPG files from this map's configured folder.
                string normalized = storedPath.Replace("\\", "/");
                int slash = normalized.LastIndexOf('/');
                string fileName = slash >= 0 ? normalized.Substring(slash + 1) : normalized;

                Guid fileID;
                string extension = Path.GetExtension(fileName);
                if (!(extension.Equals(".pdf", StringComparison.OrdinalIgnoreCase) ||
                      extension.Equals(".jpg", StringComparison.OrdinalIgnoreCase) ||
                      extension.Equals(".jpeg", StringComparison.OrdinalIgnoreCase)) ||
                    !Guid.TryParseExact(Path.GetFileNameWithoutExtension(fileName), "N", out fileID))
                    return;

                string webFolder = PB.Path_WebFolder1;
                if (String.IsNullOrWhiteSpace(webFolder)) return;

                string root = GetInspectionMapRoot();
                string companyLocation =
                    SafePathPart(Master.Mn_CompanyID) + "_" + SafePathPart(Master.Mn_LocationID);

                string physicalFolder = Path.Combine(
                    webFolder, root, "PIP_M_InspectionMap", companyLocation);

                string fullPath = Path.Combine(physicalFolder, fileName);
                if (File.Exists(fullPath)) File.Delete(fullPath);
            }
            catch { }
        }

        private long NextId(string tableName, string columnName)
        {
            // Table/column names are constants supplied only by this page.
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQuery("SELECT ISNULL(MAX(" + columnName + "),0)+1 AS NextID FROM " + tableName);
                return Convert.ToInt64(dt.Rows[0]["NextID"]);
            }
        }

        protected void txtMapCode_TextChanged(object sender, EventArgs e)
        {
            string code = txtMapCode.Text.Trim();
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT TOP 1 M.MapID, M.MapCode, M.MapName, M.Description, M.MapVersion, M.ImagePath,
       M.InspectionTypeCode, M.InspectionTypeDetailCode, M.RequireAllPoints, M.MapGroupID,
       ISNULL(G.GroupCode,'') AS GroupCode, ISNULL(G.GroupName,'') AS GroupName,
       ISNULL(G.Description,'') AS GroupDescription
FROM dbo.PIP_M_InspectionMap M
LEFT JOIN dbo.PIP_M_InspectionMapGroup G ON G.MapGroupID=M.MapGroupID AND G.CompanyID=M.CompanyID AND G.LocationID=M.LocationID
WHERE M.MapCode=@MapCode AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID
  AND M.IsCurrentVersion=1
  AND (@IsAdmin=1 OR M.EntryUser=@EmployeeID OR EXISTS
      (SELECT 1 FROM dbo.PIP_M_InspectionType IT
       INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
       WHERE IT.InspectionTypeCode=M.InspectionTypeCode
         AND S.ProfitCenterNo=@ProfitCenterNo))
ORDER BY M.MapVersion DESC",
                    new SqlParameter[] {
                        new SqlParameter("@MapCode", code),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo),
                        new SqlParameter("@EmployeeID", Master.Mn_EmployeeID)
                    });
                if (dt.Rows.Count == 0)
                {
                    hidMapID.Value = "";
                    txtMapName.Text = "";
                    txtMapDescription.Text = "";
                    txtMapGroupCode.Text = "";
                    txtMapGroupName.Text = "";
                    txtMapGroupDescription.Text = "";
                    lblMapVersion.Text = "New map · version will start at 1";
                    pnlMapPreview.Visible = false;
                    Master.TB_VisibleButton(ToolbarItem_2.Previous, false);
                    Master.TB_VisibleButton(ToolbarItem_2.Next, false);
                    BindEditorMaps();
                    pnlEditor.Visible = false;
                    litEditorPdfBackground.Text = "";
                    lnkEditorPdf.Visible = false;
                    //ShowMessage("Map tidak ditemukan atau tidak termasuk Profit Center Anda.", true);
                    BindPoints();
                    SetTab("#tab-map");
                    return;
                }
                DataRow row = dt.Rows[0];
                hidMapID.Value = Convert.ToString(row["MapID"]);
                hidMapIsDraft.Value = "0";
                txtMapCode.Text = Convert.ToString(row["MapCode"]);
                Master.TB_VisibleButton(ToolbarItem_2.Previous, true);
                Master.TB_VisibleButton(ToolbarItem_2.Next, true);
                txtMapName.Text = Convert.ToString(row["MapName"]);
                txtMapDescription.Text = Convert.ToString(row["Description"]);
                txtMapGroupCode.Text = Convert.ToString(row["GroupCode"]);
                txtMapGroupName.Text = Convert.ToString(row["GroupName"]);
                txtMapGroupDescription.Text = Convert.ToString(row["GroupDescription"]);
                lblMapVersion.Text = "Current version: " + Convert.ToString(row["MapVersion"]);
                GF.SelectListItem(ref ddlInspectionType, GF.GetString(row["InspectionTypeCode"]));
                BindInspectionDetails();
                GF.SelectListItem(ref ddlInspectionDetail, GF.GetString(row["InspectionTypeDetailCode"]));
                chkRequireAllPoints.Checked = GF.GetBoolean(row["RequireAllPoints"]);
                ShowMapPreview(row);
            }
            PreparePoint();
            txtPointSearch.Text = "";
            PointPageIndex = 0;
            BindEditorMaps();
            pnlEditor.Visible = false;
            litEditorPdfBackground.Text = "";
            lnkEditorPdf.Visible = false;
            BindPoints();
            //GF.MsgBox(this, "Map " + txtMapCode.Text + " berhasil dibuka", "BS-5.3.0");
            SetTab("#tab-map");
        }

        private void ShowPointEditor()
        {
            pnlPointEditor.Visible = true;
        }

        protected override void OnPreRender(EventArgs e)
        {
            base.OnPreRender(e);
            if (pnlPointEditor.Visible)
            {
                ScriptManager.RegisterStartupScript(this, GetType(), "showInspectionPointModal",
                    "var m=document.getElementById('pnlPointEditor');if(m){var x=bootstrap.Modal.getOrCreateInstance(m);x.show();}", true);
            }
        }

        protected void ddlInspectionType_SelectedIndexChanged(object sender, EventArgs e)
        {
            BindInspectionDetails();
            SetTab("#tab-map");
        }

        protected void btnNewPoint_Click(object sender, EventArgs e)
        {
            PreparePoint();
            ShowPointEditor();
            SetTab("#tab-point");
        }

        protected void btnClosePoint_Click(object sender, EventArgs e)
        {
            pnlPointEditor.Visible = false;
        }

        protected void btnClearMapFile_Click(object sender, EventArgs e)
        {
            // The browser-side draft is cleared by inspectionmaster.js.
            litEditorPdfBackground.Text = "";
            lnkEditorPdf.Visible = false;
            pnlEditor.Visible = false;
            pnlPointEditor.Visible = false;
            ScriptManager.RegisterStartupScript(this, GetType(), "clearInspectionMapDraft", "inspectionMasterClearDraft();", true);
            GF.MsgBox(this, "Floor Plan draft dikosongkan. Silakan attach file baru bila diperlukan.", "BS-5.3.0");
            SetTab("#tab-map");
        }

        protected void btnNewPointGrid_Click(object sender, EventArgs e)
        {
            // Add Point requires a Map Code, but the floor plan is optional.
            // A point can therefore be created before any PDF/JPG is uploaded.
            if (txtMapCode.Text == "")
            {
                GF.MsgBox(this, "Map Code must not empty.", "BS-5.3.0");
                return;
            }
            if (txtMapName.Text == "")
            {
                GF.MsgBox(this, "Map Name must not empty.", "BS-5.3.0");
                return;
            }
            if (ddlInspectionType.SelectedValue == "")
            {
                GF.MsgBox(this, "Inspection Type must not empty.", "BS-5.3.0");
                return;
            }
            if (ddlInspectionDetail.SelectedValue == "")
            {
                GF.MsgBox(this, "Inspection Type Detail must not empty.", "BS-5.3.0");
                return;
            }
            //if (String.IsNullOrWhiteSpace(txtMapCode.Text.Trim()))
            //{
            //    GF.MsgBox(this, "Isi atau pilih Map Code terlebih dahulu.", "BS-5.3.0");
            //    SetTab("#tab-map");
            //    return;
            //}

            // The selected PDF/JPG remains in browser IndexedDB across this
            // WebForms postback. It is uploaded only when Save Map is submitted.

            PreparePoint();
            BindEditorMaps();
            try
            {
                LoadEditorMapPdf();
                BindMapElements();
                pnlEditor.Visible = true;
            }
            catch (Exception ex)
            {
                GF.MsgBox(this, "Gagal memuat denah untuk Inspection Point: " + ex.Message, "BS-5.3.0");
                SetTab("#tab-map");
                return;
            }
            ShowPointEditor();
            SetTab("#tab-point");
        }

        protected void gvPoints_RowCommand(object sender, GridViewCommandEventArgs e)
        {
            long pointID;
            if (!Int64.TryParse(Convert.ToString(e.CommandArgument), out pointID)) return;

            if (e.CommandName == "DeletePoint")
            {
                using (var br = new WAL.BR.CF())
                    br.EQueryP(@"UPDATE dbo.PIP_M_InspectionPoint
SET IsActive=0, UpdateUser=@UserID, UpdateDate=GETDATE()
WHERE InspectionPointID=@PointID AND MapID=@MapID AND IsActive=1
  AND EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionMap M WHERE M.MapID=@MapID
              AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID)",
                        new SqlParameter[] {
                            new SqlParameter("@UserID", Master.Mn_EmployeeID),
                            new SqlParameter("@PointID", pointID),
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@LocationID", Master.Mn_LocationID),
                            new SqlParameter("@MapID", Convert.ToInt64(hidMapID.Value))
                        });
                BindPoints();
                BindMapElements();
                DataTable refreshedMap = GetMap(Convert.ToInt64(hidMapID.Value));
                if (refreshedMap != null && refreshedMap.Rows.Count > 0)
                    ShowMapPreview(refreshedMap.Rows[0]);
                //ShowMessage("Inspection Point berhasil dinonaktifkan.", false);
                GF.MsgBox(this, "Inspection Point berhasil dinonaktifkan.", "BS-5.3.0");
                SetTab("#tab-point");
                return;
            }

            if (e.CommandName != "EditPoint" && e.CommandName != "MapEditor") return;
            //long pointID;
            if (!Int64.TryParse(Convert.ToString(e.CommandArgument), out pointID)) return;

            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT P.*, M.InspectionTypeCode, M.InspectionTypeDetailCode
FROM dbo.PIP_M_InspectionPoint P
INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
WHERE P.InspectionPointID=@ID AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID AND P.MapID=@MapID
  AND P.IsActive=1
  AND (@IsAdmin=1 OR EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionType IT
      INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
      WHERE IT.InspectionTypeCode=M.InspectionTypeCode AND S.ProfitCenterNo=@ProfitCenterNo))",
                    new SqlParameter[] {
                        new SqlParameter("@ID", pointID),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@MapID", String.IsNullOrEmpty(hidMapID.Value) ? 0 : Convert.ToInt64(hidMapID.Value)),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
                if (dt.Rows.Count == 0) return;
                DataRow row = dt.Rows[0];
                hidPointID.Value = pointID.ToString(CultureInfo.InvariantCulture);
                btnSwapPosition.Visible = true;
                ShowPointEditor();
                txtPointCode.Text = Convert.ToString(row["PointCode"]);
                txtPointName.Text = Convert.ToString(row["PointName"]);
                if (ddlPointObjectType.Items.FindByValue(Convert.ToString(row["PointObjectType"])) != null)
                    ddlPointObjectType.SelectedValue = Convert.ToString(row["PointObjectType"]);
                if (ddlPointMap.Items.FindByValue(Convert.ToString(row["MapID"])) != null && row["MapID"] != DBNull.Value)
                    ddlPointMap.SelectedValue = Convert.ToString(row["MapID"]);
                else ddlPointMap.SelectedIndex = 0;
                txtObjectReferenceCode.Text = Convert.ToString(row["ObjectReferenceCode"]);
                txtPointDescription.Text = Convert.ToString(row["PointDescription"]);
                txtPointOrder.Text = Convert.ToString(row["DisplayOrder"]);
                chkNormalAbnormalRequired.Checked = row["IsNormalAbnormalRequired"] != DBNull.Value && Convert.ToBoolean(row["IsNormalAbnormalRequired"]);
                txtMarkerX.Text = row["MapX"] == DBNull.Value ? "" : Convert.ToDecimal(row["MapX"]).ToString("0.####", CultureInfo.InvariantCulture);
                txtMarkerY.Text = row["MapY"] == DBNull.Value ? "" : Convert.ToDecimal(row["MapY"]).ToString("0.####", CultureInfo.InvariantCulture);
                BindEditorMaps();
                LoadEditorMapPdf();
                BindMapElements();
                pnlEditor.Visible = true;
            }
            SetTab("#tab-point");
        }

        protected void btnSavePoint_Click(object sender, EventArgs e)
        {
            string code = txtPointCode.Text.Trim().ToUpperInvariant();
            string name = txtPointName.Text.Trim();
            int order;
            if (code == "" || name == "")
            {
                //ShowMessage("Point Code dan Point Name wajib diisi.", true);
                GF.MsgBox(this, "Point Code dan Point Name wajib diisi.", "BS-5.3.0");
                SetTab("#tab-point");
                return;
            }
            if (!Int32.TryParse(txtPointOrder.Text.Trim(), out order))
            {
                //ShowMessage("Display Order harus berupa angka.", true);
                GF.MsgBox(this, "Display Order harus berupa angka.", "BS-5.3.0");
                SetTab("#tab-point");
                return;
            }
            decimal? coordinateX = null;
            decimal? coordinateY = null;
            if (!String.IsNullOrWhiteSpace(txtMarkerX.Text) || !String.IsNullOrWhiteSpace(txtMarkerY.Text))
            {
                decimal parsedX, parsedY;
                if (!Decimal.TryParse(txtMarkerX.Text.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out parsedX) ||
                    !Decimal.TryParse(txtMarkerY.Text.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out parsedY) ||
                    parsedX < 0 || parsedX > 100 || parsedY < 0 || parsedY > 100)
                {
                    //ShowMessage("Koordinat X dan Y harus diisi dengan angka antara 0 sampai 100.", true);
                    GF.MsgBox(this, "Koordinat X dan Y harus diisi dengan angka antara 0 sampai 100.", "BS-5.3.0");
                    SetTab("#tab-point");
                    return;
                }
                coordinateX = parsedX;
                coordinateY = parsedY;
            }

            long mapID;
            if (!Int64.TryParse(hidMapID.Value, out mapID) || mapID <= 0)
            {
                // For a new Map, Save Inspection Point creates the Map first.
                // Its floor-plan Blob remains in browser IndexedDB until Save Map.
                try
                {
                    mapID = CreateMapForNewPoint();
                    if (mapID <= 0) return;
                    hidMapID.Value = mapID.ToString(CultureInfo.InvariantCulture);
                    hidMapIsDraft.Value = "1";
                }
                catch (Exception mapError)
                {
                    GF.MsgBox(this, "Gagal menyimpan Master Map sebelum menambah Inspection Point: " + mapError.Message, "BS-5.3.0");
                    SetTab("#tab-map");
                    return;
                }
            }

            DataTable map = GetMap(mapID);
            if (map == null || map.Rows.Count == 0)
            {
                //ShowMessage("Map tidak ditemukan atau Anda tidak memiliki akses.", true);
                GF.MsgBox(this, "Map tidak ditemukan atau Anda tidak memiliki akses.", "BS-5.3.0");
                SetTab("#tab-map");
                return;
            }
            string typeCode = Convert.ToString(map.Rows[0]["InspectionTypeCode"]);
            string detailCode = Convert.ToString(map.Rows[0]["InspectionTypeDetailCode"]);
            if (String.IsNullOrWhiteSpace(typeCode) || String.IsNullOrWhiteSpace(detailCode))
            {
                //ShowMessage("Inspection Type dan Detail harus ditentukan pada Master Map terlebih dahulu.", true);
                GF.MsgBox(this, "Inspection Type dan Detail harus ditentukan pada Master Map terlebih dahulu.", "BS-5.3.0");
                SetTab("#tab-map");
                return;
            }

            object mapValue = mapID;
            long pointID;
            bool editing = Int64.TryParse(hidPointID.Value, out pointID) && pointID > 0;

            using (var duplicateCheck = new WAL.BR.CF())
            {
                DataTable duplicate = duplicateCheck.EQueryP(@"
SELECT TOP 1 InspectionPointID
FROM dbo.PIP_M_InspectionPoint P
WHERE P.MapID=@MapID AND P.PointCode=@PointCode AND P.IsActive=1
  AND EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionMap M WHERE M.MapID=P.MapID
              AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID)
  AND InspectionPointID<>@PointID",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@MapID", mapValue),
                        new SqlParameter("@PointCode", code),
                        new SqlParameter("@PointID", editing ? pointID : 0)
                    });
                if (duplicate != null && duplicate.Rows.Count > 0)
                {
                    GF.MsgBox(this, "Point Code sudah digunakan oleh Inspection Point yang masih aktif pada Map ini. Gunakan kode lain atau nonaktifkan point lama terlebih dahulu.", "BS-5.3.0");
                    SetTab("#tab-point");
                    return;
                }
            }

            if (coordinateX.HasValue)
            {
                using (var check = new WAL.BR.CF())
                {
                    DataTable occupied = check.EQueryP(@"
SELECT TOP 1 PointCode,PointName
FROM dbo.PIP_M_InspectionPoint P
WHERE P.MapID=@MapID AND P.InspectionPointID<>@PointID AND P.IsActive=1
  AND EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionMap M WHERE M.MapID=P.MapID
              AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID)
  AND MapX IS NOT NULL AND MapY IS NOT NULL
  AND ((MapX-@MapX)*(MapX-@MapX)+(MapY-@MapY)*(MapY-@MapY))<0.25
ORDER BY PointCode",
                        new SqlParameter[] {
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@LocationID", Master.Mn_LocationID),
                            new SqlParameter("@MapID", mapValue),
                            new SqlParameter("@PointID", editing ? pointID : 0),
                            new SqlParameter("@MapX", coordinateX.Value),
                            new SqlParameter("@MapY", coordinateY.Value)
                        });
                    if (occupied.Rows.Count > 0)
                    {
                        //ShowMessage("Posisi tersebut sudah ditempati Inspection Point lain. Pilih lokasi lain atau gunakan Swap Position.", true);
                        GF.MsgBox(this, "Posisi tersebut sudah ditempati Inspection Point lain. Pilih lokasi lain atau gunakan Swap Position.", "BS-5.3.0");
                        SetTab("#tab-point");
                        return;
                    }
                }
            }

            // A newly-created Map is still a draft until Save Map. If its
            // floor plan is selected, persist it now with the first Save Point.
            // This makes the Map usable even if the browser draft is later cleared.
            if (hidMapIsDraft.Value == "1" && fuMapPdf.HasFile)
            {
                string uploadedMapPath = SaveMapFile(fuMapPdf);
                try
                {
                    DataTable currentDraftMap = GetMap(mapID);
                    if (currentDraftMap == null || currentDraftMap.Rows.Count == 0)
                        throw new Exception("Draft Map tidak ditemukan saat menyimpan denah.");

                    string previousImagePath = Convert.ToString(currentDraftMap.Rows[0]["ImagePath"]);
                    using (var mapWriter = new WAL.BR.CF())
                    {
                        mapWriter.EQueryP(@"
UPDATE dbo.PIP_M_InspectionMap
SET ImagePath=@ImagePath, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@MapID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                            new SqlParameter[] {
                                new SqlParameter("@ImagePath", uploadedMapPath),
                                new SqlParameter("@UpdateUser", Master.Mn_EmployeeID),
                                new SqlParameter("@MapID", mapID),
                                new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                                new SqlParameter("@LocationID", Master.Mn_LocationID)
                            });
                    }

                    if (!String.IsNullOrWhiteSpace(previousImagePath) &&
                        !String.Equals(previousImagePath, uploadedMapPath, StringComparison.OrdinalIgnoreCase))
                        TryDeleteFile(previousImagePath);

                    // The file is now stored on the server. Remove the browser
                    // IndexedDB copy so later Save Point clicks do not upload it again.
                    ScriptManager.RegisterStartupScript(this, GetType(),
                        "clearUploadedInspectionMapDraft", "inspectionMasterClearDraft();", true);
                }
                catch (Exception uploadError)
                {
                    TryDeleteFile(uploadedMapPath);
                    GF.MsgBox(this, "Gagal menyimpan denah: " + uploadError.Message, "BS-5.3.0");
                    SetTab("#tab-point");
                    return;
                }
            }

            try
            {
                using (var br = new WAL.BR.CF())
                {
                    if (editing)
                    {
                        br.EQueryP(@"
UPDATE dbo.PIP_M_InspectionPoint
SET PointCode=@PointCode, PointName=@PointName, PointObjectType=@ObjectType,
    PointDescription=@Description, ObjectReferenceType=@ObjectType,
    ObjectReferenceCode=@ReferenceCode, MapX=@MapX, MapY=@MapY, DisplayOrder=@DisplayOrder,
    IsNormalAbnormalRequired=@IsNormalAbnormalRequired, UpdateUser=@UserID, UpdateDate=GETDATE()
WHERE InspectionPointID=@PointID AND MapID=@MapID AND IsActive=1
  AND EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionMap M WHERE M.MapID=@MapID
              AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID)",
                            PointParameters(pointID, mapValue, code, name, order, coordinateX, coordinateY));
                    }
                    else
                    {
                        pointID = NextId("dbo.PIP_M_InspectionPoint", "InspectionPointID");
                        br.EQueryP(@"
INSERT INTO dbo.PIP_M_InspectionPoint
(InspectionPointID,PointCode,PointName,PointObjectType,PointDescription,
 ObjectReferenceType,ObjectReferenceID,ObjectReferenceCode,MapID,MapX,MapY,DisplayOrder,
 IsActive,IsNormalAbnormalRequired,EntryUser,UpdateUser)
VALUES
(@PointID,@PointCode,@PointName,@ObjectType,@Description,
 @ObjectType,'',@ReferenceCode,@MapID,@MapX,@MapY,@DisplayOrder,
 1,@IsNormalAbnormalRequired,@UserID,@UserID)",
                            PointParameters(pointID, mapValue, code, name, order, coordinateX, coordinateY));
                    }
                }
                hidPointID.Value = pointID.ToString(CultureInfo.InvariantCulture);

                // Saving a Point can also create the Map when the Map Code
                // was new. Once that save succeeds, enable Map navigation.
                Master.TB_VisibleButton(ToolbarItem_2.Previous, true);
                Master.TB_VisibleButton(ToolbarItem_2.Next, true);

                pnlPointEditor.Visible = false;
                BindPoints();
                BindEditorMaps();
                if (ddlEditorMap.Items.FindByValue(mapID.ToString(CultureInfo.InvariantCulture)) != null)
                    ddlEditorMap.SelectedValue = mapID.ToString(CultureInfo.InvariantCulture);
                LoadEditorMapPdf();
                BindMapElements();
                DataTable refreshedMap = GetMap(mapID);
                if (refreshedMap != null && refreshedMap.Rows.Count > 0)
                    ShowMapPreview(refreshedMap.Rows[0]);
                pnlEditor.Visible = true;
                //ShowMessage("Inspection Point berhasil disimpan.", false);
                GF.MsgBox(this, "Inspection Point berhasil disimpan.", "BS-5.3.0");
            }
            catch (Exception ex)
            {
                //ShowMessage("Gagal menyimpan Inspection Point: " + ex.Message, true);
                GF.MsgBox(this, "Gagal menyimpan Inspection Point: " + ex.Message, "BS-5.3.0");
            }
            SetTab("#tab-point");
        }

        private long CreateMapForNewPoint()
        {
            string code = txtMapCode.Text.Trim().ToUpperInvariant();
            string name = txtMapName.Text.Trim();
            string typeCode = ddlInspectionType.SelectedValue;
            string detailCode = ddlInspectionDetail.SelectedValue;
            string imagePath = "";

            if (String.IsNullOrWhiteSpace(code) || String.IsNullOrWhiteSpace(name) ||
                String.IsNullOrWhiteSpace(typeCode) || String.IsNullOrWhiteSpace(detailCode))
                throw new Exception("Map Code, Map Name, Inspection Type, dan Inspection Detail wajib diisi.");

            if (!IsValidMapTypeDetail(typeCode, detailCode))
                throw new Exception("Inspection Type atau Detail tidak aktif, bukan mode BATCH, atau tidak termasuk Profit Center Anda.");

            // Floor plan is optional. Keep ImagePath empty when the Map has
            // no PDF/JPG background yet.
            int version;
            using (var br = new WAL.BR.CF())
            {
                DataTable next = br.EQueryP(@"
SELECT ISNULL(MAX(MapVersion),0)+1 AS NextVersion
FROM dbo.PIP_M_InspectionMap
WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND MapCode=@MapCode",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@MapCode", code)
                    });
                version = Convert.ToInt32(next.Rows[0]["NextVersion"]);
            }

            long newMapID = NextId("dbo.PIP_M_InspectionMap", "MapID");
            using (var br = new WAL.BR.CF())
            {
                br.EQueryP(@"
INSERT INTO dbo.PIP_M_InspectionMap
(MapID,CompanyID,LocationID,MapCode,MapName,ImagePath,ViewBoxX,ViewBoxY,ViewBoxWidth,ViewBoxHeight,
 MapVersion,InspectionTypeCode,InspectionTypeDetailCode,RequireAllPoints,IsCurrentVersion,IsActive,Description,EntryUser,UpdateUser)
VALUES
(@MapID,@CompanyID,@LocationID,@MapCode,@MapName,@ImagePath,0,0,100,100,
 @MapVersion,@TypeCode,@DetailCode,@RequireAllPoints,1,1,@Description,@UserID,@UserID)",
                    new SqlParameter[] {
                        new SqlParameter("@MapID", newMapID),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@MapCode", code),
                        new SqlParameter("@MapName", name),
                        new SqlParameter("@ImagePath", imagePath),
                        new SqlParameter("@MapVersion", version),
                        new SqlParameter("@TypeCode", typeCode),
                        new SqlParameter("@DetailCode", detailCode),
                        new SqlParameter("@RequireAllPoints", chkRequireAllPoints.Checked),
                        new SqlParameter("@Description", txtMapDescription.Text.Trim()),
                        new SqlParameter("@UserID", Master.Mn_EmployeeID)
                    });
            }

            BindMaps();
            BindEditorMaps();
            DataTable savedMap = GetMap(newMapID);
            if (savedMap.Rows.Count > 0) ShowMapPreview(savedMap.Rows[0]);
            lblMapVersion.Text = "Map tersimpan otomatis saat Inspection Point pertama disimpan.";
            return newMapID;
        }

        private SqlParameter[] PointParameters(long pointID, object mapValue,
            string code, string name, int order, decimal? coordinateX, decimal? coordinateY)
        {
            return new SqlParameter[] {
                new SqlParameter("@PointID", pointID),
                // These parameters validate the owning Map; they are not Point columns.
                new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                new SqlParameter("@LocationID", Master.Mn_LocationID),
                new SqlParameter("@PointCode", code),
                new SqlParameter("@PointName", name),
                new SqlParameter("@ObjectType", ddlPointObjectType.SelectedValue),
                new SqlParameter("@Description", txtPointDescription.Text.Trim()),
                new SqlParameter("@ReferenceCode", txtObjectReferenceCode.Text.Trim()),
                new SqlParameter("@MapID", mapValue),
                new SqlParameter("@MapX", SqlDbType.Decimal) { Precision = 9, Scale = 4, Value = coordinateX.HasValue ? (object)coordinateX.Value : DBNull.Value },
                new SqlParameter("@MapY", SqlDbType.Decimal) { Precision = 9, Scale = 4, Value = coordinateY.HasValue ? (object)coordinateY.Value : DBNull.Value },
                new SqlParameter("@DisplayOrder", order),
                new SqlParameter("@IsNormalAbnormalRequired", chkNormalAbnormalRequired.Checked),
                new SqlParameter("@UserID", Master.Mn_EmployeeID)
            };
        }

        private void BindMapElements()
        {
            if (String.IsNullOrWhiteSpace(hidMapID.Value)) return;
            DataTable points;
            using (var br = new WAL.BR.CF())
                points = br.EQueryP(@"
SELECT P.InspectionPointID,
       CASE WHEN @IsAdmin=1 OR S.ProfitCenterNo=@ProfitCenterNo THEN P.PointCode ELSE 'Occupied' END AS PointCode,
       CASE WHEN @IsAdmin=1 OR S.ProfitCenterNo=@ProfitCenterNo THEN P.PointName ELSE 'Occupied by another Profit Center' END AS PointName,
       CASE WHEN @IsAdmin=1 OR S.ProfitCenterNo=@ProfitCenterNo THEN LEFT(P.PointCode,4) ELSE '•' END AS MarkerLabel,
       CASE WHEN @IsAdmin=1 OR S.ProfitCenterNo=@ProfitCenterNo THEN 1 ELSE 0 END AS CanSwap,
       P.DisplayOrder,P.MapX AS XPercent,P.MapY AS YPercent
FROM dbo.PIP_M_InspectionPoint P
INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
 INNER JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=M.InspectionTypeCode
INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID AND P.MapID=@MapID
  AND P.IsActive=1 AND P.MapX IS NOT NULL AND P.MapY IS NOT NULL
ORDER BY P.DisplayOrder,P.PointCode",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@MapID", Convert.ToInt64(hidMapID.Value)),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
            rptMapElements.DataSource = points;
            rptMapElements.DataBind();
        }

        protected void btnClearCoordinate_Click(object sender, EventArgs e)
        {
            txtMarkerX.Text = "";
            txtMarkerY.Text = "";
            //ShowMessage("Koordinat dikosongkan pada form. Klik Save Point untuk menyimpan perubahan.", false);
            GF.MsgBox(this, "Koordinat dikosongkan pada form. Klik Save Point untuk menyimpan perubahan.", "BS-5.3.0");
            pnlPointEditor.Visible = true;
            pnlEditor.Visible = true;
            BindMapElements();
            SetTab("#tab-point");
        }

        protected void btnSwapPosition_Click(object sender, EventArgs e)
        {
            long pointID, otherPointID;
            if (!Int64.TryParse(hidPointID.Value, out pointID) || pointID <= 0 ||
                !Int64.TryParse(hidSwapPointID.Value, out otherPointID) || otherPointID <= 0 ||
                pointID == otherPointID)
            {
                //ShowMessage("Pilih marker Inspection Point lain pada denah untuk melakukan Swap Position.", true);
                GF.MsgBox(this, "Pilih marker Inspection Point lain pada denah untuk melakukan Swap Position.", "BS-5.3.0");
                SetTab("#tab-point");
                return;
            }

            using (var access = new WAL.BR.CF())
            {
                DataTable allowed = access.EQueryP(@"
SELECT COUNT(DISTINCT P.InspectionPointID) AS TotalRows
FROM dbo.PIP_M_InspectionPoint P
INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
INNER JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=M.InspectionTypeCode
INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
WHERE P.InspectionPointID IN (@PointID,@OtherPointID)
  AND P.MapID=@MapID AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID
  AND (@IsAdmin=1 OR S.ProfitCenterNo=@ProfitCenterNo)",
                    new SqlParameter[] {
                        new SqlParameter("@PointID", pointID),
                        new SqlParameter("@OtherPointID", otherPointID),
                        new SqlParameter("@MapID", Convert.ToInt64(hidMapID.Value)),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
                if (allowed.Rows.Count == 0 || Convert.ToInt32(allowed.Rows[0]["TotalRows"]) != 2)
                {
                    //ShowMessage("Kedua Inspection Point tidak valid atau tidak termasuk Profit Center Anda.", true);
                    GF.MsgBox(this, "Kedua Inspection Point tidak valid atau tidak termasuk Profit Center Anda.", "BS-5.3.0");
                    SetTab("#tab-point");
                    return;
                }
            }

            try
            {
                using (var br = new WAL.BR.CF())
                {
                    br.EQueryP(@"
SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRANSACTION;
IF NOT EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionMap WITH (UPDLOCK,HOLDLOCK)
               WHERE MapID=@MapID AND CompanyID=@CompanyID AND LocationID=@LocationID)
    RAISERROR('Map tidak valid untuk Company/Location aktif.',16,1);
DECLARE @CurrentX DECIMAL(9,4), @CurrentY DECIMAL(9,4),
        @OtherX DECIMAL(9,4), @OtherY DECIMAL(9,4);
SELECT @CurrentX=MapX,@CurrentY=MapY
FROM dbo.PIP_M_InspectionPoint WITH (UPDLOCK,HOLDLOCK)
WHERE InspectionPointID=@PointID AND MapID=@MapID;
SELECT @OtherX=MapX,@OtherY=MapY
FROM dbo.PIP_M_InspectionPoint WITH (UPDLOCK,HOLDLOCK)
WHERE InspectionPointID=@OtherPointID AND MapID=@MapID;
IF @CurrentX IS NULL OR @CurrentY IS NULL OR @OtherX IS NULL OR @OtherY IS NULL
BEGIN
    RAISERROR('Kedua Inspection Point harus sudah memiliki koordinat pada Map yang sama.',16,1);
END;
UPDATE dbo.PIP_M_InspectionPoint
SET MapX=@OtherX,MapY=@OtherY,UpdateUser=@UserID,UpdateDate=GETDATE()
WHERE InspectionPointID=@PointID AND MapID=@MapID;
UPDATE dbo.PIP_M_InspectionPoint
SET MapX=@CurrentX,MapY=@CurrentY,UpdateUser=@UserID,UpdateDate=GETDATE()
WHERE InspectionPointID=@OtherPointID AND MapID=@MapID;
COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
    DECLARE @SwapError NVARCHAR(4000);
    SET @SwapError=ERROR_MESSAGE();
    RAISERROR(@SwapError,16,1);
END CATCH;",
                        new SqlParameter[] {
                            new SqlParameter("@PointID", pointID),
                            new SqlParameter("@OtherPointID", otherPointID),
                            new SqlParameter("@MapID", Convert.ToInt64(hidMapID.Value)),
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@LocationID", Master.Mn_LocationID),
                            new SqlParameter("@UserID", Master.Mn_EmployeeID)
                        });
                    DataTable currentPosition = br.EQueryP(@"
SELECT MapX,MapY FROM dbo.PIP_M_InspectionPoint
WHERE InspectionPointID=@PointID AND MapID=@MapID",
                        new SqlParameter[] {
                            new SqlParameter("@PointID", pointID),
                            new SqlParameter("@MapID", Convert.ToInt64(hidMapID.Value))
                        });
                    if (currentPosition.Rows.Count > 0)
                    {
                        txtMarkerX.Text = Convert.ToDecimal(currentPosition.Rows[0]["MapX"]).ToString("0.####", CultureInfo.InvariantCulture);
                        txtMarkerY.Text = Convert.ToDecimal(currentPosition.Rows[0]["MapY"]).ToString("0.####", CultureInfo.InvariantCulture);
                    }
                }
                hidSwapPointID.Value = "";
                BindMapElements();
                //ShowMessage("Koordinat kedua Inspection Point berhasil ditukar.", false);
                GF.MsgBox(this, "Koordinat kedua Inspection Point berhasil ditukar.", "BS-5.3.0");
            }
            catch (Exception ex)
            {
                //ShowMessage("Gagal menukar koordinat: " + ex.Message, true);
                GF.MsgBox(this, "Gagal menukar koordinat: " + ex.Message, "BS-5.3.0");
            }
            pnlPointEditor.Visible = true;
            pnlEditor.Visible = true;
            SetTab("#tab-point");
        }

    }
}
