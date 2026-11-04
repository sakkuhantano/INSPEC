using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Net;

namespace INSPEC.BRC
{
    public class SysWebCommonValue : WAL.BR.BRInteractionBase
    {
        #region Main Functions
        public DataTable SelectAll()
        {
            SqlCommand cmdToExecute = new SqlCommand();

            cmdToExecute.CommandText = "SELECT ID, Description FROM RDM.dbo.SysWebCommonValue where commongroup = @CommonGroup order by ID ";
            cmdToExecute.CommandType = CommandType.Text;

            DataTable toReturn = new DataTable("SysWebCommonValue");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

            cmdToExecute.Connection = _mainConnection;

            try
            {
                cmdToExecute.Parameters.AddWithValue("@CommonGroup", CommonGroup);
                _mainConnection.Open();

                adapter.Fill(toReturn);

                return toReturn;
            }
            catch (Exception ex)
            {
                throw new Exception(ex.Message);
            }
            finally
            {
                _mainConnection.Close();
                cmdToExecute.Dispose();
                adapter.Dispose();
            }
        }

        public DataTable SelectOne()
        {
            SqlCommand cmdToExecute = new SqlCommand();

            cmdToExecute.CommandText = "SELECT TOP 1 ID, Description FROM RDM.dbo.SysWebCommonValue where ID = @ID AND CommonGroup = @CommonGroup";
            cmdToExecute.CommandType = CommandType.Text;

            DataTable toReturn = new DataTable("SysWebCommonValue");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

            cmdToExecute.Connection = _mainConnection;

            try
            {
                cmdToExecute.Parameters.AddWithValue("@ID", ID);
                cmdToExecute.Parameters.AddWithValue("@CommonGroup", CommonGroup);
                _mainConnection.Open();

                adapter.Fill(toReturn);


                if (toReturn.Rows.Count > 0)
                {
                    ID = Convert.ToString(toReturn.Rows[0]["ID"]);
                    Description = Convert.ToString(toReturn.Rows[0]["Description"]);

                }

                return toReturn;
            }
            catch (Exception ex)
            {
                throw new Exception(ex.Message);
            }
            finally
            {
                _mainConnection.Close();
                cmdToExecute.Dispose();
                adapter.Dispose();
            }
        }
        #endregion

        public object CommonGroup { get; set; }

        public object ID { get; set; }

        public string Description { get; set; }
    }
}