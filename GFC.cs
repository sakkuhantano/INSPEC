using System.Linq;
using Microsoft.VisualBasic;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Diagnostics;
using System.Net.Mail;
using System.Net;
using System.Net.Http;
using System.Web.UI.WebControls;
using System.Web.Script.Serialization;
using System.Web;
using System.IO;
using System.Security.Cryptography;
using System.Web.UI;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using WAL;
using WAL.BR;
using System.Data.SqlClient;
using CrystalDecisions.CrystalReports.Engine;
using CrystalDecisions.Shared;
using Newtonsoft.Json.Linq;

namespace WAL
{
    public sealed class GFC
    {
        #region Variable Others
        public const string PrefixStr = "ctl00$ContentPlaceHolder1$";
        public const string XLSXFolderName = "XLSXs";
        public const string PDFFolderName = "PDFs";
        public const string FormatCurrencyAccountIdr = "#,##0_);(#,##0)";
        public const string FormatCurrencyAccountUs = "#,##0.00_);(#,##0.00)";
        public const string V_Sever_DataHO_IP = "192.168.2.30";
        public const string V_Server_DataHO_User = "Administrator";
        public const string V_Server_DataHO_Domain = V_Sever_DataHO_IP;
        public const string V_Server_DataHO_Password = "17081945Property";
        #endregion


        #region Function
        [DllImport("advapi32.DLL", SetLastError = true)]
        public static extern int LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);
        public static string PeriodMonthOrYear(DateTime _date, string _type = "Month")
        {
            string _retval = string.Empty;
            switch (_type)
            {
                case "EarlyMonth":
                    _retval = GF.CDate(_date.ToString(GF.FormatYearMonth) + "01", GF.FormatDate4).ToString(GF.FormatDate);
                    break;
                case "Month":
                    _retval = GF.CDate(_date.ToString(GF.FormatYearMonth) + "01", GF.FormatDate4).AddMonths(1).AddDays(-1).ToString(GF.FormatDate);
                    break;
                case "Year":
                    _retval = GF.CDate(_date.ToString(GF.FormatYear) + "1231", GF.FormatDate4).ToString(GF.FormatDate);
                    break;

            }
            return _retval;
        }
        public static void UpdateExpiredDate(string p_ID)
        {
            using (SysWebInfo si = new SysWebInfo())
            {
                si.ID = p_ID;
                if (si.SelectOne().Rows.Count > 0)
                {
                    si.ExpiredDate = si.UpdateDate.AddDays(-1);
                    si.UpdateExpiredDateByID();
                }
            }
        }

