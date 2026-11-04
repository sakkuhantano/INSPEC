using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Net;

namespace INSPEC.BRC
{
    public class T_DailyLogEmployee : WAL.BR.BRInteractionBase
    {
        #region Main Functions
        public bool InsertUpdateData(bool editing, string EmployeeID, string LoginUser, DateTime StartDateTime, DateTime EndDateTime, string Actvity,
                                    int DetailId, DateTime OriginalStart, DateTime OriginalEnd, string OriginalActivity, DateTime PeriodDate)
        {
            _mainConnection.Open();
            Begintrans();

            try
            {
                using (var ocf = new WAL.BR.CF())
                {
                    if (editing)
                    {
                        DataView odv = new DataView(ocf.EQueryP("sp_Inspec_DailyLog_Update",
                                                  new SqlParameter[]
                                                    { 
                                                        new SqlParameter("@EmployeeID", EmployeeID),
                                                        new SqlParameter("@LoginUser", LoginUser),
                                                        new SqlParameter("@StartDateTime", StartDateTime),
                                                        new SqlParameter("@EndDateTime", EndDateTime),
                                                        new SqlParameter("@Activity", Actvity),
                                                        new SqlParameter("@DetailId", DetailId),
                                                        new SqlParameter("@OriginalStart", OriginalStart),
                                                        new SqlParameter("@OriginalEnd", OriginalEnd),
                                                        new SqlParameter("@OriginalActivity", OriginalActivity)
                                                    }, true, ref _mainConnection, ref _transaction));
                    }
                    else
                    {
                        SqlParameter outputId = new SqlParameter("@NewDetailId", SqlDbType.Int);
                        outputId.Direction = ParameterDirection.Output;

                        DataView odv = new DataView(ocf.EQueryP("sp_Inspec_DailyLog_Insert", new SqlParameter[]
                                        {
                                            new SqlParameter("@EmployeeID", EmployeeID),
                                            new SqlParameter("@LoginUser", LoginUser),
                                            new SqlParameter("@StartDateTime", StartDateTime),
                                            new SqlParameter("@EndDateTime", EndDateTime),
                                            new SqlParameter("@Activity", Actvity),
                                            new SqlParameter("@PeriodDate", PeriodDate),
                                            outputId
                                        }, true, ref _mainConnection, ref _transaction));
                        // Ambil ID setelah Stored Procedure selesai
                        int newDetailId = Convert.ToInt32(outputId.Value);
                    }

                    CommitTrans();
                    return true;
                }
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
                //cmdToExecute.Dispose();
                //oCF.Dispose();
                //oCF = null;
            }
        }
        public bool DeleteData(int DetailId, string EmployeeID, string LoginUser, DateTime OriginalStart, DateTime OriginalEnd, string OriginalActivity)
        {
            _mainConnection.Open();
            Begintrans();

            try
            {
                using (var ocf = new WAL.BR.CF())
                {

                    DataView odv = new DataView(ocf.EQueryP("sp_Inspec_DailyLog_Delete",
                                                  new SqlParameter[]
                                                    { 
                                                        new SqlParameter("@DetailId", DetailId),
                                                        new SqlParameter("@EmployeeID", EmployeeID),
                                                        new SqlParameter("@LoginUser", LoginUser),
                                                        new SqlParameter("@OriginalStart", OriginalStart),
                                                        new SqlParameter("@OriginalEnd", OriginalEnd),
                                                        new SqlParameter("@OriginalActivity", OriginalActivity)
                                                    }, true, ref _mainConnection, ref _transaction));
                    CommitTrans();
                    return true;
                }
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
                //cmdToExecute.Dispose();
                //oCF.Dispose();
                //oCF = null;
            }
        }
        #endregion
    }
}
