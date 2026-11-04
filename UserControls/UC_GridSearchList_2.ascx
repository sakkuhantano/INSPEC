<%@ Control Language="C#" AutoEventWireup="true" CodeBehind="UC_GridSearchList_2.ascx.cs" Inherits="WAL.UC_GridSearchList_2" %>

<div class="mt-1"></div>

<table class="fz-custom1" cellspacing="0" cellpadding="0" width="100%" border="0">
<tr>
	<td align="left" width="25%">
            <div class="form-inline">
				<asp:label ID="Label2" Runat="server" Text="Max Record"/>
				&nbsp;
				<asp:TextBox id="txtMaxRecord"
								runat="server"
								Text="50"
								style="text-align:center"
								MaxLength="10"
								width="70px"
								CssClass="form-control form-control-sm rounded-pill fz-custom1"
                                AutoPostBack="true" 
                                OnTextChanged="txtMaxRecord_TextChanged"
								/>
            </div>
        <%--onkeypress="javascript:PostBackCtrlID_Enter(event.keyCode,'ctl00$lbtnOk');"--%>
	</td>
	<td align="center" valign="middle"  width="50%">
		<asp:linkButton ID="lbtnSearch" 
						Runat="server" 
						CssClass="btn btn-sm btn-outline-info fz-custom2 btn-custom1"
						ToolTip="Search"
                        OnClick="lbtnSearch_Click"
                        Width="70px"
						>
            <i class="fas fa-search"></i> Search
		</asp:linkButton>
	</td>
	<td  align="Right" width="25%">
            <asp:Label ID="lblReturnValueCol" Runat="server" Visible="false"></asp:Label>
            <asp:Label ID="lblShowReturnValue" Runat="server" Visible="false"></asp:Label>
            <asp:Label ID="lblListColNotReturnValue" Runat="server" Visible="false"></asp:Label>
			Count: <asp:label ID="lblSearchResults" Runat="server"/>
	</td>	
</tr>
</table>

<div class="mt-1 mb-1 border rounded shadow-sm fz-custom1">
<asp:DataGrid	id="grdListItem"
				runat="server" 
				BorderColor="#000"
				BorderWidth="0"  
				GridLines="None"	
				class="table table-sm table-borderless mb-0 w-100"
				CellPadding="2"
				CellSpacing="0"
				AllowSorting="true"
				ShowFooter="false"
				ShowHeader="true" 
                OnItemCreated="grdListItem_ItemCreated" 
                OnItemDataBound="grdListItem_ItemDataBound" 
                OnSortCommand="grdListItem_SortCommand" 
				>
	<HeaderStyle HorizontalAlign="left" CssClass="fz-custom1 dtgrdhd-custom1 bg-custom20"/>
	<ItemStyle HorizontalAlign="left" VerticalAlign="Top" CssClass="fz-custom1 dtgrddt-custom1"/>
	<AlternatingItemStyle HorizontalAlign="left" VerticalAlign="Top" CssClass="fz-custom1 dtgrddtalt-custom1"/>
	<FooterStyle HorizontalAlign="left"  CssClass="fz-custom1 dtgrdhd-custom1"/>
    <PagerStyle Mode="NumericPages" HorizontalAlign="right" />
	<Columns>			
            <asp:TemplateColumn runat="server" 
                            HeaderText="" 
					        HeaderStyle-HorizontalAlign="left" 
					        HeaderStyle-Width = "1px"
                            ItemStyle-HorizontalAlign="left"
                            ItemStyle-Width = "1px"
                            >
	            <itemtemplate>
	                <asp:LinkButton id="_lbtnok" runat="server" Text="·"></asp:LinkButton>
	            </itemtemplate>
            </asp:TemplateColumn>
    </Columns>
</asp:DataGrid>
</div>

	