        public static string GetHashStringSQL(string p_str)
        {
            string _retval = "";
            using (var ocf = new WAL.BR.CF())
            {
                _retval = ocf.EQuery("SELECT x.EnStr " +
                                     "FROM dbo.F_GetHashStringSQL(@p_Str, default) x ",
                                     "@p_Str=" + p_str).Rows[0]["EnStr"] + "";

            }
            return _retval;
        }
        public static string GetUserIPAddress()
        {
            System.Web.HttpContext context = System.Web.HttpContext.Current;
            string sIPAddress = context.Request.ServerVariables["HTTP_X_FORWARDED_FOR"];
            if (String.IsNullOrEmpty(sIPAddress))
            {
                return context.Request.ServerVariables["REMOTE_ADDR"];
            }
            else
            {
                return GF.SplitStr(sIPAddress, ",")[0];
            }
        }
        public static string SysWebInfo_Insert_RID(string p_UserID,
                                                   string p_Type,
                                                   string p_Description,
                                                   string p_Description1,
                                                   string p_Description2,
                                                   string p_Description3)
        {
            string _retval = "";
            DateTime V_GetDateTime = GF.DBSDatetime();
            using (var swi = new WAL.BR.SysWebInfo()
            {
                ID = GetHashStringSQL(V_GetDateTime.ToString(GF.FormatDateTime3)),
                UserID = p_UserID,
                IPAddress_User = GetUserIPAddress(),
                AppID = PB.AppID,
                Type = p_Type,
                Description = p_Description,
                Description1 = p_Description1,
                Description2 = p_Description2,
                Description3 = p_Description3,
                ExpiredDate = V_GetDateTime.AddSeconds(PB.ReportExpiresInSeconds)
            })
            {
                if (swi.InsertCustom1())
                    _retval = swi.ID;
            }
            return _retval;
        }
        public static bool F_CR_ExportToDisk(SqlConnection p_conn = null,
                                     SqlTransaction p_Trans = null,
                                     string p_FullPath = "",
                                     string p_FileNameType = "",
                                     string p_SP_Name = "",
                                     string p_RptFileName = "",
                                     SqlParameter[] p_SP_ListParam = null,
                                     string p_Rpt_ListParam = "",
                                     CREFileType p_CREFileType = CREFileType.PDF,
                                     string p_PaperSizeName = "",
                                     string p_PrinterName = "",
                                     string p_AppID = "")
        {
            bool _retval = false;

            using (ReportDocument rd = new ReportDocument())
            {
                //Begin Your .rpt file path will be below
                string _pathWebReports3 = PB.Path_WebReports3;
                if (p_AppID != "")
                {
                    _pathWebReports3 = _pathWebReports3.Replace("\\" + PB.AppID + "\\", "\\" + p_AppID + "\\");
                }
                rd.Load(_pathWebReports3 + p_RptFileName + ".rpt");
                //End Your .rpt file path will be below

                //begin set DataSource to the report . 
                using (var ocf = new WAL.BR.CF())
                {
                    rd.SetDataSource(ocf.EQP(
                        p_CommandText: p_SP_Name,
                        p_ListParam: p_SP_ListParam,
                        p_IsSP: true, p_conn: p_conn, p_Trans: p_Trans
                        ));
                }
                //End set DataSource to the report.

                //Begin Param filed report viewer.
                string[] V_SPV = WAL.GF.SplitStr(p_Rpt_ListParam, WAL.GF.Str2);
                for (int i = 0; i <= V_SPV.Count() - 1; i++)
                {
                    if (V_SPV[i] != "")
                    {
                        rd.SetParameterValue(V_SPV[i].Split('=')[0], V_SPV[i].Split('=')[1] + "");
                    }
                }
                //End Param filed report viewer.

                string V_FullPath_FileNameType = p_FullPath + "\\" + p_FileNameType;

                if (p_PaperSizeName != "")
                {
                    bool V_IsValidPaperSizeName = false;

                    try
                    {
                        if (p_PrinterName == "")
                        {
                            p_PrinterName = GF.DefaultPrinterName;
                            //p_PrinterName = "PDFill PDF&Image Writer";
                        }

                        DataView V_odv;
                        using (var ocf = new WAL.BR.CF())
                        {
                            V_odv = ocf.EQP(
                                p_CommandText: "SELECT x.* " +
                                               "FROM SysWebPrinterSettings x " +
                                               "WHERE x.IPAddress = @IPAddress " +
                                               "AND x.PrinterName = @PrinterName " +
                                               "AND x.PaperSizes = @PaperSizes ",
                                p_ListParam: new SqlParameter[] 
                                                 {
                                                     new SqlParameter("@IPAddress", HttpContext.Current.Request.Url.Host),
                                                     new SqlParameter("@PrinterName", p_PrinterName),
                                                     new SqlParameter("@PaperSizes", p_PaperSizeName)
                                                 },
                                p_IsSP: false, p_conn: p_conn, p_Trans: p_Trans
                                ).DefaultView;
                        }

                        //using (var ocf = new WAL.BR.CF())
                        //{
                        //    ocf.EQueryP("INSERT INTO abc ( testing ) " +
                        //                "SELECT @str ",
                        //                new SqlParameter[] 
                        //            {
                        //                new SqlParameter("@str", "1. Total PrinterSettings " + Convert.ToString(V_odv.Count))
                        //            });
                        //}

                        if (V_odv.Count > 0)
                        {
                            rd.PrintOptions.NoPrinter = false;
                            try
                            {
                                rd.PrintOptions.PaperSize = (CrystalDecisions.Shared.PaperSize)Convert.ToInt32(V_odv[0]["RawKind"]);
                            }
                            catch (Exception ex) { }
                            rd.PrintOptions.PrinterName = p_PrinterName;
                            V_IsValidPaperSizeName = true;

                            //using (var ocf = new WAL.BR.CF())
                            //{
                            //    ocf.EQueryP("INSERT INTO abc ( testing ) " +
                            //                "SELECT @str ",
                            //                new SqlParameter[] 
                            //        {
                            //            new SqlParameter("@str", "2. PrintOptions " + Convert.ToString((CrystalDecisions.Shared.PaperSize)Convert.ToInt32(V_odv[0]["RawKind"])) + " | " + p_PrinterName)
                            //        });
                            //}
                        }
                        else
                        {
                            System.Drawing.Printing.PrintDocument doctoprint = new System.Drawing.Printing.PrintDocument();
                            doctoprint.PrinterSettings.PrinterName = p_PrinterName;
                            foreach (System.Drawing.Printing.PaperSize oPaperSize in doctoprint.PrinterSettings.PaperSizes)
                            {
                                //strlog = strlog + "[" + Convert.ToString(oPaperSize.RawKind) + "] " + oPaperSize.PaperName + "<br/>";
                                if (oPaperSize.PaperName == p_PaperSizeName)
                                {
                                    rd.PrintOptions.NoPrinter = false;
                                    //rd.PrintOptions.PaperSize = (CrystalDecisions.Shared.PaperSize)oPaperSize.RawKind;
                                    try
                                    {
                                        rd.PrintOptions.PaperSize = (CrystalDecisions.Shared.PaperSize)oPaperSize.RawKind;
                                    }
                                    catch (Exception ex) { }
                                    rd.PrintOptions.PrinterName = p_PrinterName;
                                    V_IsValidPaperSizeName = true;

                                    using (var ocf = new WAL.BR.CF())
                                    {
                                        V_odv = ocf.EQP(
                                            p_CommandText: "INSERT INTO SysWebPrinterSettings " +
                                                           "( " +
                                                           "   IPAddress, PrinterName, RawKind, PaperSizes " +
                                                           ") " +
                                                           "SELECT @IPAddress, @PrinterName, @RawKind, @PaperSizes ",
                                            p_ListParam: new SqlParameter[] 
                                                             {
                                                                 new SqlParameter("@IPAddress", HttpContext.Current.Request.Url.Host),
                                                                 new SqlParameter("@PrinterName", p_PrinterName),
                                                                 new SqlParameter("@RawKind", oPaperSize.RawKind),
                                                                 new SqlParameter("@PaperSizes", p_PaperSizeName)
                                                             },
                                            p_IsSP: false, p_conn: p_conn, p_Trans: p_Trans
                                            ).DefaultView;
                                    }

                                    break;
                                }
                            }
                        }
                    }
                    catch (Exception ex) { }

                    if (V_IsValidPaperSizeName == false)
                    {
                        throw new Exception("PrinterName (" + p_PrinterName + ") or PaperSizeName (" + p_PaperSizeName + ") is not found.");
                    }
                }

                if (!Directory.Exists(p_FullPath))
                {
                    Directory.CreateDirectory(p_FullPath);
                }

                if (File.Exists(V_FullPath_FileNameType))
                {
                    // Hapus file yang sudah ada
                    try
                    {
                        File.Delete(V_FullPath_FileNameType);
                    }
                    catch (Exception) { }
                }

                switch (p_CREFileType)
                {
                    case CREFileType.PDF:
                        rd.ExportToDisk(ExportFormatType.PortableDocFormat, V_FullPath_FileNameType);
                        break;
                    case CREFileType.MSWord:
                        rd.ExportToDisk(ExportFormatType.WordForWindows, V_FullPath_FileNameType);
                        break;
                    case CREFileType.RTF:
                        rd.ExportToDisk(ExportFormatType.RichText, V_FullPath_FileNameType);
                        break;
                    case CREFileType.MSExcel:
                        rd.ExportToDisk(ExportFormatType.Excel, V_FullPath_FileNameType);
                        break;
                    case CREFileType.MSExcel_DataOnly:
                        rd.ExportToDisk(ExportFormatType.ExcelRecord, V_FullPath_FileNameType);
                        break;
                    case CREFileType.CSV:
                        rd.ExportToDisk(ExportFormatType.CharacterSeparatedValues, V_FullPath_FileNameType);
                        break;
                }

                _retval = File.Exists(V_FullPath_FileNameType);
            }

            return _retval;
        }
        public static string GetEmailBCC()
        {
            string EmailBCC = string.Empty;

            using (WAL.BR.CF cfoo = new WAL.BR.CF())
            {

                EmailBCC = cfoo.ExecuteSQL("select Description from syswebcommonvalue where CommonGroup = 'BCC' and APPID = 'PIP'").Rows[0]["Description"].ToString();
            }

            return EmailBCC;
        }



