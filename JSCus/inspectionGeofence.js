(function () {
    "use strict";

    var map = null;
    var drawnItems = null;
    var previewLayer = null;
    var searchMarker = null;

    function byId(id) {
        return document.getElementById(id);
    }

    function setMessage(message, isError) {
        var host = byId("mapMessage");
        if (!host) return;
        host.textContent = message;
        host.className = "small mt-2 " + (isError ? "text-danger" : "text-muted");
    }

    function readPoints() {
        var field = byId("hidPointsJson");
        if (!field || !field.value) return [];
        try {
            var points = JSON.parse(field.value);
            return Array.isArray(points) ? points : [];
        } catch (error) {
            setMessage("Koordinat polygon tidak dapat dibaca. Coba gambar ulang polygon.", true);
            return [];
        }
    }

    function writePoints(points) {
        var field = byId("hidPointsJson");
        if (!field) return;
        field.value = JSON.stringify(points);
        updateVertexBadge(points.length);
    }

    function updateVertexBadge(count) {
        var badge = byId("mapVertexBadge");
        if (badge) badge.textContent = count + " titik";
    }

    function syncPointsToGrid(points, message) {
        writePoints(points);
        setMessage(message || "Polygon diperbarui. Daftar koordinat sedang disinkronkan.", false);

        // LinkButton performs a normal WebForms postback so the server DataGrid
        // reflects exactly the vertices currently drawn on the map.
        var syncButton = byId("lbtnSyncPoints");
        if (syncButton) {
            window.setTimeout(function () {
                syncButton.click();
            }, 50);
        }
    }

    function pointsFromPolygon(layer) {
        var rings = layer.getLatLngs();
        var ring = rings && rings.length ? rings[0] : [];
        var points = [];
        for (var i = 0; i < ring.length; i++) {
            points.push({
                SequenceNo: i + 1,
                Latitude: Number(ring[i].lat.toFixed(7)),
                Longitude: Number(ring[i].lng.toFixed(7))
            });
        }
        return points;
    }

    function restorePoints(points) {
        drawnItems.clearLayers();
        previewLayer.clearLayers();

        if (points.length >= 3) {
            var latlngs = points.map(function (point) {
                return [Number(point.Latitude), Number(point.Longitude)];
            });
            var polygon = L.polygon(latlngs, {
                color: "#0d6efd",
                weight: 3,
                fillColor: "#0d6efd",
                fillOpacity: 0.16
            });
            drawnItems.addLayer(polygon);
            map.fitBounds(polygon.getBounds(), { padding: [24, 24], maxZoom: 21 });
        } else if (points.length > 0) {
            var previewLatLngs = [];
            points.forEach(function (point) {
                var latlng = [Number(point.Latitude), Number(point.Longitude)];
                previewLatLngs.push(latlng);
                L.circleMarker(latlng, {
                    radius: 6,
                    color: "#fd7e14",
                    fillColor: "#fd7e14",
                    fillOpacity: 1,
                    weight: 2
                }).addTo(previewLayer);
            });
            if (previewLatLngs.length > 1) {
                L.polyline(previewLatLngs, {
                    color: "#fd7e14",
                    weight: 3,
                    dashArray: "5,6"
                }).addTo(previewLayer);
            }
            map.fitBounds(previewLatLngs, { padding: [24, 24], maxZoom: 19 });
        }

        updateVertexBadge(points.length);
    }

    function initMap() {
        var mapElement = byId("geofenceMap");
        if (!mapElement || !window.L) {
            setMessage("Library peta tidak berhasil dimuat. Periksa koneksi internet dan refresh halaman.", true);
            return;
        }

        // Satellite imagery is the default to make building and parking areas easier to identify.
        // Actual image detail still depends on imagery coverage at each location.
        map = L.map(mapElement, {
            zoomControl: false,
            zoomSnap: 0.5,
            maxZoom: 23
        }).setView([-6.2000, 106.8167], 15);

        var satelliteLayer = L.tileLayer(
            "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", {
                minZoom: 1,
                // Esri may return a "Map data not yet available" placeholder
                // for high-zoom tiles in areas without imagery at that resolution.
                // Cap native requests at level 19; Leaflet will upscale those tiles
                // when the user zooms further, instead of requesting missing tiles.
                maxNativeZoom: 18,
                maxZoom: 23,
                attribution: "Source: Esri, Vantor, Earthstar Geographics, and the GIS User Community"
            }
        );

        var streetLayer = L.tileLayer(
            "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
                minZoom: 1,
                maxNativeZoom: 19,
                maxZoom: 23,
                attribution: "&copy; <a href='https://www.openstreetmap.org/copyright' target='_blank' rel='noopener'>OpenStreetMap contributors</a>"
            }
        );

        satelliteLayer.addTo(map);
        L.control.zoom({ position: "bottomright" }).addTo(map);
        L.control.layers({
            "Satelit (Esri)": satelliteLayer,
            "Street (OpenStreetMap)": streetLayer
        }, null, {
            position: "bottomleft",
            collapsed: false
        }).addTo(map);

        drawnItems = new L.FeatureGroup();
        map.addLayer(drawnItems);
        previewLayer = L.layerGroup().addTo(map);

        map.addControl(new L.Control.Draw({
            position: "topright",
            draw: {
                polyline: false,
                rectangle: false,
                circle: false,
                marker: false,
                circlemarker: false,
                polygon: {
                    allowIntersection: false,
                    showArea: true,
                    shapeOptions: {
                        color: "#0d6efd",
                        weight: 3,
                        fillColor: "#0d6efd",
                        fillOpacity: 0.16
                    }
                }
            },
            edit: {
                featureGroup: drawnItems,
                edit: true,
                remove: true
            }
        }));

        map.on(L.Draw.Event.CREATED, function (event) {
            if (event.layerType !== "polygon") return;
            drawnItems.clearLayers();
            previewLayer.clearLayers();
            drawnItems.addLayer(event.layer);
            syncPointsToGrid(pointsFromPolygon(event.layer), "Polygon dibuat. Periksa titik koordinat di DataGrid.");
        });

        map.on(L.Draw.Event.EDITED, function () {
            var layer = null;
            drawnItems.eachLayer(function (item) { layer = item; });
            syncPointsToGrid(layer ? pointsFromPolygon(layer) : [], "Polygon diperbarui. Periksa kembali titik koordinatnya.");
        });

        map.on(L.Draw.Event.DELETED, function () {
            syncPointsToGrid([], "Polygon dihapus. Gambar polygon baru sebelum menyimpan geofence.");
        });

        restorePoints(readPoints());
        window.setTimeout(function () { map.invalidateSize(); }, 150);
        setMessage("Peta satelit siap. Pilih Satelit/Street di kiri bawah; zoom untuk memeriksa batas gedung dan parkiran sebelum menggambar polygon.", false);
    }

    function searchAddress() {
        var input = byId("mapSearchText");
        var button = byId("btnMapSearch");
        var query = input ? input.value.replace(/^\s+|\s+$/g, "") : "";
        if (!query) {
            setMessage("Masukkan nama gedung atau alamat yang ingin dicari.", true);
            if (input) input.focus();
            return;
        }

        if (button) button.disabled = true;
        setMessage("Mencari lokasi di OpenStreetMap...", false);

        var searchQuery = /jakarta|indonesia/i.test(query) ? query : query + ", Jakarta, Indonesia";
        var url = "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=5&countrycodes=id&accept-language=id&q=" + encodeURIComponent(searchQuery);
        fetch(url, { headers: { "Accept": "application/json" } })
            .then(function (response) {
                if (!response.ok) throw new Error("Layanan pencarian lokasi tidak merespons.");
                return response.json();
            })
            .then(function (items) {
                if (!items || !items.length) {
                    setMessage("Lokasi tidak ditemukan. Coba gunakan nama jalan atau alamat yang lebih lengkap.", true);
                    return;
                }

                var item = items.filter(function (candidate) { return /jakarta/i.test(candidate.display_name || ""); })[0] || items[0];
                var lat = Number(item.lat);
                var lon = Number(item.lon);
                if (!isFinite(lat) || !isFinite(lon)) throw new Error("Koordinat hasil pencarian tidak valid.");

                map.setView([lat, lon], 18);
                window.setTimeout(function () { map.invalidateSize(); }, 100);
                if (searchMarker) map.removeLayer(searchMarker);
                searchMarker = L.marker([lat, lon]).addTo(map)
                    .bindPopup(item.display_name || query).openPopup();
                setMessage("Lokasi ditemukan. Peta dibuka pada zoom aman agar citra satelit tersedia. Zoom manual untuk memeriksa detail area sebelum menggambar polygon.", false);
            })
            .catch(function (error) {
                setMessage(error && error.message ? error.message : "Pencarian lokasi gagal.", true);
            })
            .then(function () {
                if (button) button.disabled = false;
            });
    }

    function locateCurrentPosition() {
        if (!navigator.geolocation) {
            setMessage("Browser tidak mendukung geolocation.", true);
            return;
        }
        setMessage("Meminta posisi perangkat...", false);
        navigator.geolocation.getCurrentPosition(function (position) {
            var lat = position.coords.latitude;
            var lon = position.coords.longitude;
            map.setView([lat, lon], 21);
            if (searchMarker) map.removeLayer(searchMarker);
            searchMarker = L.marker([lat, lon]).addTo(map).bindPopup("Posisi perangkat").openPopup();
            setMessage("Peta dipusatkan ke posisi perangkat. Titik ini hanya membantu navigasi peta, bukan otomatis menjadi polygon.", false);
        }, function (error) {
            setMessage(error && error.message ? error.message : "Posisi perangkat tidak dapat diperoleh.", true);
        }, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 });
    }

    document.addEventListener("DOMContentLoaded", function () {
        initMap();

        var searchButton = byId("btnMapSearch");
        var searchInput = byId("mapSearchText");
        var locateButton = byId("btnMapLocate");

        if (searchButton) searchButton.addEventListener("click", searchAddress);
        if (searchInput) searchInput.addEventListener("keydown", function (event) {
            if (event.key === "Enter") {
                event.preventDefault();
                searchAddress();
            }
        });
        if (locateButton) locateButton.addEventListener("click", locateCurrentPosition);
    });
})();
