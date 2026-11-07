using System.Linq;
using System.Web;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Diagnostics;
using System.Data.SqlClient;


namespace WAL.BR
{
    public class CF : BRInteractionBase 
	{

		#region Class Member Declarations
		#endregion

		public CF()
		{
			// // Nothing for now.
		}

		public CF(string strConnectionString)
		{
			ConnectionString = strConnectionString;
		}

		public string GetHashStringSQL(string Password)
        {
            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = "sp_GetHashStringSQL";
            cmdToExecute.CommandType = CommandType.StoredProcedure;
            DataTable toReturn = new DataTable("HashStringSQL");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

            cmdToExecute.Connection = _mainConnection;

            try
            {
                cmdToExecute.Parameters.AddWithValue("@TypeHashString", "SHA1");
                cmdToExecute.Parameters.AddWithValue("@Password", Password);

                // // Open connection.
                _mainConnection.Open();

                // // Execute query.
                adapter.Fill(toReturn);

                return Convert.ToString(GF.GetString(toReturn.Rows[0]["EncriptionPassword"]));
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object
                throw new Exception(ex.Message);
            }
            finally
            {
                // // Close connection.
                _mainConnection.Close();
                cmdToExecute.Dispose();
                adapter.Dispose();
            }
        }
        public string GetHashStringSQL(string Password, ref SqlConnection conn, ref SqlTransaction Trans)
        {
            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = "sp_GetHashStringSQL";
            //StrGenerateIDNumber(TableName, ColumnName, Prefix, TextFilterForIDMax)
            cmdToExecute.CommandType = CommandType.StoredProcedure;
            DataTable toReturn = new DataTable("HashStringSQL");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

            // // Use base class' connection object
            cmdToExecute.Connection = conn;
            cmdToExecute.Transaction = Trans;

            try
            {
                cmdToExecute.Parameters.AddWithValue("@TypeHashString", "SHA1");
                cmdToExecute.Parameters.AddWithValue("@Password", Password);

                // // Execute query.
                adapter.Fill(toReturn);

                return Convert.ToString(GF.GetString(toReturn.Rows[0]["EncriptionPassword"]));
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object
                throw new Exception(ex.Message);
            }
            finally
            {
                cmdToExecute.Dispose();
                adapter.Dispose();
            }
        }

        public string GetGenerateKeyHD(string tablename, ref SqlConnection conn, ref SqlTransaction Trans)
        {
            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = "sp_GetGenerateKeyHD";
            //StrGenerateIDNumber(TableName, ColumnName, Prefix, TextFilterForIDMax)
            cmdToExecute.CommandType = CommandType.StoredProcedure;
            DataTable toReturn = new DataTable("sp_GetGenerateKeyHD");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

            // // Use base class' connection object
            cmdToExecute.Connection = conn;
            cmdToExecute.Transaction = Trans;

            try
            {
                cmdToExecute.Parameters.AddWithValue("@Tablename", tablename);

                // // Execute query.
                adapter.Fill(toReturn);

                if(toReturn.Rows.Count > 0)
                {
                    return Convert.ToString(GF.GetString(toReturn.Rows[0]["KeyHD"]));
                }
                else
                {
                    throw new Exception("KeyHD not found");
                }
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object
                throw new Exception(ex.Message);
            }
            finally
            {
                cmdToExecute.Dispose();
                adapter.Dispose();
            }
        }

