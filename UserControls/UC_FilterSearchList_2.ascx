<%@ Control Language="C#" AutoEventWireup="true" CodeBehind="UC_FilterSearchList_2.ascx.cs" Inherits="WAL.UC_FilterSearchList_2" %>

<div class="mt-1 mb-1 border rounded shadow-sm">
<asp:DataGrid	id="gridSearch" 
                runat="server" 
                AutoGenerateColumns="False" 
                CellSpacing="0" 
                BorderColor="#394376" 
                BorderWidth="0px" 
                GridLines="None"
                class="table table-sm mb-0 table-borderless w-100"
                PageSize="20"
                AllowPaging="False"
                DataKeyField=""
                ShowFooter="false"
                ShowHeader="true"
                CellPadding="0"
                OnItemCreated="gridSearch_ItemCreated"
                >
        <%--OnItemCreated="gridSearch_ItemCreated"--%>
        <HeaderStyle CssClass="fz-custom1 dtgrdhd-custom1 bg-custom20" />
        <ItemStyle CssClass="fz-custom1 dtgrddt-custom1" Wrap="true" />
        <AlternatingItemStyle CssClass="fz-custom1 dtgrddtalt-custom1" />
        <Columns>			 
                <asp:TemplateColumn runat="server" 
                                    HeaderText="Field" 
                                    HeaderStyle-HorizontalAlign="left"                                     
                                    HeaderStyle-Width = "50%"
                                    ItemStyle-HorizontalAlign="left"   
                                    ItemStyle-Width = "50%"
                                    >
                    <itemtemplate>
                        <asp:label		
                                        runat="server" 
                                        class="align-middle"
                                        Text='<%# DataBinder.Eval(Container.DataItem, "Field") %>' 
                                        ID="_lblField"/>
                    </itemtemplate>
                </asp:TemplateColumn >
                                                
                <asp:TemplateColumn runat="server" 
                                    HeaderText="Field2" 
                                    HeaderStyle-HorizontalAlign="left" 
                                    HeaderStyle-Width = "50%"
                                    ItemStyle-HorizontalAlign="left"
                                    ItemStyle-Width = "50%"
                                    Visible="false"
                                    >
                    <itemtemplate>
                        <asp:label		runat="server" 
                                        Text='<%# DataBinder.Eval(Container.DataItem, "Field2") %>' 
                                        ID="_lblField2"/>
                    </itemtemplate>
                </asp:TemplateColumn >
                                                
                <asp:TemplateColumn runat="server" 
                                    HeaderText="Filter Value" 
                                    HeaderStyle-HorizontalAlign="left" 
                                    HeaderStyle-Width = "50%"
                                    ItemStyle-HorizontalAlign="left"
                                    ItemStyle-Width = "50%"
                                    >
                    <itemtemplate>
                        <asp:TextBox	id="_txtValue"
										runat="server"
										text="*"
										CssClass="form-control form-control-sm rounded fz-custom1"
										/>
                        <%--OnTextChanged="_txtValue_TextChanged"
										autopostback="true"--%>
                    </itemtemplate>
                </asp:TemplateColumn >                                                
        </Columns>
</asp:DataGrid>
</div>

<table cellspacing="0" cellpadding="0" width="100%" border="0">
<tr>
    <td align="right">
        <asp:label ID="lblListFieldText" runat="server" Visible="false"></asp:label>
        <asp:label ID="lblListFieldValue" runat="server" Visible="false"></asp:label>
        <%-- <asp:label ID="lblbtnOkClientID" runat="server" Visible="false"></asp:label>--%>

        <asp:TextBox	id="txt_First_Value_ClientID"
						runat="server"
						CssClass="form-control form-control-sm rounded d-none fz-custom1"
						/>
        <asp:TextBox	id="txt_Current_Value_ClientID"
						runat="server"
						CssClass="form-control form-control-sm rounded d-none fz-custom1"
						/>
        <asp:linkButton ID="lbtnOk" 
			            Runat="server" 
			            CssClass="btn btn-sm btn-outline-info fz-custom2 btn-custom1"
			            ToolTip="Ok"
                        Width="60px"
                        OnClick="lbtnOk_Click"
			            >
            <i class="fas fa-check-circle"></i> Ok
        </asp:linkButton>
	    <asp:linkButton ID="lbtnClear" 
			            Runat="server" 
			            CssClass="btn btn-sm btn-outline-info fz-custom2 btn-custom1"
			            ToolTip="Clear"
                        Width="60px"
                        OnClick="lbtnClear_Click"
			            >
            <i class="fas fa-eraser"></i> Clear
	    </asp:linkButton>
	    <asp:linkButton ID="lbtnClose" 
			            Runat="server" 
			            CssClass="btn btn-sm btn-outline-info fz-custom2 btn-custom1"
			            ToolTip="Close"
                        Width="60px"
                        OnClick="lbtnClose_Click"
			            >
            <i class="fas fa-times"></i> Close
	    </asp:linkButton>
    </td>
</tr>
</table>
