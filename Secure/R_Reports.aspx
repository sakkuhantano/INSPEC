<%@ Page Title="" Language="C#" MaintainScrollPositionOnPostback="true" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="R_Report.aspx.cs" Inherits="INSPEC.Secure.R_Report" %>
<%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %>

<asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
    <link rel="stylesheet" href="../../WebFolder/bootstrap/css/bootstrap-datepicker3.css"/>
    <script type="text/javascript" src="../../WebFolder/bootstrap/js/bootstrap-datepicker.min.js"></script>    
    <script type="text/javascript" src="../../WebFolder/Scripts/DataGrid.js"></script>  
</asp:Content>

<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <table border="0" cellspacing="0" cellpadding="0" style="width:100%;">
        <tr>
            <td>
                <asp:Label ID="lblError" runat="server" ForeColor="Red" />
                <table border="0" cellspacing="0" cellpadding="0" style="width:100%;">
                    <tr style="height:10px;"><td></td></tr>
                    <asp:Panel ID="pnl_Search" runat="server">
                        <tr>
                            <td>        
                                <div id="divsearch" runat="server" class="row justify-content-center" style="margin:auto;">
                                    <div class="col col-sm-10 border rounded shadow-sm">                
                                        <div class="row font-weight-bold bg-custom20" style="height:30px;border-bottom: 1px solid #dee2e6;">
                                            <div class="col-9 d-flex justify-content-start align-items-center">
                                                <asp:Label ID="label4" 
                                                            runat="server" 
                                                            class="align-middle"
                                                            Text="Search & Sort"></asp:Label>
                                            </div>
                                            <div class="col-3 d-flex justify-content-end align-items-center">
                                                <asp:LinkButton id="lbtn_S_IconClose" 
                                                                runat="server"
                                                                CssClass="align-bottom text-secondary fz-custom2"
                                                                ToolTip="Close"
                                                                OnClick="lbtn_S_Close_Click"
                                                                >
                                                    <i class="fas fa-times"></i>
                                                </asp:LinkButton>
                                            </div>
                                        </div>
                                        <div class="row my-1"> 
                                            <div class="col-sm-6 mb-1">
                                                <div class="row mt-1">
                                                    <div class="col-sm-3 d-flex justify-content-start align-items-center">                            
                                                        <asp:Label ID="lbl_InspectionNo" runat="server" Text="Voucher No"></asp:Label>
                                                    </div>
                                                    <div class="col-sm-9">
                                                        <asp:TextBox    id="txt_InspectionNo" 
                                                                        runat="server" 
                                                                        MaxLength="35"
                                                                        CssClass="form-control form-control-sm rounded fz-custom1"
                                                                        />
                                                    </div>
                                                </div>
                                                <div class="row mt-1">
                                                    <div class="col-sm-3 d-flex justify-content-start align-items-center">                            
                                                        <asp:Label ID="lbl_Inspection_Date" runat="server" Text="Voucher Date"></asp:Label>
                                                    </div>
                                                    <div class="col-sm-9">
                                                        <div class="form-inline">
                                                            <div class="input-group date" style="width:47%;">
                                                                <asp:TextBox ID="txt_InspectionDate"
                                                                                runat="server"
                                                                                CssClass="form-control form-control-sm rounded-left fz-custom1"
                                                                                >
                                                                </asp:TextBox>
                                                                <div class="input-group-append">
                                                                    <span id="txt_InspectionDate_Icon" runat="server" class="input-group-text bg-white fz-custom1" style="cursor:pointer;">
                                                                        <i class="far fa-calendar"></i>
                                                                    </span>
                                                                </div>
                                                            </div>
                                                        </div>                                            
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                        <div class="row mt-1 ">
                                            <div class="col-sm ">
                                                <hr class="my-0"/>
                                            </div>
                                        </div>
                                        <div class="row my-1">
                                            <div class="col d-flex justify-content-center align-items-center">
                                                <asp:LinkButton ID="lBtn_S_Apply" 
                                                                runat="server"
                                                                CssClass="btn btn-sm btn-outline-info fz-custom2 btn-custom1"
                                                                OnClick="lBtn_S_Apply_Click"
                                                                Width="70px"
                                                                OnPreRender="lbtn_PreRender"
                                                                >
                                                    <i class="fas fa-check-circle"></i> Apply
                                                </asp:LinkButton>
                                                &ensp;
                                                <asp:LinkButton ID="lbtn_S_Reset" 
                                                                runat="server"
                                                                CssClass="btn btn-sm btn-outline-info fz-custom2 btn-custom1"
                                                                OnClick="lbtn_S_Reset_Click"
                                                                Width="70px"
                                                                OnPreRender="lbtn_PreRender"
                                                                >
                                                    <i class="fas fa-eraser"></i> Reset
                                                </asp:LinkButton>
                                            </div>
                                        </div>
                                    </div>
                                </div>  
                            </td>     
                        </tr>
                    </asp:Panel>
                        <tr>
                            <td>
                                <div class="row mt-1" style="margin:auto;">
                                    <div class="col-sm-4 d-flex justify-content-start align-items-center pl-0">                            
                                        <asp:label ID="Label2" Runat="server" Text="Max Record" />
			                            &nbsp;
			                            <asp:TextBox id="txtMaxRecord"
							                            runat="server"
							                            Text="50"
							                            style="text-align:center"
							                            MaxLength="10"
							                            width="50px"
							                            CssClass="form-control form-control-sm rounded fz-custom1"
                                                        AutoPostBack="true"                                    
                                                        OnTextChanged="TextBox_TextChanged"
							                            />
                                    </div>
                                    <div class="col-sm-4 d-flex justify-content-center align-items-center">
                                        <asp:linkButton ID="lbtn_Search" 
						                                Runat="server" 
						                                CssClass="btn btn-sm btn-outline-info fz-custom2 btn-custom1"
                                                        OnClick="lbtn_Search_Click"
                                                        Width="70px"
                                                        OnPreRender="lbtn_PreRender"
						                                >
                                            <i class="fas fa-search"></i> Search
		                                </asp:linkButton>
                                    </div>
                                    <div class="col-sm-4 d-flex justify-content-end align-items-end pr-0">
                                        <asp:label ID="lblSearchResults" Runat="server"/>              
                                    </div>
                                </div>
                            </td>
                        </tr>
                    <tr>
                        <td>
                            <asp:DataGrid	id="gridAppReport" 
                                            runat="server" 
                                            AutoGenerateColumns="False" 
                                            CellSpacing="0" 
                                            BorderColor="#394376" 
                                            BorderWidth="0px" 
                                            GridLines="None"
                                            class="table table-sm table-borderless mb-0 w-100"
                                            Width="100%"
                                            PageSize="20"
                                            AllowPaging="False"
                                            DataKeyField=""
                                            ShowFooter="false"
                                            ShowHeader="true"
                                            CellPadding="0"
                                            >
                                        <HeaderStyle HorizontalAlign="left" CssClass="fz-custom1 dtgrdhd-custom1 bg-custom20"/>
	                                    <ItemStyle HorizontalAlign="left" VerticalAlign="Top" CssClass="fz-custom1 dtgrddt-custom1"/>
	                                    <AlternatingItemStyle HorizontalAlign="left" VerticalAlign="Top" CssClass="fz-custom1 dtgrddtalt-custom1"/>
                                        <EditItemStyle />
                                        <FooterStyle HorizontalAlign="left"  CssClass="fz-custom1 dtgrdhd-custom1"/>
                                        <Columns>			
                                                <asp:TemplateColumn runat="server" 
                                                                HeaderText="InspectionID" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                Visible="false"
                                                                >
                                                    <itemtemplate>
                                                            <asp:label		runat="server" 
                                                                        Text='<%# DataBinder.Eval(Container.DataItem, "InspectionID") %>' 
                                                                        ID="_lblInspectionID"/>
                                                    </itemtemplate>
                                                </asp:TemplateColumn >	
                                                <asp:TemplateColumn runat="server" 
                                                                HeaderText="ClientInspectionID" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                Visible="false"
                                                                >
                                                    <itemtemplate>
                                                            <asp:label		runat="server" 
                                                                        Text='<%# DataBinder.Eval(Container.DataItem, "ClientInspectionID") %>' 
                                                                        ID="_lblClientInspectionID"/>
                                                    </itemtemplate>
                                                </asp:TemplateColumn >		
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="Inspection No" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                SortExpression="Inspection No"
                                                                >
                                                <itemtemplate>
                                                    <asp:label		runat="server" 
                                                                        Text='<%# DataBinder.Eval(Container.DataItem, "InspectionNo") %>' 
                                                                        ID="_lblInspectionNo"/>
                                                    <%--<asp:LinkButton runat="server" 
                                                                id="_lbtnInspectionNo"
                                                                Text = '<%# DataBinder.Eval(Container.DataItem, "InspectionNo") %>'
                                                                CausesValidation="false"
                                                                ToolTip="Go to Information"
                                                                CommandName="_lbtnInspectionNo">
                                                    </asp:LinkButton> --%>
                                                </itemtemplate>
                                            </asp:TemplateColumn >		
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="CompanyID" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                Visible="false"
                                                                >
                                                <itemtemplate>
                                                                <asp:label runat="server"                                                
                                                                    Text='<%# DataBinder.Eval(Container.DataItem, "CompanyID") %>' 
                                                                    ID="_lblCompanyID"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="LocationID" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                visible="false"
                                                                >
                                                <itemtemplate>
                                                                <asp:label runat="server"                                                
                                                                    Text='<%# DataBinder.Eval(Container.DataItem, "LocationID") %>' 
                                                                    ID="_lblLocationID"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >									
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="Inspection Date" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                SortExpression="InspectionDate"
                                                                >
                                                <itemtemplate>
                                                
                                                                <asp:label	runat="server" 
                                                                            Text='<%# Convert.ToDateTime(DataBinder.Eval(Container.DataItem, "InspectionDate")).ToString(WAL.GF.FormatDate)  %>' 
                                                                            ID="_lblInspectionDate"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >	
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="Inspection Type Code" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                visible="false"
                                                                >
                                                <itemtemplate>
                                                                <asp:label runat="server"                                                
                                                                    Text='<%# DataBinder.Eval(Container.DataItem, "InspectionTypeCode") %>' 
                                                                    ID="_lblInspectionTypeCode"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >				
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="Inspection Type Name" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                SortExpression="InspectionTypeName"
                                                                >
                                                <itemtemplate>
                                                                <asp:label runat="server"                                                
                                                                    Text='<%# DataBinder.Eval(Container.DataItem, "InspectionTypeName") %>' 
                                                                    ID="_lblInspectionTypeName"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >		
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="Inspection Type Detail Code" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                visible="false"
                                                                >
                                                <itemtemplate>
                                                                <asp:label runat="server"                                                
                                                                    Text='<%# DataBinder.Eval(Container.DataItem, "InspectionTypeDetailCode") %>' 
                                                                    ID="_lblInspectionTypeDetailCode"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >				
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="Inspection Type Detail Name" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                SortExpression="InspectionTypeDetailName"
                                                                >
                                                <itemtemplate>
                                                                <asp:label runat="server"                                                
                                                                    Text='<%# DataBinder.Eval(Container.DataItem, "InspectionTypeDetailName") %>' 
                                                                    ID="_lblInspectionTypeDetailName"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >	
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="Template No" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                visible="false"
                                                                >
                                                <itemtemplate>
                                                                <asp:label runat="server"                                                
                                                                    Text='<%# DataBinder.Eval(Container.DataItem, "TemplateNo") %>' 
                                                                    ID="_lblTemplateNo"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >		
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="Template Name" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                SortExpression="TemplateName"
                                                                >
                                                <itemtemplate>
                                                                <asp:label runat="server"                                                
                                                                    Text='<%# DataBinder.Eval(Container.DataItem, "TemplateName") %>' 
                                                                    ID="_lblTemplateName"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >	
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="Status Postponed" 
                                                                HeaderStyle-HorizontalAlign="left" 
                                                                HeaderStyle-Width = "2%"
                                                                ItemStyle-HorizontalAlign="left"
                                                                ItemStyle-Width = "2%"
                                                                >
                                                <itemtemplate>
                                                                <asp:label runat="server"                                                
                                                                    Text='<%# DataBinder.Eval(Container.DataItem, "Status") %>' 
                                                                    ID="_lblStatusPostpone"/>
                                                </itemtemplate>
                                            </asp:TemplateColumn >
                                            <asp:TemplateColumn runat="server" 
                                                                HeaderText="" 
                                                                HeaderStyle-HorizontalAlign="center" 
                                                                HeaderStyle-Width = "3%"
                                                                ItemStyle-HorizontalAlign="center"
                                                                ItemStyle-Width = "3%"
                                                                >
                                                <HeaderTemplate >
                                                        <div class="form-check">
                                                            <asp:checkbox ID="_chkGroupType1SelectAll" 
                                                                            runat="server" 
                                                                            onclick="CheckAll_2(this.id, '_chkboxupdateGridH', '')" 
                                                                            />
                                                            <asp:Label ID="_lblGroupType1SelectAll" 
                                                                        runat="server" 
                                                                        Text="ALL" 
                                                                        onclick="CheckAll_2_lbl(this.id, '_lblGroupType1SelectAll', '_chkGroupType1SelectAll', '_chkboxupdateGridH', '')" 
                                                                        style="cursor:default"
                                                                        ></asp:Label>
                                                        </div>
                                                </HeaderTemplate>  
                                                <itemtemplate>
                                                        <asp:checkbox ID="_chkboxupdateGridH" 
                                                                runat="server" />      
                                                </itemtemplate>      
                                        </asp:TemplateColumn >																																							
                                    </Columns>
                            </asp:DataGrid>	
                       
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</asp:Content>