		public string GetGenerateID(string _Type, string TableName, string ColumnName, string Prefix = "", string TextFilterForIDMax = "")
		{
			SqlCommand cmdToExecute = new SqlCommand();
			cmdToExecute.CommandText = "sp_GetGenerateID";
			//StrGenerateIDNumber(TableName, ColumnName, Prefix, TextFilterForIDMax)
			cmdToExecute.CommandType = CommandType.StoredProcedure;
			DataTable toReturn = new DataTable("GetGenerateID");
			SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

			// // Use base class' connection object
			cmdToExecute.Connection = _mainConnection;

			try {
				cmdToExecute.Parameters.AddWithValue("@Type", _Type);
				cmdToExecute.Parameters.AddWithValue("@TableName", TableName);
				cmdToExecute.Parameters.AddWithValue("@ColumnName", ColumnName);
				cmdToExecute.Parameters.AddWithValue("@Prefix", Prefix);
				cmdToExecute.Parameters.AddWithValue("@TextFilterForIDMax", TextFilterForIDMax);
				// // Open connection.
				_mainConnection.Open();

				// // Execute query.
				adapter.Fill(toReturn);

				return Convert.ToString(GF.GetString(toReturn.Rows[0]["ID"]));
			} catch (Exception ex) {
				// // some error occured. Bubble it to caller and encapsulate Exception object
				throw new Exception(ex.Message);
			} finally {
				// // Close connection.
				_mainConnection.Close();
				cmdToExecute.Dispose();
				adapter.Dispose();
			}
		}
		public string GetGenerateID(string _Type, string TableName, string ColumnName, ref SqlConnection conn, ref SqlTransaction Trans, string Prefix, string TextFilterForIDMax)
		{
			SqlCommand cmdToExecute = new SqlCommand();
			cmdToExecute.CommandText = "sp_GetGenerateID";
			//StrGenerateIDNumber(TableName, ColumnName, Prefix, TextFilterForIDMax)
			cmdToExecute.CommandType = CommandType.StoredProcedure;
			DataTable toReturn = new DataTable("GetGenerateIDWithBeginTrans");
			SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

			// // Use base class' connection object
			cmdToExecute.Connection = conn;
			cmdToExecute.Transaction = Trans;

			try {
				cmdToExecute.Parameters.AddWithValue("@Type", _Type);
				cmdToExecute.Parameters.AddWithValue("@TableName", TableName);
				cmdToExecute.Parameters.AddWithValue("@ColumnName", ColumnName);
				cmdToExecute.Parameters.AddWithValue("@Prefix", Prefix);
				cmdToExecute.Parameters.AddWithValue("@TextFilterForIDMax", TextFilterForIDMax);

				// // Execute query.
				adapter.Fill(toReturn);

				return Convert.ToString(GF.GetString(toReturn.Rows[0]["ID"]));
			} catch (Exception ex) {
				// // some error occured. Bubble it to caller and encapsulate Exception object
				throw new Exception(ex.Message);
			} finally {
				cmdToExecute.Dispose();
				adapter.Dispose();
			}
		}

        public string GetGenerateAutoNumID(string AutoNumID, bool IsUpdateSeqNo, ref SqlConnection conn, ref SqlTransaction Trans, string CompanyID = "", string LocationID = "")
        {
            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = "sp_GetGenerateAutoNumID";
            //StrGenerateIDNumber(TableName, ColumnName, Prefix, TextFilterForIDMax)
            cmdToExecute.CommandType = CommandType.StoredProcedure;
            DataTable toReturn = new DataTable("GetGenerateAutoNumID");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

            // // Use base class' connection object
            cmdToExecute.Connection = conn;
            cmdToExecute.Transaction = Trans;

            try
            {
                cmdToExecute.Parameters.AddWithValue("@AppID", PB.AppID);
                cmdToExecute.Parameters.AddWithValue("@AutoNum", AutoNumID);
                cmdToExecute.Parameters.AddWithValue("@IsUpdateSeqNo", IsUpdateSeqNo);
                cmdToExecute.Parameters.AddWithValue("@CompanyID", CompanyID);
                cmdToExecute.Parameters.AddWithValue("@LocationID", LocationID);

                // // Execute query.
                adapter.Fill(toReturn);

                if (toReturn.Rows.Count > 0)
                {
                    return GF.GetString(toReturn.Rows[0]["ID"]);
                }
                else
                {
                    throw new Exception("AutoNumID not found");
                }
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object
                throw new Exception(ex.Message);
            }
            finally
            {
                cmdToExecute.Dispose();
                adapter.Dispose();
            }
        }

