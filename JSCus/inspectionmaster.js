(function () {
    var inspectionDraftDbPromise = null;
    var inspectionDraftWritePromise = Promise.resolve();
    var inspectionDraftRestorePromise = Promise.resolve();
    var inspectionDraftObjectUrl = null;

    function inspectionDraftKey() {
        var input = document.getElementById('fuMapPdf');
        return input ? input.getAttribute('data-inspection-draft-key') : null;
    }
    function inspectionSetUploadPostbackMode(control) {
        var input = document.getElementById('fuMapPdf');
        if (!input) return;
        if (!input.getAttribute('data-inspection-original-name') && input.name)
            input.setAttribute('data-inspection-original-name', input.name);
        var originalName = input.getAttribute('data-inspection-original-name');
        var isSaveMap = !!(control && control.id && control.id.indexOf('lbtn_TB_Save') >= 0);
        if (isSaveMap && originalName) input.name = originalName;
        else input.removeAttribute('name');
    }
    function inspectionOpenDraftDb() {
        if (inspectionDraftDbPromise) return inspectionDraftDbPromise;
        inspectionDraftDbPromise = new Promise(function (resolve, reject) {
            if (!window.indexedDB) { reject(new Error('Browser tidak mendukung IndexedDB.')); return; }
            var request = indexedDB.open('INSPEC_InspectionMapDraft', 1);
            request.onupgradeneeded = function () {
                var db = request.result;
                if (!db.objectStoreNames.contains('drafts')) db.createObjectStore('drafts');
            };
            request.onsuccess = function () { resolve(request.result); };
            request.onerror = function () { reject(request.error || new Error('Gagal membuka IndexedDB.')); };
        });
        return inspectionDraftDbPromise;
    }
    function inspectionDraftStore(mode, key, value) {
        return inspectionOpenDraftDb().then(function (db) {
            return new Promise(function (resolve, reject) {
                var tx = db.transaction('drafts', mode);
                var store = tx.objectStore('drafts');
                var request = mode === 'readwrite'
                    ? (value === null ? store.delete(key) : store.put(value, key))
                    : store.get(key);
                var result;
                request.onsuccess = function () { result = request.result; };
                request.onerror = function () { reject(request.error || new Error('IndexedDB request failed.')); };
                tx.oncomplete = function () { resolve(result); };
                tx.onerror = function () { reject(tx.error || new Error('IndexedDB transaction failed.')); };
                tx.onabort = function () { reject(tx.error || new Error('IndexedDB transaction aborted.')); };
            });
        });
    }
    function inspectionShowDraftPreview(blob, fileName) {
        var board = document.getElementById('inspectionCoordinateBoard');
        var content = document.getElementById('inspectionCoordinateContent');
        if (!board || !content) return;
        var extension = (fileName || '').toLowerCase().split('.').pop();
        if (inspectionDraftObjectUrl) URL.revokeObjectURL(inspectionDraftObjectUrl);
        inspectionDraftObjectUrl = URL.createObjectURL(blob);
        var old = document.getElementById('inspectionPdfCanvas');
        if (extension === 'jpg' || extension === 'jpeg' || (blob.type || '').toLowerCase() === 'image/jpeg') {
            var img = old && old.tagName === 'IMG' ? old : document.createElement('img');
            img.id = 'inspectionPdfCanvas';
            img.className = 'inspection-coordinate-pdf';
            img.alt = 'Inspection floor plan';
            img.onload = function () {
                board.style.aspectRatio = img.naturalWidth + ' / ' + img.naturalHeight;
                var status = document.getElementById('inspectionPdfStatus');
                if (status) status.style.display = 'none';
            };
            if (old && old !== img && old.parentNode) old.parentNode.replaceChild(img, old);
            else if (!old) content.insertBefore(img, content.firstChild);
            img.src = inspectionDraftObjectUrl;
        } else {
            var canvas = old && old.tagName === 'CANVAS' ? old : document.createElement('canvas');
            canvas.id = 'inspectionPdfCanvas';
            canvas.className = 'inspection-coordinate-pdf';
            canvas.setAttribute('data-map-url', inspectionDraftObjectUrl);
            if (old && old !== canvas && old.parentNode) old.parentNode.replaceChild(canvas, old);
            else if (!old) content.insertBefore(canvas, content.firstChild);
            var status = document.getElementById('inspectionPdfStatus');
            if (!status) {
                status = document.createElement('div');
                status.id = 'inspectionPdfStatus';
                status.className = 'inspection-pdf-status';
                content.insertBefore(status, canvas.nextSibling);
            }
            status.textContent = 'Memuat denah draft...';
            status.style.display = 'flex';
            window.requestAnimationFrame(renderInspectionPdf);
        }
    }
    function inspectionRestoreDraft() {
        var key = inspectionDraftKey();
        var input = document.getElementById('fuMapPdf');
        if (!key || !input) return Promise.resolve();
        return inspectionDraftStore('readonly', key).then(function (draft) {
            if (!draft || !draft.blob) return;
            if (!input.files || !input.files.length) {
                try {
                    var file = new File([draft.blob], draft.fileName || 'inspection-map.pdf', {
                        type: draft.fileType || draft.blob.type || 'application/pdf',
                        lastModified: draft.lastModified || Date.now()
                    });
                    var transfer = new DataTransfer();
                    transfer.items.add(file);
                    input.files = transfer.files;
                } catch (error) {
                    console.error('Cannot restore inspection map draft to FileUpload:', error);
                }
            }
            // Keep the Blob local during Add Point / other postbacks. Only the
            // toolbar Save action temporarily restores the FileUpload name.
            input.removeAttribute('name');
            inspectionShowDraftPreview(draft.blob, draft.fileName);
        }).catch(function (error) {
            console.error('Inspection map draft restore failed:', error);
        });
    }
    window.inspectionMasterClearDraft = function () {
        var key = inspectionDraftKey();
        var input = document.getElementById('fuMapPdf');
        if (input) input.value = '';
        inspectionDraftWritePromise = inspectionDraftWritePromise.then(function () {
            return key ? inspectionDraftStore('readwrite', key, null) : null;
        }).then(function () {
            if (inspectionDraftObjectUrl) URL.revokeObjectURL(inspectionDraftObjectUrl);
            inspectionDraftObjectUrl = null;
        }).catch(function (error) { console.error('Inspection map draft clear failed:', error); });
        return true;
    };
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
        var media = document.getElementById('inspectionMapPreviewMedia');
        var stage = document.getElementById('inspectionMapPreviewStage');
        var status = document.getElementById('inspectionMapPreviewStatus');
        if (!url || !media || !stage) return;
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
            media.style.width = width + 'px';
            media.style.height = stage.clientHeight + 'px';
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
    function initMapPreviewInteraction() {
        var stage = document.getElementById('inspectionMapPreviewStage');
        var media = document.getElementById('inspectionMapPreviewMedia');
        if (!stage || !media) return;
        var zoom = 1, panX = 0, panY = 0, dragging = false, moved = false, startX = 0, startY = 0;
        var label = document.getElementById('lblMapPreviewZoom');
        var image = media.querySelector('.inspection-image-preview');
        if (image) {
            var sizeImage = function () {
                if (!image.naturalWidth || !image.naturalHeight) return;
                media.style.width = stage.clientWidth + 'px';
                media.style.height = stage.clientHeight + 'px';
                image.style.width = '100%';
                image.style.height = '100%';
                image.style.maxWidth = 'none';
                image.style.maxHeight = 'none';
                image.style.objectFit = 'fill';
            };
            image.addEventListener('load', sizeImage);
            if (image.complete) sizeImage();
        }
        function apply() {
            media.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + zoom + ')';
            if (label) label.textContent = Math.round(zoom * 100) + '%';
            stage.classList.toggle('inspection-map-preview-zoomed', zoom > 1);
        }
        function setZoom(next, cx, cy) {
            next = Math.max(1, Math.min(5, next));
            if (next === zoom) return;
            var rect = stage.getBoundingClientRect();
            var x = cx == null ? rect.width / 2 : cx;
            var y = cy == null ? rect.height / 2 : cy;
            var ratio = next / zoom;
            panX = x - (x - panX) * ratio;
            panY = y - (y - panY) * ratio;
            zoom = next;
            if (zoom === 1) { panX = 0; panY = 0; }
            apply();
        }
        var zoomIn = document.getElementById('btnMapPreviewZoomIn');
        var zoomOut = document.getElementById('btnMapPreviewZoomOut');
        var fit = document.getElementById('btnMapPreviewZoomFit');
        if (zoomIn) zoomIn.addEventListener('click', function () { setZoom(zoom + 0.25); });
        if (zoomOut) zoomOut.addEventListener('click', function () { setZoom(zoom - 0.25); });
        if (fit) fit.addEventListener('click', function () { zoom = 1; panX = 0; panY = 0; apply(); });
        stage.addEventListener('wheel', function (event) {
            if (!event.ctrlKey && !event.shiftKey) return;
            event.preventDefault();
            var rect = stage.getBoundingClientRect();
            setZoom(zoom + (event.deltaY < 0 ? 0.25 : -0.25), event.clientX - rect.left, event.clientY - rect.top);
        }, { passive: false });
        stage.addEventListener('pointerdown', function (event) {
            if (zoom <= 1 || event.button !== 0) return;
            dragging = true; moved = false;
            startX = event.clientX - panX; startY = event.clientY - panY;
            stage.setPointerCapture(event.pointerId);
        });
        stage.addEventListener('pointermove', function (event) {
            if (!dragging) return;
            var nx = event.clientX - startX, ny = event.clientY - startY;
            if (Math.abs(nx - panX) + Math.abs(ny - panY) > 3) moved = true;
            panX = nx; panY = ny; apply();
        });
        stage.addEventListener('pointerup', function () { dragging = false; });
        stage.addEventListener('pointercancel', function () { dragging = false; });
        apply();
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
        var draftInput = document.getElementById('fuMapPdf');
        if (draftInput) {
            draftInput.addEventListener('change', function () {
                var file = draftInput.files && draftInput.files[0];
                var key = inspectionDraftKey();
                if (!file || !key) return;
                if (!draftInput.getAttribute('data-inspection-original-name') && draftInput.name)
                    draftInput.setAttribute('data-inspection-original-name', draftInput.name);
                inspectionDraftWritePromise = inspectionDraftWritePromise.then(function () {
                    return inspectionDraftStore('readwrite', key, {
                        blob: file, fileName: file.name, fileType: file.type,
                        lastModified: file.lastModified
                    });
                }).then(function () { inspectionShowDraftPreview(file, file.name); });
            });
            inspectionDraftRestorePromise = inspectionRestoreDraft();
        }
        document.addEventListener('click', function (event) {
            var control = event.target && event.target.closest
                ? event.target.closest('a,button,input[type="submit"]') : null;
            if (!control || control.id === 'fuMapPdf' || control.getAttribute('data-inspection-click-ready') === '1') return;
            var href = control.getAttribute('href') || '';
            var clickCode = control.getAttribute('onclick') || '';
            var isPostback = /__doPostBack|WebForm_DoPostBackWithOptions/.test(href + ' ' + clickCode) ||
                control.type === 'submit' || control.getAttribute('type') === 'submit';
            if (!isPostback) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            Promise.all([inspectionDraftWritePromise, inspectionDraftRestorePromise]).then(function () {
                inspectionSetUploadPostbackMode(control);
                control.setAttribute('data-inspection-click-ready', '1');
                control.click();
                control.removeAttribute('data-inspection-click-ready');
            }).catch(function (error) {
                console.error('Cannot prepare inspection map draft before postback:', error);
                alert('Gagal menyiapkan draft denah di browser. Silakan coba lagi.');
            });
        }, true);
        if (document.forms && document.forms.length) {
            document.forms[0].addEventListener('submit', function (event) {
                if (document.forms[0].getAttribute('data-inspection-draft-ready') === '1') return;
                event.preventDefault();
                Promise.all([inspectionDraftWritePromise, inspectionDraftRestorePromise]).then(function () {
                    document.forms[0].setAttribute('data-inspection-draft-ready', '1');
                    if (document.forms[0].requestSubmit) document.forms[0].requestSubmit(event.submitter || undefined);
                    else document.forms[0].submit();
                });
            }, true);
        }
        restoreTab();
        if (window.bootstrap && window.bootstrap.Tooltip) {
            document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (element) {
                window.bootstrap.Tooltip.getOrCreateInstance(element);
            });
        }
        window.requestAnimationFrame(renderMapPreviewPdf);
        window.requestAnimationFrame(renderInspectionPdf);
        initMapPreviewInteraction();
        var pointModal = document.getElementById('pnlPointEditor');
        if (pointModal) pointModal.addEventListener('shown.bs.modal', function () { window.requestAnimationFrame(renderInspectionPdf); });
        var board = document.getElementById('inspectionCoordinateBoard');
        var content = document.getElementById('inspectionCoordinateContent');
        var markerX = document.getElementById('txtMarkerX');
        var markerY = document.getElementById('txtMarkerY');
        var swapTarget = document.getElementById('hidSwapPointID');
        var swapLabel = document.getElementById('lblSwapTarget');
        var clearCoordinateButton = document.getElementById('btnClearCoordinate');
        if (clearCoordinateButton) {
            clearCoordinateButton.addEventListener('click', function (event) {
                event.preventDefault();
                event.stopPropagation();
                var xField = document.getElementById('txtMarkerX');
                var yField = document.getElementById('txtMarkerY');
                if (xField) xField.value = '';
                if (yField) yField.value = '';
                var preview = document.getElementById('inspectionCoordinatePreview');
                if (preview && preview.parentNode) preview.parentNode.removeChild(preview);
                var swapTargetField = document.getElementById('hidSwapPointID');
                var swapTargetLabel = document.getElementById('lblSwapTarget');
                if (swapTargetField) swapTargetField.value = '';
                if (swapTargetLabel) swapTargetLabel.textContent = 'Koordinat dikosongkan.';
            });
        }
        if (board && content && markerX && markerY) {
            var zoom = 1, panX = 0, panY = 0, dragging = false, moved = false, startX = 0, startY = 0;
            var zoomLabel = document.getElementById('lblMapZoom');
            function updateMarkerScale() {
                // Markers are children of the zoomed content, so compensate for
                // the content scale. Include dynamically-created preview markers.
                var markers = content.querySelectorAll('.inspection-coordinate-marker, .inspection-coordinate-preview');
                var inverseScale = 1 / zoom;
                for (var i = 0; i < markers.length; i++) {
                    markers[i].style.transform = 'translate(-50%, -50%) scale(' + inverseScale + ')';
                }
            }
            function applyView() {
                content.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + zoom + ')';
                updateMarkerScale();
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
                // A preview may be created after the last zoom event. Apply the
                // current inverse scale immediately so its visible size stays fixed.
                updateMarkerScale();
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