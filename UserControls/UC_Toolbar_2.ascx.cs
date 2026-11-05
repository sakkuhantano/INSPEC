using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;

namespace WAL
{
    public partial class UC_Toolbar_2 : System.Web.UI.UserControl
    {
     
        //public event EventHandler ToolbarClick;
        public event EventHandler<ToolBarEventArgs_2> ToolbarClick;

        private void Page_Init(object sender, System.EventArgs e)
        {
            if (!IsPostBack)
            {
                _PrepareScreen();
            }
            else
            {

            }
        }
        protected void Page_Load(object sender, EventArgs e)
        {
            if (!IsPostBack)
            {
                //_PrepareScreen();
            }
        }
        private void _PrepareScreen()
        {
            SetIcon(ToolbarItem_2.Back, "<i class=\"fas fa-arrow-left\"></i>");
            SetIcon(ToolbarItem_2.New, "<i class=\"fas fa-eraser\"></i>");
            SetIcon(ToolbarItem_2.Save, "<i class=\"fas fa-save\"></i>");
            SetIcon(ToolbarItem_2.Delete, "<i class=\"fas fa-trash-alt\"></i>");
            SetIcon(ToolbarItem_2.Refresh, "<i class=\"fas fa-sync-alt\"></i>");
            SetIcon(ToolbarItem_2.Process, "<i class=\"fas fa-hourglass-half\"></i>");
            SetIcon(ToolbarItem_2.Approve, "<i class=\"fas fa-lock\"></i>");
            SetIcon(ToolbarItem_2.Void, "<i class=\"fas fa-lock-open\"></i>");
            SetIcon(ToolbarItem_2.Complete, "<i class=\"fas fa-clipboard-check\"></i>");
            SetIcon(ToolbarItem_2.Send, "<i class=\"fas fa-paper-plane\"></i>");
            //SetIcon(ToolbarItem_2.Print, "<i class=\"fas fa-print\"></i>");
            SetIcon(ToolbarItem_2.Print, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi bi-printer-fill\" viewBox=\"0 0 16 16\"> <path d=\"M5 1a2 2 0 0 0-2 2v1h10V3a2 2 0 0 0-2-2H5zm6 8H5a1 1 0 0 0-1 1v3a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1v-3a1 1 0 0 0-1-1z\"/><path d=\"M0 7a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2h-1v-2a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v2H2a2 2 0 0 1-2-2V7zm2.5 1a.5.5 0 1 0 0-1 .5.5 0 0 0 0 1z\"/></svg>");
            SetIcon(ToolbarItem_2.Previous, "<i class=\"fas fa-arrow-circle-left\"></i>");
            SetIcon(ToolbarItem_2.Next, "<i class=\"fas fa-arrow-circle-right\"></i>");


            //SetConfirmMessage(ToolbarItem_2.Save, lbtn_Save.Enabled && chk_Save_IsMsg.Checked, GF.MSG_SAVE);
            //SetConfirmMessage(ToolbarItem_2.Delete, lbtn_Delete.Enabled && chk_Delete_IsMsg.Checked, GF.MSG_DELETE);
            //SetConfirmMessage(ToolbarItem_2.Process, lbtn_Process.Enabled && chk_Process_IsMsg.Checked, GF.MSG_PROCESS);
            //SetConfirmMessage(ToolbarItem_2.Approve, lbtn_Approve.Enabled && chk_Approve_IsMsg.Checked, GF.MSG_APPROVE);
            //SetConfirmMessage(ToolbarItem_2.Void, lbtn_Void.Enabled && chk_Void_IsMsg.Checked, GF.MSG_VOID);
            //SetConfirmMessage(ToolbarItem_2.Complete, lbtn_Complete.Enabled && chk_Complete_IsMsg.Checked, GF.MSG_COMPLETE);
            //SetConfirmMessage(ToolbarItem_2.Send, lbtn_Send.Enabled && chk_Send_IsMsg.Checked, GF.MSG_Send);
            //SetConfirmMessage(ToolbarItem_2.Print, lbtn_Print.Enabled && chk_Print_IsMsg.Checked, GF.MSG_PRINT);

            //SetConfirmMessage(ToolbarItem_2.Save, chk_Save_IsMsg.Checked, GF.MSG_SAVE);
            //SetConfirmMessage(ToolbarItem_2.Delete, chk_Delete_IsMsg.Checked, GF.MSG_DELETE);
            //SetConfirmMessage(ToolbarItem_2.Process, chk_Process_IsMsg.Checked, GF.MSG_PROCESS);
            //SetConfirmMessage(ToolbarItem_2.Approve, chk_Approve_IsMsg.Checked, GF.MSG_APPROVE);
            //SetConfirmMessage(ToolbarItem_2.Void, chk_Void_IsMsg.Checked, GF.MSG_VOID);
            //SetConfirmMessage(ToolbarItem_2.Complete, chk_Complete_IsMsg.Checked, GF.MSG_COMPLETE);
            //SetConfirmMessage(ToolbarItem_2.Send, chk_Send_IsMsg.Checked, GF.MSG_Send);
            //SetConfirmMessage(ToolbarItem_2.Print, chk_Print_IsMsg.Checked, GF.MSG_PRINT);

            if (lit_Save_Msg.Text == "")
            {
                SetConfirmMessage(ToolbarItem_2.Save, GF.MSG_SAVE);
            }
            IsConfirmMessage(ToolbarItem_2.Save, true);

            if (lit_Delete_Msg.Text == "")
            {
                SetConfirmMessage(ToolbarItem_2.Delete, GF.MSG_DELETE);
            }
            IsConfirmMessage(ToolbarItem_2.Delete, true);

            if (lit_Process_Msg.Text == "")
            {
                SetConfirmMessage(ToolbarItem_2.Process, GF.MSG_PROCESS);
            }
            IsConfirmMessage(ToolbarItem_2.Process, true);

            if (lit_Approve_Msg.Text == "")
            {
                SetConfirmMessage(ToolbarItem_2.Approve, GF.MSG_APPROVE);
            }
            IsConfirmMessage(ToolbarItem_2.Approve, true);

            if (lit_Void_Msg.Text == "")
            {
                SetConfirmMessage(ToolbarItem_2.Void, GF.MSG_VOID);
            }
            IsConfirmMessage(ToolbarItem_2.Void, true);

            if (lit_Complete_Msg.Text == "")
            {
                SetConfirmMessage(ToolbarItem_2.Complete, GF.MSG_COMPLETE);
            }
            IsConfirmMessage(ToolbarItem_2.Complete, true);

            if (lit_Send_Msg.Text == "")
            {
                SetConfirmMessage(ToolbarItem_2.Send, GF.MSG_Send);
            }
            IsConfirmMessage(ToolbarItem_2.Send, true);

            if (lit_Print_Msg.Text == "")
            {
                SetConfirmMessage(ToolbarItem_2.Print, GF.MSG_PRINT);
            }
            IsConfirmMessage(ToolbarItem_2.Print, true);
        }