		public DataTable ExecuteSQL(string SQLString)
		{
			SqlCommand cmdToExecute = new SqlCommand();
			cmdToExecute.CommandText = SQLString;
			cmdToExecute.CommandType = CommandType.Text;
			DataTable toReturn = new DataTable("ExecuteSQL");
			SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

			// // Use base class' connection object                
			cmdToExecute.Connection = _mainConnection;
			cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;
            
			try {
				// // Open connection.                
				_mainConnection.Open();

				// // Execute query.                
				adapter.Fill(toReturn);

				//If toReturn.Rows.Count > 0 Then

				//End If

				return toReturn;
			} catch (Exception ex) {
				// // some error occured. Bubble it to caller and encapsulate Exception object                
				throw new Exception(ex.Message);
			} finally {
				// // Close connection.                
				_mainConnection.Close();
				cmdToExecute.Dispose();
				adapter.Dispose();
			}
		}
        public DataTable ExecuteSQL(string SQLString, ref SqlConnection conn, ref SqlTransaction Trans)
        {
            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = SQLString;
            cmdToExecute.CommandType = CommandType.Text;
            DataTable toReturn = new DataTable("ExecuteSQLWithParamBeginTrans");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

            cmdToExecute.Connection = conn;
            cmdToExecute.Transaction = Trans;
            cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

            try
            {
                // // Execute query.    
                adapter.Fill(toReturn);

                return toReturn;
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object    
                throw new Exception(ex.Message);
            }
            finally
            {
                cmdToExecute.Dispose();
                adapter.Dispose();
            }
        }

		public DataTable ExecuteSQLWithBeginTrans(string SQLString)
		{
			SqlCommand cmdToExecute = new SqlCommand();
			cmdToExecute.CommandText = SQLString;
			cmdToExecute.CommandType = CommandType.Text;
			DataTable toReturn = new DataTable("ExecuteSQLWithBeginTrans");
			SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

			_mainConnection.Open();
			Begintrans();

			try {
				cmdToExecute.Connection = _mainConnection;
				cmdToExecute.Transaction = _transaction;
				cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

				// // Execute query.    
				adapter.Fill(toReturn);

				CommitTrans();
				return toReturn;
			} catch (Exception ex) {
				// // Rollback all changes    
				RollBackTrans();
				// // some error occured. Bubble it to caller and encapsulate Exception object    
				throw new Exception(ex.Message);
			} finally {
				Dispose();

				cmdToExecute.Dispose();
			}
		}

		public DataTable ExecuteSP(string p_SPName, string[] p_ListParam)
		{
			SqlCommand cmdToExecute = new SqlCommand();
			cmdToExecute.CommandText = p_SPName;
			cmdToExecute.CommandType = CommandType.StoredProcedure;
			DataTable toReturn = new DataTable("ExecuteSP");
			SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

			// // Use base class' connection object                
			cmdToExecute.Connection = _mainConnection;
			cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

			try {
                
				for (int i = 0; i <= p_ListParam.Count() - 1; i++) {
                    cmdToExecute.Parameters.AddWithValue("@" + p_ListParam[i].Split('=')[0] , p_ListParam[i].Split('=')[1]);
				}

				// // Open connection.                
				_mainConnection.Open();

				// // Execute query.                
				adapter.Fill(toReturn);

				//If toReturn.Rows.Count > 0 Then

				//End If

				return toReturn;
			} catch (Exception ex) {
				// // some error occured. Bubble it to caller and encapsulate Exception object                
				throw new Exception(ex.Message);
			} finally {
				// // Close connection.                
				_mainConnection.Close();
				cmdToExecute.Dispose();
				adapter.Dispose();
			}
		}

        public DataTable ExecuteSP(string p_SPName, string[] p_ListParam, ref SqlConnection conn, ref SqlTransaction Trans)
        {
            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = p_SPName;
            cmdToExecute.CommandType = CommandType.StoredProcedure ;
            DataTable toReturn = new DataTable("ExecuteSPWithParamBeginTrans");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

            cmdToExecute.Connection = conn;
            cmdToExecute.Transaction = Trans;
            cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

            try
            {
                for (int i = 0; i <= p_ListParam.Count() - 1; i++)
                {
                    cmdToExecute.Parameters.AddWithValue("@" + p_ListParam[i].Split('=')[0], p_ListParam[i].Split('=')[1]);
                }

                // // Execute query.    
                adapter.Fill(toReturn);

                return toReturn;
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object    
                throw new Exception(ex.Message);
            }
            finally
            {
                cmdToExecute.Dispose();
                adapter.Dispose();
            }
        }

