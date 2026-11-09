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
      FROM dbo.PIP_M_InspectionPoint P
      INNER JOIN dbo.PIP_M_InspectionMap MP ON MP.MapID=P.MapID
        INNER JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=MP.InspectionTypeCode
      INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
      WHERE P.MapID=M.MapID AND S.ProfitCenterNo=@ProfitCenterNo))
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
                    ShowMessage(direction < 0 ? "Sudah di Map pertama." : "Sudah di Map terakhir.", false);
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
(SELECT 1 FROM dbo.syswebuserusergroup WHERE usergroupid='administrator' AND userid=@EmployeeID)
THEN 1 ELSE 0 END AS IsAdmin",
                    new SqlParameter[] { new SqlParameter("@EmployeeID", Master.Mn_EmployeeID) });
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
WHERE P.CompanyID=@CompanyID AND P.LocationID=@LocationID AND P.MapID=@MapID
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
           M.InspectionTypeCode, M.InspectionTypeDetailCode,
           P.PointObjectType, P.IsActive,
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
    LEFT JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
    WHERE P.CompanyID=@CompanyID AND P.LocationID=@LocationID AND P.MapID=@MapID
      AND (@Keyword='' OR P.PointCode LIKE '%' + @Keyword + '%')
      AND (@IsAdmin=1 OR EXISTS
      (
          SELECT 1
          FROM dbo.PIP_M_InspectionType IT
          INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
          WHERE IT.InspectionTypeCode=P.InspectionTypeCode
            AND S.ProfitCenterNo=@ProfitCenterNo
      ))
)
SELECT InspectionPointID, PointCode, PointName,
       InspectionTypeCode, InspectionTypeDetailCode,
       PointObjectType, IsActive, DisplayOrder, MapCode
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
WHERE P.CompanyID=@CompanyID AND P.LocationID=@LocationID AND P.MapID=@MapID
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
                ShowMessage("Nomor halaman tidak valid.", true);
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
            txtMapCode.Text = "";
            Master.TB_VisibleButton(ToolbarItem_2.Previous, false);
            Master.TB_VisibleButton(ToolbarItem_2.Next, false);
            txtMapName.Text = "";
            txtMapDescription.Text = "";
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
                ShowMessage("Map ID tidak valid. Silakan refresh daftar map.", true);
                SetTab("#tab-map");
                return;
            }

            try
            {
                DataTable dt = GetMap(mapID);
                if (dt == null || dt.Rows.Count == 0)
                {
                    ShowMessage("Data map tidak ditemukan untuk Map ID " +
                        mapID.ToString(CultureInfo.InvariantCulture) +
                        ". Periksa CompanyID/LocationID atau refresh daftar map.", true);
                    SetTab("#tab-map");
                    return;
                }

                DataRow row = dt.Rows[0];
                if (commandName == "EditMap")
                {
                    hidMapID.Value = mapID.ToString(CultureInfo.InvariantCulture);
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
                ShowMessage("Gagal membuka map: " + ex.Message, true);
                SetTab("#tab-map");
            }
        }

        private DataTable GetMap(long mapID)
        {
            using (var br = new WAL.BR.CF())
                return br.EQueryP(@"
SELECT M.MapID, M.MapCode, M.MapName, M.ImagePath, M.MapVersion, M.IsActive, M.Description,
       M.InspectionTypeCode, M.InspectionTypeDetailCode,
       ISNULL(M.RequireAllPoints,1) AS RequireAllPoints
FROM dbo.PIP_M_InspectionMap M
WHERE M.MapID=@MapID AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID
  AND (@IsAdmin=1 OR M.EntryUser=@EmployeeID OR EXISTS
      (SELECT 1 FROM dbo.PIP_M_InspectionPoint P
       INNER JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=M.InspectionTypeCode
       INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
       WHERE P.MapID=M.MapID AND S.ProfitCenterNo=@ProfitCenterNo))",
                    new SqlParameter[] {
                        new SqlParameter("@MapID", mapID),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@IsAdmin", IsAdministrator()),
                        new SqlParameter("@EmployeeID", Master.Mn_EmployeeID),
                        new SqlParameter("@ProfitCenterNo", Master.Mn_ProfitCenterNo)
                    });
        }

        private string ResolveMapPdfUrl(string storedPath)
        {
            string path = (storedPath ?? "").Trim();
            if (path == "") return "";

            Uri absoluteUrl;
            if (Uri.TryCreate(path, UriKind.Absolute, out absoluteUrl) &&
                (absoluteUrl.Scheme == Uri.UriSchemeHttp || absoluteUrl.Scheme == Uri.UriSchemeHttps))
                return path;

            if (path.StartsWith("~/", StringComparison.Ordinal))
                return ResolveUrl(path);

            if (path.StartsWith("/", StringComparison.Ordinal))
                return path;

            return ResolveUrl("~/" + path.TrimStart('/'));
        }

        private void ShowMapPreview(DataRow row)
        {
            string url = ResolveMapPdfUrl(Convert.ToString(row["ImagePath"]));
            string extension = Path.GetExtension(url).ToLowerInvariant();
            bool isJpeg = extension == ".jpg" || extension == ".jpeg";
            lblMapPreviewTitle.Text = Convert.ToString(row["MapCode"]) + " - " + Convert.ToString(row["MapName"]) + " (v" + Convert.ToString(row["MapVersion"]) + ")";
            lnkMapPdf.NavigateUrl = url;
            litMapPreview.Text = isJpeg
                ? "<div class='inspection-map-preview-stage'><img class='inspection-image-preview' alt='Inspection floor plan' src='" + HttpUtility.HtmlAttributeEncode(url) + "' /></div>"
                : "<div class='inspection-map-preview-stage'><canvas id='inspectionMapPreviewCanvas' class='inspection-map-preview-canvas' data-map-url='" + HttpUtility.HtmlAttributeEncode(url) + "' aria-label='Inspection floor plan'></canvas><div id='inspectionMapPreviewStatus' class='inspection-pdf-status'>Memuat denah...</div></div>";
            pnlMapPreview.Visible = true;
        }

        private void LoadEditorMapPdf()
        {
            if (String.IsNullOrWhiteSpace(ddlEditorMap.SelectedValue)) { litEditorPdfBackground.Text = ""; lnkEditorPdf.Visible = false; return; }
            DataTable selectedMap = GetMap(Convert.ToInt64(ddlEditorMap.SelectedValue));
            if (selectedMap == null || selectedMap.Rows.Count == 0) throw new Exception("Map yang dipilih tidak ditemukan.");
            string url = ResolveMapPdfUrl(Convert.ToString(selectedMap.Rows[0]["ImagePath"]));
            if (String.IsNullOrWhiteSpace(url)) throw new Exception("File denah untuk map ini belum tersedia.");
            string extension = Path.GetExtension(url).ToLowerInvariant();
            bool isJpeg = extension == ".jpg" || extension == ".jpeg";
            string media = isJpeg
                ? "<img id='inspectionPdfCanvas' class='inspection-coordinate-pdf' data-map-url='" + HttpUtility.HtmlAttributeEncode(url) + "' alt='Inspection floor plan' />"
                : "<canvas id='inspectionPdfCanvas' class='inspection-coordinate-pdf' data-map-url='" + HttpUtility.HtmlAttributeEncode(url) + "' aria-label='Inspection floor plan'></canvas>";
            litEditorPdfBackground.Text = media + "<div id='inspectionPdfStatus' class='inspection-pdf-status'>Memuat denah...</div>";
            lnkEditorPdf.NavigateUrl = url; lnkEditorPdf.Visible = true;
            lblPointMapCode.Text = "· " + Convert.ToString(selectedMap.Rows[0]["MapCode"]);
        }
        protected void btnSaveMap_Click(object sender, EventArgs e)
        {
            string code = txtMapCode.Text.Trim().ToUpperInvariant();
            string name = txtMapName.Text.Trim();
            string typeCode = ddlInspectionType.SelectedValue;
            string detailCode = ddlInspectionDetail.SelectedValue;
            if (code == "" || name == "" || typeCode == "" || detailCode == "")
            {
                ShowMessage("Map Code, Map Name, Inspection Type, dan Inspection Detail wajib diisi.", true);
                SetTab("#tab-map");
                return;
            }

            string savedPath = "";
            bool databaseSaved = false;
            try
            {
                if (fuMapPdf.HasFile)
                    savedPath = SaveMapFile(fuMapPdf);

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
SET MapCode=@MapCode, MapName=@MapName, Description=@Description,
    InspectionTypeCode=@TypeCode, InspectionTypeDetailCode=@DetailCode,
    RequireAllPoints=@RequireAllPoints, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@MapID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                                MapParameters(oldID, code, name, Convert.ToString(old.Rows[0]["ImagePath"])));
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
 MapVersion,InspectionTypeCode,InspectionTypeDetailCode,RequireAllPoints,IsCurrentVersion,IsActive,Description,EntryUser,UpdateUser)
