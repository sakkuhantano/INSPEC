(function () {
    function restoreTab() {
        var hidden = document.getElementById('hidActiveTab');
        var target = hidden && hidden.value ? hidden.value : '#tab-map';
        var tab = document.querySelector('[data-bs-target="' + target + '"]');
        if (tab && window.bootstrap && window.bootstrap.Tab) {
            window.bootstrap.Tab.getOrCreateInstance(tab).show();
        }
    }
    function renderMapPreviewPdf() {
        var canvas = document.getElementById('inspectionMapPreviewCanvas');
        if (!canvas) return;
        var url = canvas.getAttribute('data-map-url');
        var stage = canvas.parentNode;
        var status = document.getElementById('inspectionMapPreviewStatus');
        if (!url) return;
        if (!window.pdfjsLib) {
            if (status) status.textContent = 'PDF.js tidak berhasil dimuat. Periksa JSCus/pdf.min.js.';
            return;
        }
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = '../JSCus/pdf.worker.min.js';
        window.pdfjsLib.getDocument({ url: url }).promise.then(function (pdf) {
            return pdf.getPage(1);
        }).then(function (page) {
            var base = page.getViewport({ scale: 1 });
            var width = stage.clientWidth;
            if (!width) throw new Error('Area preview denah belum terlihat.');
            var viewport = page.getViewport({ scale: width / base.width });
            stage.style.aspectRatio = base.width + ' / ' + base.height;
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
                status.textContent = 'Gagal memuat denah PDF: ' + (error && error.message ? error.message : error);
            }
            if (window.console && console.error) console.error('Inspection map preview error:', error);
        });
    }
    var inspectionPdfRenderVersion = 0;
    var inspectionPdfRenderTask = null;
    function renderInspectionPdf() {
        var renderVersion = ++inspectionPdfRenderVersion;
        if (inspectionPdfRenderTask && inspectionPdfRenderTask.cancel) {
            try { inspectionPdfRenderTask.cancel(); } catch (ignore) { }
            inspectionPdfRenderTask = null;
        }
        var media = document.getElementById('inspectionPdfCanvas');
        if (!media) return;
        var url = media.getAttribute('data-map-url') || media.getAttribute('data-pdf-url');
        if (!url) return;
        var board = document.getElementById('inspectionCoordinateBoard');
        var content = document.getElementById('inspectionCoordinateContent');
        var status = document.getElementById('inspectionPdfStatus');
        if (media.tagName === 'IMG') {
            media.onload = function () { if (board) board.style.aspectRatio = media.naturalWidth + ' / ' + media.naturalHeight; if (status) status.style.display = 'none'; };
            media.onerror = function () { if (status) { status.style.display = 'flex'; status.textContent = 'Gagal memuat gambar denah JPG/JPEG.'; } };
            media.src = url;
            if (media.complete && media.naturalWidth) { if (board) board.style.aspectRatio = media.naturalWidth + ' / ' + media.naturalHeight; if (status) status.style.display = 'none'; }
            return;
        }
        if (!window.pdfjsLib) { if (status) status.textContent = 'PDF.js tidak berhasil dimuat. Periksa file JSCus/pdf.min.js.'; return; }
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = '../JSCus/pdf.worker.min.js';
        window.pdfjsLib.getDocument({ url: url }).promise.then(function (pdf) { return pdf.getPage(1); }).then(function (page) {
            if (renderVersion !== inspectionPdfRenderVersion) return null;
            var base = page.getViewport({ scale: 1 }); var width = board.clientWidth;
            if (!width) throw new Error('Area denah belum terlihat.');
            var viewport = page.getViewport({ scale: width / base.width });
            board.style.aspectRatio = base.width + ' / ' + base.height; content.style.width = '100%'; content.style.height = '100%';
            media.width = Math.floor(viewport.width * window.devicePixelRatio); media.height = Math.floor(viewport.height * window.devicePixelRatio);
            media.style.width = '100%'; media.style.height = '100%';
            var context = media.getContext('2d'); context.setTransform(window.devicePixelRatio, 0, 0, window.devicePixelRatio, 0, 0);
            inspectionPdfRenderTask = page.render({ canvasContext: context, viewport: viewport });
            return inspectionPdfRenderTask.promise;
        }).then(function () {
            if (renderVersion !== inspectionPdfRenderVersion) return;
            inspectionPdfRenderTask = null;
            if (status) status.style.display = 'none';
        }).catch(function (error) {
            if (renderVersion !== inspectionPdfRenderVersion || (error && error.name === 'RenderingCancelledException')) return;
            inspectionPdfRenderTask = null;
            if (status) { status.style.display = 'flex'; status.textContent = 'Gagal memuat denah: ' + (error && error.message ? error.message : error); }
            if (window.console && console.error) console.error('Inspection map render error:', error);
        });
    }
    document.addEventListener('DOMContentLoaded', function () {
        restoreTab();
        window.requestAnimationFrame(renderMapPreviewPdf);
        window.requestAnimationFrame(renderInspectionPdf);
        var pointModal = document.getElementById('pnlPointEditor');
        if (pointModal) pointModal.addEventListener('shown.bs.modal', function () { window.requestAnimationFrame(renderInspectionPdf); });
        var board = document.getElementById('inspectionCoordinateBoard');
        var content = document.getElementById('inspectionCoordinateContent');
        var markerX = document.getElementById('txtMarkerX');
        var markerY = document.getElementById('txtMarkerY');
        var swapTarget = document.getElementById('hidSwapPointID');
        var swapLabel = document.getElementById('lblSwapTarget');
        if (board && content && markerX && markerY) {
            var zoom = 1, panX = 0, panY = 0, dragging = false, moved = false, startX = 0, startY = 0;
            var zoomLabel = document.getElementById('lblMapZoom');
            function applyView() {
                content.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + zoom + ')';
                // Keep marker circles readable and easy to select while the PDF is zoomed.
                // The parent scales up, so each marker receives the inverse scale.
                var markers = content.querySelectorAll('.inspection-coordinate-marker, .inspection-coordinate-preview');
                for (var i = 0; i < markers.length; i++) {
                    markers[i].style.transform = 'translate(-50%, -50%) scale(' + (1 / zoom) + ')';
                }
                if (zoomLabel) zoomLabel.textContent = Math.round(zoom * 100) + '%';
                board.classList.toggle('inspection-map-zoomed', zoom > 1);
            }
            function setZoom(next, centerX, centerY) {
                next = Math.max(1, Math.min(5, next));
                if (next === zoom) return;
                var rect = board.getBoundingClientRect();
                var cx = centerX == null ? rect.width / 2 : centerX;
                var cy = centerY == null ? rect.height / 2 : centerY;
                var ratio = next / zoom;
                panX = cx - (cx - panX) * ratio;
                panY = cy - (cy - panY) * ratio;
                zoom = next;
                if (zoom === 1) { panX = 0; panY = 0; }
                applyView();
            }
            document.getElementById('btnMapZoomIn').addEventListener('click', function () { setZoom(zoom + 0.25); });
            document.getElementById('btnMapZoomOut').addEventListener('click', function () { setZoom(zoom - 0.25); });
            document.getElementById('btnMapZoomFit').addEventListener('click', function () { zoom = 1; panX = 0; panY = 0; applyView(); });
            board.addEventListener('wheel', function (event) {
                if (!event.ctrlKey && !event.shiftKey) return;
                event.preventDefault();
                var rect = board.getBoundingClientRect();
                setZoom(zoom + (event.deltaY < 0 ? 0.25 : -0.25), event.clientX - rect.left, event.clientY - rect.top);
            }, { passive: false });
            board.addEventListener('pointerdown', function (event) {
                if ((event.target.closest && event.target.closest('.inspection-coordinate-marker')) || zoom <= 1 || event.button !== 0) return;
                dragging = true; moved = false; startX = event.clientX - panX; startY = event.clientY - panY;
                board.setPointerCapture(event.pointerId);
            });
            board.addEventListener('pointermove', function (event) {
                if (!dragging) return;
                var nx = event.clientX - startX, ny = event.clientY - startY;
                if (Math.abs(nx - panX) + Math.abs(ny - panY) > 3) moved = true;
                panX = nx; panY = ny; applyView();
            });
            board.addEventListener('pointerup', function () { dragging = false; });
            board.addEventListener('pointercancel', function () { dragging = false; });
            content.addEventListener('click', function (event) {
                var marker = event.target.closest ? event.target.closest('.inspection-coordinate-marker') : null;
                if (marker) {
                    event.preventDefault(); event.stopPropagation();
                    var activeId = document.getElementById('hidPointID');
                    if (activeId && marker.getAttribute('data-point-id') !== activeId.value) {
                        if (marker.getAttribute('data-can-swap') === '1') {
                            if (swapTarget) swapTarget.value = marker.getAttribute('data-point-id');
                            if (swapLabel) swapLabel.textContent = 'Swap target: ' + marker.getAttribute('title');
                        } else {
                            if (swapTarget) swapTarget.value = '';
                            if (swapLabel) swapLabel.textContent = 'Point lain berada di Profit Center berbeda; swap tidak tersedia.';
                        }
                    }
                }
            });
            board.addEventListener('click', function (event) {
                if (moved) { moved = false; return; }
                var rect = board.getBoundingClientRect();
                var x = Math.max(0, Math.min(100, ((event.clientX - rect.left - panX) / (rect.width * zoom)) * 100));
                var y = Math.max(0, Math.min(100, ((event.clientY - rect.top - panY) / (rect.height * zoom)) * 100));
                markerX.value = x.toFixed(2); markerY.value = y.toFixed(2);
                if (swapTarget) swapTarget.value = '';
                if (swapLabel) swapLabel.textContent = 'Posisi baru dipilih.';
                var preview = document.getElementById('inspectionCoordinatePreview');
                if (!preview) {
                    preview = document.createElement('span');
                    preview.id = 'inspectionCoordinatePreview';
                    preview.className = 'inspection-coordinate-preview';
                    preview.textContent = '+';
                    content.appendChild(preview);
                }
                preview.style.left = x + '%'; preview.style.top = y + '%';
            });
            applyView();
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