		public DataTable ExecuteSPWithBeginTrans(string p_SPName, string[] p_ListParam)
		{
			SqlCommand cmdToExecute = new SqlCommand();
			cmdToExecute.CommandText = p_SPName;
			cmdToExecute.CommandType = CommandType.StoredProcedure;
			DataTable toReturn = new DataTable("ExecuteSPWithBeginTrans");
			SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

			_mainConnection.Open();
			Begintrans();

			try {
				cmdToExecute.Connection = _mainConnection;
				cmdToExecute.Transaction = _transaction;
				cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

				for (int i = 0; i <= p_ListParam.Count() - 1; i++) {
					cmdToExecute.Parameters.AddWithValue("@" + p_ListParam[i].Split('=')[0], p_ListParam[i].Split('=')[1]);
				}

				// // Execute query.    
				adapter.Fill(toReturn);

				CommitTrans();
				return toReturn;
			} catch (Exception ex) {
				// // Rollback all changes    
				RollBackTrans();
				// // some error occured. Bubble it to caller and encapsulate Exception object    
				throw new Exception(ex.Message);
			} finally {
				Dispose();

				cmdToExecute.Dispose();
			}
		}


        public DataTable EQuery(string p_CommandText, 
                                string p_ListParam = "",
                                bool p_IsSP = false, 
                                bool p_IsWithBeginTrans = false)
        {

            if (p_IsWithBeginTrans)
            {
                SqlCommand cmdToExecute = new SqlCommand();
                cmdToExecute.CommandText = p_CommandText;
                if (p_IsSP)
                {
                    cmdToExecute.CommandType = CommandType.StoredProcedure;
                }
                else
                {
                    cmdToExecute.CommandType = CommandType.Text;
                }
                DataTable toReturn = new DataTable("EQueryWBT");
                SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

                _mainConnection.Open();
                Begintrans();

                try
                {
                    cmdToExecute.Connection = _mainConnection;
                    cmdToExecute.Transaction = _transaction;
                    cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

                    if (p_ListParam != "")
                    {
                        string[] V_ListParam = GF.SplitStr(p_ListParam, GF.Str2);
                        for (int i = 0; i <= V_ListParam.Count() - 1; i++)
                        {
                            cmdToExecute.Parameters.AddWithValue(V_ListParam[i].Split('=')[0], V_ListParam[i].Split('=')[1]);
                        }
                    }
                    
                    // // Execute query.    
                    adapter.Fill(toReturn);

                    CommitTrans();
                    return toReturn;
                }
                catch (Exception ex)
                {
                    // // Rollback all changes    
                    RollBackTrans();
                    // // some error occured. Bubble it to caller and encapsulate Exception object    
                    throw new Exception(ex.Message);
                }
                finally
                {
                    Dispose();
                    cmdToExecute.Dispose();
                }

            }
            else
            {

                SqlCommand cmdToExecute = new SqlCommand();
                cmdToExecute.CommandText = p_CommandText;
                if (p_IsSP)
                {
                    cmdToExecute.CommandType = CommandType.StoredProcedure;
                }
                else
                {
                    cmdToExecute.CommandType = CommandType.Text;
                }
                DataTable toReturn = new DataTable("EQuery");
                SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

                try
                {
                    cmdToExecute.Connection = _mainConnection;
                    cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

                    if (p_ListParam != "")
                    {
                        string[] V_ListParam = GF.SplitStr(p_ListParam, GF.Str2);
                        for (int i = 0; i <= V_ListParam.Count() - 1; i++)
                        {
                            cmdToExecute.Parameters.AddWithValue(V_ListParam[i].Split('=')[0], V_ListParam[i].Split('=')[1]);
                        }
                    }

                    // // Open connection.                
                    _mainConnection.Open();

                    // // Execute query.                
                    adapter.Fill(toReturn);

                    //If toReturn.Rows.Count > 0 Then

                    //End If

                    return toReturn;
                }
                catch (Exception ex)
                {
                    // // some error occured. Bubble it to caller and encapsulate Exception object                
                    throw new Exception(ex.Message);
                }
                finally
                {
                    // // Close connection.                
                    _mainConnection.Close();
                    cmdToExecute.Dispose();
                    adapter.Dispose();
                }
            }

        }

