<%@ Control Language="C#" AutoEventWireup="true" CodeBehind="UC_Toolbar_2.ascx.cs" Inherits="WAL.UC_Toolbar_2" %>

<%--<div class="modal fade" id="exampleModal" tabindex="-1" role="dialog" aria-labelledby="exampleModalLabel" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered modal-sm" role="document">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="exampleModalLabel">Modal title</h5>
        <button type="button" class="close" data-dismiss="modal" aria-label="Close">
          <span aria-hidden="true">&times;</span>
        </button>
      </div>
      <div class="modal-body">
        ...
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
        <button type="button" class="btn btn-primary">Save changes</button>
      </div>
    </div>
  </div>
</div>
<script>
   $(document).ready(function(){ 
       $("#exampleModal").modal({ 
           backdrop: 'static', 
           keyboard: false, 
           show: true 
       }); 
   });
</script>--%>
<%--bg-custom16--%>
    <div class="row border rounded shadow-sm w-100" style="margin:auto;border-color:black;">
        <div class="col">
            <asp:linkbutton Runat="server" 
                            id="lbtn_Back"                             
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Back_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Back_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Back_Text" runat="server" Text="Back"></asp:Literal>                
                <asp:CheckBox ID="chk_Back_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_Back_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_New" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_New_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_New_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_New_Text" runat="server" Text="New"></asp:Literal>
                <asp:CheckBox ID="chk_New_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_New_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Save" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Save_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Save_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Save_Text" runat="server" Text="Save"></asp:Literal>
                <asp:CheckBox ID="chk_Save_IsMsg" runat="server" Checked="true" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_Save_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Delete" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Delete_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Delete_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Delete_Text" runat="server" Text="Delete"></asp:Literal>
                <asp:CheckBox ID="chk_Delete_IsMsg" runat="server" Checked="true" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_Delete_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Refresh" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Refresh_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Refresh_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Refresh_Text" runat="server" Text="Refresh"></asp:Literal>
                <asp:CheckBox ID="chk_Refresh_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_Refresh_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Process" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Process_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Process_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Process_Text" runat="server" Text="Process"></asp:Literal>
                <asp:CheckBox ID="chk_Process_IsMsg" runat="server" Checked="true" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_Process_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Approve" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Approve_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Approve_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Approve_Text" runat="server" Text="Approve"></asp:Literal>
                <asp:CheckBox ID="chk_Approve_IsMsg" runat="server" Checked="true" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_Approve_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Void" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Void_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Void_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Void_Text" runat="server" Text="Void"></asp:Literal>
                <asp:CheckBox ID="chk_Void_IsMsg" runat="server" Checked="true" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_Void_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Complete" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Complete_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Complete_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Complete_Text" runat="server" Text="Complete"></asp:Literal>
                <asp:CheckBox ID="chk_Complete_IsMsg" runat="server" Checked="true" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_Complete_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Send" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Send_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Send_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Send_Text" runat="server" Text="Send"></asp:Literal>
                <asp:CheckBox ID="chk_Send_IsMsg" runat="server" Checked="true" Visible="false"></asp:CheckBox>                
                <asp:Literal ID="lit_Send_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Print" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Print_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Print_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Print_Text" runat="server" Text="Print"></asp:Literal>
                <asp:CheckBox ID="chk_Print_IsMsg" runat="server" Checked="true" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Print_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Previous" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Previous_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Previous_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Previous_Text" runat="server" Text="Previous"></asp:Literal>
                <asp:CheckBox ID="chk_Previous_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Previous_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton Runat="server" 
                            id="lbtn_Next" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Next_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Next_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Next_Text" runat="server" Text="Next"></asp:Literal>
                <asp:CheckBox ID="chk_Next_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Next_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_1" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_1_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_1_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_1_Text" runat="server" Text="Custom_1"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_1_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_1_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>
                        
            <asp:linkbutton ID="lbtn_Custom_2" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_2_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_2_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_2_Text" runat="server" Text="Custom_2"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_2_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_2_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_3" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_3_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_3_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_3_Text" runat="server" Text="Custom_3"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_3_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_3_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_4" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_4_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_4_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_4_Text" runat="server" Text="Custom_4"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_4_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_4_Msg" runat="server" Visible="false"></asp:Literal>                
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_5" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_5_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_5_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_5_Text" runat="server" Text="Custom_5"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_5_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_5_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_6" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_6_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_6_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_6_Text" runat="server" Text="Custom_6"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_6_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_6_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_7" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_7_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_7_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_7_Text" runat="server" Text="Custom_7"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_7_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_7_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_8" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_8_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_8_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_8_Text" runat="server" Text="Custom_8"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_8_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_8_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_9" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_9_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_9_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_9_Text" runat="server" Text="Custom_9"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_9_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_9_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_10" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_10_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_10_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_10_Text" runat="server" Text="Custom_10"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_10_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_10_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_11" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_11_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_11_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_11_Text" runat="server" Text="Custom_11"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_11_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_11_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_12" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_12_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_12_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_12_Text" runat="server" Text="Custom_12"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_12_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_12_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_13" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_13_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_13_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_13_Text" runat="server" Text="Custom_13"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_13_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_13_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_14" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_14_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_14_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_14_Text" runat="server" Text="Custom_14"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_14_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_14_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>

            <asp:linkbutton ID="lbtn_Custom_15" 
                            runat="server" 
                            CssClass="btn btn-sm btn-outline-info mt-1 mb-1 px-3 fz-custom2 btn-custom2"                            
                            OnClick="lbtn_Custom_15_Click"
                            OnPreRender="lbtn_PreRender"
                            Visible="false"
                            >
                <asp:Literal ID="lit_Custom_15_Icon" runat="server" Text=""></asp:Literal>
                <asp:Literal ID="lit_Custom_15_Text" runat="server" Text="Custom_15"></asp:Literal>
                <asp:CheckBox ID="chk_Custom_15_IsMsg" runat="server" Checked="false" Visible="false"></asp:CheckBox>
                <asp:Literal ID="lit_Custom_15_Msg" runat="server" Visible="false"></asp:Literal>
            </asp:linkbutton>
        </div>
    </div>


<%--
<i class="fas fa-eraser"></i>
<i class="fas fa-save"></i>
<i class="fas fa-trash-alt"></i>
<i class="fas fa-sync-alt"></i>
<i class="fas fa-lock"></i>
<i class="fas fa-lock-open"></i>
<i class="fas fa-print"></i>
<i class="fas fa-paper-plane"></i>                
<i class="fas fa-hourglass-half"></i>
<i class="fas fa-arrow-left"></i>
<i class="fas fa-arrow-circle-left"></i>
<i class="fas fa-arrow-circle-right"></i>
--%>

