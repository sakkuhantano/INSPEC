(function () {
    function restoreTab() {
        var hidden = document.getElementById('hidActiveTab');
        var target = hidden && hidden.value ? hidden.value : '#tab-map';
        var tab = document.querySelector('[data-bs-target="' + target + '"]');
        if (tab && window.bootstrap && window.bootstrap.Tab) {
            window.bootstrap.Tab.getOrCreateInstance(tab).show();
        }
    }
    function renderInspectionPdf() {
        var canvas = document.getElementById('inspectionPdfCanvas');
        if (!canvas || !canvas.getAttribute('data-pdf-url')) return;
        var board = document.getElementById('inspectionCoordinateBoard');
        var status = document.getElementById('inspectionPdfStatus');
        if (!window.pdfjsLib) {
            if (status) status.textContent = 'PDF.js tidak berhasil dimuat. Periksa file JSCus/pdf.min.js.';
            return;
        }
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = '../JSCus/pdf.worker.min.js';
        var loadingTask = window.pdfjsLib.getDocument({ url: canvas.getAttribute('data-pdf-url') });
        loadingTask.promise.then(function (pdf) {
            return pdf.getPage(1);
        }).then(function (page) {
            var baseViewport = page.getViewport({ scale: 1 });
            var width = board.clientWidth;
            if (!width) throw new Error('Area denah belum terlihat.');
            var scale = width / baseViewport.width;
            var viewport = page.getViewport({ scale: scale });
            board.style.aspectRatio = baseViewport.width + ' / ' + baseViewport.height;
            canvas.width = Math.floor(viewport.width * window.devicePixelRatio);
            canvas.height = Math.floor(viewport.height * window.devicePixelRatio);
            canvas.style.width = '100%';
            canvas.style.height = '100%';
            var context = canvas.getContext('2d');
            context.setTransform(window.devicePixelRatio, 0, 0, window.devicePixelRatio, 0, 0);
            return page.render({ canvasContext: context, viewport: viewport }).promise;
        }).then(function () {
            if (status) status.style.display = 'none';
        }).catch(function (error) {
            if (status) {
                status.style.display = 'flex';
                status.textContent = 'Gagal memuat PDF: ' + (error && error.message ? error.message : error);
            }
            if (window.console && console.error) console.error('Inspection PDF render error:', error);
        });
    }
    document.addEventListener('DOMContentLoaded', function () {
        restoreTab();
        window.requestAnimationFrame(renderInspectionPdf);
        var board = document.getElementById('inspectionCoordinateBoard');
        var markerX = document.getElementById('txtMarkerX');
        var markerY = document.getElementById('txtMarkerY');
        if (board && markerX && markerY) {
            board.addEventListener('click', function (event) {
                var rect = board.getBoundingClientRect();
                var x = Math.max(0, Math.min(100, ((event.clientX - rect.left) / rect.width) * 100));
                var y = Math.max(0, Math.min(100, ((event.clientY - rect.top) / rect.height) * 100));
                markerX.value = x.toFixed(2);
                markerY.value = y.toFixed(2);
                var preview = document.getElementById('inspectionCoordinatePreview');
                if (!preview) {
                    preview = document.createElement('span');
                    preview.id = 'inspectionCoordinatePreview';
                    preview.className = 'inspection-coordinate-preview';
                    preview.textContent = '+';
                    board.appendChild(preview);
                }
                preview.style.left = x + '%';
                preview.style.top = y + '%';
            });
        }
        document.querySelectorAll('#inspectionMasterTabs [data-bs-toggle="tab"]').forEach(function (tab) {
            tab.addEventListener('shown.bs.tab', function (event) {
                var hidden = document.getElementById('hidActiveTab');
                if (hidden) hidden.value = event.target.getAttribute('data-bs-target');
            });
        });
    });
    window.inspectionMasterSetTab = function (selector) {
        var hidden = document.getElementById('hidActiveTab');
        if (hidden) hidden.value = selector;
    };
})();