using OfficeOpenXml;
using OfficeOpenXml.Style;
using System;
using System.Data;
using System.Drawing;
using System.IO;
using System.Web;
using System.Web.Services;
using System.Web.UI;

namespace INSPEC.Secure
{
    public partial class R_Reports : Page
    {
        private const string ReportFolder = "~/App_Data/InspectionReports/";

        protected void Page_Load(object sender, EventArgs e)
        {
            if (!String.IsNullOrWhiteSpace(Request.QueryString["download"]))
            {
                DownloadGeneratedReport(Request.QueryString["download"]);
                return;
            }
        }

        [WebMethod(EnableSession = true)]
        public static object GenerateReport(long[] inspectionIds, string employeeId,
            string companyId, string locationId)
        {
            try
            {
                employeeId = GFC.RequireMenuEmployee("20022");
                DataTable data = inspection.GetAuthorizedInspectionSelection(inspectionIds, companyId, locationId);
                if (data == null || data.Rows.Count == 0)
                    throw new HttpException(400, "Tidak ada transaksi inspeksi yang dapat dibuatkan report.");

                string folder = HttpContext.Current.Server.MapPath(ReportFolder);
                if (!Directory.Exists(folder))
                    Directory.CreateDirectory(folder);

                CleanupOldReports(folder);

                string fileName = "Inspection_Report_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") +
                    "_" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".xlsx";
                string physicalPath = Path.Combine(folder, fileName);

                using (ExcelPackage package = new ExcelPackage())
                {
                    ExcelWorksheet sheet = package.Workbook.Worksheets.Add("Inspection Report");
                    sheet.Cells["A1"].Value = "INSPECTION REPORT";
                    sheet.Cells["A1"].Style.Font.Bold = true;
                    sheet.Cells["A1"].Style.Font.Size = 14;
                    DataTable export = data.DefaultView.ToTable(false,
                        "InspectionNo", "InspectionTypeCode", "InspectionTypeName",
                        "InspectionTypeDetailCode", "InspectionTypeDetailName",
                        "InspectionDate", "TemplateNo", "TemplateName",
                        "OwnerEmployeeID", "Status", "IsApprove");
                    sheet.Cells["A3"].LoadFromDataTable(export, true);
                    var header = sheet.Cells[3, 1, 3, export.Columns.Count];
                    header.Style.Font.Bold = true;
                    header.Style.Fill.PatternType = ExcelFillStyle.Solid;
                    header.Style.Fill.BackgroundColor.SetColor(Color.LightSteelBlue);
                    header.Style.WrapText = true;
                    sheet.View.FreezePanes(4, 1);
                    sheet.Cells[sheet.Dimension.Address].AutoFitColumns();
                    package.SaveAs(new FileInfo(physicalPath));
                }

                string token = Guid.NewGuid().ToString("N");
                HttpContext.Current.Session["InspectionReportFile_" + token] = physicalPath;
                HttpContext.Current.Session["InspectionReportName_" + token] = fileName;

                string filePath = VirtualPathUtility.ToAbsolute("~/Secure/R_Reports.aspx?download=" + token);
                return new {
                    success = true,
                    status = "SUCCESS",
                    fileName = fileName,
                    filePath = filePath,
                    storagePath = ReportFolder + fileName,
                    message = "Report berhasil dibuat."
                };
            }
            catch (Exception ex)
            {
                return new {
                    success = false,
                    status = "FAILED",
                    fileName = "",
                    filePath = "",
                    storagePath = "",
                    message = ex.Message
                };
            }
        }

        private void DownloadGeneratedReport(string token)
        {
            GFC.RequireMenuEmployee("20022");
            if (String.IsNullOrWhiteSpace(token) || token.Length != 32)
                throw new HttpException(400, "Token download report tidak valid.");

            string fileKey = "InspectionReportFile_" + token;
            string nameKey = "InspectionReportName_" + token;
            string physicalPath = Convert.ToString(Session[fileKey]);
            string fileName = Convert.ToString(Session[nameKey]);
            if (String.IsNullOrWhiteSpace(physicalPath) || String.IsNullOrWhiteSpace(fileName) ||
                !File.Exists(physicalPath))
                throw new HttpException(404, "File report tidak ditemukan atau sesi download sudah berakhir.");

            Session.Remove(fileKey);
            Session.Remove(nameKey);
            byte[] file = File.ReadAllBytes(physicalPath);

            Response.Clear();
            Response.Buffer = true;
            Response.ContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
            Response.AddHeader("Content-Disposition", "attachment; filename=" + fileName);
            Response.BinaryWrite(file);
            Response.Flush();
            try { File.Delete(physicalPath); }
            catch { }
            Response.SuppressContent = true;
            HttpContext.Current.ApplicationInstance.CompleteRequest();
        }

        private static void CleanupOldReports(string folder)
        {
            try
            {
                foreach (string file in Directory.GetFiles(folder, "Inspection_Report_*.xlsx"))
                {
                    try
                    {
                        if (File.GetLastWriteTimeUtc(file) < DateTime.UtcNow.AddHours(-24))
                            File.Delete(file);
                    }
                    catch { }
                }
            }
            catch { }
        }
    }
}
