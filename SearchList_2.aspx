<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="SearchList_2.aspx.cs" Inherits="INSPEC.SearchList_2" %>

<%@ Register Src="~/UserControls/UC_FilterSearchList_2.ascx" TagPrefix="uc1" TagName="UC_FilterSearchList" %>

<!DOCTYPE html>

<html xmlns="http://www.w3.org/1999/xhtml">
<head runat="server">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><asp:Literal ID="litSearchList" runat="server" Text="" /></title>
    <link rel="shortcut icon" type="image/x-icon" href="../../WebFolder/images/favicon.ico" />

    <link rel="stylesheet" href="../../WebFolder/bootstrap/css/bootstrap.min.css"/>
    <link rel="Stylesheet" type="text/css" href="../../WebFolder/Css/styles_2.css" />
    <link rel="stylesheet" type="text/css" href="../../WebFolder/fontawesome/css/all.min.css"/>

    <script src="../../WebFolder/jquery/jquery.min.js"></script>
    <script src="../../WebFolder/bootstrap/js/bootstrap.min.js"></script>
    <%--<script type="text/javascript" src="../../WebFolder/fontawesome/js/all.min.js"></script>--%>
    <script type="text/javascript" src="../../WebFolder/Scripts/JScript.js"></script>
	<script type="text/javascript" src="../../WebFolder/Scripts1/DisableKey.js"></script>

</head>
<body onkeydown="closeWindow_Escape(event.keyCode)">
    <form id="form1" runat="server">
    <div style="margin:auto;width:98%;">
        <div style="height:2px;"></div>

        <asp:Panel ID="pnlSearch" runat="server">
        <table border="0" cellspacing="0" cellpadding="0" style="width:100%">
            <tr>
                <td width="20%">
                </td>
                <td >
                    <uc1:UC_FilterSearchList runat="server" 
                                             ID="ucfsl" 
                                             OnFilterSearchListClick="ucfsl_FilterSearchListClick" />
                </td>
                <td width="20%">
                </td>
            </tr> 
        </table>
        </asp:Panel>  
        <table id="tbl_SeachList_2" border="0" cellspacing="0" cellpadding="0" style="width:100%">
		<tr>
		    <td align="center" valign="middle">
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
	                <FooterStyle HorizontalAlign="left"  CssClass="fz-custom1 dtgrddtalt-custom1"/>
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
			</td>
		</tr>
        <tr>
            <td>
                <div class="mt-3"></div>
            </td>
        </tr>
	    </table>
    </div>
    </form>
</body>
</html>
