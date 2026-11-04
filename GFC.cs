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

        #endregion
    }
}



