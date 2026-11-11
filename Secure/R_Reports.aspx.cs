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
                // Selalu gunakan NIK dari session login, bukan nilai employeeId dari browser.
                employeeId = GFC.RequireMenuEmployee("20022");

                // Validasi otorisasi, scope company/location, jumlah transaksi,
                // serta satu InspectionType dilakukan ulang di server.
                DataTable authorized = inspection.GetAuthorizedInspectionSelection(
                    inspectionIds, companyId, locationId);

                if (authorized == null || authorized.Rows.Count == 0)
                    throw new HttpException(400, "Tidak ada transaksi inspeksi yang dapat dibuatkan report.");

                // Gunakan InspectionID sebagai key transaksi yang unik lintas company.
                // DataTable yang dikirim ke generator hanya memiliki satu kolom dan
                // satu row untuk setiap transaksi yang dipilih.
                DataTable inspectionIdsTable = new DataTable();
                inspectionIdsTable.Columns.Add("InspectionID", typeof(long));

                foreach (DataRow row in authorized.Rows)
                {
                    inspectionIdsTable.Rows.Add(Convert.ToInt64(row["InspectionID"]));
                }

                INSPEC.Secure.ReportFileResult generated =
                    INSPEC.Secure.R_Report.GenerateInspectionXlsx(inspectionIdsTable, employeeId);

                if (generated == null || !generated.Success ||
                    String.IsNullOrWhiteSpace(generated.StoragePath) ||
                    !File.Exists(generated.StoragePath))
                {
                    throw new InvalidOperationException(
                        generated != null && !String.IsNullOrWhiteSpace(generated.Message)
                            ? generated.Message
                            : "Gagal membuat file Excel preview.");
                }

                string token = Guid.NewGuid().ToString("N");
                HttpContext.Current.Session["InspectionReportFile_" + token] = generated.StoragePath;
                HttpContext.Current.Session["InspectionReportName_" + token] = generated.FileName;

                string filePath = VirtualPathUtility.ToAbsolute(
                    "~/Secure/R_Reports.aspx?download=" + token);

                return new
                {
                    success = true,
                    status = "SUCCESS",
                    fileName = generated.FileName,
                    filePath = filePath,
                    storagePath = generated.StoragePath,
                    message = generated.Message
                };
            }
            catch (Exception ex)
            {
                return new
                {
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
