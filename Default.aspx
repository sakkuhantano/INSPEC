<%@ Page Language="C#" AutoEventWireup="true" MaintainScrollPositionOnPostback="true" CodeBehind="Default.aspx.cs" Inherits="INSPEC._Default" %>

<!DOCTYPE html>

<html xmlns="http://www.w3.org/1999/xhtml">
<head runat="server">
    <meta charset="UTF-8" />
	<meta name="viewport" content="width=device-width, initial-scale=1.0" />

    <title><asp:Literal ID="litTitle" runat="server" Text="" /></title>
    <link rel="shortcut icon" type="image/x-icon" href="../WebFolder/Images/Icon_128x128-R.png" />
    
    <link rel="stylesheet" type="text/css" href="../WebFolder/bootstrap-5.3.0-dist/css/bootstrap.min.css"/>
    
    <link rel="stylesheet" type="text/css" href="../WebFolder/fontawesome-free-6.4.0-web/css/all.min.css"/>
    <link rel="stylesheet" type="text/css" href="../WebFolder/bootstrap-icons-1.10.5/font/bootstrap-icons.min.css"/>
    
    <script type="text/javascript" src="../WebFolder/jquery/jquery-3.7.0.min.js"></script>
    <script type="text/javascript" src="../WebFolder/bootstrap-5.3.0-dist/js/bootstrap.bundle.min.js"></script>
    
    <link rel="Stylesheet" type="text/css" href="../WebFolder/css/styles_2.css" />
    <script type="text/javascript" src="../WebFolder/Scripts/JScript.js"></script>
    
    <style>
        /*.table-fixed thead {
          width: 97%;
        }*/
        /*.table-fixed tbody {
          height: 230px;
          overflow-y: auto;
          width: 100%;
        }*/
        /*.table-fixed thead, .table-fixed tbody, .table-fixed tr, .table-fixed td, .table-fixed th {
          display: block;
        }*/
        /*.table-fixed tbody td, .table-fixed thead > tr> th {
          float: left;
          border-bottom-width: 0;
        }*/
    </style>
</head>