        private string F_Script_ConfirmMessage(string strMsg)
        {
            string _retval = "";

            _retval = _retval + "javascript: if (!confirm('" + strMsg + "')) return false; return true;";
            
            return _retval;
        }
        private string F_tipe(ToolbarItem_2 item,
                            string tipe, 
                            ref LinkButton lbtn, 
                            ref Literal lit_Text,
                            ref Literal lit_Icon,
                            ref CheckBox chk_IsMsg,
                            ref Literal lit_Msg,
                            string value)
        {
            string _retval = "";

            switch (tipe)
            {
                case "IsConfirmMessage":
                    chk_IsMsg.Checked = Convert.ToBoolean(value);
                    if (lbtn.Enabled && chk_IsMsg.Checked)
                    {
                        lbtn.Attributes.Add("OnClick", F_Script_ConfirmMessage(lit_Msg.Text));
                    }
                    else
                    {
                        lbtn.Attributes.Remove("OnClick");
                    }
                    break;
                case "SetConfirmMessage":
                    lit_Msg.Text = value;
                    break;
                case "SetIcon":
                    lit_Icon.Text = value + "&nbsp;";
                    break;
                case "SetText":
                    lit_Text.Text = value;
                    break;
                case "SetWidth":
                    lbtn.Width = new Unit(value);
                    break;
                case "EnableButton":
                    lbtn.Enabled = Convert.ToBoolean(value);
                    if (lbtn.Enabled && chk_IsMsg.Checked)
                    {
                        lbtn.Attributes.Add("OnClick", F_Script_ConfirmMessage(lit_Msg.Text));
                    }
                    else
                    {
                        lbtn.Attributes.Remove("OnClick");
                    }
                    break;
                case "GetEnableButton":                     
                    _retval = Convert.ToString(lbtn.Enabled);
                    break;
                case "VisibleButton":
                    lbtn.Visible = Convert.ToBoolean(value);
                    break;
                case "GetVisibleButton":
                    _retval = Convert.ToString(lbtn.Visible);
                    break;
                    
            }

            return _retval;
        }
        private string F_ToolbarItem_2(ToolbarItem_2 item, string tipe, string value)
        {
            string _retval = "";

            switch (item)
            {
                case ToolbarItem_2.Back:
                    _retval = F_tipe(item, tipe, ref lbtn_Back, ref lit_Back_Text, ref lit_Back_Icon, ref chk_Back_IsMsg, ref lit_Back_Msg, value);
                    break;
                case ToolbarItem_2.New:
                    _retval = F_tipe(item, tipe, ref lbtn_New, ref lit_New_Text, ref lit_New_Icon, ref chk_New_IsMsg, ref lit_New_Msg, value);
                    break;
                case ToolbarItem_2.Save:
                    _retval = F_tipe(item, tipe, ref lbtn_Save, ref lit_Save_Text, ref lit_Save_Icon, ref chk_Save_IsMsg, ref lit_Save_Msg, value);
                    break;
                case ToolbarItem_2.Delete:
                    _retval = F_tipe(item, tipe, ref lbtn_Delete, ref lit_Delete_Text, ref lit_Delete_Icon, ref chk_Delete_IsMsg, ref lit_Delete_Msg, value);
                    break;
                case ToolbarItem_2.Refresh:
                    _retval = F_tipe(item, tipe, ref lbtn_Refresh, ref lit_Refresh_Text, ref lit_Refresh_Icon, ref chk_Refresh_IsMsg, ref lit_Refresh_Msg, value);
                    break;
                case ToolbarItem_2.Process:
                    _retval = F_tipe(item, tipe, ref lbtn_Process, ref lit_Process_Text, ref lit_Process_Icon, ref chk_Process_IsMsg, ref lit_Process_Msg, value);
                    break;
                case ToolbarItem_2.Approve:
                    _retval = F_tipe(item, tipe, ref lbtn_Approve, ref lit_Approve_Text, ref lit_Approve_Icon, ref chk_Approve_IsMsg, ref lit_Approve_Msg, value);
                    break;
                case ToolbarItem_2.Void:
                    _retval = F_tipe(item, tipe, ref lbtn_Void, ref lit_Void_Text, ref lit_Void_Icon, ref chk_Void_IsMsg, ref lit_Void_Msg, value);
                    break;
                case ToolbarItem_2.Complete:
                    _retval = F_tipe(item, tipe, ref lbtn_Complete, ref lit_Complete_Text, ref lit_Complete_Icon, ref chk_Complete_IsMsg, ref lit_Complete_Msg, value);
                    break;
                case ToolbarItem_2.Send:
                    _retval = F_tipe(item, tipe, ref lbtn_Send, ref lit_Send_Text, ref lit_Send_Icon, ref chk_Send_IsMsg, ref lit_Send_Msg, value);
                    break;
                case ToolbarItem_2.Print:
                    _retval = F_tipe(item, tipe, ref lbtn_Print, ref lit_Print_Text, ref lit_Print_Icon, ref chk_Print_IsMsg, ref lit_Print_Msg, value);
                    break;
                case ToolbarItem_2.Previous:
                    _retval = F_tipe(item, tipe, ref lbtn_Previous, ref lit_Previous_Text, ref lit_Previous_Icon, ref chk_Previous_IsMsg, ref lit_Previous_Msg, value);
                    break;
                case ToolbarItem_2.Next:
                    _retval = F_tipe(item, tipe, ref lbtn_Next, ref lit_Next_Text, ref lit_Next_Icon, ref chk_Next_IsMsg, ref lit_Next_Msg, value);
                    break;

                case ToolbarItem_2.Custom_1:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_1, ref lit_Custom_1_Text, ref lit_Custom_1_Icon, ref chk_Custom_1_IsMsg, ref lit_Custom_1_Msg, value);
                    break;
                case ToolbarItem_2.Custom_2:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_2, ref lit_Custom_2_Text, ref lit_Custom_2_Icon, ref chk_Custom_2_IsMsg, ref lit_Custom_2_Msg, value);
                    break;
                case ToolbarItem_2.Custom_3:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_3, ref lit_Custom_3_Text, ref lit_Custom_3_Icon, ref chk_Custom_3_IsMsg, ref lit_Custom_3_Msg, value);
                    break;
                case ToolbarItem_2.Custom_4:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_4, ref lit_Custom_4_Text, ref lit_Custom_4_Icon, ref chk_Custom_4_IsMsg, ref lit_Custom_4_Msg, value);
                    break;
                case ToolbarItem_2.Custom_5:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_5, ref lit_Custom_5_Text, ref lit_Custom_5_Icon, ref chk_Custom_5_IsMsg, ref lit_Custom_5_Msg, value);
                    break;
                case ToolbarItem_2.Custom_6:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_6, ref lit_Custom_6_Text, ref lit_Custom_6_Icon, ref chk_Custom_6_IsMsg, ref lit_Custom_6_Msg, value);
                    break;
                case ToolbarItem_2.Custom_7:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_7, ref lit_Custom_7_Text, ref lit_Custom_7_Icon, ref chk_Custom_7_IsMsg, ref lit_Custom_7_Msg, value);
                    break;
                case ToolbarItem_2.Custom_8:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_8, ref lit_Custom_8_Text, ref lit_Custom_8_Icon, ref chk_Custom_8_IsMsg, ref lit_Custom_8_Msg, value);
                    break;
                case ToolbarItem_2.Custom_9:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_9, ref lit_Custom_9_Text, ref lit_Custom_9_Icon, ref chk_Custom_9_IsMsg, ref lit_Custom_9_Msg, value);
                    break;
                case ToolbarItem_2.Custom_10:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_10, ref lit_Custom_10_Text, ref lit_Custom_10_Icon, ref chk_Custom_10_IsMsg, ref lit_Custom_10_Msg, value);
                    break;
                case ToolbarItem_2.Custom_11:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_11, ref lit_Custom_11_Text, ref lit_Custom_11_Icon, ref chk_Custom_11_IsMsg, ref lit_Custom_11_Msg, value);
                    break;
                case ToolbarItem_2.Custom_12:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_12, ref lit_Custom_12_Text, ref lit_Custom_12_Icon, ref chk_Custom_12_IsMsg, ref lit_Custom_12_Msg, value);
                    break;
                case ToolbarItem_2.Custom_13:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_13, ref lit_Custom_13_Text, ref lit_Custom_13_Icon, ref chk_Custom_13_IsMsg, ref lit_Custom_13_Msg, value);
                    break;
                case ToolbarItem_2.Custom_14:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_14, ref lit_Custom_14_Text, ref lit_Custom_14_Icon, ref chk_Custom_14_IsMsg, ref lit_Custom_14_Msg, value);
                    break;
                case ToolbarItem_2.Custom_15:
                    _retval = F_tipe(item, tipe, ref lbtn_Custom_15, ref lit_Custom_15_Text, ref lit_Custom_15_Icon, ref chk_Custom_15_IsMsg, ref lit_Custom_15_Msg, value);
                    break;
            }

            return _retval;
        }

        public void IsConfirmMessage(ToolbarItem_2 item, bool value)
        {
            F_ToolbarItem_2(item, "IsConfirmMessage", Convert.ToString(value));
        }
        public void SetConfirmMessage(ToolbarItem_2 item, string value)
        {
            F_ToolbarItem_2(item, "SetConfirmMessage", value);
        }
        public void SetConfirmMessage(ToolbarItem_2 item, bool IsConfirmMsg, string value)
        {
            SetConfirmMessage(item, value);
            IsConfirmMessage(item, IsConfirmMsg);
        }


        public void SetIcon(ToolbarItem_2 item, string value)
        {
            F_ToolbarItem_2(item, "SetIcon", value);
        }
        public void SetText(ToolbarItem_2 item, string value)
        {
            F_ToolbarItem_2(item, "SetText", value);
        }
        public void SetWidth(ToolbarItem_2 item, string value)
        {
            F_ToolbarItem_2(item, "SetWidth", value);
        }

        public void EnableButton(ToolbarItem_2 item, bool value)
        {
            F_ToolbarItem_2(item, "EnableButton", Convert.ToString(value));
        }
        public bool EnableButton(ToolbarItem_2 item)
        {
            bool _retval = false;
            
            _retval = Convert.ToBoolean(F_ToolbarItem_2(item, "GetEnableButton", ""));

            return _retval;
        }

        public void VisibleButton(ToolbarItem_2 item, bool value)
        {
            F_ToolbarItem_2(item, "VisibleButton", Convert.ToString(value));
        }
        public bool VisibleButton(ToolbarItem_2 item)
        {
            bool _retval = false;

            _retval = Convert.ToBoolean(F_ToolbarItem_2(item, "GetVisibleButton", ""));

            return _retval;
        }
        public void VisibleButton(ToolbarItem_2 item, 
                                  bool value, 
                                  string p_Text = "", 
                                  string p_Icon = "",
                                  string p_Width = ""
                                  )
        {
            VisibleButton(item, value);
            SetText(item, p_Text);
            SetIcon(item, p_Icon);
            SetWidth(item, p_Width);
        }

        


        protected void lbtn_Back_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Back });
        }
        protected void lbtn_New_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.New });
        }
        protected void lbtn_Save_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Save });
        }
        protected void lbtn_Delete_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Delete });
        }
        protected void lbtn_Refresh_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Refresh });
        }
        protected void lbtn_Process_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Process });
        }
        protected void lbtn_Approve_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Approve });
        }
        protected void lbtn_Void_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Void });
        }
        protected void lbtn_Complete_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Complete });
        }
        protected void lbtn_Send_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Send });
        }
        protected void lbtn_Print_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Print });
        }
        protected void lbtn_Previous_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Previous });
        }
        protected void lbtn_Next_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Next });
        }


        protected void lbtn_Custom_1_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_1 });
        }
        protected void lbtn_Custom_2_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_2 });
        }
        protected void lbtn_Custom_3_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_3 });
        }
        protected void lbtn_Custom_4_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_4 });
        }
        protected void lbtn_Custom_5_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_5 });
        }
        protected void lbtn_Custom_6_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_6 });
        }
        protected void lbtn_Custom_7_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_7 });
        }
        protected void lbtn_Custom_8_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_8 });
        }
        protected void lbtn_Custom_9_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_9 });
        }
        protected void lbtn_Custom_10_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_10 });
        }
        protected void lbtn_Custom_11_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_11 });
        }
        protected void lbtn_Custom_12_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_12 });
        }
        protected void lbtn_Custom_13_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_13 });
        }
        protected void lbtn_Custom_14_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_14 });
        }
        protected void lbtn_Custom_15_Click(object sender, EventArgs e)
        {
            ToolbarClick(sender, new ToolBarEventArgs_2() { ToolbarItem = ToolbarItem_2.Custom_15 });
        }
        

        protected void lbtn_PreRender(object sender, EventArgs e)
        {
            GF.AddAttdisabled_2(sender);
        }        
    }
}