VALUES
(@NewMapID,@CompanyID,@LocationID,@MapCode,@MapName,@ImagePath,0,0,100,100,
 @MapVersion,@TypeCode,@DetailCode,@RequireAllPoints,1,1,@Description,@UpdateUser,@UpdateUser);
UPDATE dbo.PIP_M_InspectionPoint SET MapID=@NewMapID, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@OldMapID AND CompanyID=@CompanyID AND LocationID=@LocationID;
",
                                new SqlParameter[] {
                                    new SqlParameter("@OldMapID", oldID), new SqlParameter("@NewMapID", newID),
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
                        if (savedPath == "") throw new Exception("Pilih file PDF atau JPG/JPEG denah terlebih dahulu.");
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
 MapVersion,InspectionTypeCode,InspectionTypeDetailCode,RequireAllPoints,IsCurrentVersion,IsActive,Description,EntryUser,UpdateUser)
VALUES
(@MapID,@CompanyID,@LocationID,@MapCode,@MapName,@ImagePath,0,0,100,100,
 @MapVersion,@TypeCode,@DetailCode,@RequireAllPoints,1,1,@Description,@UpdateUser,@UpdateUser)",
                            new SqlParameter[] {
                                new SqlParameter("@MapID", newID), new SqlParameter("@CompanyID", Master.Mn_CompanyID),
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

                BindMaps();
                BindPointLookups();
                BindEditorMaps();
                PointPageIndex = 0;
                txtPointSearch.Text = "";
                BindPoints();
                DataTable current = GetMap(Convert.ToInt64(hidMapID.Value));
                if (current.Rows.Count > 0) ShowMapPreview(current.Rows[0]);
                lblMapVersion.Text = "Map tersimpan. PDF dan versi map sudah tercatat.";
                ShowMessage("Map berhasil disimpan.", false);
            }
            catch (Exception ex)
            {
                if (!databaseSaved && savedPath != "") TryDeleteFile(savedPath);
                ShowMessage("Gagal menyimpan map: " + ex.Message, true);
            }
            SetTab("#tab-map");
        }

        private SqlParameter[] MapParameters(long mapID, string code, string name, string imagePath)
        {
            return new SqlParameter[] {
                new SqlParameter("@MapID", mapID), new SqlParameter("@MapCode", code),
                new SqlParameter("@MapName", name), new SqlParameter("@ImagePath", imagePath),
                new SqlParameter("@Description", txtMapDescription.Text.Trim()),
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
            return (PB.Url_WebFolder1 ?? "").TrimEnd('/') + "/" + relativeFolder.Replace("\\", "/") + "/" + fileName;
        }
        private string GetInspectionMapRoot()
        {
            string appPath = System.Web.HttpContext.Current.Request.ApplicationPath ?? "";
            string appId = PB.AppID ?? "";

            string root = appPath.Replace("/", "");
            if (!String.IsNullOrEmpty(appId))
                root = root.Replace(appId, "PIP");

            return root;
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

                // ImagePath stores the URL returned by SavePdfFile.
                // Only delete GUID-named PDFs from this map's configured folder.
                string normalized = storedPath.Replace("\\", "/");
                int slash = normalized.LastIndexOf('/');
                string fileName = slash >= 0 ? normalized.Substring(slash + 1) : normalized;

                Guid fileID;
                if (!fileName.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase) ||
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
SELECT TOP 1 MapID, MapCode, MapName, Description, MapVersion, ImagePath,
       InspectionTypeCode, InspectionTypeDetailCode
FROM dbo.PIP_M_InspectionMap M
WHERE M.MapCode=@MapCode AND M.CompanyID=@CompanyID AND M.LocationID=@LocationID
  AND M.IsCurrentVersion=1
  AND (@IsAdmin=1 OR M.EntryUser=@EmployeeID OR EXISTS
      (SELECT 1 FROM dbo.PIP_M_InspectionPoint P
       INNER JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=M.InspectionTypeCode
       INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
       WHERE P.MapID=M.MapID AND S.ProfitCenterNo=@ProfitCenterNo))
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
                    Master.TB_VisibleButton(ToolbarItem_2.Previous, false);
                    Master.TB_VisibleButton(ToolbarItem_2.Next, false);
                    BindEditorMaps();
                    pnlEditor.Visible = false;
                    litEditorPdfBackground.Text = "";
                    lnkEditorPdf.Visible = false;
                    ShowMessage("Map tidak ditemukan atau tidak termasuk Profit Center Anda.", true);
                    BindPoints();
                    SetTab("#tab-map");
                    return;
                }
                DataRow row = dt.Rows[0];
                hidMapID.Value = Convert.ToString(row["MapID"]);
                txtMapCode.Text = Convert.ToString(row["MapCode"]);
                Master.TB_VisibleButton(ToolbarItem_2.Previous, true);
                Master.TB_VisibleButton(ToolbarItem_2.Next, true);
                txtMapName.Text = Convert.ToString(row["MapName"]);
                txtMapDescription.Text = Convert.ToString(row["Description"]);
                lblMapVersion.Text = "Current version: " + Convert.ToString(row["MapVersion"]);
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
            GF.MsgBox(this, "Map " + txtMapCode.Text + " berhasil dibuka", "BS-5.3.0");
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

        protected void btnNewPointGrid_Click(object sender, EventArgs e)
        {
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
                ShowMessage("Gagal memuat denah untuk Inspection Point: " + ex.Message, true);
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
WHERE InspectionPointID=@PointID AND CompanyID=@CompanyID AND LocationID=@LocationID AND MapID=@MapID AND IsActive=1",
                        new SqlParameter[] {
                            new SqlParameter("@UserID", Master.Mn_EmployeeID),
                            new SqlParameter("@PointID", pointID),
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                            new SqlParameter("@LocationID", Master.Mn_LocationID),
                            new SqlParameter("@MapID", Convert.ToInt64(hidMapID.Value))
                        });
                BindPoints();
                BindMapElements();
                ShowMessage("Inspection Point berhasil dinonaktifkan.", false);
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
WHERE P.InspectionPointID=@ID AND P.CompanyID=@CompanyID AND P.LocationID=@LocationID AND P.MapID=@MapID
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
                ddlInspectionType.SelectedValue = Convert.ToString(row["InspectionTypeCode"]);
                BindInspectionDetails();
                if (ddlInspectionDetail.Items.FindByValue(Convert.ToString(row["InspectionTypeDetailCode"])) != null)
                    ddlInspectionDetail.SelectedValue = Convert.ToString(row["InspectionTypeDetailCode"]);
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
                ShowMessage("Point Code dan Point Name wajib diisi.", true);
                SetTab("#tab-point");
                return;
            }
            if (!Int32.TryParse(txtPointOrder.Text.Trim(), out order))
            {
                ShowMessage("Display Order harus berupa angka.", true);
                SetTab("#tab-point");
                return;
            }
            long mapID;
            if (!Int64.TryParse(hidMapID.Value, out mapID) || mapID <= 0)
            {
                ShowMessage("Find Map terlebih dahulu sebelum menambah Inspection Point.", true);
                SetTab("#tab-map");
                return;
            }

            DataTable map = GetMap(mapID);
            if (map == null || map.Rows.Count == 0)
            {
                ShowMessage("Map tidak ditemukan atau Anda tidak memiliki akses.", true);
                SetTab("#tab-map");
                return;
            }
            string typeCode = Convert.ToString(map.Rows[0]["InspectionTypeCode"]);
            string detailCode = Convert.ToString(map.Rows[0]["InspectionTypeDetailCode"]);
            if (String.IsNullOrWhiteSpace(typeCode) || String.IsNullOrWhiteSpace(detailCode))
            {
                ShowMessage("Inspection Type dan Detail harus ditentukan pada Master Map terlebih dahulu.", true);
                SetTab("#tab-map");
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
                    ShowMessage("Koordinat X dan Y harus diisi dengan angka antara 0 sampai 100.", true);
                    SetTab("#tab-point");
                    return;
                }
                coordinateX = parsedX;
                coordinateY = parsedY;
            }

            object mapValue = mapID;
            long pointID;
            bool editing = Int64.TryParse(hidPointID.Value, out pointID) && pointID > 0;
            if (coordinateX.HasValue)
            {
                using (var check = new WAL.BR.CF())
                {
                    DataTable occupied = check.EQueryP(@"
SELECT TOP 1 PointCode,PointName
FROM dbo.PIP_M_InspectionPoint
WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND MapID=@MapID
  AND InspectionPointID<>@PointID AND IsActive=1
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
                        ShowMessage("Posisi tersebut sudah ditempati Inspection Point lain. Pilih lokasi lain atau gunakan Swap Position.", true);
                        SetTab("#tab-point");
                        return;
                    }
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
WHERE InspectionPointID=@PointID AND CompanyID=@CompanyID AND LocationID=@LocationID AND MapID=@MapID AND IsActive=1",
                            PointParameters(pointID, mapValue, code, name, order, coordinateX, coordinateY));
                    }
                    else
                    {
                        pointID = NextId("dbo.PIP_M_InspectionPoint", "InspectionPointID");
                        br.EQueryP(@"
INSERT INTO dbo.PIP_M_InspectionPoint
(InspectionPointID,CompanyID,LocationID,PointCode,PointName,PointObjectType,PointDescription,
 ObjectReferenceType,ObjectReferenceID,ObjectReferenceCode,MapID,MapX,MapY,DisplayOrder,
 IsActive,IsNormalAbnormalRequired,EntryUser,UpdateUser)
VALUES
(@PointID,@CompanyID,@LocationID,@PointCode,@PointName,@ObjectType,@Description,
 @ObjectType,'',@ReferenceCode,@MapID,@MapX,@MapY,@DisplayOrder,
 1,@IsNormalAbnormalRequired,@UserID,@UserID)",
                            PointParameters(pointID, mapValue, code, name, order, coordinateX, coordinateY));
                    }
                }
                hidPointID.Value = pointID.ToString(CultureInfo.InvariantCulture);
                pnlPointEditor.Visible = false;
                BindPoints();
                BindMapElements();
                pnlEditor.Visible = true;
                ShowMessage("Inspection Point berhasil disimpan.", false);
            }
            catch (Exception ex)
            {
                ShowMessage("Gagal menyimpan Inspection Point: " + ex.Message, true);
            }
            SetTab("#tab-point");
        }

        private SqlParameter[] PointParameters(long pointID, object mapValue,
            string code, string name, int order, decimal? coordinateX, decimal? coordinateY)
        {
            return new SqlParameter[] {
                new SqlParameter("@PointID", pointID),
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
INNER JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=P.InspectionTypeCode
INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
WHERE P.CompanyID=@CompanyID AND P.LocationID=@LocationID AND P.MapID=@MapID
  AND P.MapX IS NOT NULL AND P.MapY IS NOT NULL
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
            ShowMessage("Koordinat dikosongkan pada form. Klik Save Point untuk menyimpan perubahan.", false);
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
                ShowMessage("Pilih marker Inspection Point lain pada denah untuk melakukan Swap Position.", true);
                SetTab("#tab-point");
                return;
            }

            using (var access = new WAL.BR.CF())
            {
                DataTable allowed = access.EQueryP(@"
SELECT COUNT(DISTINCT P.InspectionPointID) AS TotalRows
FROM dbo.PIP_M_InspectionPoint P
INNER JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=P.InspectionTypeCode
INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
WHERE P.InspectionPointID IN (@PointID,@OtherPointID)
  AND P.MapID=@MapID AND P.CompanyID=@CompanyID AND P.LocationID=@LocationID
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
                    ShowMessage("Kedua Inspection Point tidak valid atau tidak termasuk Profit Center Anda.", true);
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
DECLARE @CurrentX DECIMAL(9,4), @CurrentY DECIMAL(9,4),
        @OtherX DECIMAL(9,4), @OtherY DECIMAL(9,4);
SELECT @CurrentX=MapX,@CurrentY=MapY
FROM dbo.PIP_M_InspectionPoint WITH (UPDLOCK,HOLDLOCK)
WHERE InspectionPointID=@PointID AND MapID=@MapID
  AND CompanyID=@CompanyID AND LocationID=@LocationID;
SELECT @OtherX=MapX,@OtherY=MapY
FROM dbo.PIP_M_InspectionPoint WITH (UPDLOCK,HOLDLOCK)
WHERE InspectionPointID=@OtherPointID AND MapID=@MapID
  AND CompanyID=@CompanyID AND LocationID=@LocationID;
IF @CurrentX IS NULL OR @CurrentY IS NULL OR @OtherX IS NULL OR @OtherY IS NULL
BEGIN
    RAISERROR('Kedua Inspection Point harus sudah memiliki koordinat pada Map yang sama.',16,1);
END;
UPDATE dbo.PIP_M_InspectionPoint
SET MapX=@OtherX,MapY=@OtherY,UpdateUser=@UserID,UpdateDate=GETDATE()
WHERE InspectionPointID=@PointID AND MapID=@MapID
  AND CompanyID=@CompanyID AND LocationID=@LocationID;
UPDATE dbo.PIP_M_InspectionPoint
SET MapX=@CurrentX,MapY=@CurrentY,UpdateUser=@UserID,UpdateDate=GETDATE()
WHERE InspectionPointID=@OtherPointID AND MapID=@MapID
  AND CompanyID=@CompanyID AND LocationID=@LocationID;
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
                ShowMessage("Koordinat kedua Inspection Point berhasil ditukar.", false);
            }
            catch (Exception ex)
            {
                ShowMessage("Gagal menukar koordinat: " + ex.Message, true);
            }
            pnlPointEditor.Visible = true;
            pnlEditor.Visible = true;
            SetTab("#tab-point");
        }

    }
}