<body id="body1" runat="server">
    <form id="form1" runat="server">
    <div>
        <table class="fz-custom1" border="0" cellspacing="0" cellpadding="0" style="margin:auto;width:99%;height:100vh;">
        <tr style="height:67px;">
            <td>
                <div class="row justify-content-center rounded shadow bg-custom3" style="margin:auto;">
                    <div class="col px-1">
                        <table border="0" cellspacing="0" cellpadding="0" style="width:100%;margin:auto;height:65px;max-width:1366px;">
                        <tr>
                            <td style="width:215px;text-align:left;border:0px solid red;">
                                <table border="0" cellspacing="0" cellpadding="0" style="width:100%;">
                                <tr>
                                    <td style="width:10px;"></td>
                                    <td style="width:40px;">
                                        <a href="#">
                                            <img src="../WebFolder/Images/muliaLogo.png" align='absmiddle' width="50px" height="35px"  alt="" border="0" />
                                        </a>
                                    </td>
                                    <td style="width:3px;"></td>
                                    <td>
                                        <span class="CUS-shimmer" style="font-size:16px;font-weight:normal;letter-spacing:-0.5px;color:white;">MULIA APPLICATION</span>
                                        <%--<span style="font-family:'Courier New', Courier, monospace; font-size:16px;font-weight:bold;color:white;">MULIA APPLICATION</span>--%>
                                    </td>
                                </tr>
                                </table>
                            </td>
                            <td style="text-align:center;border:0px solid red;">
                            </td>
                            <td style="width:150px;text-align:right;border:0px solid red;">
                                <table border="0" cellspacing="0" cellpadding="0" style="width:100%;">
                                <tr>                                    
                                    <td>
                                        
                                    </td>
                                    <td style="width:10px;"></td>
                                </tr>
                                </table>
                            </td>
                        </tr>
                        </table>
                    </div>
                </div>
            </td>
        </tr>
        <tr style="height:5px;"><td></td></tr>
        <tr>
            <td>
                <style>
                    .css_img_login_cover {
                        max-height:700px;
                    }

                    .css_bor_login {
                        border-radius:15px 65px 15px 65px;
                    }

                    @media only screen and (max-width: 576px) {
                        /*.css_img_login_cover {
                            max-height:500px;
                        }*/
                        .css_img_login_cover {
                            object-fit:cover; /* Do not scale the image */
                            object-position: bottom; /* Center the image within the element */
                            width: 100%;
                            max-height: 240px;
                            margin-bottom: 0rem;
                        }

                        .css_bor_login {
                            border-radius:20px;
                        }
                    }
                </style>
                <%--
                background-color:whitesmoke;border-radius:20px;
                col col-sm-10 col-md-10 col-lg-9 col-xl-8
                --%>                    
                <div class="row my-2 py-4 justify-content-center align-items-center" style="margin:auto;max-width:1366px;">
                    <div class="col col-sm-12 col-md-11 col-lg-10 col-xl-10" style="max-width:97%;">
                        <div class="row border shadow-lg bg-white css_bor_login">
                            <div class="col-sm-6 col-xl-7">
                                <img id="img_login_cover" src="../WebFolder/Images/skyBridge.jpg"
                                    class="d-block img-fluid w-100 my-3 css_img_login_cover css_bor_login"
                                    />
                            </div>
                            <div class="col-sm-6 col-xl-5 d-flex flex-column justify-content-center">
                                <div class="row mt-3">
                                    <div class="col-sm text-center">
                                        <span style="font-size:18px;font-weight:bold;"> 
                                            SIGN IN
                                        </span> 
                                    </div>
                                </div>
                                <div class="row mt-0 mt-lg-3">
                                    <div class="col-sm">
                                    </div>
                                </div>
                                <div class="row mt-3 justify-content-center">
                                    <div class="col-sm-11">
                                        <span style="font-size:12px;font-weight:bold;"> 
                                            USERNAME
                                        </span> 
                                    </div>
                                </div>
                                <div class="row mt-2 justify-content-center">
                                    <div class="col-sm-11">
                                        <div class="input-group">
                                            <div class="input-group-prepend" style="position: absolute;left:3px;top:5px;z-index:3;">
                                                <span class="input-group-text bg-transparent border-0">
                                                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-person-fill" viewBox="0 0 16 16">
                                                        <path d="M3 14s-1 0-1-1 1-4 6-4 6 3 6 4-1 1-1 1H3Zm5-6a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z"/>
                                                    </svg>
                                                </span>
                                            </div>
                                            <asp:TextBox ID="txt_Login_UserID"
                                                        runat="server"
                                                        CssClass="form-control CUS-placeholder-1 py-2"
                                                        Style="border-radius:20px;font-size:13px;padding-left:38px;z-index:2;"
                                                        placeholder="User Name"
                                                        onkeypress="javascript:PostBackCtrlID_Enter(event.keyCode,'lbtn_Login');if(event.keyCode == 13){lbtn_Login.style.display='none';document.getElementById('lbtn_LoginLoading').style.display = '';}"
                                                        ></asp:TextBox>
                                        </div>
                                    </div>
                                </div>
                                <div class="row mt-0 mt-lg-1">
                                    <div class="col-sm">
                                    </div>
                                </div>
                                <div class="row mt-4 justify-content-center">
                                    <div class="col-sm-11">
                                        <span style="font-size:12px;font-weight:bold;"> 
                                            PASSWORD
                                        </span> 
                                    </div>
                                </div>
                                <div class="row mt-2 justify-content-center">
                                    <div class="col-sm-11">
                                        <div class="input-group">
                                            <div class="input-group-prepend" style="position: absolute;left:3px;top:4px;z-index:3;">
                                                <span class="input-group-text bg-transparent border-0" style="font-size:13px;">
                                                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-lock-fill" viewBox="0 0 16 16">
                                                        <path d="M8 1a2 2 0 0 1 2 2v4H6V3a2 2 0 0 1 2-2zm3 6V3a3 3 0 0 0-6 0v4a2 2 0 0 0-2 2v5a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2z"/>
                                                    </svg>
                                                </span>
                                            </div>
                                            <asp:TextBox ID="txt_Login_Password"
                                                        runat="server"
                                                        Class="form-control CUS-placeholder-1 py-2"
                                                        Style="border-radius:20px;font-size:13px;padding-left:38px;padding-right:38px;z-index:2;"
                                                        placeholder="Password"
                                                        onkeypress="javascript:PostBackCtrlID_Enter(event.keyCode,'lbtn_Login');if(event.keyCode == 13){lbtn_Login.style.display='none';document.getElementById('lbtn_LoginLoading').style.display = '';}"
                                                        ></asp:TextBox>
                                            <div class="input-group-append" style="position: absolute;right:3px;top:4px;z-index:3;">
                                                <span id="spn_Login_Password_icon" class="input-group-text bg-transparent border-0" style="cursor:pointer;font-size:13px;">
                                                    <svg id="ico_Login_Password_hide" style="display:'';" width="1.2em" height="1.2em" viewBox="0 0 16 16" class="bi bi-eye-slash" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
                                                        <path d="M13.359 11.238C15.06 9.72 16 8 16 8s-3-5.5-8-5.5a7.028 7.028 0 0 0-2.79.588l.77.771A5.944 5.944 0 0 1 8 3.5c2.12 0 3.879 1.168 5.168 2.457A13.134 13.134 0 0 1 14.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755-.165.165-.337.328-.517.486l.708.709z"/>
                                                        <path d="M11.297 9.176a3.5 3.5 0 0 0-4.474-4.474l.823.823a2.5 2.5 0 0 1 2.829 2.829l.822.822zm-2.943 1.299l.822.822a3.5 3.5 0 0 1-4.474-4.474l.823.823a2.5 2.5 0 0 0 2.829 2.829z"/>
                                                        <path d="M3.35 5.47c-.18.16-.353.322-.518.487A13.134 13.134 0 0 0 1.172 8l.195.288c.335.48.83 1.12 1.465 1.755C4.121 11.332 5.881 12.5 8 12.5c.716 0 1.39-.133 2.02-.36l.77.772A7.029 7.029 0 0 1 8 13.5C3 13.5 0 8 0 8s.939-1.721 2.641-3.238l.708.709z"/>
                                                        <path fill-rule="evenodd" d="M13.646 14.354l-12-12 .708-.708 12 12-.708.708z"/>
                                                    </svg>
                                                    <svg id="ico_Login_Password_show" style="display:none;" width="1.2em" height="1.2em" viewBox="0 0 16 16" class="bi bi-eye" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
                                                        <path fill-rule="evenodd" d="M16 8s-3-5.5-8-5.5S0 8 0 8s3 5.5 8 5.5S16 8 16 8zM1.173 8a13.134 13.134 0 0 0 1.66 2.043C4.12 11.332 5.88 12.5 8 12.5c2.12 0 3.879-1.168 5.168-2.457A13.134 13.134 0 0 0 14.828 8a13.133 13.133 0 0 0-1.66-2.043C11.879 4.668 10.119 3.5 8 3.5c-2.12 0-3.879 1.168-5.168 2.457A13.133 13.133 0 0 0 1.172 8z"/>
                                                        <path fill-rule="evenodd" d="M8 5.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM4.5 8a3.5 3.5 0 1 1 7 0 3.5 3.5 0 0 1-7 0z"/>
                                                    </svg>
                                                </span>
                                            </div>
                                            <asp:HiddenField ID="hf_Login_Password" runat="server" Value="0"/>
                                        </div>
                                    </div>
                                </div>
                                <div class="row mt-1 justify-content-center" style="height:25px;">
                                    <div class="col-sm-11">
                                        <asp:Label runat="server" ID="lbl_Login_Invalid" ForeColor="red" Font-Size="Smaller"></asp:Label>                                
                                    </div>
                                </div>
                                <div class="row mt-0 mt-lg-2">
                                    <div class="col-sm">
                                    </div>
                                </div>
                                <div class="row mt-2 justify-content-center">
                                    <div class="col col-sm-11">
                                        <div class="row justify-content-end">
                                            <div class="col ">
                                                <asp:LinkButton ID="lbtn_Login" 
                                                                runat="server"
                                                                class="btn CUS-btn-PColor-2 shadow w-100 CUS-fz-5 py-2" 
                                                                OnClick="lbtn_Login_Click" 
                                                                OnClientClick="this.style.display='none';document.getElementById('lbtn_LoginLoading').style.display = '';"
                                                                style="height:36px;border-radius:20px;"
                                                                >
                                                    <%--<svg xmlns="http://www.w3.org/2000/svg" style="margin-bottom:3px;margin-right:2px;" width="16" height="16" fill="currentColor" class="bi bi-rocket-takeoff-fill" viewBox="0 0 16 16">
                                                        <path d="M12.17 9.53c2.307-2.592 3.278-4.684 3.641-6.218.21-.887.214-1.58.16-2.065a3.578 3.578 0 0 0-.108-.563 2.22 2.22 0 0 0-.078-.23V.453c-.073-.164-.168-.234-.352-.295a2.35 2.35 0 0 0-.16-.045 3.797 3.797 0 0 0-.57-.093c-.49-.044-1.19-.03-2.08.188-1.536.374-3.618 1.343-6.161 3.604l-2.4.238h-.006a2.552 2.552 0 0 0-1.524.734L.15 7.17a.512.512 0 0 0 .433.868l1.896-.271c.28-.04.592.013.955.132.232.076.437.16.655.248l.203.083c.196.816.66 1.58 1.275 2.195.613.614 1.376 1.08 2.191 1.277l.082.202c.089.218.173.424.249.657.118.363.172.676.132.956l-.271 1.9a.512.512 0 0 0 .867.433l2.382-2.386c.41-.41.668-.949.732-1.526l.24-2.408Zm.11-3.699c-.797.8-1.93.961-2.528.362-.598-.6-.436-1.733.361-2.532.798-.799 1.93-.96 2.528-.361.599.599.437 1.732-.36 2.531Z"/>
                                                        <path d="M5.205 10.787a7.632 7.632 0 0 0 1.804 1.352c-1.118 1.007-4.929 2.028-5.054 1.903-.126-.127.737-4.189 1.839-5.18.346.69.837 1.35 1.411 1.925Z"/>
                                                    </svg>--%>
                                                    SIGN IN
                                                </asp:LinkButton>
                                                <%--<br /><br />--%>
                                                <button 
                                                    id="lbtn_LoginLoading" 
                                                    type="button" 
                                                    class="btn CUS-btn-PColor-2 shadow w-100 CUS-fz-5 py-2" 
                                                    style="height:36px;border-radius:20px;display:none;"
                                                    >
                                                    <span style="margin-top:1px;" class="spinner-border spinner-border-sm align-top" role="status" aria-hidden="true"></span> 
                                                    <span class="align-top"> Loading... </span>
                                                </button>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                                <div class="row mt-4 mt-lg-0">
                                    <div class="col-sm">
                                    </div>
                                </div>
                                <div class="row mt-3 mt-lg-0">
                                    <div class="col-sm">
                                    </div>
                                </div> 
                            </div>
                        </div>
                    </div>
                </div>
            </td>
        </tr>
        <tr style="height:5px;"><td></td></tr>
        <tr style="height:3px;vertical-align:bottom;">
            <td>
                <div class="row justify-content-center rounded shadow bg-custom3" style="margin:auto;height:40px;">
                    <div class="col my-2 text-white text-center" style="max-width:1366px;">
                        <%--<a href="javascript:openWindow('/NEW_EXE/ip_messenger.exe','_IPM',200,100);"  title="Click here to run/download IPM">
                            <img src="../WebFolder/Images/IPM.png" alt="Click here to run/download IP Messenger" width="16px" height="16px" border="0" align='absmiddle'/>
                        </a>
                        &nbsp;·&nbsp;
                        <a href="JavaScript:fullscreen();" title="Click here to full screen">
                            <img src="../WebFolder/Images/17x17_view_fullscreen.png" alt="Click here to full screen" border="0" align='absmiddle'/>
                        </a>
                        &nbsp;·&nbsp;
                        <a href="javascript:openWindow('/ToolsLib/npviewer.exe','_CRViewer',200,100);"  title="Click here to run/download crystal report viewer">
                            <img src="../WebFolder/Images/CRViewer.gif" alt="Click here to run/download crystal report viewer" width="16px" height="16px" border="0" align='absmiddle'/>
                        </a>
                        &nbsp;·&nbsp;
                        <asp:LinkButton id="lBtnPrintTest" Runat="server" 
                                        text="Print Test"
                                        CausesValidation="False" 
                                        title="Click here to Print Test">
                                        <img src="../WebFolder/Images/PrintTest.gif" alt="Click here to Print Test" border="0" align='absmiddle'/>
                        </asp:LinkButton>
                        &nbsp;·&nbsp;
                        <a href="javascript:openWindow('/ToolsLib/ie_tab_Mozilla.rar','_IETabForMozilla',200,100);" title="Click here to download IE Tab For Mozilla">
                            <img src="../WebFolder/Images/20x20_IETab.png"  width="17px" height="17px" alt="Click here to download IE Tab For Mozilla" border="0" align='absmiddle'/>
                        </a>
                        &nbsp;·&nbsp;
                        <a href="javascript:openWindow('/ToolsLib/Firefox Setup 9.0.1.exe','_IETabForMozilla',200,100);" title="Click here to download Mozilla">
                            <img src="../WebFolder/Images/20x20_Firefox.png"  width="17px" height="17px" alt="Click here to download Mozilla" border="0" align='absmiddle'/>
                        </a>         
                        &nbsp;·&nbsp;
                        <asp:LinkButton runat="server" ID="lbtnKuisioner" Visible="true" title="Click here to download Kuisioner"><img src="../WebFolder/images/true.png" width="17px" height="17px" border="0" align='absmiddle' alt="Click here to download Mozilla"/></asp:LinkButton>
                        &nbsp;·&nbsp;
                        <asp:LinkButton runat="server" ID="lbtnTrainingDoc" Visible="true" title="Click here to download Training Documents"><img src="../WebFolder/images/true.png" width="17px" height="17px" border="0" align='absmiddle' alt="Click here to download Mozilla"/></asp:LinkButton>--%>
                        
                        <span id="spn_MuliaGroup" class="CUS-shimmer CUS-fz-5 text-white px-3 align-middle">MULIA GROUP</span> 
                    </div>
                </div>
            </td>
        </tr>
        </table>

        <script>
            function F_DisplayPassStyle(p_hf_showpassiconID, p_txtboxID, p_showPassID, p_hidePassID) {
                if ($("#" + p_hf_showpassiconID).val() == "1") {
                    $("#" + p_txtboxID).attr('type', 'text');
                    $("#" + p_hidePassID).css("display", "none");
                    $("#" + p_showPassID).css("display", "");
                } else if ($('#' + p_hf_showpassiconID).val() == "0") {
                    $("#" + p_txtboxID).attr('type', 'password');
                    $("#" + p_hidePassID).css("display", "");
                    $("#" + p_showPassID).css("display", "none");
                }
            }

            function F_SetValue_hf_showpassicon(p_hf_showpassiconID) {
                if ($('#' + p_hf_showpassiconID).val() == "1") {
                    $('#' + p_hf_showpassiconID).val("0");
                }
                else if ($('#' + p_hf_showpassiconID).val() == "0") {
                    $('#' + p_hf_showpassiconID).val("1");
                }
            }

            F_DisplayPassStyle("hf_Login_Password", "txt_Login_Password", "ico_Login_Password_show", "ico_Login_Password_hide");

            $(document).ready(function () {
                $("#spn_Login_Password_icon").on('click', function (event) {
                    F_SetValue_hf_showpassicon("hf_Login_Password");
                    F_DisplayPassStyle("hf_Login_Password", "txt_Login_Password", "ico_Login_Password_show", "ico_Login_Password_hide");
                });
            });

        </script>
    </div>
    </form>
</body>
</html>
