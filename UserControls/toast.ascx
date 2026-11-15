<%@ Control Language="C#" AutoEventWireup="true" CodeBehind="toast.ascx.cs" Inherits="INSPEC.toast" %>


<style>
    /* Toast Notification */
    .toast-container {
        position: fixed;
        top: 80px;
        left: 50%;
        transform: translateX(-50%);
        width: min(560px, calc(100vw - 24px));
        z-index: 1100;
        pointer-events: none;
    }

    .custom-toast {
        display: flex;
        align-items: flex-start;
        width: 100%;
        background: #fff;
        border-radius: 10px;
        box-shadow: 0 5px 20px rgba(0, 0, 0, 0.15);
        border-left: 5px solid #0a8a8a;
        overflow: hidden;
        opacity: 0;
        transform: translateY(-15px);
        transition: opacity 0.25s ease, transform 0.25s ease;
        pointer-events: auto;
    }

    .custom-toast.show {
        opacity: 1;
        transform: translateY(0);
    }

    .custom-toast.hide {
        opacity: 0;
        transform: translateY(-15px);
    }

    .custom-toast .toast-body {
        display: flex;
        align-items: flex-start;
        gap: 0.5rem;
        flex: 1 1 auto;
        min-width: 0;
        max-height: 70vh;
        overflow-y: auto;
        padding: 1rem 0.75rem 1rem 1.25rem;
        font-weight: 500;
        color: #333;
        white-space: normal;
        overflow-wrap: anywhere;
        word-break: normal;
    }

    .custom-toast .toast-message {
        min-width: 0;
        flex: 1 1 auto;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
    }

    .custom-toast .toast-close {
        flex: 0 0 auto;
        margin: 0.55rem 0.65rem 0 0;
        padding: 0.25rem 0.4rem;
        border: 0;
        border-radius: 0.375rem;
        background: transparent;
        color: #555;
        font-size: 1.25rem;
        line-height: 1;
        cursor: pointer;
    }

    .custom-toast .toast-close:hover,
    .custom-toast .toast-close:focus {
        color: #111;
        background: rgba(0, 0, 0, 0.06);
    }
</style>

<!-- Toast Container -->
<div class="toast-container"></div>

<script>
    // Show toast notification. Toast stays visible until the user closes it.
    function showToast(arg1, arg2, arg3) {
        let message, type, duration;

        // MODE 1: Object parameter
        if (typeof arg1 === 'object' && arg1 !== null) {
            ({
                message,
                type = 'success',
                duration = 3000
            } = arg1);
        }
        // MODE 2: Legacy parameters
        else {
            message = arg1;
            type = arg2 || 'success';
            duration = arg3 || 3000;
        }

        // duration is retained for backward compatibility; notifications are no longer auto-dismissed.
        void duration;

        if (type === "danger") type = "error";
        if (!message) return;

        // Replace any previous notification so the newest message is immediately visible.
        document.querySelectorAll('.custom-toast').forEach(t => t.remove());

        const toast = document.createElement('div');
        toast.className = 'custom-toast';
        toast.setAttribute('role', type === 'error' ? 'alert' : 'status');
        toast.setAttribute('aria-live', type === 'error' ? 'assertive' : 'polite');

        let icon = 'bi-check-circle-fill';
        let color = '#0a8a8a';

        switch (type) {
            case 'error':
                icon = 'bi-exclamation-triangle-fill';
                color = '#dc3545';
                break;
            case 'warning':
                icon = 'bi-x-circle-fill';
                color = '#ffc107';
                break;
            case 'info':
                icon = 'bi-info-circle-fill';
                color = '#0a6b6b';
                break;
        }

        toast.innerHTML = `
            <div class="toast-body">
                <i class="bi ${icon} me-1 mt-1 flex-shrink-0" style="color:${color}" aria-hidden="true"></i>
                <div class="toast-message">${message}</div>
            </div>
            <button type="button" class="toast-close" aria-label="Tutup notifikasi" title="Tutup">
                <i class="bi bi-x-lg" aria-hidden="true"></i>
            </button>
        `;
        toast.style.borderLeftColor = color;

        const toastContainer = document.querySelector('.toast-container');
        if (!toastContainer) return;

        const closeButton = toast.querySelector('.toast-close');
        closeButton.addEventListener('click', function () {
            toast.classList.remove('show');
            toast.classList.add('hide');
            window.setTimeout(function () {
                if (toast.parentNode) toast.remove();
            }, 250);
        });

        toastContainer.appendChild(toast);
        requestAnimationFrame(() => toast.classList.add('show'));
    }
</script>