        public static object getData(DataTable dt)
        {
            List<Dictionary<string, object>> list =
                new List<Dictionary<string, object>>();

            foreach (DataRow row in dt.Rows)
            {
                Dictionary<string, object> dict =
                    new Dictionary<string, object>();

                foreach (DataColumn col in dt.Columns)
                {
                    if (col.ColumnName.ToUpper() != "LASTSYNC")
                        dict[col.ColumnName] = row[col];
                }
                list.Add(dict);
            }
            return new
            {
                data = list,
                serverTime = GF.DBSDatetime().ToString("yyyy-MM-ddTHH:mm:ss")
            };
        }

        public static DataTable JsonToDataTable(JArray arr)
        {
            DataTable dt = new DataTable();

            if (arr == null || arr.Count == 0)
                return dt;

            // Sediakan Unix Epoch di awal (Kompatibel C# 5.0 / VS 2013)
            DateTime epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);

            // BUILD COLUMNS
            foreach (JToken token in arr)
            {
                JObject obj = (JObject)token;

                foreach (var prop in obj.Properties())
                {
                    if (!dt.Columns.Contains(prop.Name))
                    {
                        dt.Columns.Add(prop.Name, typeof(string));
                    }
                }
            }

            // ROWS
            foreach (JToken token in arr)
            {
                JObject obj = (JObject)token;
                DataRow row = dt.NewRow();

                foreach (var prop in obj.Properties())
                {
                    if (prop.Value == null || prop.Value.Type == JTokenType.Null)
                    {
                        row[prop.Name] = "";
                    }
                    else
                    {
                        string valStr = prop.Value.ToString();

                        // Cek apakah string berisi format /Date(...)/
                        if (valStr.StartsWith("/Date(") && valStr.EndsWith(")/"))
                        {
                            string msString = Regex.Match(valStr, @"\d+").Value;
                            long ms = long.Parse(msString);
                            DateTime dateVal = epoch.AddMilliseconds(ms).ToLocalTime();
                            row[prop.Name] = dateVal.ToString("yyyy-MM-dd HH:mm:ss");
                        }
                        else
                        {
                            row[prop.Name] = valStr;
                        }
                    }
                }

                dt.Rows.Add(row);
            }

