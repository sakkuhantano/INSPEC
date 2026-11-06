<%@ Page Language="C#" AutoEventWireup="true" MaintainScrollPositionOnPostback="true" CodeBehind="Login.aspx.cs" Inherits="INSPEC.Login" %>
<%@ Register Src="~/UserControls/toast.ascx" TagPrefix="uc1" TagName="toast" %>

<!DOCTYPE html>
<html lang="en" class="h-100">
<head runat="server">
    <meta charset="UTF-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>
    <title>Mobile Inspection | Sign In</title>

    <link rel="stylesheet" type="text/css" href="../WebFolder/bootstrap-5.3.8-dist/css/bootstrap.min.css" />
    <link rel="stylesheet" href="../WebFolder/bootstrap-icons-1.11.3/font/bootstrap-icons.min.css"/>

    <style>
        :root {
            --mi-primary: #045d5d;
            --mi-primary-light: #0a8a8a;
            --mi-dark: #0f2f32;
            --mi-muted: #64748b;
            --mi-surface: #f4f8f8;
        }

        * { box-sizing: border-box; }

        body {
            min-height: 100vh;
            min-height: 100dvh;
            margin: 0;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            color: var(--mi-dark);
            background: #eef5f5;
            overflow-x: hidden;
        }

        /* Animated background bubbles, adapted from the original login page. */
        .page-bg {
            position: fixed;
            inset: 0;
            z-index: 0;
            overflow: hidden;
            background:
                radial-gradient(circle at top left, rgba(10,138,138,.25), transparent 40%),
                radial-gradient(circle at bottom right, rgba(0,0,0,.08), transparent 45%),
                #f4f7fb;
        }

        .page-bg::before,
        .page-bg::after {
            content: "";
            position: absolute;
            border-radius: 50%;
            pointer-events: none;
        }

        .page-bg::before {
            width: 420px;
            height: 420px;
            top: -140px;
            left: -140px;
            background: radial-gradient(circle, rgba(10,138,138,.35), rgba(10,138,138,.05) 70%, transparent 75%);
        }

        .page-bg::after {
            width: 320px;
            height: 320px;
            right: -120px;
            bottom: -120px;
            background: radial-gradient(circle, rgba(0,0,0,.12), rgba(0,0,0,.03) 65%, transparent 75%);
        }

        .bg-bubbles {
            position: absolute;
            inset: 0;
            overflow: hidden;
        }

        .bg-bubbles span {
            position: absolute;
            bottom: -150px;
            border-radius: 50%;
            background: rgba(10,138,138,.18);
            animation: floatUp 18s infinite ease-in-out;
        }

        .bg-bubbles span:nth-child(1) {
            width: 220px;
            height: 220px;
            left: 10%;
            animation-duration: 22s;
        }

        .bg-bubbles span:nth-child(2) {
            width: 140px;
            height: 140px;
            left: 55%;
            animation-duration: 18s;
            background: rgba(0,0,0,.1);
        }

        .bg-bubbles span:nth-child(3) {
            width: 180px;
            height: 180px;
            left: 80%;
            animation-duration: 25s;
        }

        @keyframes floatUp {
            0% { transform: translateY(0) scale(1); opacity: 0; }
            20% { opacity: 1; }
            100% { transform: translateY(-120vh) scale(1.2); opacity: 0; }
        }

        .login-shell {
            width: 100%;
            min-height: 100vh;
            min-height: 100dvh;
            position: relative;
            z-index: 1;
            display: flex;
            align-items: stretch;
            overflow: hidden;
        }

        .login-art {
            width: 46%;
            min-height: 100vh;
            position: relative;
            overflow: hidden;
            display: flex;
            align-items: center;
            padding: 7vw;
            color: #fff;
            background:
                radial-gradient(circle at 15% 20%, rgba(64, 214, 205, .28), transparent 28%),
                radial-gradient(circle at 85% 80%, rgba(255,255,255,.12), transparent 30%),
                linear-gradient(145deg, #063f41 0%, #075c5c 48%, #0b8888 100%);
        }

        .login-art::before,
        .login-art::after {
            content: "";
            position: absolute;
            border-radius: 50%;
            pointer-events: none;
        }

        .login-art::before {
            width: 520px;
            height: 520px;
            right: -260px;
            top: -180px;
            border: 1px solid rgba(255,255,255,.16);
            box-shadow: 0 0 0 70px rgba(255,255,255,.035), 0 0 0 140px rgba(255,255,255,.025);
        }

        .login-art::after {
            width: 260px;
            height: 260px;
            left: -120px;
            bottom: -120px;
            background: rgba(255,255,255,.07);
        }

        .art-content {
            position: relative;
            z-index: 2;
            max-width: 520px;
        }

        .brand-mark {
            width: 58px;
            height: 58px;
            border-radius: 18px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background: rgba(255,255,255,.14);
            border: 1px solid rgba(255,255,255,.2);
            box-shadow: 0 18px 40px rgba(0,0,0,.14);
            font-size: 1.55rem;
            margin-bottom: 28px;
        }

        .brand-kicker {
            font-size: .72rem;
            font-weight: 800;
            letter-spacing: .18em;
            text-transform: uppercase;
            opacity: .78;
        }

        .art-content h1 {
            font-size: clamp(2.4rem, 5vw, 4.5rem);
            line-height: .98;
            letter-spacing: -.055em;
            font-weight: 800;
            margin: 10px 0 18px;
        }

        .art-content .lead {
            max-width: 450px;
            font-size: 1.03rem;
            line-height: 1.75;
            color: rgba(255,255,255,.78);
            margin-bottom: 34px;
        }

        .feature-list {
            display: grid;
            gap: 12px;
        }

        .feature-item {
            display: flex;
            align-items: center;
            gap: 12px;
            color: rgba(255,255,255,.88);
            font-size: .9rem;
        }

        .feature-item i {
            width: 34px;
            height: 34px;
            border-radius: 11px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background: rgba(255,255,255,.1);
            color: #b9fffa;
        }

        .login-panel {
            width: 54%;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 40px 6vw;
            background:
                radial-gradient(circle at 80% 10%, rgba(10,138,138,.08), transparent 30%),
                #f8fbfb;
        }

        .login-card {
            width: 100%;
            max-width: 440px;
        }

        .mobile-brand {
            display: none;
        }

        .login-heading {
            margin-bottom: 30px;
        }

        .login-heading .eyebrow {
            color: var(--mi-primary);
            font-size: .7rem;
            font-weight: 800;
            letter-spacing: .16em;
            text-transform: uppercase;
            margin-bottom: 9px;
        }

        .login-heading h2 {
            font-size: 2rem;
            letter-spacing: -.035em;
            font-weight: 800;
            margin-bottom: 8px;
            color: #123b3d;
        }

        .login-heading p {
            color: var(--mi-muted);
            margin: 0;
            line-height: 1.6;
        }

        .field {
            margin-bottom: 20px;
        }

        .field-label {
            display: block;
            color: #334e52;
            font-size: .72rem;
            font-weight: 800;
            letter-spacing: .09em;
            text-transform: uppercase;
            margin-bottom: 8px;
        }

        .input-wrap {
            position: relative;
        }

        .input-wrap .input-icon {
            position: absolute;
            z-index: 2;
            left: 17px;
            top: 50%;
            transform: translateY(-50%);
            color: #7a9698;
            font-size: 1.05rem;
            pointer-events: none;
        }

        .input-wrap .form-control {
            height: 54px;
            padding: 0 48px;
            border: 1px solid #d6e3e3;
            border-radius: 15px;
            background: #fff;
            color: #17383a;
            font-size: .95rem;
            box-shadow: 0 5px 18px rgba(15,47,50,.035);
            transition: border-color .2s ease, box-shadow .2s ease, transform .2s ease;
        }

        .input-wrap .form-control:focus {
            border-color: #0a8a8a;
            box-shadow: 0 0 0 4px rgba(10,138,138,.11), 0 8px 24px rgba(15,47,50,.06);
        }

        .input-wrap .form-control::placeholder {
            color: #a1b1b2;
        }

        .password-toggle {
            position: absolute;
            z-index: 3;
            right: 15px;
            top: 50%;
            transform: translateY(-50%);
            border: 0;
            background: transparent;
            color: #7a9698;
            padding: 5px;
            line-height: 1;
        }

        .password-toggle:hover { color: var(--mi-primary); }

        .login-button {
            height: 54px;
            border: 0;
            border-radius: 15px;
            width: 100%;
            color: #fff;
            font-weight: 800;
            letter-spacing: .01em;
            background: linear-gradient(135deg, #045d5d, #0a8a8a);
            box-shadow: 0 12px 28px rgba(4,93,93,.22);
            transition: transform .2s ease, box-shadow .2s ease, opacity .2s ease;
        }

        .login-button:hover {
            color: #fff;
            transform: translateY(-1px);
            box-shadow: 0 15px 32px rgba(4,93,93,.28);
        }

        .login-button:disabled {
            opacity: .7;
            transform: none;
        }

        .login-button.btn-loading::after {
            content: "";
            display: inline-block;
            width: 16px;
            height: 16px;
            margin-left: 9px;
            vertical-align: -2px;
            border: 2px solid rgba(255,255,255,.45);
            border-top-color: #fff;
            border-radius: 50%;
            animation: spin .7s linear infinite;
        }

        .security-note {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 7px;
            color: #8a9b9c;
            font-size: .72rem;
            margin-top: 22px;
        }

        .security-note i { color: #0a8a8a; }

        .login-footer {
            margin-top: 38px;
            padding-top: 17px;
            border-top: 1px solid #e1eaea;
            color: #91a1a2;
            font-size: .68rem;
            display: flex;
            justify-content: space-between;
            gap: 15px;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        @media (max-width: 991.98px) {
            .login-art { display: none; }

            .login-panel {
                width: 100%;
                min-height: 100vh;
                padding: 30px 22px;
            }

            .login-card { max-width: 430px; }

            .mobile-brand {
                display: flex;
                align-items: center;
                gap: 12px;
                margin-bottom: 42px;
            }

            .mobile-brand .brand-mark {
                width: 44px;
                height: 44px;
                border-radius: 14px;
                margin: 0;
                background: linear-gradient(135deg, #045d5d, #0a8a8a);
                color: #fff;
                box-shadow: 0 10px 24px rgba(4,93,93,.18);
                font-size: 1.15rem;
            }

            .mobile-brand strong {
                color: #123b3d;
                font-size: .95rem;
                letter-spacing: -.01em;
            }

            .mobile-brand small {
                display: block;
                color: #829596;
                font-size: .65rem;
                margin-top: 1px;
                letter-spacing: .08em;
                text-transform: uppercase;
            }
        }

        @media (max-width: 575.98px) {
            /* Keep the complete login screen inside the phone's visible viewport. */
            body {
                min-height: 100svh;
                min-height: 100dvh;
                overflow-y: auto;
            }

            .login-shell,
            .login-panel {
                min-height: 100svh;
                min-height: 100dvh;
            }

            .login-shell { align-items: center; }

            .login-panel {
                align-items: center;
                background: rgba(248,251,251,.78);
                padding: max(12px, env(safe-area-inset-top)) 19px max(12px, env(safe-area-inset-bottom));
            }

            .login-card { max-width: 430px; }

            .mobile-brand {
                margin-bottom: 16px;
                gap: 10px;
            }

            .mobile-brand .brand-mark {
                width: 38px;
                height: 38px;
                border-radius: 12px;
                font-size: 1rem;
            }

            .mobile-brand strong { font-size: .88rem; }
            .mobile-brand small { font-size: .6rem; }

            .login-heading { margin-bottom: 18px; }
            .login-heading .eyebrow { font-size: .62rem; margin-bottom: 5px; }
            .login-heading h2 { font-size: 1.55rem; margin-bottom: 4px; }
            .login-heading p { font-size: .83rem; line-height: 1.4; }

            .field { margin-bottom: 13px; }
            .field-label { font-size: .66rem; margin-bottom: 5px; }

            .input-wrap .form-control {
                height: 47px;
                border-radius: 12px;
                font-size: .88rem;
                padding-left: 43px;
            }

            .input-wrap .input-icon { left: 14px; }
            .password-toggle { right: 12px; }

            .login-button {
                height: 48px;
                border-radius: 12px;
                font-size: .9rem;
            }

            .security-note {
                margin-top: 13px;
                font-size: .65rem;
                text-align: center;
            }

            .login-footer {
                margin-top: 17px;
                padding-top: 11px;
                flex-direction: row;
                justify-content: space-between;
                gap: 8px;
                font-size: .62rem;
                text-align: left;
            }
        }

        @media (max-width: 575.98px) and (max-height: 700px) {
            .login-panel { align-items: center; }
            .mobile-brand { margin-bottom: 10px; }
            .login-heading { margin-bottom: 12px; }
            .field { margin-bottom: 9px; }
            .security-note { margin-top: 9px; }
            .login-footer { margin-top: 11px; padding-top: 8px; }
        }
    </style>
</head>

<body>
    <div class="page-bg" aria-hidden="true">
        <div class="bg-bubbles">
            <span></span>
            <span></span>
            <span></span>
        </div>
    </div>
    <div class="login-shell">
        <section class="login-art">
            <div class="art-content">
                <div class="brand-mark"><i class="bi bi-clipboard2-check"></i></div>
                <%--<div class="brand-kicker">Global Utility Services</div>--%>
                <h1>Mobile<br/>Inspection</h1>
                <p class="lead">
                    A focused workspace for field inspections, work orders,
                    meter readings and daily operational reporting.
                </p>

                <div class="feature-list">
                    <div class="feature-item">
                        <i class="bi bi-phone"></i>
                        <span>Designed for field operations and mobile devices</span>
                    </div>
                    <div class="feature-item">
                        <i class="bi bi-cloud-arrow-up"></i>
                        <span>Work online or continue working with local data</span>
                    </div>
                    <div class="feature-item">
                        <i class="bi bi-shield-check"></i>
                        <span>Secure access with user-specific authorization</span>
                    </div>
                </div>
            </div>
        </section>

        <section class="login-panel">
            <main class="login-card">
                <div class="mobile-brand">
                    <div class="brand-mark"><i class="bi bi-clipboard2-check"></i></div>
                    <div>
                        <strong>Mobile Inspection</strong>
                        <%--<small>Global Utility Services</small>--%>
                    </div>
                </div>

                <div class="login-heading">
                    <div class="eyebrow">Inspection Management System</div>
                    <h2>Welcome back</h2>
                    <p>Sign in to continue to your inspection workspace.</p>
                </div>

                <form onsubmit="return false;">
                    <div class="field">
                        <label for="txt_Login_UserID" class="field-label">Username</label>
                        <div class="input-wrap">
                            <i class="bi bi-person input-icon"></i>
                            <input type="text"
                                   id="txt_Login_UserID"
                                   class="form-control"
                                   autocomplete="username"
                                   placeholder="Enter your username"/>
                        </div>
                    </div>

                    <div class="field">
                        <label for="txt_Login_Password" class="field-label">Password</label>
                        <div class="input-wrap">
                            <i class="bi bi-lock input-icon"></i>
                            <input type="password"
                                   id="txt_Login_Password"
                                   class="form-control"
                                   autocomplete="current-password"
                                   placeholder="Enter your password"/>
                            <button type="button" class="password-toggle" id="passwordToggle" aria-label="Show password">
                                <i class="bi bi-eye-slash-fill" id="passwordIcon"></i>
                            </button>
                        </div>
                    </div>

                    <button class="login-button" type="button" id="btn_Login">
                        <i class="bi bi-box-arrow-in-right me-2"></i>Sign In
                    </button>
                </form>

                <div class="security-note">
                    <i class="bi bi-shield-lock-fill"></i>
                    <span>Your session is protected by server-side authentication.</span>
                </div>

                <div class="login-footer">
                    <span>© 2026 Mulia Group</span>
                    <span>Version 1.0.0-STABLE</span>
                </div>
            </main>
        </section>
    </div>

    <uc1:toast runat="server" />
    <script type="text/javascript" src="JSCus/GFC_FO.js"></script>
    <script type="text/javascript" src="JSCus/Login.js"></script>
</body>
</html>