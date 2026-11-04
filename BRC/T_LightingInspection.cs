using System;
using System.Data;
using System.Data.SqlClient;

namespace INSPEC.BRC
{
    public class T_LightingInspection : WAL.BR.BRInteractionBase
    {
        private const string AllowedCompanyID = "I00024012";
        private const string AllowedLocationID = "R02";

        private static void ValidateScope(string companyID, string locationID)
        {
            if (!String.Equals(companyID, AllowedCompanyID, StringComparison.Ordinal) ||
                !String.Equals(locationID, AllowedLocationID, StringComparison.Ordinal))
                throw new UnauthorizedAccessException("CompanyID/LocationID tidak diizinkan untuk Lighting Inspection.");
        }

        private static SqlParameter Varchar(string name, int size, string value)
        {
            return new SqlParameter(name, SqlDbType.VarChar, size) { Value = value };
        }

        private DataSet ExecuteRead(string procedureName, SqlParameter[] parameters)
        {
            DataSet result = new DataSet();
            try
            {
                _mainConnection.Open();
                using (SqlCommand cmd = new SqlCommand(procedureName, _mainConnection))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 120;
                    cmd.Parameters.AddRange(parameters);
                    using (SqlDataAdapter adapter = new SqlDataAdapter(cmd))
                    {
                        adapter.Fill(result);
                    }
                }
                return result;
            }
            finally
            {
                Dispose();
            }
        }

        public DataSet GetLightingMap(string companyID, string locationID)
        {
            ValidateScope(companyID, locationID);
            DataSet ds = ExecuteRead("spINSPEC_GetLightingMap", new SqlParameter[]
            {
                Varchar("@CompanyID", 20, companyID),
                Varchar("@LocationID", 20, locationID)
            });
            if (ds.Tables.Count != 4)
                throw new DataException("spINSPEC_GetLightingMap harus mengembalikan 4 result set.");
            return ds;
        }

        public DataSet GetLightingChecklist(string companyID, string locationID, DateTime inspectionDate)
        {
            ValidateScope(companyID, locationID);
            DataSet ds = ExecuteRead("spINSPEC_GetLightingChecklist", new SqlParameter[]
            {
                Varchar("@CompanyID", 20, companyID),
                Varchar("@LocationID", 20, locationID),
                new SqlParameter("@InspectionDate", SqlDbType.Date) { Value = inspectionDate.Date }
            });
            if (ds.Tables.Count != 2)
                throw new DataException("spINSPEC_GetLightingChecklist harus mengembalikan 2 result set.");
            return ds;
        }

        public static DataTable CreateInspectionItemsTable()
        {
            DataTable table = new DataTable();
            table.Columns.Add("ScheduleID", typeof(int));
            table.Columns.Add("LightID", typeof(int));
            table.Columns.Add("LightStatus", typeof(string));
            table.Columns.Add("Notes", typeof(string));
            return table;
        }

        private static void ValidateItems(DataTable items)
        {
            if (items == null) throw new ArgumentNullException("items");
            string[] columns = { "ScheduleID", "LightID", "LightStatus", "Notes" };
            if (items.Columns.Count != columns.Length)
                throw new ArgumentException("TVP harus berisi tepat 4 kolom.", "items");
            for (int i = 0; i < columns.Length; i++)
                if (items.Columns[i].ColumnName != columns[i])
                    throw new ArgumentException("Urutan kolom TVP tidak sesuai: " + columns[i], "items");
            if (items.Columns[0].DataType != typeof(int) ||
                items.Columns[1].DataType != typeof(int) ||
                items.Columns[2].DataType != typeof(string) ||
                items.Columns[3].DataType != typeof(string))
                throw new ArgumentException("Tipe data kolom TVP tidak sesuai.", "items");

            System.Collections.Generic.HashSet<string> keys = new System.Collections.Generic.HashSet<string>();
            foreach (DataRow row in items.Rows)
            {
                if (row.RowState == DataRowState.Deleted) continue;
                if (row.IsNull("ScheduleID") || row.IsNull("LightID") || row.IsNull("LightStatus"))
                    throw new ArgumentException("ScheduleID, LightID, dan LightStatus wajib diisi.", "items");
                int scheduleID = (int)row["ScheduleID"];
                int lightID = (int)row["LightID"];
                string status = (string)row["LightStatus"];
                if (scheduleID <= 0 || lightID <= 0 || (status != "ON" && status != "OFF"))
                    throw new ArgumentException("Item inspeksi tidak valid; status hanya ON atau OFF.", "items");
                if (!keys.Add(scheduleID.ToString() + ":" + lightID.ToString()))
                    throw new ArgumentException("Terdapat ScheduleID dan LightID duplikat.", "items");
                if (!row.IsNull("Notes") && ((string)row["Notes"]).Length > 2000)
                    throw new ArgumentException("Notes maksimal 2000 karakter.", "items");
            }
        }

        public long SaveLightingInspection(string companyID, string locationID,
            DateTime inspectionDate, string updatedBy, DataTable items)
        {
            ValidateScope(companyID, locationID);
            if (String.IsNullOrWhiteSpace(updatedBy) || updatedBy.Length > 200)
                throw new ArgumentException("UpdatedBy wajib diisi (maksimal 200 karakter).", "updatedBy");
            ValidateItems(items);
            if (items.Rows.Count == 0)
                throw new ArgumentException("Tidak ada status ON/OFF untuk disimpan.", "items");

            try
            {
                _mainConnection.Open();
                // SP memiliki transaksi sendiri; JANGAN panggil Begintrans().
                using (SqlCommand cmd = new SqlCommand("spINSPEC_SaveLightingInspection", _mainConnection))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandTimeout = 120;
                    cmd.Parameters.Add(Varchar("@CompanyID", 20, companyID));
                    cmd.Parameters.Add(Varchar("@LocationID", 20, locationID));
                    cmd.Parameters.Add(new SqlParameter("@InspectionDate", SqlDbType.Date) { Value = inspectionDate.Date });
                    cmd.Parameters.Add(new SqlParameter("@UpdatedBy", SqlDbType.NVarChar, 200) { Value = updatedBy });
                    SqlParameter tvp = new SqlParameter("@Items", SqlDbType.Structured);
                    tvp.TypeName = "dbo.INSPEC_LightingInspectionItemType";
                    tvp.Value = items;
                    cmd.Parameters.Add(tvp);
                    SqlParameter output = new SqlParameter("@InspectionID", SqlDbType.BigInt);
                    output.Direction = ParameterDirection.Output;
                    cmd.Parameters.Add(output);
                    cmd.ExecuteNonQuery();
                    if (output.Value == null || output.Value == DBNull.Value)
                        throw new DataException("Stored procedure tidak mengembalikan InspectionID.");
                    return Convert.ToInt64(output.Value);
                }
            }
            finally
            {
                Dispose();
            }
        }
    }
}