            return dt;
        }

        #region INSPEC SysWeb2 Authorization
        public const string CookieName = "INSPEC_AUTH";
        public static void SetCookie(string token)
        {
            HttpContext c = HttpContext.Current;
            if (c == null || c.Response == null) return;
            HttpCookie k = new HttpCookie(CookieName, token ?? "");
            k.HttpOnly = true; k.Secure = c.Request.IsSecureConnection;
            k.Path = "/";
            k.Expires = DateTime.Now.AddDays(2); c.Response.Cookies.Add(k);
        }
        public static void ClearCookie()
        {
            HttpContext c = HttpContext.Current;
            if (c == null || c.Response == null) return;
            HttpCookie k = new HttpCookie(CookieName, "");
            k.HttpOnly = true; k.Secure = c.Request.IsSecureConnection;
            k.Path = "/";
            k.Expires = DateTime.Now.AddDays(-1); c.Response.Cookies.Add(k);
        }
        public static string CurrentEmployeeID()
        {
            HttpContext c = HttpContext.Current;
            HttpCookie k = c == null ? null : c.Request.Cookies[CookieName];
            string token = k == null ? "" : Convert.ToString(k.Value).Trim();
            Guid parsedToken;
            if (String.IsNullOrEmpty(token) || !Guid.TryParse(token, out parsedToken))
                throw new HttpException(401, "Authentication is required.");
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQuery(@"SELECT TOP 1 U.employeeid FROM dbo.UserSession S
                    INNER JOIN dbo.SysWebUser U ON U.EmployeeID=S.UserID
                    WHERE S.Token=@Token AND S.IsActive=1 AND S.ExpireTime>GETDATE() AND U.IsActive=1",
                    "@Token=" + token);
                if (dt.Rows.Count != 1) throw new HttpException(401, "Login session is invalid or expired.");
                return Convert.ToString(dt.Rows[0]["employeeid"]).Trim();
            }
        }
        public static bool HasMenu(string employeeID, string menuID)
        {
            if (String.IsNullOrWhiteSpace(employeeID) || String.IsNullOrWhiteSpace(menuID)) return false;
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQuery(@"SELECT TOP 1 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') M WHERE M.MenuID=@MenuID",
                    "@EmployeeID=" + employeeID + GF.Str2 + "@MenuID=" + menuID);
                return dt.Rows.Count > 0;
            }
        }
        public static void RequireCompanyLocation(string employeeID, string companyID, string locationID)
        {
            if (String.IsNullOrWhiteSpace(employeeID) || String.IsNullOrWhiteSpace(companyID) || String.IsNullOrWhiteSpace(locationID))
                throw new HttpException(400, "Company and location are required.");
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQuery(@"SELECT TOP 1 1 FROM dbo.SysWebUser U
                    WHERE U.employeeid=@EmployeeID AND U.IsActive=1 AND (
                        EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C WHERE C.UserID=@EmployeeID AND C.AppID='pip' AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
                        OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', @EmployeeID, '') L WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID))",
                    "@EmployeeID=" + employeeID + GF.Str2 + "@CompanyID=" + companyID + GF.Str2 + "@LocationID=" + locationID);
                if (dt.Rows.Count == 0) throw new HttpException(403, "Company/location is not authorized for this account.");
            }
        }
        public static string GetEmployeeSection(string employeeID)
        {
            using (var br = new WAL.BR.CF())
            {
                // Section priority:
                // 1. administrator -> PENG/PHKP/PSEC
                // 2. INSPEC_User.SectionList
                // 3. SysWebUserProfit -> PIP_M_Section (or PENG/PHKP/PSEC for *ALL)
                // 4. M_HRD_Employee.SectionID
                DataTable dt = br.EQueryP(@"
DECLARE @SectionList VARCHAR(8000);
SET @SectionList='';

IF EXISTS (
    SELECT 1
    FROM dbo.SysWebUserUserGroup
    WHERE UserID=@EmployeeID
      AND UserGroupID='administrator'
)
BEGIN
    SELECT @SectionList=ISNULL(STUFF((
        SELECT ';'+S.SectionID
        FROM dbo.PIP_M_Section S
        WHERE S.ProfitCenterNo IN ('peng','phkp','psec')
        FOR XML PATH(''), TYPE).value('.','varchar(8000)'),1,1,''),'');
END;

IF ISNULL(@SectionList,'')=''
BEGIN
    SELECT TOP 1 @SectionList=ISNULL(I.SectionList,'')
    FROM dbo.INSPEC_User I
    WHERE I.UserID=@EmployeeID
      AND ISNULL(I.IsActive,0)=1;
END;

IF ISNULL(@SectionList,'')=''
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dbo.SysWebUserProfit P
        WHERE P.AppID='inspec'
          AND P.UserID=@EmployeeID
          AND P.ProfitCenterNo='*ALL'
    )
    BEGIN
        SELECT @SectionList=ISNULL(STUFF((
            SELECT ';'+S.SectionID
            FROM dbo.PIP_M_Section S
            WHERE S.ProfitCenterNo IN ('peng','phkp','psec')
            FOR XML PATH(''), TYPE).value('.','varchar(8000)'),1,1,''),'');
    END
    ELSE
    BEGIN
        SELECT @SectionList=ISNULL(STUFF((
            SELECT DISTINCT ';'+S.SectionID
            FROM dbo.SysWebUserProfit P
            INNER JOIN dbo.PIP_M_Section S ON S.ProfitCenterNo=P.ProfitCenterNo
            WHERE P.AppID='inspec'
              AND P.UserID=@EmployeeID
              AND ISNULL(P.ProfitCenterNo,'')<>''
            FOR XML PATH(''), TYPE).value('.','varchar(8000)'),1,1,''),'');
    END
END;

IF ISNULL(@SectionList,'')=''
BEGIN
    SELECT TOP 1 @SectionList=ISNULL(E.SectionID,'')
    FROM dbo.M_HRD_Employee E
    WHERE E.EmployeeID=@EmployeeID;
END;

SELECT ISNULL(@SectionList,'') Section;",
                new System.Data.SqlClient.SqlParameter[] {
                    new System.Data.SqlClient.SqlParameter("@EmployeeID", employeeID)
                });
                return dt.Rows.Count == 0 ? "" : Convert.ToString(dt.Rows[0]["Section"]);
            }
        }
        public static string RequireMenuEmployee(string menuID)
        {
            string id = CurrentEmployeeID();
            if (!HasMenu(id, menuID)) throw new HttpException(403, "You are not authorized to access this function.");
            return id;
        }
        public static string RequireAnyMenuEmployee(params string[] menuIDs)
        {
            string id = CurrentEmployeeID();

            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQueryP(@"
SELECT TOP 1 1
FROM dbo.SysWebUserUserGroup UG
INNER JOIN dbo.SysWebUserGroupMenu GM ON GM.UserGroupID=UG.UserGroupID
INNER JOIN dbo.SysWebMenu M ON M.MenuID=GM.MenuID
WHERE UG.UserID=@EmployeeID
  AND M.AppID='inspecfo'",
                    new System.Data.SqlClient.SqlParameter[] {
                        new System.Data.SqlClient.SqlParameter("@EmployeeID", id)
                    });

                if (dt.Rows.Count > 0) return id;
            }

            throw new HttpException(403, "You are not authorized to access this function.");
        }
        #endregion
        #endregion
    }
}