        public DataTable EQuery(string p_CommandText,
                                string p_ListParam,
                                bool p_IsSP, 
                                ref SqlConnection conn, 
                                ref SqlTransaction Trans)
        {

            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = p_CommandText;
            if (p_IsSP)
            {
                cmdToExecute.CommandType = CommandType.StoredProcedure;
            }
            else
            {
                cmdToExecute.CommandType = CommandType.Text;
            }
            DataTable toReturn = new DataTable("EQueryCT");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);


            try
            {
                cmdToExecute.Connection = conn;
                cmdToExecute.Transaction = Trans;
                cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;


                if (p_ListParam != "")
                {
                    string[] V_ListParam = GF.SplitStr(p_ListParam, GF.Str2);
                    for (int i = 0; i <= V_ListParam.Count() - 1; i++)
                    {
                        cmdToExecute.Parameters.AddWithValue(V_ListParam[i].Split('=')[0], V_ListParam[i].Split('=')[1]);
                    }
                }
                
                // // Execute query.    
                adapter.Fill(toReturn);

                return toReturn;
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object    
                throw new Exception(ex.Message);
            }
            finally
            {
                cmdToExecute.Dispose();
                adapter.Dispose();
            }

        }

       
        public DataTable EQueryP(string p_CommandText,
                                 SqlParameter[] p_ListParam = null,
                                 bool p_IsSP = false,
                                 bool p_IsWithBeginTrans = false)
        {

            if (p_IsWithBeginTrans)
            {
                SqlCommand cmdToExecute = new SqlCommand();
                cmdToExecute.CommandText = p_CommandText;
                if (p_IsSP)
                {
                    cmdToExecute.CommandType = CommandType.StoredProcedure;
                }
                else
                {
                    cmdToExecute.CommandType = CommandType.Text;
                }
                DataTable toReturn = new DataTable("EQueryPWBT");
                SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

                _mainConnection.Open();
                Begintrans();

                try
                {
                    cmdToExecute.Connection = _mainConnection;
                    cmdToExecute.Transaction = _transaction;
                    cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

                    if (p_ListParam != null)
                    {
                        //for (int i = 0; i <= p_ListParam.Count() - 1; i++)
                        //{
                        //    cmdToExecute.Parameters.AddWithValue(p_ListParam[i].ParameterName, p_ListParam[i].Value);
                        //}
                        cmdToExecute.Parameters.AddRange(p_ListParam);
                    }

                    // // Execute query.    
                    adapter.Fill(toReturn);

                    CommitTrans();
                    return toReturn;
                }
                catch (Exception ex)
                {
                    // // Rollback all changes    
                    RollBackTrans();
                    // // some error occured. Bubble it to caller and encapsulate Exception object    
                    throw new Exception(ex.Message);
                }
                finally
                {
                    Dispose();
                    cmdToExecute.Dispose();
                }

            }
            else
            {

                SqlCommand cmdToExecute = new SqlCommand();
                cmdToExecute.CommandText = p_CommandText;
                if (p_IsSP)
                {
                    cmdToExecute.CommandType = CommandType.StoredProcedure;
                }
                else
                {
                    cmdToExecute.CommandType = CommandType.Text;
                }
                DataTable toReturn = new DataTable("EQueryP");
                SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

                try
                {
                    cmdToExecute.Connection = _mainConnection;
                    cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

                    if (p_ListParam != null)
                    {
                        //for (int i = 0; i <= p_ListParam.Count() - 1; i++)
                        //{
                        //    cmdToExecute.Parameters.AddWithValue(p_ListParam[i].ParameterName, p_ListParam[i].Value);
                        //}
                        cmdToExecute.Parameters.AddRange(p_ListParam);
                    }

                    // // Open connection.                
                    _mainConnection.Open();

                    // // Execute query.                
                    adapter.Fill(toReturn);

                    //If toReturn.Rows.Count > 0 Then

                    //End If

                    return toReturn;
                }
                catch (Exception ex)
                {
                    // // some error occured. Bubble it to caller and encapsulate Exception object                
                    throw new Exception(ex.Message);
                }
                finally
                {
                    // // Close connection.                
                    _mainConnection.Close();
                    cmdToExecute.Dispose();
                    adapter.Dispose();
                }
            }

        }

