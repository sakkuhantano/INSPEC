using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.MasterPages
{
    public partial class Site1 : System.Web.UI.MasterPage
    {
        protected void Page_Init(object sender, EventArgs e)
        {
            ucToolbar.ToolbarClick += UC_ToolbarClick;
        }

        private void UC_ToolbarClick(object sender, ToolBarEventArgs_2 e)
        {
            I_ToolBar_2 page = Page as I_ToolBar_2;
            if (page != null)
            {
                page.Toolbar_Click(sender, e);
            }
        }

        public void TB_VisibleToolbar(bool value)
        {
            GF.ShowPanel(ref pnl_TB, value);
        }

        public void TB_IsConfirmMessage(ToolbarItem_2 item, bool value)
        {
            ucToolbar.IsConfirmMessage(item, value);
        }

        public void TB_SetConfirmMessage(ToolbarItem_2 item, string value)
        {
            ucToolbar.SetConfirmMessage(item, value);
        }

        public void TB_SetConfirmMessage(ToolbarItem_2 item, bool isConfirmMessage, string value)
        {
            ucToolbar.SetConfirmMessage(item, isConfirmMessage, value);
        }

        public void TB_SetIcon(ToolbarItem_2 item, string value)
        {
            ucToolbar.SetIcon(item, value);
        }

        public void TB_SetText(ToolbarItem_2 item, string value)
        {
            ucToolbar.SetText(item, value);
        }

        public void TB_SetWidth(ToolbarItem_2 item, string value)
        {
            ucToolbar.SetWidth(item, value);
        }

        public void TB_EnableButton(ToolbarItem_2 item, bool value)
        {
            ucToolbar.EnableButton(item, value);
        }

        public bool TB_EnableButton(ToolbarItem_2 item)
        {
            return ucToolbar.EnableButton(item);
        }

        public void TB_VisibleButton(ToolbarItem_2 item, bool value)
        {
            ucToolbar.VisibleButton(item, value);
        }

        public bool TB_VisibleButton(ToolbarItem_2 item)
        {
            return ucToolbar.VisibleButton(item);
        }

        public void TB_VisibleButton(ToolbarItem_2 item, bool value, string p_Text = "", string p_Icon = "", string p_Width = "")
        {
            ucToolbar.VisibleButton(item, value, p_Text, p_Icon, p_Width);
        }

        protected void Page_Load(object sender, EventArgs e)
        {

        }
    }
}