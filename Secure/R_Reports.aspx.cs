using OfficeOpenXml;
using OfficeOpenXml.Style;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    using Rpt = INSPEC.BRC.Report;
    using ReportData = INSPEC.BRC.Report.ReportData;
    public partial class R_Report : WAL.PB, WAL.I_ToolBar_2
    {
        private const string _MenuID = "12011";
        protected void Page_Load(object sender, EventArgs e)
        {
            if (!IsPostBack)
            {
                using (WAL.BR.SysWebMenu sw = new WAL.BR.SysWebMenu())
                {
                    sw.AppID = PB.AppID;
                    sw.MenuID = _MenuID;
                    if (sw.SelectOneByMenuID().Rows.Count > 0)
                    {
                        Master.Mn_lit_Title = WAL.PB.AppID + " -> " + sw.Description;
                    }
                }
                InitToolbar();
                PreapareScreen();
            }

        }

        private void PreapareScreen()
        {
            F_Close_pnl_Search();
            UpdateViewGridReport();
        }

        private static void _CreateXLSXFile(ReportData report, FileInfo newFile)
        {
            if (newFile == null) throw new ArgumentNullException("newFile");

            using (ExcelPackage pck = new ExcelPackage(newFile))
            {
                foreach (var group in report.Groups)
                {
                    string sheetName = NewSheetName(group.DetailName);
                    ExcelWorksheet ws = pck.Workbook.Worksheets.Add(sheetName);
                    List<DataRow> headers = group.Headers.OrderBy(h => BRC.Report.DateKey(h))
                                            .ThenBy(h => BRC.Report.TimeOf(h))
                                            .ThenBy(h => BRC.Report.GetValue(h, "InspectionNo")).ToList();
                    var items = group.Items;  // ItemDef tetap di Report.cs
                    var units = group.Units;  // SELURUH unit master (termasuk yang kosong)
                    string layout = group.Layout;
                    int lastCol = layout == "H" ? items.Count + 6 : units.Count + 1;
                    int lastRow;

                    if ((layout != "H" && layout != "V") || lastCol > 16384 || lastCol < 2)
                        throw new InvalidOperationException("Layout atau jumlah kolom tidak valid.");

                    ws.Cells[1, 1, 1, lastCol].Merge = true;
                    Put(ws.Cells[1, 1], group.Title);
                    ws.Cells[1, 1, 1, lastCol].Style.Font.Bold = true;
                    ws.Cells[1, 1, 1, lastCol].Style.Font.UnderLine = true;
                    ws.Cells[1, 1, 1, lastCol].Style.Font.Size = 18;
                    ws.Cells[1, 1, 1, lastCol].Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
                    ws.Row(1).Height = 32;

                    ws.Cells[2, 1, 2, lastCol].Merge = true;
                    var dates = headers.Select(h => BRC.Report.DateOf(h)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
                    string periodLabel = dates.Count == 1 ? dates[0] : "MULTI DATE";
                    Put(ws.Cells[2, 1], "PERIODE " + periodLabel + "  |  " + group.GroupLabel);
                    ws.Cells[2, 1, 2, lastCol].Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
                    ws.Cells[2, 1, 2, lastCol].Style.Font.Size = 12;

                    int headerRow = 4;
                    int firstRow = 5;
                    int currentRow = firstRow;

                    if (layout == "H")
                    {
                        string[] fixedHeaders = { "DATE", "TIME", "FLOOR / UNIT" };
                        for (int i = 0; i < fixedHeaders.Length; i++)
                            Put(ws.Cells[headerRow, i + 1], fixedHeaders[i]);
                        for (int i = 0; i < items.Count; i++)
                            Put(ws.Cells[headerRow, i + 4], items[i].Label);
                        Put(ws.Cells[headerRow, items.Count + 4], "KETERANGAN");
                        Put(ws.Cells[headerRow, items.Count + 5], "INSPECTED BY");
                        Put(ws.Cells[headerRow, items.Count + 6], "APPROVED BY");

                        foreach (var unit in units)
                        {
                            List<DataRow> unitHeaders = headers.Where(h => String.Equals(BRC.Report.GetValue(h, "InspectionTypeDetailCode").Trim(),
                                                                           unit.Code, StringComparison.OrdinalIgnoreCase)).ToList();

                            if (unitHeaders.Count == 0)
                            {
                                Put(ws.Cells[currentRow, 3], unit.Name);
                                currentRow++;
                                continue;
                            }

                            foreach (DataRow h in unitHeaders)
                            {
                                Put(ws.Cells[currentRow, 1], BRC.Report.DateOf(h));
                                Put(ws.Cells[currentRow, 2], BRC.Report.TimeOf(h));
                                Put(ws.Cells[currentRow, 3], unit.Name);
                                var values = BRC.Report.ValuesFor(h, report.ResultLookup);
                                for (int i = 0; i < items.Count; i++)
                                {
                                    DataRow result;
                                    if (values.TryGetValue(items[i].Id, out result))
                                        Put(ws.Cells[currentRow, i + 4], CheckValue(BRC.Report.GetValue(result, "Value")));
                                }
                                Put(ws.Cells[currentRow, items.Count + 4], BRC.Report.Notes(h, report.ResultLookup));
                                Put(ws.Cells[currentRow, items.Count + 5], BRC.Report.GetValue(h, "InspectedByName"));
                                Put(ws.Cells[currentRow, items.Count + 6], BRC.Report.GetValue(h, "ApprovedBy"));
                                currentRow++;
                            }
                        }
                        lastRow = currentRow - 1;
                    }
                    else
                    {
                        // VERTICAL: ItemLabel menjadi baris; SEMUA unit MASTER
                        // menjadi kolom (tidak tergantung jumlah InspectionNo).
                        Put(ws.Cells[headerRow, 1], "INSPECTED ITEM");
                        var rowsByUnit = units.Select(unit => headers.Where(h => String.Equals(BRC.Report.GetValue(h, "InspectionTypeDetailCode").Trim(),
                                                                                 unit.Code, StringComparison.OrdinalIgnoreCase)).ToList()).ToList();
                        var valuesByUnit = rowsByUnit.Select(groupHeaders => groupHeaders.Select(h => BRC.Report.ValuesFor(h, report.ResultLookup)).ToList()).ToList();

                        for (int j = 0; j < units.Count; j++)
                            Put(ws.Cells[headerRow, j + 2], units[j].Name);

                        foreach (var item in items)
                        {
                            Put(ws.Cells[currentRow, 1], item.Label);
                            for (int j = 0; j < units.Count; j++)
                            {
                                List<string> matches = new List<string>();
                                for (int k = 0; k < rowsByUnit[j].Count; k++)
                                {
                                    DataRow result;
                                    if (!valuesByUnit[j][k].TryGetValue(item.Id, out result))
                                        continue;
                                    string value = CheckValue(BRC.Report.GetValue(result, "Value"));
                                    if (String.IsNullOrWhiteSpace(value)) continue;

                                    matches.Add(value);
                                }
                                if (matches.Count == 1)
                                    Put(ws.Cells[currentRow, j + 2], matches[0]);
                                else if (matches.Count > 1)
                                {
                                    List<string> valueLines = new List<string>();
                                    for (int k = 0; k < rowsByUnit[j].Count; k++)
                                    {
                                        DataRow r;
                                        if (!valuesByUnit[j][k].TryGetValue(item.Id, out r)) continue;
                                        string val = CheckValue(BRC.Report.GetValue(r, "Value"));
                                        if (String.IsNullOrWhiteSpace(val)) continue;
                                        DataRow h = rowsByUnit[j][k];
                                        valueLines.Add(BRC.Report.DateOf(h) + " " + BRC.Report.TimeOf(h) + " [" + BRC.Report.GetValue(h, "InspectionNo") + "]: " + val);
                                    }
                                    Put(ws.Cells[currentRow, j + 2], String.Join("\n", valueLines.ToArray()));
                                    ws.Row(currentRow).Height = Math.Min(90, Math.Max(24, valueLines.Count * 15));
                                }
                            }
                            currentRow++;
                        }

                        Put(ws.Cells[currentRow, 1], "KETERANGAN / FOLLOW UP");
                        ws.Cells[currentRow, 1].Style.Font.Bold = true;
                        ws.Cells[currentRow, 1].Style.WrapText = true;

                        int maxNoteLines = 1;
                        for (int j = 0; j < units.Count; j++)
                        {
                            List<string> notes = new List<string>();
                            foreach (DataRow h in rowsByUnit[j])
                            {
                                string note = BRC.Report.Notes(h, report.ResultLookup);
                                if (String.IsNullOrWhiteSpace(note)) continue;

                                if (rowsByUnit[j].Count > 1)
                                    note = BRC.Report.GetValue(h, "InspectionNo") + ": " + note;

                                notes.Add(note);
                            }

                            if (notes.Count == 0) continue;

                            Put(ws.Cells[currentRow, j + 2], String.Join("\n", notes.ToArray()));
                            ws.Cells[currentRow, j + 2].Style.WrapText = true;
                            maxNoteLines = Math.Max(maxNoteLines, notes.Count);
                        }

                        ws.Row(currentRow).Height = Math.Min(120, Math.Max(32, maxNoteLines * 20));
                        lastRow = currentRow; // Masukkan baris keterangan ke border dan print area.
                    }

                    // Format tabel sederhana seperti Closing Report kantor.
                    ExcelRange table = ws.Cells[headerRow, 1, Math.Max(headerRow, lastRow), lastCol];
                    table.Style.Border.Top.Style = ExcelBorderStyle.Thin;
                    table.Style.Border.Bottom.Style = ExcelBorderStyle.Thin;
                    table.Style.Border.Left.Style = ExcelBorderStyle.Thin;
                    table.Style.Border.Right.Style = ExcelBorderStyle.Thin;
                    table.Style.WrapText = true;
                    table.Style.VerticalAlignment = ExcelVerticalAlignment.Center;
                    ws.Cells[headerRow, 1, headerRow, lastCol].Style.Font.Bold = true;
                    ws.Cells[headerRow, 1, headerRow, lastCol].Style.Fill.PatternType = ExcelFillStyle.Solid;
                    ws.Cells[headerRow, 1, headerRow, lastCol].Style.Fill.BackgroundColor.SetColor(Color.FromArgb(232, 238, 242));
                    ws.Cells[headerRow, 1, headerRow, lastCol].Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
                    ws.Row(headerRow).Height = layout == "H" ? 55 : 40;
                    ws.View.FreezePanes(firstRow, layout == "H" ? 4 : 2);

                    ConfigurePageSetup(ws);
                    ws.PrinterSettings.PrintArea = ws.Cells[1, 1, Math.Max(lastRow, currentRow), lastCol];
                }
                pck.Save();
            }
        }

        public static ReportFileResult GenerateInspectionXlsx(DataTable selectedInspections, string userId)
        {
            try
            {
                if (selectedInspections == null)
                    throw new ArgumentNullException("selectedInspections");
                if (String.IsNullOrWhiteSpace(userId))
                    throw new ArgumentException("UserID folder export wajib diisi.", "userId");

                if (!selectedInspections.Columns.Contains("InspectionID"))
                    throw new ArgumentException("DataTable harus memiliki kolom InspectionID.");

                if (selectedInspections.Rows.Count == 0 || selectedInspections.Rows.Count > 500)
                    throw new InvalidOperationException("Pilih 1 sampai 500 baris inspeksi.");

                List<string> inspectionIds = new List<string>();
                HashSet<long> knownIds = new HashSet<long>();

                for (int i = 0; i < selectedInspections.Rows.Count; i++)
                {
                    DataRow row = selectedInspections.Rows[i];
                    if (row.RowState == DataRowState.Deleted) continue;

                    string rawId = Convert.ToString(row["InspectionID"], CultureInfo.InvariantCulture).Trim();
                    long id;
                    if (!Int64.TryParse(rawId, NumberStyles.None, CultureInfo.InvariantCulture, out id) || id <= 0)
                        throw new ArgumentException("InspectionID tidak valid pada baris " + (i + 1) + ".");

                    if (knownIds.Add(id))
                        inspectionIds.Add(id.ToString(CultureInfo.InvariantCulture));
                }

                if (inspectionIds.Count == 0)
                    throw new InvalidOperationException("Tidak ada InspectionID aktif yang dipilih.");

                Rpt.InspectionScope scope = Rpt.GetInspectionScope(inspectionIds);
                string companyId = scope.CompanyID;
                string locationId = scope.LocationID;

                ValidateDataTableScope(companyId, locationId);
                return GenerateInspectionXlsxCore(inspectionIds, companyId, locationId, userId);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("GenerateInspectionXlsx(DataTable, userId): " + ex);
                bool isDebug = HttpContext.Current != null && HttpContext.Current.IsDebuggingEnabled;
                string friendly = ex is ArgumentException || ex is InvalidOperationException ||
                                  ex is UnauthorizedAccessException ? ex.Message : "Gagal memproses DataTable inspeksi. Periksa log server.";
                return new ReportFileResult
                {
                    Success = false,
                    Status = "FAILED",
                    FileName = String.Empty,
                    StoragePath = String.Empty,
                    Message = isDebug ? ex.GetBaseException().Message : friendly
                };
            }
        }

        private static void ValidateDataTableScope(string companyId, string locationId)
        {
            HttpContext context = HttpContext.Current;
            if (context == null)
                throw new UnauthorizedAccessException("Tidak ada konteks ASP.NET.");

            Page page = context.Handler as Page;
            MasterPage master = page == null ? null : page.Master;
            string masterCompany = TryGetMasterLoginValue(master, "Mn_CompanyID");
            string masterLocation = TryGetMasterLoginValue(master, "Mn_LocationID");

            if (String.IsNullOrWhiteSpace(masterCompany) || String.IsNullOrWhiteSpace(masterLocation))
                throw new UnauthorizedAccessException(
                    "MasterPage pemanggil tidak menyediakan scope CompanyID/LocationID. " +
                    "Hubungkan ke otorisasi supervisor pada server sebelum mencetak.");

            if (!String.Equals(masterCompany, companyId, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(masterLocation, locationId, StringComparison.OrdinalIgnoreCase))
                throw new UnauthorizedAccessException("CompanyID/LocationID transaksi tidak sesuai scope login.");
        }

        private static string TryGetMasterLoginValue(MasterPage master, string memberName)
        {
            for (MasterPage current = master; current != null; current = current.Master)
            {
                Type type = current.GetType();
                PropertyInfo property = type.GetProperty(memberName, BindingFlags.Instance | BindingFlags.Public);
                if (property != null && property.GetIndexParameters().Length == 0)
                    return (Convert.ToString(property.GetValue(current, null)) ?? "").Trim();
                FieldInfo field = type.GetField(memberName, BindingFlags.Instance | BindingFlags.Public);
                if (field != null)
                    return (Convert.ToString(field.GetValue(current)) ?? "").Trim();
            }
            return String.Empty;
        }

        public static ReportFileResult GenerateInspectionXlsx(IEnumerable<string> inspectionIds)
        {
            try
            {
                if (inspectionIds == null)
                    throw new ArgumentNullException("inspectionIds");

                List<string> selected = Rpt.NormalizeInspectionIds(inspectionIds).Select(id => id.ToString(CultureInfo.InvariantCulture)).ToList();

                if (selected.Count == 0 || selected.Count > 500)
                    throw new InvalidOperationException("Pilih 1 sampai 500 InspectionID.");

                HttpContext context = HttpContext.Current;
                Page currentPage = context == null ? null : context.Handler as Page;
                if (currentPage == null || currentPage.Master == null)
                    throw new UnauthorizedAccessException("Laporan harus dibuat dari halaman login ASP.NET dengan MasterPage.");

                string loginCompany = GetMasterLoginValue(currentPage.Master, "Mn_CompanyID");
                string loginLocation = GetMasterLoginValue(currentPage.Master, "Mn_LocationID");
                string loginUser = GetMasterLoginValue(currentPage.Master, "Mn_UserID");

                if (String.IsNullOrWhiteSpace(loginCompany) || String.IsNullOrWhiteSpace(loginLocation) || String.IsNullOrWhiteSpace(loginUser))
                    throw new UnauthorizedAccessException("Konteks login tidak tersedia.");

                Rpt.InspectionScope scope = Rpt.GetInspectionScope(selected);

                // Data transaksi tidak otomatis berarti boleh diakses.
                if (!String.Equals(scope.CompanyID, loginCompany, StringComparison.OrdinalIgnoreCase) || 
                    !String.Equals(scope.LocationID, loginLocation, StringComparison.OrdinalIgnoreCase))
                    throw new UnauthorizedAccessException("InspectionID tidak sesuai company/location login.");

                return GenerateInspectionXlsxCore(selected, scope.CompanyID, scope.LocationID, loginUser);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("GenerateInspectionXlsx scope validation: " + ex);
                bool isDebug = HttpContext.Current != null && HttpContext.Current.IsDebuggingEnabled;
                string friendly = ex is ArgumentException || ex is InvalidOperationException || ex is UnauthorizedAccessException
                                  ? ex.Message : "Gagal memvalidasi inspeksi. Periksa log server.";
                return new ReportFileResult
                {
                    Success = false,
                    Status = "FAILED",
                    FileName = String.Empty,
                    StoragePath = String.Empty,
                    Message = isDebug ? ex.GetBaseException().Message : friendly
                };
            }
        }

        private static string GetMasterLoginValue(MasterPage master, string memberName)
        {
            for (MasterPage current = master; current != null; current = current.Master)
            {
                Type type = current.GetType();
                PropertyInfo property = type.GetProperty(memberName, BindingFlags.Instance | BindingFlags.Public);
                if (property != null && property.GetIndexParameters().Length == 0)
                    return (Convert.ToString(property.GetValue(current, null)) ?? String.Empty).Trim();

                FieldInfo field = type.GetField(memberName, BindingFlags.Instance | BindingFlags.Public);
                if (field != null)
                    return (Convert.ToString(field.GetValue(current)) ?? String.Empty).Trim();
            }

            throw new UnauthorizedAccessException("MasterPage tidak menyediakan data login: " + memberName);
        }

        private static ReportFileResult GenerateInspectionXlsxCore(IEnumerable<string> inspectionIds, string companyId, string locationId, string userId)
        {
            string storagePath = null;
            string exportFolder = null;
            string stage = "VALIDASI INPUT";
            try
            {
                if (inspectionIds == null)
                    throw new ArgumentNullException("inspectionIds");
                if (String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                    throw new ArgumentException("CompanyID/LocationID login tidak boleh kosong.");
                if (String.IsNullOrWhiteSpace(userId))
                    throw new ArgumentException("UserID untuk nama folder export wajib diisi.");

                List<string> selected = Rpt.NormalizeInspectionIds(inspectionIds).Select(id => id.ToString(CultureInfo.InvariantCulture)).ToList();

                if (selected.Count == 0)
                    throw new InvalidOperationException("Pilih minimal satu InspectionID.");
                if (selected.Count > 500)
                    throw new InvalidOperationException("Maksimal 500 InspectionID per export.");

                stage = "BACA DATABASE / REPORT.CS";
                ReportData report = Rpt.Prepare(selected, companyId, locationId);
                if (report == null || report.Groups == null || report.Groups.Count == 0)
                    throw new InvalidOperationException("Tidak ada worksheet yang dapat dibuat.");

                stage = "BUAT NAMA DAN FOLDER";
                string V_FileType = "xlsx";
                string V_Path_FolerView = GF.Path_FolerView();
                string V_FileName = Path.GetFileNameWithoutExtension(SafeExcelFileName(report.Title));
                string V_FileNameType = V_FileName + "_" + GF.DBSDatetime().ToString(GF.FormatDateTime2) + "." + V_FileType;

                if (String.IsNullOrWhiteSpace(V_Path_FolerView))
                    throw new InvalidOperationException("GF.Path_FolerView() belum dikonfigurasi.");
                if (!Directory.Exists(V_Path_FolerView))
                    Directory.CreateDirectory(V_Path_FolerView);

                string folderName = SafeFolderSegment(userId);
                exportFolder = Path.Combine(V_Path_FolerView, folderName);
                Directory.CreateDirectory(exportFolder);
                storagePath = Path.Combine(exportFolder, V_FileNameType);

                // UserID dan waktu di nama subfolder agar nama file Excel
                // tidak perlu diberi prefix/suffix dan tetap sama dengan judul.
                // GUID di sini hanya menghindari bentrok antar-request, BUKAN token login.
                //string folderName = "[" + SafeFolderSegment(userId) + "]" +
                //    SafeFolderSegment(GF.DBSDatetime().ToString(GF.FormatDateTime2)) +
                //    "_" + Guid.NewGuid().ToString("N").Substring(0, 8);
                //exportFolder = Path.Combine(V_Path_FolerView, folderName);
                //Directory.CreateDirectory(exportFolder);
                //storagePath = Path.Combine(exportFolder, V_FileNameType);

                stage = "GENERATE XLSX / EPPLUS";
                _CreateXLSXFile(report, new FileInfo(storagePath));

                stage = "UJI FILE HASIL SAVE";
                FileInfo created = new FileInfo(storagePath);
                if (!created.Exists || created.Length == 0)
                    throw new IOException("File Excel tidak tersimpan atau kosong.");

                int actualSheets = 0;
                using (ExcelPackage check = new ExcelPackage(new FileInfo(storagePath)))
                {
                    foreach (ExcelWorksheet sheet in check.Workbook.Worksheets)
                    {
                        actualSheets++;
                        if (sheet.Dimension == null)
                            throw new InvalidOperationException("Worksheet '" + sheet.Name + "' kosong.");
                        if (!String.Equals(sheet.Cells[1, 1].Text.Trim(), report.Title.Trim(), StringComparison.Ordinal))
                            throw new InvalidOperationException("Judul worksheet '" + sheet.Name + "' tidak cocok dengan TemplateName.");
                    }
                }
                if (actualSheets != report.Groups.Count)
                    throw new InvalidOperationException("Jumlah worksheet hasil save tidak cocok dengan GroupingBy.");

                System.Diagnostics.Trace.TraceInformation("InspectionReport SUCCESS; InspectionCount={0}; Sheets={1}; Bytes={2}",
                                                           selected.Count, actualSheets, created.Length);

                return new ReportFileResult
                {
                    Success = true,
                    Status = "SUCCESS",
                    FileName = V_FileNameType,
                    StoragePath = storagePath,
                    Message = "Excel berhasil dibuat dan lolos pemeriksaan EPPlus."
                };
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("GenerateInspectionXlsx FAILED at " + stage + ": " + ex.ToString());
                if (!String.IsNullOrWhiteSpace(storagePath))
                {
                    try { if (File.Exists(storagePath)) File.Delete(storagePath); }
                    catch (Exception cleanupEx)
                    { System.Diagnostics.Trace.TraceWarning(cleanupEx.ToString()); }
                }
                if (!String.IsNullOrWhiteSpace(exportFolder))
                {
                    try
                    {
                        if (Directory.Exists(exportFolder) && Directory.GetFileSystemEntries(exportFolder).Length == 0)
                            Directory.Delete(exportFolder);
                    }
                    catch (Exception cleanupEx)
                    { System.Diagnostics.Trace.TraceWarning(cleanupEx.ToString()); }
                }
                bool isDebug = HttpContext.Current != null && HttpContext.Current.IsDebuggingEnabled;
                string friendly = ex is ArgumentException || ex is InvalidOperationException ||
                                  ex is UnauthorizedAccessException ? ex.Message : "Gagal membuat Excel. Periksa log server.";

                return new ReportFileResult
                {
                    Success = false,
                    Status = "FAILED",
                    FileName = String.Empty,
                    StoragePath = String.Empty,
                    Message = isDebug ? "[DEBUG " + stage + "] " + ex.GetBaseException().Message : friendly
                };
            }
        }

        private static string SafeFolderSegment(string value)
        {
            string clean = Regex.Replace((value ?? "").Trim(), @"[\\/:*?""<>|\x00-\x1F]", "_").Trim().Trim('.');
            if (clean.Length == 0) clean = "USER";
            return clean.Substring(0, Math.Min(40, clean.Length));
        }

        public static string GetInspectionFileUrl(ReportFileResult result)
        {
            if (result == null || !result.Success || String.IsNullOrWhiteSpace(result.StoragePath))
                throw new ArgumentException("Hasil generate Excel tidak valid.");

            string rootPath = Path.GetFullPath(GF.Path_FolerView()).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string physicalPath = Path.GetFullPath(result.StoragePath);
            if (!physicalPath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase) || !File.Exists(physicalPath))
                throw new InvalidOperationException("File Excel tidak ditemukan dalam folder laporan.");

            string relativePath = physicalPath.Substring(rootPath.Length);
            string[] parts = relativePath.Split(new char[] {
                                                    Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar
                                                }, StringSplitOptions.RemoveEmptyEntries);
            string baseUrl = GF.Url_FolerView();
            if (String.IsNullOrWhiteSpace(baseUrl))
                throw new InvalidOperationException("GF.Url_FolerView() belum dikonfigurasi.");
            baseUrl = baseUrl.TrimEnd('/');
            if (baseUrl.StartsWith("~/", StringComparison.Ordinal)) baseUrl = VirtualPathUtility.ToAbsolute(baseUrl);
            else if (!baseUrl.StartsWith("/", StringComparison.Ordinal) && !Uri.IsWellFormedUriString(baseUrl, UriKind.Absolute))
                baseUrl = VirtualPathUtility.ToAbsolute("~/" + baseUrl.TrimStart('/'));

            return baseUrl + "/" + String.Join("/", parts.Select(HttpUtility.UrlPathEncode).ToArray());
        }

        private static void ConfigurePageSetup(ExcelWorksheet ws)
        {
            ws.Cells.AutoFitColumns();
            // Hindari kolom raksasa akibat ItemLabel/Remark panjang.
            for (int i = 1; i <= ws.Dimension.End.Column; i++)
                if (ws.Column(i).Width > 42) ws.Column(i).Width = 42;
            ws.PrinterSettings.FitToPage = false;
            ws.PrinterSettings.Scale = 63;
            ws.PrinterSettings.TopMargin = 0.15M;
            ws.PrinterSettings.LeftMargin = 0.15M;
            ws.PrinterSettings.RightMargin = 0.15M;
            ws.PrinterSettings.BottomMargin = 0.15M;
            ws.PrinterSettings.Orientation = eOrientation.Landscape;
            ws.PrinterSettings.PaperSize = ePaperSize.A3;
        }

        private static string NewSheetName(string name)
        {
            string clean = Regex.Replace((name ?? "").Trim(), @"[\\/:*?\[\]\x00-\x1F]", " ").Trim('\'');

            if (String.IsNullOrWhiteSpace(clean)) clean = "Inspection";

            // Batas nama worksheet Excel maksimal 31 karakter.
            return clean.Substring(0, Math.Min(31, clean.Length)).TrimEnd(' ', '\'');
        }
        
        private static string SafeExcelFileName(string title)
        {
            string name = Regex.Replace((title ?? "").Trim(), @"[\\/:*?""<>|\x00-\x1F]", " ").Trim().TrimEnd('.');
            if (name.Length > 120) name = name.Substring(0, 120).Trim().TrimEnd('.');
            if (String.IsNullOrWhiteSpace(name))
                throw new InvalidOperationException("TemplateName tidak valid untuk nama file Excel.");
            string upper = name.ToUpperInvariant();
            string deviceName = upper.Split('.')[0];
            if (deviceName == "CON" || deviceName == "PRN" || deviceName == "AUX" ||
                deviceName == "NUL" || Regex.IsMatch(deviceName, @"^(COM|LPT)[1-9]$"))
                name = "Report_" + name;
            return name + ".xlsx";
        }

        private static void Put(ExcelRange cell, string text)
        {
            text = text ?? "";
            //Mencegah Excel Injection
            if (text.Length > 0 && "=+-@".IndexOf(text[0]) >= 0) text = "'" + text;
            //Length Excelnya
            if (text.Length > 32000) text = text.Substring(0, 32000);
            cell.Style.Numberformat.Format = "@";
            cell.Value = text;
        }

        private static string CheckValue(string text)
        {
            if (String.Equals(text, "V", StringComparison.OrdinalIgnoreCase)) return "✓";
            if (String.Equals(text, "X", StringComparison.OrdinalIgnoreCase)) return "X";
            return text ?? "";
        }

        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            switch (e.ToolbarItem)
            {
                case ToolbarItem_2.Refresh:
                    //PrepareScreen();
                    break;
                case ToolbarItem_2.Print:
                    _printReport();
                    break;
            }
        }

        private void InitToolbar()
        {
            Master.TB_VisibleToolbar(true);
            Master.TB_VisibleButton(ToolbarItem_2.Refresh, true);
            Master.TB_VisibleButton(ToolbarItem_2.Print, true);
        }

        // DEBUG LOKAL: tombol Print pada halaman MasterPage B memanggil
        // method publik yang SAMA dengan Preview milik rekan (MasterPage A).
        private void _printReport()
        {
            lblError.Text = String.Empty;
            try
            {
                DataTable selectedInspections = new DataTable();
                selectedInspections.Columns.Add("InspectionID", typeof(long));
                foreach (DataGridItem item in gridAppReport.Items)
                {
                    CheckBox chk = item.FindControl("_chkboxupdateGridH") as CheckBox;
                    Label lbl = item.FindControl("_lblInspectionID") as Label;
                    if (chk == null || lbl == null)
                        throw new InvalidOperationException("Checkbox/InspectionID tidak ditemukan pada DataGrid.");
                    if (chk.Checked && !String.IsNullOrWhiteSpace(lbl.Text))
                        selectedInspections.Rows.Add(Int64.Parse(lbl.Text.Trim(), CultureInfo.InvariantCulture));
                }

                // Uji overload DataTable yang sama dengan halaman teman.
                ReportFileResult result = GenerateInspectionXlsx(selectedInspections, Master.Mn_UserID);
                if (!result.Success)
                {
                    lblError.ForeColor = Color.Red;
                    lblError.Text = Server.HtmlEncode(result.Message);
                    return;
                }

                // Preview sederhana; ukuran dan jumlah worksheet hanya dicatat di Trace.
                // Link manual tetap ada kalau browser memblokir popup.
                string fileUrl = GetInspectionFileUrl(result);
                string safeUrlHtml = HttpUtility.HtmlAttributeEncode(fileUrl);
                lblError.ForeColor = Color.Green;
                lblError.Text = "DEBUG OK - " +
                    selectedInspections.Rows.Count +
                    " InspectionID (DataTable). <a href=\"" + safeUrlHtml +
                    "\" target=\"_blank\" rel=\"noopener\">Buka / Download Excel</a>";

                string jsUrl = HttpUtility.JavaScriptStringEncode(fileUrl);
                string script = "if (typeof openWindow === 'function') { " +
                    "openWindow('" + jsUrl + "', '_blank',800,600,'yes','yes'); " +
                    "} else { window.open('" + jsUrl + "', '_blank'); }";
                // UpdatePanel: ClientScript biasa tidak selalu dijalankan setelah async postback.
                if (ScriptManager.GetCurrent(Page) != null)
                    ScriptManager.RegisterStartupScript(Page, Page.GetType(),
                        "InspectionExcelOpen", script, true);
                else
                    ClientScript.RegisterStartupScript(GetType(),
                        "InspectionExcelOpen", script, true);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("_printReport: " + ex);
                lblError.ForeColor = Color.Red;
                lblError.Text = "Gagal membuat Excel: " + Server.HtmlEncode(ex.GetBaseException().Message);
            }
        }

        private void UpdateViewGridReport()
        {
            txtMaxRecord.Text = (GF.IsNumeric(txtMaxRecord.Text.Trim()) && Convert.ToInt16(txtMaxRecord.Text.Trim()) > 0 ? Convert.ToString(Convert.ToInt16(txtMaxRecord.Text.Trim())) : "50");

            using (WAL.BR.CF ocf = new WAL.BR.CF())
            {
                DataTable V_gd = (ocf.EQuery(
                                "SELECT " +
                                "    InspectionID, ClientInspectionID,  " +
                                "    InspectionNo,  " +
                                "    CompanyID,  " +
                                "    LocationID,  " +
                                "    SectionID, InspectionTypeCode, InspectionTypeName, InspectionTypeDetailCode,  " +
                                "    InspectionTypeDetailName, InspectionDate, TemplateNo, TemplateName, [Status] " +
                                "FROM PIP_T_Inspection "
                               ));
                gridAppReport.DataSource = V_gd;
                gridAppReport.DataBind();
                gridAppReport.ShowFooter = (gridAppReport.Items.Count == 0) ? true : false;

            }

            lblSearchResults.Text = "Count : " + gridAppReport.Items.Count.ToString();

        }

        protected void grdListItem_SortCommand(object source, System.Web.UI.WebControls.DataGridSortCommandEventArgs e)
        {
            if (gridAppReport.Items.Count > 0)
            {
                string sortExpression = Convert.ToString(ViewState[GF.Key_CacheSLSortExpression]);
                string sortDirection = Convert.ToString(ViewState[GF.Key_CacheSLSortExpression]);

                if (sortExpression != e.SortExpression)
                {
                    sortExpression = e.SortExpression;
                    sortDirection = "asc";
                }
                else
                {
                    if (sortDirection == "asc")
                    {
                        sortDirection = "desc";
                    }
                    else
                    {
                        sortDirection = "asc";
                    }

                }

                ViewState[GF.Key_CacheSLSortExpression] = sortExpression;
                ViewState[GF.Key_CacheSLSortExpression] = sortDirection;
                BindDataGrid(sortExpression + " " + sortDirection);
            }
        }

        protected void lbtn_Search_Click(object sender, EventArgs e)
        {
            F_Open_pnl_Search();
            GF.Focus(this.Page, txt_InspectionNo.ClientID);
        }

        protected void lBtn_S_Apply_Click(object sender, EventArgs e)
        {
            UpdateViewGridReport();
            GF.Focus(this.Page, txt_InspectionNo.ClientID);
        }
        protected void lbtn_S_Reset_Click(object sender, EventArgs e)
        {
            GF.Focus(this.Page, txt_InspectionNo.ClientID);
        }
        protected void lbtn_S_Close_Click(object sender, EventArgs e)
        {
            F_Close_pnl_Search();
            GF.Focus(this.Page, lbtn_Search.ClientID);
        }

        private void F_Open_pnl_Search()
        {
            lbtn_Search.Visible = false;
            GF.ShowPanel(ref pnl_Search, true);
        }
        private void F_Close_pnl_Search()
        {
            lbtn_Search.Visible = true;
            GF.ShowPanel(ref pnl_Search, false);
        }

        protected void lbtn_PreRender(object sender, EventArgs e)
        {
            GF.AddAttdisabled_2(sender);
        }

        private void BindDataGrid(string sortExpression)
        {
            DataView dv = (DataView)Session[GF.Key_CacheSLDictatedDV];

            if (sortExpression.Length > 0)
            {
                dv.Sort = sortExpression;
                Session[GF.Key_CacheSLDictatedDV] = dv;
            }

            gridAppReport.DataSource = dv;
            gridAppReport.DataBind();

        }

        protected void TextBox_TextChanged(object sender, System.EventArgs e)
        {
            TextBox a = (TextBox)sender;
            switch (a.ID)
            {
                case "txtMaxRecord":
                    UpdateViewGridReport();
                    GF.Focus(this.Page, txtMaxRecord.ClientID);
                    break;
            }
        }
    }

    public sealed class ReportFileResult
    {
        public bool Success { get; set; }
        public string Status { get; set; }
        public string FileName { get; set; }
        public string StoragePath { get; set; }
        public string Message { get; set; }
    }
}
