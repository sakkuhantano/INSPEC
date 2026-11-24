using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    public class InspectionGeofencePoint
    {
        public int SequenceNo { get; set; }
        public double Latitude { get; set; }
        public double Longitude { get; set; }
    }

    public partial class M_InspectionGeofence : WAL.PB, WAL.I_ToolBar_2
    {
        // Reuse the existing Master Inspection Type permission while this new
        // master page is being introduced. A dedicated MenuID can be assigned later.
        private const string _MenuID = "1530";

        protected void Page_Load(object sender, EventArgs e)
        {
            if (!IsPostBack)
            {
                if (base.AllowRead(_MenuID) == 2)
                    throw new Exception(WAL.GF.MSG_ACCESS_DENIED);

                Master.Mn_lit_Title = WAL.PB.AppID + " -> Master Inspection Geofence";
                litCompany.Text = Server.HtmlEncode(Master.Mn_CompanyID);
                litLocation.Text = Server.HtmlEncode(Master.Mn_LocationID);

                InitToolbar();
                _PrepareScreen();
                GF.Focus(this, txtGeofenceName.ClientID);
            }
        }

        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            switch (e.ToolbarItem)
            {
                case ToolbarItem_2.New:
                    _PrepareScreen();
                    GF.Focus(this, txtGeofenceName.ClientID);
                    break;
                case ToolbarItem_2.Save:
                    _Save();
                    break;
                case ToolbarItem_2.Delete:
                    txtConfirmAction.Text = "";
                    GF.ConfirmMsg_2(this.Page, txtConfirmAction.ClientID, "Are you sure want to delete this geofence?", "2");
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

        protected void txtConfirmAction_TextChanged(object sender, EventArgs e)
        {
            if (GF.SplitStr(txtConfirmAction.Text)[0] == "2")
                _Delete();
        }

        protected void ddlSavedGeofence_SelectedIndexChanged(object sender, EventArgs e)
        {
            int id;
            if (Int32.TryParse(ddlSavedGeofence.SelectedValue, out id) && id > 0)
                _Open(id);
            else
                _PrepareScreen();
        }

        private void _PrepareScreen()
        {
            txtIsNew.Text = "1";
            txtGeofenceID.Text = "";
            txtGeofenceName.Text = "";
            txtDescription.Text = "";
            chkIsActive.Checked = true;
            hidPointsJson.Value = "[]";
            hidEditingSequence.Value = "";
            pnlPointEditor.Visible = false;
            _BindPoints(new List<InspectionGeofencePoint>());
            _RefreshSavedGeofenceList("");
            Master.TB_VisibleButton(ToolbarItem_2.Save, true);
            Master.TB_VisibleButton(ToolbarItem_2.Delete, false);
        }

        private void _Open(int geofenceID)
        {
            DataTable header;
            DataTable detail;
            using (var br = new WAL.BR.CF())
            {
                header = br.EQueryP(@"SELECT GeofenceID, GeofenceName, Description, IsActive
FROM dbo.PIP_M_InspectionGeofence
WHERE GeofenceID=@GeofenceID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                    new SqlParameter[] {
                        new SqlParameter("@GeofenceID", geofenceID),
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });

                if (header.Rows.Count == 0)
                {
                    GF.MsgBox(this, "Geofence was not found in the current Company and Location.", "BS-5.3.0");
                    _PrepareScreen();
                    return;
                }

                detail = br.EQueryP(@"SELECT SequenceNo, Latitude, Longitude
FROM dbo.PIP_M_InspectionGeofencePoint
WHERE GeofenceID=@GeofenceID
ORDER BY SequenceNo",
                    new SqlParameter[] { new SqlParameter("@GeofenceID", geofenceID) });
            }

            txtGeofenceID.Text = Convert.ToString(header.Rows[0]["GeofenceID"]);
            txtGeofenceName.Text = Convert.ToString(header.Rows[0]["GeofenceName"]);
            txtDescription.Text = Convert.ToString(header.Rows[0]["Description"]);
            chkIsActive.Checked = Convert.ToBoolean(header.Rows[0]["IsActive"]);
            txtIsNew.Text = "0";

            List<InspectionGeofencePoint> points = new List<InspectionGeofencePoint>();
            foreach (DataRow row in detail.Rows)
            {
                points.Add(new InspectionGeofencePoint
                {
                    SequenceNo = Convert.ToInt32(row["SequenceNo"]),
                    Latitude = Convert.ToDouble(row["Latitude"], CultureInfo.InvariantCulture),
                    Longitude = Convert.ToDouble(row["Longitude"], CultureInfo.InvariantCulture)
                });
            }

            _WritePoints(points);
            _BindPoints(points);
            hidEditingSequence.Value = "";
            pnlPointEditor.Visible = false;
            _RefreshSavedGeofenceList(geofenceID.ToString(CultureInfo.InvariantCulture));
            Master.TB_VisibleButton(ToolbarItem_2.Save, true);
            Master.TB_VisibleButton(ToolbarItem_2.Delete, true);
            GF.Focus(this, txtGeofenceName.ClientID);
        }

        private void _RefreshSavedGeofenceList(string selectedID)
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"SELECT GeofenceID,
       CASE WHEN IsActive=1 THEN GeofenceName ELSE GeofenceName + N' (Inactive)' END AS GeofenceName
FROM dbo.PIP_M_InspectionGeofence
WHERE CompanyID=@CompanyID AND LocationID=@LocationID
ORDER BY IsActive DESC, GeofenceName",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", Master.Mn_CompanyID),
                        new SqlParameter("@LocationID", Master.Mn_LocationID)
                    });

                ddlSavedGeofence.DataSource = dt;
                ddlSavedGeofence.DataTextField = "GeofenceName";
                ddlSavedGeofence.DataValueField = "GeofenceID";
                ddlSavedGeofence.DataBind();
            }

            ddlSavedGeofence.Items.Insert(0, new ListItem("-- New / Select Geofence --", ""));
            if (!String.IsNullOrEmpty(selectedID) && ddlSavedGeofence.Items.FindByValue(selectedID) != null)
                ddlSavedGeofence.SelectedValue = selectedID;
            else
                ddlSavedGeofence.SelectedIndex = 0;
        }

        protected void lbtnSyncPoints_Click(object sender, EventArgs e)
        {
            try
            {
                List<InspectionGeofencePoint> points = _ReadPoints();
                _WritePoints(points);
                _BindPoints(points);
                pnlPointEditor.Visible = false;
                hidEditingSequence.Value = "";
            }
            catch (Exception ex)
            {
                GF.MsgBox(this, "Unable to read polygon coordinates: " + ex.Message, "BS-5.3.0");
            }
        }

        protected void gridPoints_ItemCommand(object source, DataGridCommandEventArgs e)
        {
            int sequenceNo;
            if (!Int32.TryParse(Convert.ToString(e.CommandArgument), out sequenceNo))
                return;

            List<InspectionGeofencePoint> points = _ReadPoints();
            InspectionGeofencePoint point = points.FirstOrDefault(x => x.SequenceNo == sequenceNo);
            if (point == null)
                return;

            if (e.CommandName == "EditPoint")
            {
                hidEditingSequence.Value = sequenceNo.ToString(CultureInfo.InvariantCulture);
                lblEditingPoint.Text = "#" + sequenceNo.ToString(CultureInfo.InvariantCulture);
                txtPointLatitude.Text = point.Latitude.ToString("0.0000000", CultureInfo.InvariantCulture);
                txtPointLongitude.Text = point.Longitude.ToString("0.0000000", CultureInfo.InvariantCulture);
                pnlPointEditor.Visible = true;
            }
            else if (e.CommandName == "DeletePoint")
            {
                points.Remove(point);
                _NormalizePoints(points);
                _WritePoints(points);
                _BindPoints(points);
                pnlPointEditor.Visible = false;
                hidEditingSequence.Value = "";
            }
        }

        protected void lbtnApplyPoint_Click(object sender, EventArgs e)
        {
            int sequenceNo;
            double latitude, longitude;
            if (!Int32.TryParse(hidEditingSequence.Value, out sequenceNo) ||
                !Double.TryParse(txtPointLatitude.Text.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out latitude) ||
                !Double.TryParse(txtPointLongitude.Text.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out longitude))
            {
                GF.MsgBox(this, "Latitude and Longitude must be valid numeric coordinates using decimal degrees.", "BS-5.3.0");
                return;
            }

            if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180)
            {
                GF.MsgBox(this, "Latitude must be between -90 and 90 and Longitude between -180 and 180.", "BS-5.3.0");
                return;
            }

            List<InspectionGeofencePoint> points = _ReadPoints();
            InspectionGeofencePoint point = points.FirstOrDefault(x => x.SequenceNo == sequenceNo);
            if (point == null)
            {
                GF.MsgBox(this, "The selected polygon point no longer exists.", "BS-5.3.0");
                return;
            }

            point.Latitude = latitude;
            point.Longitude = longitude;
            _NormalizePoints(points);
            _WritePoints(points);
            _BindPoints(points);
            pnlPointEditor.Visible = false;
            hidEditingSequence.Value = "";
        }

        protected void lbtnCancelPoint_Click(object sender, EventArgs e)
        {
            pnlPointEditor.Visible = false;
            hidEditingSequence.Value = "";
        }

        private void _BindPoints(List<InspectionGeofencePoint> points)
        {
            DataTable dt = new DataTable();
            dt.Columns.Add("SequenceNo", typeof(int));
            dt.Columns.Add("Latitude", typeof(string));
            dt.Columns.Add("Longitude", typeof(string));

            foreach (InspectionGeofencePoint point in points)
            {
                DataRow row = dt.NewRow();
                row["SequenceNo"] = point.SequenceNo;
                row["Latitude"] = point.Latitude.ToString("0.0000000", CultureInfo.InvariantCulture);
                row["Longitude"] = point.Longitude.ToString("0.0000000", CultureInfo.InvariantCulture);
                dt.Rows.Add(row);
            }

            gridPoints.DataSource = dt;
            gridPoints.DataBind();
            pnlPointsEmpty.Visible = points.Count == 0;
            lblPointCount.Text = points.Count.ToString(CultureInfo.InvariantCulture) + " titik";
        }

        private List<InspectionGeofencePoint> _ReadPoints()
        {
            string json = (hidPointsJson.Value ?? "").Trim();
            if (json == "" || json == "null")
                return new List<InspectionGeofencePoint>();

            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            List<InspectionGeofencePoint> points = serializer.Deserialize<List<InspectionGeofencePoint>>(json);
            if (points == null)
                points = new List<InspectionGeofencePoint>();
            _NormalizePoints(points);
            return points;
        }

        private void _WritePoints(List<InspectionGeofencePoint> points)
        {
            _NormalizePoints(points);
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            hidPointsJson.Value = serializer.Serialize(points);
        }

        private void _NormalizePoints(List<InspectionGeofencePoint> points)
        {
            for (int i = 0; i < points.Count; i++)
                points[i].SequenceNo = i + 1;
        }

        private bool _ValidSave()
        {
            string message = "";
            List<InspectionGeofencePoint> points;

            if (String.IsNullOrWhiteSpace(Master.Mn_CompanyID))
                message = "Current Company is not available.";
            else if (String.IsNullOrWhiteSpace(Master.Mn_LocationID))
                message = "Current Location is not available.";
            else if (String.IsNullOrWhiteSpace(txtGeofenceName.Text))
                message = "Geofence Name cannot be empty.";
            else
            {
                try
                {
                    points = _ReadPoints();
                    if (points.Count < 3)
                        message = "Draw a polygon with at least 3 points before saving.";
                    else if (points.Any(x => Double.IsNaN(x.Latitude) || Double.IsInfinity(x.Latitude) ||
                                             Double.IsNaN(x.Longitude) || Double.IsInfinity(x.Longitude) ||
                                             x.Latitude < -90 || x.Latitude > 90 ||
                                             x.Longitude < -180 || x.Longitude > 180))
                        message = "Polygon coordinates are invalid.";
                    else if (points.Select(x => x.Latitude.ToString("F7", CultureInfo.InvariantCulture) + "," +
                                               x.Longitude.ToString("F7", CultureInfo.InvariantCulture)).Distinct().Count() < 3)
                        message = "Polygon must contain at least 3 different coordinates.";
                }
                catch
                {
                    message = "Polygon coordinates could not be read. Please redraw the polygon.";
                }
            }

            if (message != "")
                GF.MsgBox(this, message, "BS-5.3.0");
            return message == "";
        }

        private bool _Save()
        {
            if (!_ValidSave())
                return false;

            bool isNew = txtIsNew.Text == "1";
            int geofenceID = 0;
            if (!isNew && !Int32.TryParse(txtGeofenceID.Text, out geofenceID))
            {
                GF.MsgBox(this, "Invalid Geofence ID. Please open the record again.", "BS-5.3.0");
                return false;
            }

            string headerType = isNew ? "1" : "2";
            DataTable result;
            try
            {
                using (var br = new WAL.BR.CF())
                {
                    result = br.EQueryP("spPIP_InsertUpdateDeleteInput_PIP_M_InspectionGeofence",
                        _GeofenceParameters(headerType, "0", geofenceID, null), true);
                }

                if (result == null || result.Rows.Count == 0 || !Int32.TryParse(Convert.ToString(result.Rows[0]["GeofenceID"]), out geofenceID))
                {
                    GF.MsgBox(this, "Header was not saved because Geofence ID was not returned.", "BS-5.3.0");
                    return false;
                }

                txtGeofenceID.Text = geofenceID.ToString(CultureInfo.InvariantCulture);
                txtIsNew.Text = "0";

                if (!_SaveDt(isNew ? "1" : "2"))
                    return false;

                GF.MsgBox(this, "Geofence saved successfully.", "BS-5.3.0");
                _Open(geofenceID);
                return true;
            }
            catch (Exception ex)
            {
                GF.MsgBox(this, "Save failed: " + ex.Message, "BS-5.3.0");
                return false;
            }
        }

        // Save polygon vertices through the same CRUD procedure:
        // @p_Tipe1=1 inserts a new point set; @p_Tipe1=2 replaces an existing point set.
        private bool _SaveDt(string detailType)
        {
            int geofenceID;
            if (!Int32.TryParse(txtGeofenceID.Text, out geofenceID) || geofenceID <= 0)
            {
                GF.MsgBox(this, "Save the geofence header before saving polygon details.", "BS-5.3.0");
                return false;
            }

            List<InspectionGeofencePoint> points = _ReadPoints();
            string xml = _BuildPointsXml(points);

            using (var br = new WAL.BR.CF())
                br.EQueryP("spPIP_InsertUpdateDeleteInput_PIP_M_InspectionGeofence",
                    _GeofenceParameters("0", detailType, geofenceID, xml), true);

            return true;
        }

        private bool _Delete()
        {
            int geofenceID;
            if (!Int32.TryParse(txtGeofenceID.Text, out geofenceID) || geofenceID <= 0)
            {
                GF.MsgBox(this, "Select a geofence before deleting.", "BS-5.3.0");
                return false;
            }

            try
            {
                using (var br = new WAL.BR.CF())
                    br.EQueryP("spPIP_InsertUpdateDeleteInput_PIP_M_InspectionGeofence",
                        _GeofenceParameters("3", "0", geofenceID, null), true);

                GF.MsgBox(this, "Geofence deactivated successfully.", "BS-5.3.0");
                _PrepareScreen();
                return true;
            }
            catch (Exception ex)
            {
                GF.MsgBox(this, "Delete failed: " + ex.Message, "BS-5.3.0");
                return false;
            }
        }

        private SqlParameter[] _GeofenceParameters(string headerType, string detailType, int geofenceID, string pointsXml)
        {
            SqlParameter pointParameter = new SqlParameter("@p_PointsXml", SqlDbType.Xml);
            pointParameter.Value = pointsXml == null ? (object)DBNull.Value : pointsXml;

            return new SqlParameter[] {
                new SqlParameter("@p_Tipe", headerType),
                new SqlParameter("@p_Tipe1", detailType),
                new SqlParameter("@p_GeofenceID", geofenceID),
                new SqlParameter("@p_CompanyID", Master.Mn_CompanyID),
                new SqlParameter("@p_LocationID", Master.Mn_LocationID),
                new SqlParameter("@p_GeofenceName", txtGeofenceName.Text.Trim()),
                new SqlParameter("@p_Description", txtDescription.Text.Trim()),
                new SqlParameter("@p_IsActive", chkIsActive.Checked),
                pointParameter,
                new SqlParameter("@p_UpdateUser", Master.Mn_EmployeeID)
            };
        }

        private string _BuildPointsXml(List<InspectionGeofencePoint> points)
        {
            StringBuilder xml = new StringBuilder();
            xml.Append("<Points>");
            for (int i = 0; i < points.Count; i++)
            {
                InspectionGeofencePoint point = points[i];
                xml.Append("<Point SequenceNo=\"");
                xml.Append((i + 1).ToString(CultureInfo.InvariantCulture));
                xml.Append("\" Latitude=\"");
                xml.Append(point.Latitude.ToString("0.0000000", CultureInfo.InvariantCulture));
                xml.Append("\" Longitude=\"");
                xml.Append(point.Longitude.ToString("0.0000000", CultureInfo.InvariantCulture));
                xml.Append("\" />");
            }
            xml.Append("</Points>");
            return xml.ToString();
        }
    }
}