        public DataTable EQueryP(string p_CommandText,
                                 SqlParameter[] p_ListParam,
                                 bool p_IsSP,
                                 ref SqlConnection conn,
                                 ref SqlTransaction Trans)
        {

            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = p_CommandText;
            if (p_IsSP)
            {
                cmdToExecute.CommandType = CommandType.StoredProcedure;
            }
            else
            {
                cmdToExecute.CommandType = CommandType.Text;
            }
            DataTable toReturn = new DataTable("EQueryPCT");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);


            try
            {
                cmdToExecute.Connection = conn;
                cmdToExecute.Transaction = Trans;
                cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;


                if (p_ListParam != null)
                {
                    //for (int i = 0; i <= p_ListParam.Count() - 1; i++)
                    //{
                    //    cmdToExecute.Parameters.AddWithValue(p_ListParam[i].ParameterName, p_ListParam[i].Value);
                    //}
                    cmdToExecute.Parameters.AddRange(p_ListParam);
                }

                // // Execute query.    
                adapter.Fill(toReturn);

                return toReturn;
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object    
                throw new Exception(ex.Message);
            }
            finally
            {
                cmdToExecute.Dispose();
                adapter.Dispose();
            }

        }

        
        public DataSet EQuery_DS(string p_CommandText,
                                 string p_ListParam = "",
                                 bool p_IsSP = false,
                                 bool p_IsWithBeginTrans = false)
        {

            if (p_IsWithBeginTrans)
            {
                SqlCommand cmdToExecute = new SqlCommand();
                cmdToExecute.CommandText = p_CommandText;
                if (p_IsSP)
                {
                    cmdToExecute.CommandType = CommandType.StoredProcedure;
                }
                else
                {
                    cmdToExecute.CommandType = CommandType.Text;
                }
                DataSet toReturn = new DataSet("EQueryWBT");
                SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

                _mainConnection.Open();
                Begintrans();

                try
                {
                    cmdToExecute.Connection = _mainConnection;
                    cmdToExecute.Transaction = _transaction;
                    cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

                    if (p_ListParam != "")
                    {
                        string[] V_ListParam = GF.SplitStr(p_ListParam, GF.Str2);
                        for (int i = 0; i <= V_ListParam.Count() - 1; i++)
                        {
                            cmdToExecute.Parameters.AddWithValue(V_ListParam[i].Split('=')[0], V_ListParam[i].Split('=')[1]);
                        }
                    }

                    // // Execute query.    
                    adapter.Fill(toReturn);

                    CommitTrans();
                    return toReturn;
                }
                catch (Exception ex)
                {
                    // // Rollback all changes    
                    RollBackTrans();
                    // // some error occured. Bubble it to caller and encapsulate Exception object    
                    throw new Exception(ex.Message);
                }
                finally
                {
                    Dispose();
                    cmdToExecute.Dispose();
                }

            }
            else
            {

                SqlCommand cmdToExecute = new SqlCommand();
                cmdToExecute.CommandText = p_CommandText;
                if (p_IsSP)
                {
                    cmdToExecute.CommandType = CommandType.StoredProcedure;
                }
                else
                {
                    cmdToExecute.CommandType = CommandType.Text;
                }
                DataSet toReturn = new DataSet("EQuery");
                SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

                try
                {
                    cmdToExecute.Connection = _mainConnection;
                    cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

                    if (p_ListParam != "")
                    {
                        string[] V_ListParam = GF.SplitStr(p_ListParam, GF.Str2);
                        for (int i = 0; i <= V_ListParam.Count() - 1; i++)
                        {
                            cmdToExecute.Parameters.AddWithValue(V_ListParam[i].Split('=')[0], V_ListParam[i].Split('=')[1]);
                        }
                    }

                    // // Open connection.                
                    _mainConnection.Open();

                    // // Execute query.                
                    adapter.Fill(toReturn);

                    //If toReturn.Rows.Count > 0 Then

                    //End If

                    return toReturn;
                }
                catch (Exception ex)
                {
                    // // some error occured. Bubble it to caller and encapsulate Exception object                
                    throw new Exception(ex.Message);
                }
                finally
                {
                    // // Close connection.                
                    _mainConnection.Close();
                    cmdToExecute.Dispose();
                    adapter.Dispose();
                }
            }

        }

        public DataSet EQuery_DS(string p_CommandText,
                                 string p_ListParam,
                                 bool p_IsSP,
                                 ref SqlConnection conn,
                                 ref SqlTransaction Trans)
        {

            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = p_CommandText;
            if (p_IsSP)
            {
                cmdToExecute.CommandType = CommandType.StoredProcedure;
            }
            else
            {
                cmdToExecute.CommandType = CommandType.Text;
            }
            DataSet toReturn = new DataSet("EQueryCT_DS");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);


            try
            {
                cmdToExecute.Connection = conn;
                cmdToExecute.Transaction = Trans;
                cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;


                if (p_ListParam != "")
                {
                    string[] V_ListParam = GF.SplitStr(p_ListParam, GF.Str2);
                    for (int i = 0; i <= V_ListParam.Count() - 1; i++)
                    {
                        cmdToExecute.Parameters.AddWithValue(V_ListParam[i].Split('=')[0], V_ListParam[i].Split('=')[1]);
                    }
                }

                // // Execute query.    
                adapter.Fill(toReturn);

                return toReturn;
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object    
                throw new Exception(ex.Message);
            }
            finally
            {
                cmdToExecute.Dispose();
                adapter.Dispose();
            }

        }


        public DataSet EQueryP_DS(string p_CommandText,
                                  SqlParameter[] p_ListParam = null,
                                  bool p_IsSP = false,
                                  bool p_IsWithBeginTrans = false)
        {

            if (p_IsWithBeginTrans)
            {
                SqlCommand cmdToExecute = new SqlCommand();
                cmdToExecute.CommandText = p_CommandText;
                if (p_IsSP)
                {
                    cmdToExecute.CommandType = CommandType.StoredProcedure;
                }
                else
                {
                    cmdToExecute.CommandType = CommandType.Text;
                }
                DataSet toReturn = new DataSet("EQueryPWBT_DS");
                SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

                _mainConnection.Open();
                Begintrans();

                try
                {
                    cmdToExecute.Connection = _mainConnection;
                    cmdToExecute.Transaction = _transaction;
                    cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

                    if (p_ListParam != null)
                    {
                        //for (int i = 0; i <= p_ListParam.Count() - 1; i++)
                        //{
                        //    cmdToExecute.Parameters.AddWithValue(p_ListParam[i].ParameterName, p_ListParam[i].Value);
                        //}
                        cmdToExecute.Parameters.AddRange(p_ListParam);
                    }

                    // // Execute query.    
                    adapter.Fill(toReturn);

                    CommitTrans();
                    return toReturn;
                }
                catch (Exception ex)
                {
                    // // Rollback all changes    
                    RollBackTrans();
                    // // some error occured. Bubble it to caller and encapsulate Exception object    
                    throw new Exception(ex.Message);
                }
                finally
                {
                    Dispose();
                    cmdToExecute.Dispose();
                }

            }
            else
            {

                SqlCommand cmdToExecute = new SqlCommand();
                cmdToExecute.CommandText = p_CommandText;
                if (p_IsSP)
                {
                    cmdToExecute.CommandType = CommandType.StoredProcedure;
                }
                else
                {
                    cmdToExecute.CommandType = CommandType.Text;
                }
                DataSet toReturn = new DataSet("EQueryP_DS");
                SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);

                try
                {
                    cmdToExecute.Connection = _mainConnection;
                    cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;

                    if (p_ListParam != null)
                    {
                        //for (int i = 0; i <= p_ListParam.Count() - 1; i++)
                        //{
                        //    cmdToExecute.Parameters.AddWithValue(p_ListParam[i].ParameterName, p_ListParam[i].Value);
                        //}
                        cmdToExecute.Parameters.AddRange(p_ListParam);
                    }

                    // // Open connection.                
                    _mainConnection.Open();

                    // // Execute query.                
                    adapter.Fill(toReturn);

                    //If toReturn.Rows.Count > 0 Then

                    //End If

                    return toReturn;
                }
                catch (Exception ex)
                {
                    // // some error occured. Bubble it to caller and encapsulate Exception object                
                    throw new Exception(ex.Message);
                }
                finally
                {
                    // // Close connection.                
                    _mainConnection.Close();
                    cmdToExecute.Dispose();
                    adapter.Dispose();
                }
            }

        }

        public DataSet EQueryP_DS(string p_CommandText,
                                  SqlParameter[] p_ListParam,
                                  bool p_IsSP,
                                  ref SqlConnection conn,
                                  ref SqlTransaction Trans)
        {

            SqlCommand cmdToExecute = new SqlCommand();
            cmdToExecute.CommandText = p_CommandText;
            if (p_IsSP)
            {
                cmdToExecute.CommandType = CommandType.StoredProcedure;
            }
            else
            {
                cmdToExecute.CommandType = CommandType.Text;
            }
            DataSet toReturn = new DataSet("EQueryPCT_DS");
            SqlDataAdapter adapter = new SqlDataAdapter(cmdToExecute);


            try
            {
                cmdToExecute.Connection = conn;
                cmdToExecute.Transaction = Trans;
                cmdToExecute.CommandTimeout = PB.DB_PageCacheExpiresInSeconds;


                if (p_ListParam != null)
                {
                    //for (int i = 0; i <= p_ListParam.Count() - 1; i++)
                    //{
                    //    cmdToExecute.Parameters.AddWithValue(p_ListParam[i].ParameterName, p_ListParam[i].Value);
                    //}
                    cmdToExecute.Parameters.AddRange(p_ListParam);
                }

                // // Execute query.    
                adapter.Fill(toReturn);

                return toReturn;
            }
            catch (Exception ex)
            {
                // // some error occured. Bubble it to caller and encapsulate Exception object    
                throw new Exception(ex.Message);
            }
            finally
            {
                cmdToExecute.Dispose();
                adapter.Dispose();
            }

        }


        public DataTable EQP(string p_CommandText,
                             SqlParameter[] p_ListParam = null,
                             bool p_IsSP = false,
                             bool p_IsWithBeginTrans = false,
                             SqlConnection p_conn = null,
                             SqlTransaction p_Trans = null)
        {
            DataTable V_retval;

            if (p_conn == null && p_Trans == null)
            {
                V_retval = EQueryP(p_CommandText: p_CommandText,
                                   p_ListParam: p_ListParam,
                                   p_IsSP: p_IsSP,
                                   p_IsWithBeginTrans: p_IsWithBeginTrans);
            }
            else
            {
                V_retval = EQueryP(p_CommandText: p_CommandText,
                                   p_ListParam: p_ListParam,
                                   p_IsSP: p_IsSP,
                                   conn: ref p_conn,
                                   Trans: ref p_Trans);
            }

            return V_retval;
        }

        public DataSet EQP_DS(string p_CommandText,
                                SqlParameter[] p_ListParam = null,
                                bool p_IsSP = false,
                                bool p_IsWithBeginTrans = false,
                                SqlConnection p_conn = null,
                                SqlTransaction p_Trans = null)
        {
            DataSet V_retval;

            if (p_conn == null && p_Trans == null)
            {
                V_retval = EQueryP_DS(p_CommandText: p_CommandText,
                                      p_ListParam: p_ListParam,
                                      p_IsSP: p_IsSP,
                                      p_IsWithBeginTrans: p_IsWithBeginTrans);
            }
            else
            {
                V_retval = EQueryP_DS(p_CommandText: p_CommandText,
                                      p_ListParam: p_ListParam,
                                      p_IsSP: p_IsSP,
                                      conn: ref p_conn,
                                      Trans: ref p_Trans);
            }

            return V_retval;
        }

	}
}




