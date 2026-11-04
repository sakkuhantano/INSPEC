<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="WAL.ErrMsg.aspx.cs" Inherits="WAL.ErrMsg" %>

<!DOCTYPE html>

<html xmlns="http://www.w3.org/1999/xhtml">
<head runat="server">
    <title><asp:Literal ID="litErrMsg" runat="server" Text="" /></title>
    <link rel="shortcut icon" type="image/x-icon" href="../WebFolder/Images/favicon.ico" />

    <%--
        <link rel="Stylesheet" type="text/css" href="../WebFolder/Css/styles.css" />
    --%>
    <link rel="stylesheet" type="text/css" href="../../WebFolder/bootstrap/css/bootstrap.min.css"/>
    <link rel="Stylesheet" type="text/css" href="../../WebFolder/Css/styles_2.css" />
    

	<script type="text/javascript" src="../WebFolder/Scripts/DisableKey.js"></script>
</head>
<body>
    <form id="form1" runat="server">
    <div>
        <%--
        <table cellspacing="0" cellpadding="0" width="100%" border="0">
		<tr>
			<td valign="middle" align="center">
			    <br /><br /><br /><br />
				<strong><font face="Verdana" size="4">Message</font></strong>
			</td>
		</tr>				
		<tr>					
			<td valign="top" colspan="2" align="center">		
				<br/><br/><br/>
				<asp:Label id="lblErrorDesc" CssClass="ErrorMsg" runat="server"></asp:Label>						
				<br/><br/><br/><br/>
			</td>
		</tr>
		<tr>
			<td valign="middle" align="center">
				<a href="javascript:history.back();">Back</a> to previous page.
			</td>
		</tr>
	    </table>
        --%>

        <table class="fz-custom1" border="0" cellspacing="0" cellpadding="0" style="margin:auto;width:99%;height:100vh;">
        <tr>
            <td>
                <table cellspacing="0" cellpadding="0" width="100%" border="0">
		        <tr>
			        <td valign="middle" align="center">
				        <strong><font face="Verdana" size="4">Message</font></strong>
			        </td>
		        </tr>	
                <tr>
                    <td>
                        <br/>
                    </td>
                </tr>			
		        <tr>					
			        <td valign="top" colspan="2" align="center">		   
                        <div id="diverr" class="row justify-content-center align-items-center font-weight-bold" style="width:100%; margin:auto;">
                            <div class="col-10 alert alert-info shadow-sm d-flex justify-content-center align-items-center" style="height:100%;min-height:150px;">
                                  <asp:Label id="lblErrorDesc" runat="server"></asp:Label>						
                            </div>
                        </div>
			        </td>
		        </tr>
                <tr>
                    <td>
                        <br/>
                    </td>
                </tr>
		        <tr>
			        <td valign="middle" align="center">
                        <div class="fz-custom1">
                            <a href="javascript:history.back();">Back</a> to previous page.
                        </div>
			        </td>
		        </tr>
	            </table>

            </td>
        </tr>
        </table>
    </div>
    </form>
</body>
</html>
