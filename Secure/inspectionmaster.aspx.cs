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
    public partial class inspectionmaster : WAL.PB
    {
        // Reuse the Inspection Type master permission while the dedicated
        // Inspection Setup menu entry is registered in the menu master.
        private const string _MenuID = "1530";
        private const int _MaxPdfBytes = 50 * 1024 * 1024;

        protected void Page_Load(object sender, EventArgs e)
        {
            if (!IsPostBack)
            {
                if (base.AllowRead(_MenuID) == 2)
                    throw new Exception(WAL.GF.MSG_ACCESS_DENIED);

                Master.Mn_lit_Title = WAL.PB.AppID + " -> Inspection Setup";
                BindAll();
                PrepareMap();
                PreparePoint();
            }
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

        private void BindMaps()
        {
            using (var br = new WAL.BR.CF())
            {
                gvMaps.DataSource = br.EQueryP(@"
SELECT MapID, MapCode, MapName, MapVersion, IsActive, ImagePath
FROM dbo.PIP_M_InspectionMap
WHERE CompanyID=@CompanyID AND LocationID=@LocationID
  AND IsCurrentVersion=1
ORDER BY MapCode",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });
                gvMaps.DataBind();
            }
        }

        private void BindPointLookups()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable types = br.EQuery(@"
SELECT InspectionTypeCode, InspectionTypeName
FROM dbo.PIP_M_InspectionType
WHERE IsActive=1
ORDER BY InspectionTypeCode");
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
  AND CompanyID=@CompanyID AND LocationID=@LocationID
  AND IsActive=1
ORDER BY InspectionTypeDetailCode",
                    new SqlParameter[] {
                        new SqlParameter("@TypeCode", selected),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
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

        private void BindPoints()
        {
            using (var br = new WAL.BR.CF())
            {
                gvPoints.DataSource = br.EQueryP(@"
SELECT P.InspectionPointID, P.PointCode, P.PointName,
       P.InspectionTypeCode, P.InspectionTypeDetailCode,
       P.PointObjectType, P.IsActive, ISNULL(M.MapCode,'') AS MapCode
FROM dbo.PIP_M_InspectionPoint P
LEFT JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
WHERE P.CompanyID=@CompanyID AND P.LocationID=@LocationID
ORDER BY P.InspectionTypeCode, P.InspectionTypeDetailCode, P.DisplayOrder, P.PointCode",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });
                gvPoints.DataBind();
            }
        }

        private void BindEditorMaps()
        {
            string mapID = ddlEditorMap.SelectedValue;
            if (!String.IsNullOrEmpty(mapID) && ddlEditorMap.Items.FindByValue(mapID) != null)
                ddlEditorMap.SelectedValue = mapID;
            BindEditorPoints();
        }

        private void BindEditorPoints()
        {
            ddlEditorPoint.Items.Clear();
            ddlEditorPoint.Items.Add(new ListItem("-- Select Inspection Point --", ""));
            if (String.IsNullOrWhiteSpace(ddlEditorMap.SelectedValue)) return;

            using (var br = new WAL.BR.CF())
            {
                DataTable points = br.EQueryP(@"
SELECT InspectionPointID, PointCode, PointName
FROM dbo.PIP_M_InspectionPoint
WHERE CompanyID=@CompanyID AND LocationID=@LocationID
  AND IsActive=1 AND (MapID IS NULL OR MapID=@MapID)
ORDER BY DisplayOrder, PointCode",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID),
                        new SqlParameter("@MapID", Convert.ToInt64(ddlEditorMap.SelectedValue))
                    });
                if (points != null)
                {
                    foreach (DataRow row in points.Rows)
                        ddlEditorPoint.Items.Add(new ListItem(
                            Convert.ToString(row["PointCode"]) + " - " + Convert.ToString(row["PointName"]),
                            Convert.ToString(row["InspectionPointID"])));
                }
            }
        }

        private void PrepareMap()
        {
            hidMapID.Value = "";
            txtMapCode.Text = "";
            txtMapName.Text = "";
            txtMapDescription.Text = "";
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
            chkPointActive.Checked = true;
            if (ddlInspectionType.Items.Count > 0) ddlInspectionType.SelectedIndex = 0;
            BindInspectionDetails();
            if (ddlPointMap.Items.Count > 0) ddlPointMap.SelectedIndex = 0;
        }

        protected void btnNewMap_Click(object sender, EventArgs e)
        {
            PrepareMap();
            SetTab("#tab-map");
        }

        protected void btnRefreshMap_Click(object sender, EventArgs e)
        {
            BindMaps();
            BindPointLookups();
            BindEditorMaps();
            SetTab("#tab-map");
        }

        protected void gvMaps_RowCommand(object sender, GridViewCommandEventArgs e)
        {
            long mapID;
            if (!Int64.TryParse(Convert.ToString(e.CommandArgument), out mapID)) return;

            DataTable dt = GetMap(mapID);
            if (dt.Rows.Count == 0) return;
            DataRow row = dt.Rows[0];

            if (e.CommandName == "EditMap")
            {
                hidMapID.Value = mapID.ToString(CultureInfo.InvariantCulture);
                txtMapCode.Text = Convert.ToString(row["MapCode"]);
                txtMapName.Text = Convert.ToString(row["MapName"]);
                txtMapDescription.Text = Convert.ToString(row["Description"]);
                lblMapVersion.Text = "Current version: " + Convert.ToString(row["MapVersion"]) +
                    " · Upload PDF baru untuk membuat versi berikutnya.";
                pnlMapPreview.Visible = true;
                ShowMapPreview(row);
                SetTab("#tab-map");
            }
            else if (e.CommandName == "PreviewMap")
            {
                pnlMapPreview.Visible = true;
                lblMapPreviewTitle.Text = Convert.ToString(row["MapCode"]) + " - " + Convert.ToString(row["MapName"]);
                ShowMapPreview(row);
                SetTab("#tab-map");
            }
        }

        private DataTable GetMap(long mapID)
        {
            using (var br = new WAL.BR.CF())
                return br.EQueryP(@"
SELECT MapID, MapCode, MapName, ImagePath, MapVersion, IsActive, Description
FROM dbo.PIP_M_InspectionMap
WHERE MapID=@MapID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                    new SqlParameter[] {
                        new SqlParameter("@MapID", mapID),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });
        }

        private void ShowMapPreview(DataRow row)
        {
            string path = Convert.ToString(row["ImagePath"]);
            string url = ResolveUrl("~/" + path.TrimStart('/'));
            lblMapPreviewTitle.Text = Convert.ToString(row["MapCode"]) + " - " +
                Convert.ToString(row["MapName"]) + " (v" + Convert.ToString(row["MapVersion"]) + ")";
            lnkMapPdf.NavigateUrl = url;
            litMapPreview.Text = "<iframe class='inspection-pdf-preview' title='Inspection floor plan' src='" +
                HttpUtility.HtmlAttributeEncode(url) + "'></iframe>";
            pnlMapPreview.Visible = true;
        }

        protected void btnSaveMap_Click(object sender, EventArgs e)
        {
            string code = txtMapCode.Text.Trim().ToUpperInvariant();
            string name = txtMapName.Text.Trim();
            if (code == "" || name == "")
            {
                ShowMessage("Map Code dan Map Name wajib diisi.", true);
                SetTab("#tab-map");
                return;
            }

            string savedPath = "";
            try
            {
                if (fuMapPdf.HasFile)
                    savedPath = SavePdfFile(fuMapPdf);

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
SET MapCode=@MapCode, MapName=@MapName, Description=@Description, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@MapID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                                MapParameters(oldID, code, name, Convert.ToString(old.Rows[0]["ImagePath"])), true);
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
 MapVersion,IsCurrentVersion,IsActive,Description,EntryUser,UpdateUser)
VALUES
(@NewMapID,@CompanyID,@LocationID,@MapCode,@MapName,@ImagePath,0,0,100,100,
 @MapVersion,1,1,@Description,@UpdateUser,@UpdateUser);
UPDATE dbo.PIP_M_InspectionPoint SET MapID=@NewMapID, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@OldMapID AND CompanyID=@CompanyID AND LocationID=@LocationID;
UPDATE dbo.PIP_M_InspectionMapElement SET MapID=@NewMapID, UpdateUser=@UpdateUser, UpdateDate=GETDATE()
WHERE MapID=@OldMapID;",
                                new SqlParameter[] {
                                    new SqlParameter("@OldMapID", oldID), new SqlParameter("@NewMapID", newID),
                                    new SqlParameter("@CompanyID", Master.Mn_CompanyID), new SqlParameter("@LocationID", Master.Mn_LocationID),
                                    new SqlParameter("@MapCode", code), new SqlParameter("@MapName", name),
                                    new SqlParameter("@ImagePath", savedPath), new SqlParameter("@MapVersion", version),
                                    new SqlParameter("@Description", txtMapDescription.Text.Trim()),
                                    new SqlParameter("@UpdateUser", Master.Mn_EmployeeID)
                                }, true);
                            hidMapID.Value = newID.ToString(CultureInfo.InvariantCulture);
                        }
                    }
                    else
                    {
                        if (savedPath == "") throw new Exception("Pilih file PDF denah terlebih dahulu.");
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
 MapVersion,IsCurrentVersion,IsActive,Description,EntryUser,UpdateUser)
VALUES
(@MapID,@CompanyID,@LocationID,@MapCode,@MapName,@ImagePath,0,0,100,100,
 @MapVersion,1,1,@Description,@UpdateUser,@UpdateUser)",
                            new SqlParameter[] {
                                new SqlParameter("@MapID", newID), new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                                new SqlParameter("@LocationID", Master.Mn_LocationID), new SqlParameter("@MapCode", code),
                                new SqlParameter("@MapName", name), new SqlParameter("@ImagePath", savedPath),
                                new SqlParameter("@MapVersion", version), new SqlParameter("@Description", txtMapDescription.Text.Trim()),
                                new SqlParameter("@UpdateUser", Master.Mn_EmployeeID)
                            }, true);
                        hidMapID.Value = newID.ToString(CultureInfo.InvariantCulture);
                    }
                }

                BindMaps();
                BindPointLookups();
                BindEditorMaps();
                DataTable current = GetMap(Convert.ToInt64(hidMapID.Value));
                if (current.Rows.Count > 0) ShowMapPreview(current.Rows[0]);
                lblMapVersion.Text = "Map tersimpan. PDF dan versi map sudah tercatat.";
                ShowMessage("Map berhasil disimpan.", false);
            }
            catch (Exception ex)
            {
                if (savedPath != "") TryDeleteFile(savedPath);
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
                new SqlParameter("@UpdateUser", Master.Mn_EmployeeID),
                new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                new SqlParameter("@LocationID", Master.Mn_LocationID)
            };
        }

        private string SavePdfFile(FileUpload upload)
        {
            if (upload.PostedFile.ContentLength <= 0 || upload.PostedFile.ContentLength > _MaxPdfBytes)
                throw new Exception("Ukuran PDF harus lebih dari 0 dan maksimal 50 MB.");
            string extension = Path.GetExtension(upload.FileName);
            if (!String.Equals(extension, ".pdf", StringComparison.OrdinalIgnoreCase))
                throw new Exception("File denah harus berformat PDF.");

            byte[] signature = new byte[5];
            upload.PostedFile.InputStream.Position = 0;
            if (upload.PostedFile.InputStream.Read(signature, 0, signature.Length) != 5 ||
                System.Text.Encoding.ASCII.GetString(signature) != "%PDF-")
                throw new Exception("File yang dipilih bukan PDF yang valid.");

            string folder = "~/Upload/InspectionMaps/" +
                SafePathPart(Master.Mn_CompanyID) + "/" + SafePathPart(Master.Mn_LocationID);
            string physicalFolder = Server.MapPath(folder);
            if (!Directory.Exists(physicalFolder)) Directory.CreateDirectory(physicalFolder);

            string fileName = Guid.NewGuid().ToString("N") + ".pdf";
            string fullPath = Path.Combine(physicalFolder, fileName);
            upload.PostedFile.InputStream.Position = 0;
            upload.SaveAs(fullPath);
            return (folder.TrimStart('~', '/') + "/" + fileName).Replace("\\", "/");
        }

        private string SafePathPart(string value)
        {
            string result = new string((value ?? "").Where(c => Char.IsLetterOrDigit(c) || c == '-' || c == '_').ToArray());
            return result == "" ? "_" : result;
        }

        private void TryDeleteFile(string relativePath)
        {
            try
            {
                string full = Server.MapPath("~/" + relativePath.TrimStart('/'));
                if (File.Exists(full)) File.Delete(full);
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

        protected void ddlInspectionType_SelectedIndexChanged(object sender, EventArgs e)
        {
            BindInspectionDetails();
            SetTab("#tab-point");
        }

        protected void btnNewPoint_Click(object sender, EventArgs e)
        {
            PreparePoint();
            SetTab("#tab-point");
        }

        protected void gvPoints_RowCommand(object sender, GridViewCommandEventArgs e)
        {
            if (e.CommandName != "EditPoint") return;
            long pointID;
            if (!Int64.TryParse(Convert.ToString(e.CommandArgument), out pointID)) return;

            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT * FROM dbo.PIP_M_InspectionPoint
WHERE InspectionPointID=@ID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                    new SqlParameter[] {
                        new SqlParameter("@ID", pointID),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });
                if (dt.Rows.Count == 0) return;
                DataRow row = dt.Rows[0];
                hidPointID.Value = pointID.ToString(CultureInfo.InvariantCulture);
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
                chkPointActive.Checked = Convert.ToBoolean(row["IsActive"]);
            }
            SetTab("#tab-point");
        }

        protected void btnSavePoint_Click(object sender, EventArgs e)
        {
            string typeCode = ddlInspectionType.SelectedValue;
            string detailCode = ddlInspectionDetail.SelectedValue;
            string code = txtPointCode.Text.Trim().ToUpperInvariant();
            string name = txtPointName.Text.Trim();
            int order;
            if (typeCode == "" || detailCode == "" || code == "" || name == "")
            {
                ShowMessage("Inspection Type, Detail, Point Code, dan Point Name wajib diisi.", true);
                SetTab("#tab-point");
                return;
            }
            if (!Int32.TryParse(txtPointOrder.Text.Trim(), out order))
            {
                ShowMessage("Display Order harus berupa angka.", true);
                SetTab("#tab-point");
                return;
            }

            object mapValue = String.IsNullOrWhiteSpace(ddlPointMap.SelectedValue)
                ? (object)DBNull.Value : Convert.ToInt64(ddlPointMap.SelectedValue);
            long pointID;
            bool editing = Int64.TryParse(hidPointID.Value, out pointID) && pointID > 0;
            try
            {
                using (var br = new WAL.BR.CF())
                {
                    if (editing)
                    {
                        br.EQueryP(@"
UPDATE dbo.PIP_M_InspectionPoint
SET InspectionTypeCode=@TypeCode, InspectionTypeDetailCode=@DetailCode,
    PointCode=@PointCode, PointName=@PointName, PointObjectType=@ObjectType,
    PointDescription=@Description, ObjectReferenceType=@ObjectType,
    ObjectReferenceCode=@ReferenceCode, MapID=@MapID, DisplayOrder=@DisplayOrder,
    IsActive=@IsActive, UpdateUser=@UserID, UpdateDate=GETDATE()
WHERE InspectionPointID=@PointID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                            PointParameters(pointID, mapValue, typeCode, detailCode, code, name, order), true);
                    }
                    else
                    {
                        pointID = NextId("dbo.PIP_M_InspectionPoint", "InspectionPointID");
                        br.EQueryP(@"
INSERT INTO dbo.PIP_M_InspectionPoint
(InspectionPointID,CompanyID,LocationID,InspectionTypeCode,InspectionTypeDetailCode,
 PointCode,PointName,PointObjectType,PointDescription,ObjectReferenceType,ObjectReferenceID,
 ObjectReferenceCode,MapID,DisplayOrder,IsActive,EntryUser,UpdateUser)
VALUES
(@PointID,@CompanyID,@LocationID,@TypeCode,@DetailCode,@PointCode,@PointName,@ObjectType,
 @Description,@ObjectType,'',@ReferenceCode,@MapID,@DisplayOrder,@IsActive,@UserID,@UserID)",
                            PointParameters(pointID, mapValue, typeCode, detailCode, code, name, order), true);
                    }
                }
                hidPointID.Value = pointID.ToString(CultureInfo.InvariantCulture);
                BindPoints();
                BindEditorPoints();
                ShowMessage("Inspection Point berhasil disimpan.", false);
            }
            catch (Exception ex)
            {
                ShowMessage("Gagal menyimpan Inspection Point: " + ex.Message, true);
            }
            SetTab("#tab-point");
        }

        private SqlParameter[] PointParameters(long pointID, object mapValue, string typeCode,
            string detailCode, string code, string name, int order)
        {
            return new SqlParameter[] {
                new SqlParameter("@PointID", pointID),
                new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                new SqlParameter("@LocationID", Master.Mn_LocationID),
                new SqlParameter("@TypeCode", typeCode),
                new SqlParameter("@DetailCode", detailCode),
                new SqlParameter("@PointCode", code),
                new SqlParameter("@PointName", name),
                new SqlParameter("@ObjectType", ddlPointObjectType.SelectedValue),
                new SqlParameter("@Description", txtPointDescription.Text.Trim()),
                new SqlParameter("@ReferenceCode", txtObjectReferenceCode.Text.Trim()),
                new SqlParameter("@MapID", mapValue),
                new SqlParameter("@DisplayOrder", order),
                new SqlParameter("@IsActive", chkPointActive.Checked),
                new SqlParameter("@UserID", Master.Mn_EmployeeID)
            };
        }

        protected void ddlEditorMap_SelectedIndexChanged(object sender, EventArgs e)
        {
            BindEditorPoints();
            pnlEditor.Visible = false;
            lnkEditorPdf.Visible = false;
            SetTab("#tab-editor");
        }

        protected void btnLoadEditor_Click(object sender, EventArgs e)
        {
            if (String.IsNullOrWhiteSpace(ddlEditorMap.SelectedValue))
            {
                ShowMessage("Pilih map terlebih dahulu.", true);
                SetTab("#tab-editor");
                return;
            }
            BindEditorPoints();
            DataTable selectedMap = GetMap(Convert.ToInt64(ddlEditorMap.SelectedValue));
            if (selectedMap.Rows.Count > 0)
            {
                string pdfPath = ResolveUrl("~/" + Convert.ToString(selectedMap.Rows[0]["ImagePath"]).TrimStart('/'));
                lnkEditorPdf.NavigateUrl = pdfPath;
                lnkEditorPdf.Visible = true;
            }
            BindMapElements();
            pnlEditor.Visible = true;
            SetTab("#tab-editor");
        }

        private void BindMapElements()
        {
            if (String.IsNullOrWhiteSpace(ddlEditorMap.SelectedValue)) return;
            DataTable source;
            using (var br = new WAL.BR.CF())
                source = br.EQueryP(@"
SELECT E.MapElementID,E.InspectionPointID,E.ElementID,E.ShapeAttributes,
       P.PointCode,P.PointName,P.DisplayOrder
FROM dbo.PIP_M_InspectionMapElement E
INNER JOIN dbo.PIP_M_InspectionPoint P ON P.InspectionPointID=E.InspectionPointID
WHERE E.MapID=@MapID AND E.IsActive=1 AND E.IsDeleted=0
ORDER BY P.DisplayOrder,P.PointCode",
                    new SqlParameter[] { new SqlParameter("@MapID", Convert.ToInt64(ddlEditorMap.SelectedValue)) });

            DataTable display = new DataTable();
            display.Columns.Add("MapElementID", typeof(long));
            display.Columns.Add("InspectionPointID", typeof(long));
            display.Columns.Add("PointCode", typeof(string));
            display.Columns.Add("PointName", typeof(string));
            display.Columns.Add("DisplayOrder", typeof(int));
            display.Columns.Add("XPercent", typeof(decimal));
            display.Columns.Add("YPercent", typeof(decimal));

            if (source != null)
            {
                foreach (DataRow row in source.Rows)
                {
                    decimal x, y;
                    ParseCoordinates(Convert.ToString(row["ShapeAttributes"]), out x, out y);
                    DataRow target = display.NewRow();
                    target["MapElementID"] = row["MapElementID"];
                    target["InspectionPointID"] = row["InspectionPointID"];
                    target["PointCode"] = row["PointCode"];
                    target["PointName"] = row["PointName"];
                    target["DisplayOrder"] = row["DisplayOrder"];
                    target["XPercent"] = x;
                    target["YPercent"] = y;
                    display.Rows.Add(target);
                }
            }
            rptMapElements.DataSource = display;
            rptMapElements.DataBind();
            gvMapElements.DataSource = display;
            gvMapElements.DataBind();
        }

        protected void btnSaveMarker_Click(object sender, EventArgs e)
        {
            long mapID, pointID;
            decimal x, y;
            if (!Int64.TryParse(ddlEditorMap.SelectedValue, out mapID) ||
                !Int64.TryParse(ddlEditorPoint.SelectedValue, out pointID))
            {
                ShowMessage("Pilih Map dan Inspection Point.", true);
                SetTab("#tab-editor");
                return;
            }
            if (!Decimal.TryParse(txtMarkerX.Text.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out x) ||
                !Decimal.TryParse(txtMarkerY.Text.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out y) ||
                x < 0 || x > 100 || y < 0 || y > 100)
            {
                ShowMessage("Koordinat X dan Y harus berupa angka antara 0 sampai 100.", true);
                SetTab("#tab-editor");
                return;
            }

            string attributes = "x=" + x.ToString("0.####", CultureInfo.InvariantCulture) +
                ";y=" + y.ToString("0.####", CultureInfo.InvariantCulture);
            string elementID = "POINT_" + pointID.ToString(CultureInfo.InvariantCulture);
            try
            {
                using (var br = new WAL.BR.CF())
                {
                    br.EQueryP(@"
IF EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionMapElement WHERE MapID=@MapID AND InspectionPointID=@PointID)
BEGIN
    UPDATE dbo.PIP_M_InspectionMapElement
    SET ElementID=@ElementID, ShapeType='CIRCLE', SvgPathData=@PathData,
        ShapeAttributes=@Attributes, IsActive=1, IsDeleted=0,
        DeletedBy='', DeletedDate='19000101', UpdateUser=@UserID, UpdateDate=GETDATE()
    WHERE MapID=@MapID AND InspectionPointID=@PointID;
END
ELSE
BEGIN
    DECLARE @NewElementID BIGINT;
    SELECT @NewElementID=ISNULL(MAX(MapElementID),0)+1 FROM dbo.PIP_M_InspectionMapElement;
    INSERT INTO dbo.PIP_M_InspectionMapElement
    (MapElementID,MapID,InspectionPointID,ElementID,ShapeType,SvgPathData,ShapeAttributes,
     StrokeWidth,DisplayOrder,IsVisible,IsActive,IsDeleted,DeletedBy,DeletedDate,EntryUser,UpdateUser)
    VALUES
    (@NewElementID,@MapID,@PointID,@ElementIDText,'CIRCLE',@PathData,@Attributes,2,0,1,1,0,'','19000101',@UserID,@UserID);
END;
UPDATE dbo.PIP_M_InspectionPoint
SET MapID=@MapID, UpdateUser=@UserID, UpdateDate=GETDATE()
WHERE InspectionPointID=@PointID AND CompanyID=@CompanyID AND LocationID=@LocationID;",
                        new SqlParameter[] {
                            new SqlParameter("@MapID", mapID), new SqlParameter("@PointID", pointID),
                            new SqlParameter("@ElementID", elementID), new SqlParameter("@ElementIDText", elementID),
                            new SqlParameter("@PathData", "M " + x.ToString("0.####", CultureInfo.InvariantCulture) + " " +
                                y.ToString("0.####", CultureInfo.InvariantCulture)),
                            new SqlParameter("@Attributes", attributes), new SqlParameter("@UserID", Master.Mn_EmployeeID),
                            new SqlParameter("@CompanyID", Master.Mn_CompanyID), new SqlParameter("@LocationID", Master.Mn_LocationID)
                        }, true);
                }
                BindEditorPoints();
                BindMapElements();
                pnlEditor.Visible = true;
                ShowMessage("Marker berhasil disimpan.", false);
            }
            catch (Exception ex)
            {
                ShowMessage("Gagal menyimpan marker: " + ex.Message, true);
            }
            SetTab("#tab-editor");
        }

        protected void gvMapElements_RowCommand(object sender, GridViewCommandEventArgs e)
        {
            if (e.CommandName != "EditMarker") return;
            long elementID;
            if (!Int64.TryParse(Convert.ToString(e.CommandArgument), out elementID)) return;
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT E.MapElementID,E.InspectionPointID,E.ShapeAttributes
FROM dbo.PIP_M_InspectionMapElement E
WHERE E.MapElementID=@ID AND E.MapID=@MapID",
                    new SqlParameter[] {
                        new SqlParameter("@ID", elementID),
                        new SqlParameter("@MapID", Convert.ToInt64(ddlEditorMap.SelectedValue))
                    });
                if (dt.Rows.Count > 0)
                {
                    hidElementID.Value = elementID.ToString(CultureInfo.InvariantCulture);
                    string pointID = Convert.ToString(dt.Rows[0]["InspectionPointID"]);
                    if (ddlEditorPoint.Items.FindByValue(pointID) != null)
                        ddlEditorPoint.SelectedValue = pointID;
                    decimal x, y;
                    ParseCoordinates(Convert.ToString(dt.Rows[0]["ShapeAttributes"]), out x, out y);
                    txtMarkerX.Text = x.ToString("0.####", CultureInfo.InvariantCulture);
                    txtMarkerY.Text = y.ToString("0.####", CultureInfo.InvariantCulture);
                }
            }
            pnlEditor.Visible = true;
            BindMapElements();
            SetTab("#tab-editor");
        }

        private void ParseCoordinates(string attributes, out decimal x, out decimal y)
        {
            x = 50;
            y = 50;
            string[] parts = (attributes ?? "").Split(';');
            foreach (string part in parts)
            {
                string[] pair = part.Split('=');
                if (pair.Length != 2) continue;
                decimal value;
                if (!Decimal.TryParse(pair[1], NumberStyles.Number, CultureInfo.InvariantCulture, out value))
                    continue;
                if (pair[0].Trim().Equals("x", StringComparison.OrdinalIgnoreCase)) x = Math.Max(0, Math.Min(100, value));
                if (pair[0].Trim().Equals("y", StringComparison.OrdinalIgnoreCase)) y = Math.Max(0, Math.Min(100, value));
            }
        }
    }
}
