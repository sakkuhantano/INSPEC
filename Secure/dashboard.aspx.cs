using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using System.Data;
using System.Data.SqlClient;
using WAL;
using System.Web.Services;

namespace INSPEC.Secure
{
    public partial class dashboard : System.Web.UI.Page
    {
        // Positional TVP contract: first supplied value -> C1, second -> C2, etc.; parameter names are not serialized.
        private static SqlParameter[] InspectionDashboardQueryParameters(string type, params SqlParameter[] values)
        {
            DataTable data = new DataTable();
            for (int i = 1; i <= 13; i++)
                data.Columns.Add("C" + i, typeof(string));
            DataRow row = data.NewRow();
            int index = 0;
            if (values != null)
            {
                foreach (SqlParameter parameter in values)
                {
                    if (parameter == null) continue;
                    if (index >= 13) throw new ArgumentException("Inspection dashboard TVP supports at most 13 values.", "values");
                    object value = parameter.Value;
                    row[index++] = value == null || value == DBNull.Value
                        ? (object)DBNull.Value
                        : Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture);
                }
            }
            data.Rows.Add(row);
            SqlParameter tvp = new SqlParameter("@p_Data", SqlDbType.Structured);
            tvp.TypeName = "dbo.Type_N_Tbl_C13";
            tvp.Value = data;
            return new SqlParameter[] { new SqlParameter("@p_Tipe", type), tvp };
        }

        private static DataTable BuildDashboardQueryData(params string[] values)
        {
            DataTable table = new DataTable();
            for (int i = 1; i <= 13; i++)
                table.Columns.Add("C" + i, typeof(string));
            DataRow row = table.NewRow();
            for (int i = 0; i < values.Length && i < 13; i++)
                row[i] = values[i] ?? String.Empty;
            table.Rows.Add(row);
            return table;
        }

        private static SqlParameter[] DashboardQueryParameters(string type, params string[] values)
        {
            SqlParameter data = new SqlParameter("@p_Data", SqlDbType.Structured);
            data.TypeName = "dbo.Type_N_Tbl_C13";
            data.Value = BuildDashboardQueryData(values);
            return new SqlParameter[] { new SqlParameter("@p_Tipe", type), data };
        }

        private static string GetCurrentSessionToken()
        {
            HttpContext context = HttpContext.Current;
            HttpCookie cookie = context == null ? null : context.Request.Cookies[GFC.CookieName];
            return cookie == null ? String.Empty : Convert.ToString(cookie.Value).Trim();
        }

        protected void Page_Load(object sender, EventArgs e)
        {
            try
            {
                GFC.RequireAnyMenuEmployee();
            }
            catch (HttpException ex)
            {
                // An invalid/expired session or missing INSPEC authorization
                // must return the user to Login.aspx instead of showing ASP.NET 401/403.
                if (ex.GetHttpCode() == 401 || ex.GetHttpCode() == 403)
                {
                    Response.Redirect(ResolveUrl("~/Login.aspx"), false);
                    Context.ApplicationInstance.CompleteRequest();
                    return;
                }

                throw;
            }
        }
        [WebMethod]
        public static object getCheckList(string section, string templateNo, string version, string modelcode = "", string companyId = "", string locationId = "", string templateType = "W", string employeeId = "")
        {
            if (!String.Equals(templateType, "W", StringComparison.OrdinalIgnoreCase) &&
                !String.Equals(templateType, "I", StringComparison.OrdinalIgnoreCase))
                throw new HttpException(400, "Invalid checklist template type.");
            employeeId = String.Equals(templateType, "I", StringComparison.OrdinalIgnoreCase)
                ? GFC.RequireAnyMenuEmployee("20021", "20022")
                : GFC.RequireAnyMenuEmployee("20011", "20012");
            var result = new List<Dictionary<string, object>>();
            using (var br = new WAL.BR.CF())
            {
                if (String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                    throw new HttpException(400, "Company/location is required for checklist download.");
                GFC.RequireCompanyLocation(employeeId, companyId, locationId);
                // Inspection master downloads must be scoped by the server-side section resolver,
                // not by a section list supplied by browser localStorage.
                if (String.Equals(templateType, "I", StringComparison.OrdinalIgnoreCase))
                {
                    if (String.IsNullOrWhiteSpace(employeeId))
                        throw new HttpException(403, "Employee identity is required for inspection template download.");

                    DataTable auth = br.EQueryP(
                        "spPIP_Inspection_Query",
                        InspectionDashboardQueryParameters("081", new SqlParameter[] {
                            new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                            new SqlParameter("@EmployeeID", employeeId),
                            new SqlParameter("@CompanyID", companyId),
                            new SqlParameter("@LocationID", locationId)
                        }));

                    if (auth.Rows.Count == 0 || !Convert.ToBoolean(auth.Rows[0]["IsWO"]))
                        throw new HttpException(403, "This account is not authorized for inspection entry.");

                    var allowedSections = auth.Rows[0]["Section"].ToString()
                        .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                        .Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
                    var requestedSections = (section ?? "")
                        .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                        .Select(s => s.Trim()).Where(s => s.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

                    if (requestedSections.Count == 0 ||
                        requestedSections.Any(s => !allowedSections.Contains(s, StringComparer.OrdinalIgnoreCase)))
                        throw new HttpException(403, "Requested inspection section is not assigned to this employee.");
                    section = String.Join(";", requestedSections);
                }
                else
                {
                    var allowedSections = GFC.GetEmployeeSection(employeeId)
                        .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                        .Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
                    var requestedSections = (section ?? "")
                        .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                        .Select(s => s.Trim()).Where(s => s.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
                    if (requestedSections.Count == 0 ||
                        requestedSections.Any(s => !allowedSections.Contains(s, StringComparer.OrdinalIgnoreCase)))
                        throw new HttpException(403, "Requested Work Order section is not assigned to this employee.");
                    section = String.Join(";", requestedSections);
                }
                DataTable dt = br.EQueryP(
                    "spPIP_Inspection_Query",
                    DashboardQueryParameters("206", section, templateNo, version, companyId, locationId, templateType, employeeId));
                foreach (DataRow row in dt.Rows)
                {
                    var dict = new Dictionary<string, object>();
                    dict["CompanyID"] = companyId;
                    dict["LocationID"] = locationId;
                    dict["IDTemplate"] = Convert.ToInt32(row["IDTemplate"]);
                    dict["IDVersion"] = Convert.ToInt32(row["IDVersion"]);
                    dict["Version"] = row["Version"].ToString();
                    dict["SectionID"] = row["SectionID"].ToString();
                    dict["TemplateType"] = row["TemplateType"].ToString();
                    dict["InspectionTypeCode"] = row["InspectionTypeCode"].ToString();
                    dict["InspectionTypeDetailCode"] = row["InspectionTypeDetailCode"].ToString();
                    // Keep the current master assignment fields in the offline template row too.
                    dict["CompanyScope"] = row["CompanyScope"].ToString();
                    dict["CompanyLocationList"] = row["CompanyLocationList"].ToString();
                    dict["EmployeeList"] = row["EmployeeList"].ToString();
                    dict["TemplateNo"] = row["TemplateNo"].ToString();
                    dict["TemplateName"] = row["TemplateName"].ToString();
                    dict["StatusOption"] = row["StatusOption"].ToString();
                    dict["SummarySampleText"] = GF.GetString(row["SummarySampleText"]);
                    dict["IsSummaryRequired"] = row["VersionIsSummaryRequired"] == DBNull.Value || Convert.ToBoolean(row["VersionIsSummaryRequired"]);
                    dict["IsFollowUpRequired"] = row["VersionIsFollowUpRequired"] == DBNull.Value || Convert.ToBoolean(row["VersionIsFollowUpRequired"]);
                    dict["RemarkRequiredOptions"] = String.IsNullOrWhiteSpace(GF.GetString(row["VersionRemarkRequiredOptions"])) ? new string[0] : GF.GetString(row["VersionRemarkRequiredOptions"]).Split(';');
                    dict["IsRemark1Required"] = Convert.ToBoolean(row["VersionIsRemark1Required"]);
                    dict["Remark1Text"] = GF.GetString(row["VersionRemark1Text"]);
                    dict["IsRemark2Required"] = Convert.ToBoolean(row["VersionIsRemark2Required"]);
                    dict["Remark2Text"] = GF.GetString(row["VersionRemark2Text"]);
                    dict["PhotoRequirement"] = new[] { "NONE", "BEFORE", "AFTER", "BOTH" }.Contains(GF.GetString(row["PhotoRequirement"]).ToUpperInvariant()) ? GF.GetString(row["PhotoRequirement"]).ToUpperInvariant() : "NONE";
                    DataTable dt1 = br.EQueryP(
                        "spPIP_Inspection_Query",
                        DashboardQueryParameters("207", row["IDTemplate"].ToString(), row["IDVersion"].ToString(),
                            row["TemplateNo"].ToString(), templateType, modelcode));
                    DataTable dt2 = br.EQueryP(
                        "spPIP_Inspection_Query",
                        DashboardQueryParameters("208"));
                    DataTable dtRepeat = br.EQueryP(
                        "spPIP_Inspection_Query",
                        DashboardQueryParameters("209", row["IDVersion"].ToString()));
                    DataTable dtRepeatFields = br.EQueryP(
                        "spPIP_Inspection_Query",
                        DashboardQueryParameters("210", row["IDVersion"].ToString()));
                    var sections = dt1.AsEnumerable()
                        .GroupBy(r => new
                        {
                            IDSection = r["IDSection"],
                            SectionName = r["SectionName"],
                            SectionOrder = r["SectionOrder"]
                        })
                        .OrderBy(g => g.Key.SectionOrder)
                        .Select(sec => new
                        {

                            idSection = sec.Key.IDSection,
                            sectionName = sec.Key.SectionName,

                            items = sec.Select(item =>
                            {

                                string itemType = item["ItemType"].ToString();

                                // OPTION LOGIC 🔥
                                string optionList = null;
                                if (itemType == "OPTION")
                                {
                                    optionList = string.IsNullOrEmpty(item["OptionList"].ToString())
                                        ? item["StatusOption"].ToString()
                                        : item["OptionList"].ToString();
                                }

                                // GROUP LOGIC 🔥
                                var groups = dt2.AsEnumerable()
                                    .Where(g => g["IDItem"].ToString() == item["IDItem"].ToString())
                                    .OrderBy(g => g["DisplayOrder"])
                                    .Select(g => new
                                    {
                                        groupName = g["GroupName"].ToString(),
                                        fieldList = g["FieldList"].ToString(),
                                        unit = g["Unit"].ToString()
                                    }).ToList();

                                return new
                                {
                                    idItem = item["IDItem"],
                                    idSubSection = item["IDSubSection"] == DBNull.Value ? 0 : Convert.ToInt32(item["IDSubSection"]),
                                    subSectionName = item["SubSectionName"].ToString(),
                                    subSectionOrder = Convert.ToInt32(item["SubSectionOrder"]),
                                    itemOrder = Convert.ToInt32(item["ItemOrder"]),
                                    label = item["ItemLabel"].ToString(),
                                    type = itemType,
                                    optionList = optionList,
                                    min = item["MinValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(item["MinValue"]),
                                    max = item["MaxValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(item["MaxValue"]),
                                    unit = item["Unit"].ToString(),
                                    showUnitInRange = Convert.ToBoolean(item["ShowUnitInRange"]),
                                    isValueRequired = Convert.ToBoolean(item["IsValueRequired"]),
                                    versionIsRemark1Required = Convert.ToBoolean(row["VersionIsRemark1Required"]),
                                    versionIsRemark2Required = Convert.ToBoolean(row["VersionIsRemark2Required"]),
                                    versionRemark1Text = GF.GetString(row["VersionRemark1Text"]),
                                    versionRemark2Text = GF.GetString(row["VersionRemark2Text"]),
                                    isRemark1Required = Convert.ToBoolean(row["VersionIsRemark1Required"]) && (Convert.ToBoolean(item["IsUseDefaultRemark1"]) || Convert.ToBoolean(item["IsRemark1Required"])),
                                    isRemark2Required = Convert.ToBoolean(row["VersionIsRemark2Required"]) && (Convert.ToBoolean(item["IsUseDefaultRemark2"]) || Convert.ToBoolean(item["IsRemark2Required"])),
                                    isRemark1Mandatory = Convert.ToBoolean(item["IsRemark1Mandatory"]),
                                    isRemark2Mandatory = Convert.ToBoolean(item["IsRemark2Mandatory"]),
                                    isUseDefaultRemark1 = Convert.ToBoolean(item["IsUseDefaultRemark1"]),
                                    isUseDefaultRemark2 = Convert.ToBoolean(item["IsUseDefaultRemark2"]),
                                    // Default OPTION list inherits the version-level rule.
                                    // Custom OPTION list uses the item's own selected required options.
                                    remarkRequiredOptions = !(Convert.ToBoolean(row["VersionIsRemark1Required"]) || Convert.ToBoolean(row["VersionIsRemark2Required"]))
                                        ? new string[0]
                                        : (itemType == "OPTION" && String.IsNullOrWhiteSpace(GF.GetString(item["OptionList"]))
                                            ? (String.IsNullOrWhiteSpace(GF.GetString(row["VersionRemarkRequiredOptions"])) ? new string[0] : GF.GetString(row["VersionRemarkRequiredOptions"]).Split(';'))
                                            : (String.IsNullOrWhiteSpace(GF.GetString(item["ItemRemarkRequiredOptions"])) ? new string[0] : GF.GetString(item["ItemRemarkRequiredOptions"]).Split(';'))),
                                    remark1Text = Convert.ToBoolean(item["IsUseDefaultRemark1"]) ? GF.GetString(row["VersionRemark1Text"]) : (item["Remark1Text"] == DBNull.Value ? "Remark" : item["Remark1Text"].ToString()),
                                    remark2Text = Convert.ToBoolean(item["IsUseDefaultRemark2"]) ? GF.GetString(row["VersionRemark2Text"]) : (item["Remark2Text"] == DBNull.Value ? "Remark" : item["Remark2Text"].ToString()),
                                    isToleranceRequired = GF.GetBoolean(item["IsToleranceRequired"]),
                                    mintol = item["MinTolerance"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(item["MinTolerance"]),
                                    maxtol = item["MaxTolerance"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(item["MaxTolerance"]),
                                    modelcode = GF.GetString(item["ModelCode"]),
                                    groups = groups.Count > 0 ? groups : null,
                                    repeat = dtRepeat.AsEnumerable()
                                        .Where(r => r["IDItem"].ToString() == item["IDItem"].ToString())
                                        .Select(r => new
                                        {
                                            repeatMode = r["RepeatMode"].ToString(),
                                            columnCount = Convert.ToInt32(r["ColumnCount"]),
                                            objectLabel = GF.GetString(r["ObjectLabel"]),
                                            countMode = r["CountMode"].ToString(),
                                            fixedCount = r["FixedCount"] == DBNull.Value ? (int?)null : Convert.ToInt32(r["FixedCount"]),
                                            minCount = r["MinCount"] == DBNull.Value ? (int?)null : Convert.ToInt32(r["MinCount"]),
                                            maxCount = r["MaxCount"] == DBNull.Value ? (int?)null : Convert.ToInt32(r["MaxCount"])
                                        }).FirstOrDefault(),
                                    repeatFields = dtRepeatFields.AsEnumerable()
                                        .Where(f => f["IDItem"].ToString() == item["IDItem"].ToString())
                                        .OrderBy(f => f["DisplayOrder"])
                                        .Select(f => new
                                        {
                                            idRepeat = Convert.ToInt32(f["IDRepeat"]),
                                            fieldLabel = f["FieldLabel"].ToString(),
                                            fieldType = f["FieldType"].ToString(),
                                            optionList = String.IsNullOrWhiteSpace(GF.GetString(f["OptionList"])) ? new string[0] : GF.GetString(f["OptionList"]).Split(';'),
                                            unit = GF.GetString(f["Unit"]),
                                            min = f["MinValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(f["MinValue"]),
                                            max = f["MaxValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(f["MaxValue"]),
                                            minInclusive = f["MinInclusive"] == DBNull.Value || Convert.ToBoolean(f["MinInclusive"]),
                                            maxInclusive = f["MaxInclusive"] == DBNull.Value || Convert.ToBoolean(f["MaxInclusive"]),
                                            isRequired = Convert.ToBoolean(f["IsRequired"]),
                                            groupName = GF.GetString(f["GroupName"]),
                                            displayOrder = Convert.ToInt32(f["DisplayOrder"])
                                        }).ToList()
                                };

                            }).ToList()
                        }).ToList();
                    dict["sections"] = sections;
                    result.Add(dict);
                }
                
                //DataSet ds = new DataSet();
                //dt.TableName = "templates";
                //ds.Tables.Add(dt);
                //dt = br.EQuery("SELECT a.TemplateNo, a.IDSection,SectionName, a.DisplayOrder " +
                //               "FROM PIP_M_CheckListWOPM_Section a JOIN PIP_M_CheckListWOPM b ON b.TemplateNo = a.TemplateNo " +
                //               "WHERE b.SectionID=@SectionID ORDER BY a.DisplayOrder", "@SectionID=" + _sectionId);
                //dt.TableName = "sections";
                //ds.Tables.Add(dt);
                //dt = br.EQuery("SELECT c.TemplateNo, a.IDSection, a.IDItem, a.ItemLabel, a.ItemType, a.OptionList, a.MinValue, a.MaxValue, a.Unit, a.ShowUnitInRange, a.IsValueRequired, a.IsRemarkRequired, a.DisplayOrder " +
                //               "FROM PIP_M_CheckListWOPM_Item a JOIN PIP_M_CheckListWOPM_Section b ON b.IDSection = a.IDSection " +
                //               "JOIN PIP_M_CheckListWOPM c ON c.TemplateNo = b.TemplateNo " +
                //               "WHERE c.SectionID=@SectionID ORDER BY a.DisplayOrder", "@SectionID=" + _sectionId);
                //dt.TableName = "items";
                //ds.Tables.Add(dt);
                //dt = br.EQuery("SELECT d.TemplateNo, c.IDSection, b.IDItem, a.IDGroup, a.GroupName, a.FieldList, a.Unit, a.DisplayOrder " +
                //               "FROM PIP_M_CheckListWOPM_ItemGroup a JOIN PIP_M_CheckListWOPM_Item b ON b.IDItem = a.IDItem " +
                //               "JOIN PIP_M_CheckListWOPM_Section c ON c.IDSection = b.IDSection " +
                //               "JOIN PIP_M_CheckListWOPM d ON d.TemplateNo = c.TemplateNo " +
                //               "WHERE d.SectionID=@SectionID ORDER BY a.DisplayOrder", "@SectionID=" + _sectionId);
                //dt.TableName = "groups";
                //ds.Tables.Add(dt);
                //return GFC.getData_DS(ds);
            }
            return result;
        }
        [WebMethod]
        public static object getInspectionMasters(string section, string employeeId, string companyId, string locationId)
        {
            employeeId = GFC.RequireAnyMenuEmployee("20021", "20022");
            using (var br = new WAL.BR.CF())
            {
                if (String.IsNullOrWhiteSpace(employeeId))
                    throw new HttpException(403, "Employee identity is required for inspection master download.");

                DataTable auth = br.EQueryP(
                    "spPIP_Inspection_Query",
                    InspectionDashboardQueryParameters("082", new SqlParameter[] {
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@EmployeeID", employeeId)
                    }));

                if (auth.Rows.Count == 0 || !Convert.ToBoolean(auth.Rows[0]["IsWO"]))
                    throw new HttpException(403, "This account is not authorized for inspection entry.");

                var allowedSections = auth.Rows[0]["Section"].ToString()
                    .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
                var requestedSections = (section ?? "")
                    .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(s => s.Trim()).Where(s => s.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

                if (requestedSections.Count == 0 ||
                    requestedSections.Any(s => !allowedSections.Contains(s, StringComparer.OrdinalIgnoreCase)))
                    throw new HttpException(403, "Requested inspection section is not assigned to this employee.");
                section = String.Join(";", requestedSections);

                if (String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                    throw new HttpException(400, "Company and location are required for inspection master download.");

                DataTable companyAuth = br.EQueryP(
                    "spPIP_Inspection_Query",
                    InspectionDashboardQueryParameters("083", new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    }));
                if (companyAuth.Rows.Count == 0)
                    throw new HttpException(403, "Employee is not authorized for this company/location.");

                DataTable types = br.EQueryP(
                    "spPIP_Inspection_Query",
                    InspectionDashboardQueryParameters("084", new SqlParameter[] {
                        new SqlParameter("@SectionList", section),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@EmployeeID", employeeId)
                    }));

                DataTable details = br.EQueryP(
                    "spPIP_Inspection_Query",
                    InspectionDashboardQueryParameters("085", new SqlParameter[] {
                        new SqlParameter("@SectionList", section),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    }));

                var typeRows = types.AsEnumerable().Select(row => new
                {
                    InspectionTypeCode = GF.GetString(row["InspectionTypeCode"]),
                    InspectionTypeName = GF.GetString(row["InspectionTypeName"]),
                    SectionID = GF.GetString(row["SectionID"]),
                    InspectionMode = GF.GetString(row["InspectionMode"]),
                    CompanyID = companyId,
                    LocationID = locationId
                }).ToList();
                var detailRows = details.AsEnumerable().Select(row => new
                {
                    CompanyID = companyId,
                    LocationID = locationId,
                    InspectionTypeCode = GF.GetString(row["InspectionTypeCode"]),
                    InspectionTypeDetailCode = GF.GetString(row["InspectionTypeDetailCode"]),
                    InspectionTypeDetailName = GF.GetString(row["InspectionTypeDetailName"]),
                    ScheduleTime = GF.GetString(row["ScheduleTime"])
                }).ToList();
                return new { types = typeRows, details = detailRows };
            }
        }

        [WebMethod]
        public static object getEmployees(string employeeid, string lastSync)
        {
            employeeid = GFC.RequireMenuEmployee("20011");
            string sessionToken = GetCurrentSessionToken();
            if (String.IsNullOrWhiteSpace(sessionToken))
                throw new HttpException(401, "INSPEC device session is missing.");
            using (var br=new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(
                    "spPIP_Inspection_Query",
                    DashboardQueryParameters("211", employeeid, sessionToken,
                        Convert.ToDateTime(lastSync).ToString("yyyy-MM-ddTHH:mm:ss.fff", System.Globalization.CultureInfo.InvariantCulture)));
                return GFC.getData(dt);
            }
        }
        [WebMethod]
        public static object Ping()
        {
            return new { status = "OK" };
        }
    }
    
}