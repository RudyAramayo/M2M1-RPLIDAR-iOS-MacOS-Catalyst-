//
//  RPLidarViewController.swift
//  test
//
//  Created by ROB on 10/5/21.
//  Copyright © 2021 OrbitusRobotics. All rights reserved.
//
import UIKit
import CoreLocation
import SlamwareSDK
import UniformTypeIdentifiers

class RPLidarViewController: UIViewController {
    private let passthroughServer = RPLidarPassthroughServer.shared
    private var rpLidar: RPLidarController? { passthroughServer.lidar }
    private var autoNetClient: AutoNetClient { passthroughServer.autoNetClient }
    private let openStreetMapView = ROBOpenStreetMapView(frame: .zero)
    private let locationManager = CLLocationManager()
    private var latestDeviceLocation: CLLocation?
    private var locationTimeoutWorkItem: DispatchWorkItem?
    private var transportStatusTimer: Timer?
    private var lastOpenStreetMapSearchUptime: TimeInterval = 0
    private var mapZoomScale: CGFloat = 1
    private let transportStatusLabel = UILabel()
    private let transportRouteLabel = UILabel()
    private let pairButton = UIButton(type: .system)
    private let forgetPairingButton = UIButton(type: .system)
    private let mapStatusLabel = UILabel()
    private let resetMapButton = UIButton(type: .system)
    private let loadMapButton = UIButton(type: .system)
    private let saveMapButton = UIButton(type: .system)
    private let destinationsButton = UIButton(type: .system)
    private var mapDocumentOperation = MapDocumentOperation.none
    private var relocalizationMonitorGeneration = 0
    let distance_filter: Float = 1.0
    let angleFilter: Float = 0.50
    
    private var queue: DispatchQueue { passthroughServer.operationQueue }
    
    var currentLocation: RPLocation?
    var currentMap: RPMap?
    var currentCompositeMap: RPCompositeMap?
    var currentPose: RPPose?
    var currentLaserPoints: [RPLidarScanPoint]?
    
    @IBOutlet var rpLidarImageView: UIImageView!
    @IBOutlet var rpLidarPolarView: RPLidarPolarView!
    @IBOutlet var locationLabel: UILabel!
    @IBOutlet var rotationLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        installOpenStreetMap()
        configureLocationServices()
        passthroughServer.delegate = self
        passthroughServer.start()
        installTransportControls()
        installMapControls()
        refreshPublisherIdentity()
        refreshTransportStatus()
        transportStatusTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(refreshTransportStatus),
            userInfo: nil,
            repeats: true
        )
        rpLidarImageView.contentMode = .scaleAspectFit
        rpLidarPolarView.contentMode = .scaleAspectFit
        applyMapZoom()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startLocationUpdatesIfAuthorized()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        locationManager.stopUpdatingLocation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // The image and overlay were authored with different storyboard
        // frames. Matching their bounds and center makes scaleAspectFit use
        // the exact same bitmap rectangle in both layers on every device.
        rpLidarImageView.bounds = rpLidarPolarView.bounds
        rpLidarImageView.center = rpLidarPolarView.center
        applyMapZoom()
    }

    deinit {
        transportStatusTimer?.invalidate()
        locationTimeoutWorkItem?.cancel()
        locationManager.stopUpdatingLocation()
        passthroughServer.detach(self)
    }

    private func installOpenStreetMap() {
        openStreetMapView.translatesAutoresizingMaskIntoConstraints = false
        openStreetMapView.mapDelegate = self
        view.insertSubview(openStreetMapView, at: 0)
        NSLayoutConstraint.activate([
            openStreetMapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            openStreetMapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            openStreetMapView.topAnchor.constraint(equalTo: view.topAnchor),
            openStreetMapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // These storyboard views were the old full-screen map renderer. Keep
        // them as data sinks for compatibility, but do not let them cover the
        // OpenStreetMap surface or its controls.
        rpLidarImageView.isHidden = true
        rpLidarPolarView.isHidden = true
        locationLabel.superview?.superview?.isHidden = true

        if let recent = RPLidarDestinationHistoryStore().destinations.first {
            openStreetMapView.showDestination(
                latitude: recent.latitude,
                longitude: recent.longitude,
                title: recent.displayName
            )
        }
    }

    private func configureLocationServices() {
        locationManager.delegate = self
        locationManager.distanceFilter = 2
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private func startLocationUpdatesIfAuthorized() {
        guard CLLocationManager.locationServicesEnabled() else {
            mapStatusLabel.text = "Location Services are disabled on this device"
            mapStatusLabel.textColor = .systemYellow
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            mapStatusLabel.text = "Finding current location…"
            mapStatusLabel.textColor = .white
            scheduleLocationTimeoutIfNeeded()
            locationManager.requestLocation()
            locationManager.startUpdatingLocation()
        case .notDetermined:
            mapStatusLabel.text = "RPLidar needs location permission to center the map"
            mapStatusLabel.textColor = .systemYellow
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            mapStatusLabel.text = "Location denied — allow RPLidar in System Settings"
            mapStatusLabel.textColor = .systemYellow
        @unknown default:
            break
        }
    }

    private func scheduleLocationTimeoutIfNeeded() {
        guard latestDeviceLocation == nil else { return }
        locationTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.latestDeviceLocation == nil else { return }
            self.mapStatusLabel.text = "No Mac location fix — check Location Services and Wi-Fi"
            self.mapStatusLabel.textColor = .systemYellow
        }
        locationTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }
    
    @IBAction func clearMapAction() {
        let alert = UIAlertController(
            title: "Reset the current map?",
            message: "This clears the map in Slamware and starts a new live map. Saved .robomap files are not deleted.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset Map", style: .destructive) { [weak self] _ in
            self?.resetCurrentMap()
        })
        present(alert, animated: true)
    }
    
    @IBAction func zoomAction(sender: UISlider) {
        mapZoomScale = max(0.01, CGFloat(sender.value) / 100)
        applyMapZoom()
    }

    private func applyMapZoom() {
        let transform = CGAffineTransform(scaleX: mapZoomScale, y: mapZoomScale)
        rpLidarImageView.transform = transform
        rpLidarPolarView.transform = transform
    }
    
    func reconnect() {
        passthroughServer.requestReconnect()
    }

    private func installMapControls() {
        mapStatusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        mapStatusLabel.text = "Map: live mapping"
        mapStatusLabel.textColor = .white
        mapStatusLabel.textAlignment = .center
        mapStatusLabel.numberOfLines = 2

        resetMapButton.setTitle("Reset Map", for: .normal)
        resetMapButton.tintColor = .systemRed
        resetMapButton.addTarget(self, action: #selector(clearMapAction), for: .touchUpInside)

        loadMapButton.setTitle("Load Map…", for: .normal)
        loadMapButton.addTarget(self, action: #selector(chooseMapToLoad), for: .touchUpInside)

        saveMapButton.setTitle("Save Map…", for: .normal)
        saveMapButton.addTarget(self, action: #selector(saveCurrentMap), for: .touchUpInside)

        destinationsButton.setTitle("Destinations…", for: .normal)
        destinationsButton.addTarget(
            self,
            action: #selector(showDestinationChooser),
            for: .touchUpInside
        )

        let firstButtonRow = UIStackView(arrangedSubviews: [
            resetMapButton,
            loadMapButton
        ])
        let secondButtonRow = UIStackView(arrangedSubviews: [
            saveMapButton,
            destinationsButton
        ])
        [firstButtonRow, secondButtonRow].forEach { row in
            row.axis = .horizontal
            row.alignment = .fill
            row.distribution = .fillEqually
            row.spacing = 8
        }

        let buttonStack = UIStackView(arrangedSubviews: [firstButtonRow, secondButtonRow])
        buttonStack.axis = .vertical
        buttonStack.alignment = .fill
        buttonStack.spacing = 4

        let stack = UIStackView(arrangedSubviews: [mapStatusLabel, buttonStack])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        stack.layer.cornerRadius = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -52),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            buttonStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
    }

    @objc private func showDestinationChooser() {
        let chooser = RPLidarDestinationChooserViewController()
        chooser.initialDeviceLocation = latestDeviceLocation ?? locationManager.location
        chooser.onDestinationSelected = { [weak self, weak chooser] destination in
            self?.selectDestination(
                name: destination.displayName,
                latitude: destination.latitude,
                longitude: destination.longitude
            )
            chooser?.dismiss(animated: true)
        }

        let navigationController = UINavigationController(rootViewController: chooser)
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.selectedDetentIdentifier = .large
        }
        present(navigationController, animated: true)
    }

    private func presentDestinationSearch() {
        let alert = UIAlertController(
            title: "OpenStreetMap Destination",
            message: "Search for a place, path, or address.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Place, path, or address"
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
            field.returnKeyType = .search
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Search", style: .default) { [weak self, weak alert] _ in
            let query = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !query.isEmpty else {
                self?.presentMapNotice(
                    title: "Destination required",
                    message: "Enter a place or address to search OpenStreetMap."
                )
                return
            }
            self?.searchOpenStreetMap(for: query)
        })
        present(alert, animated: true)
    }

    private func searchOpenStreetMap(for query: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastOpenStreetMapSearchUptime >= 1 else {
            presentMapNotice(
                title: "Please wait",
                message: "OpenStreetMap search is limited to one submitted request per second."
            )
            return
        }
        lastOpenStreetMapSearchUptime = now

        let configuredEndpoint = UserDefaults.standard.string(forKey: "ROBNominatimEndpoint")
        let endpoint = configuredEndpoint?.isEmpty == false
            ? configuredEndpoint!
            : "https://nominatim.openstreetmap.org/search"
        guard var components = URLComponents(string: endpoint) else {
            presentMapNotice(
                title: "Search unavailable",
                message: "The configured OpenStreetMap search endpoint is invalid."
            )
            return
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else {
            presentMapNotice(
                title: "Search unavailable",
                message: "The configured OpenStreetMap search endpoint is invalid."
            )
            return
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 12
        )
        request.setValue(
            "RPLidar/1 (destination selection; https://orbitusrobotics.com)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            Locale.preferredLanguages.first ?? "en",
            forHTTPHeaderField: "Accept-Language"
        )
        mapStatusLabel.text = "Searching OpenStreetMap…"
        mapStatusLabel.textColor = .white

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard error == nil,
                      (200 ... 299).contains(statusCode),
                      let data,
                      data.count <= 500_000 else {
                    self.mapStatusLabel.text = "OpenStreetMap search failed"
                    self.mapStatusLabel.textColor = .systemRed
                    self.presentMapNotice(
                        title: "OpenStreetMap search failed",
                        message: error?.localizedDescription ??
                            "The search service did not return a usable response."
                    )
                    return
                }

                let results = (try? JSONDecoder().decode(
                    [RPLidarNominatimPlace].self,
                    from: data
                ))?.filter(\.isValid) ?? []
                guard !results.isEmpty else {
                    self.mapStatusLabel.text = "No destinations found"
                    self.mapStatusLabel.textColor = .systemYellow
                    self.presentMapNotice(
                        title: "No destinations found",
                        message: "Try a more specific OpenStreetMap search."
                    )
                    return
                }
                self.presentSearchResults(Array(results.prefix(3)))
            }
        }.resume()
    }

    private func presentSearchResults(_ results: [RPLidarNominatimPlace]) {
        let chooser = UIAlertController(
            title: "Choose Destination",
            message: "OpenStreetMap search results.",
            preferredStyle: .alert
        )
        for result in results {
            let shortName = result.displayName.count > 80
                ? String(result.displayName.prefix(77)) + "…"
                : result.displayName
            chooser.addAction(UIAlertAction(title: shortName, style: .default) { [weak self] _ in
                self?.selectDestination(
                    name: result.displayName,
                    latitude: result.latitude,
                    longitude: result.longitude
                )
            })
        }
        chooser.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(chooser, animated: true)
    }

    private func selectDestination(name: String, latitude: Double, longitude: Double) {
        let historyStore = RPLidarDestinationHistoryStore()
        guard let destination = historyStore.record(
            name: name,
            latitude: latitude,
            longitude: longitude
        ) else {
            presentMapNotice(title: "Invalid destination", message: "That coordinate is not usable.")
            return
        }
        openStreetMapView.showDestination(
            latitude: destination.latitude,
            longitude: destination.longitude,
            title: destination.displayName
        )
        mapStatusLabel.text = "Destination: \(destination.displayName)"
        mapStatusLabel.textColor = .white
    }

    @objc private func chooseMapToLoad() {
        guard case .none = mapDocumentOperation else { return }

        mapDocumentOperation = .importing
        setMapControlsBusy(true, status: "Choose a .robomap file…")
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [Self.roboMapContentType],
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func saveCurrentMap() {
        guard case .none = mapDocumentOperation else { return }

        setMapControlsBusy(true, status: "Reading map and pose from RPLidar…")
        queue.async { [weak self] in
            guard let self else { return }

            do {
                guard let lidar = self.rpLidar else {
                    throw RPLidarControllerError.notConnected
                }
                guard let map = try lidar.getCurrentMap() else {
                    throw RPLidarMapFileError.mapUnavailable
                }
                guard let pose = try lidar.getPose() else {
                    throw RPLidarMapFileError.poseUnavailable
                }

                let archive = ROBOMap(map: map, pose: pose)
                let data = try archive.encoded()
                let exportURL = try self.makeTemporaryMapURL(
                    named: self.getCurrentLocationName(),
                    data: data
                )
                self.currentMap = map
                self.currentPose = pose

                DispatchQueue.main.async {
                    self.mapDocumentOperation = .exporting(exportURL)
                    self.mapStatusLabel.text = "Choose where to save the map…"

                    let picker = UIDocumentPickerViewController(
                        forExporting: [exportURL],
                        asCopy: true
                    )
                    picker.delegate = self
                    self.present(picker, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.setMapControlsBusy(false, status: "Map save failed", isError: true)
                    self.presentMapNotice(title: "Unable to save map", error: error)
                }
            }
        }
    }

    private func resetCurrentMap() {
        relocalizationMonitorGeneration += 1
        setMapControlsBusy(true, status: "Resetting map…")
        let resetStartedAt = Date()

        queue.async { [weak self] in
            guard let self else { return }

            do {
                guard let lidar = self.rpLidar else {
                    throw RPLidarControllerError.notConnected
                }
                try lidar.resetMap()
                self.passthroughServer.invalidateSnapshotsAfterMapReset()
                self.currentMap = nil
                self.currentCompositeMap = nil
                self.currentPose = nil
                self.currentLocation = nil
                self.currentLaserPoints = nil
                let elapsed = Date().timeIntervalSince(resetStartedAt)

                DispatchQueue.main.async {
                    self.rpLidarImageView.image = nil
                    self.openStreetMapView.updateOccupancyMapImage(nil)
                    self.openStreetMapView.updateLaserPoints([], headingRadians: 0)
                    self.rpLidarPolarView.mapFrame = nil
                    self.rpLidarPolarView.robotPose = nil
                    self.rpLidarPolarView.laserPoints = []
                    self.rpLidarPolarView.setNeedsDisplay()
                    self.locationLabel.text = "X: 0.0   Y: 0.0   Z: 0.0"
                    self.rotationLabel.text = "Yaw: 0.0   Pitch: 0.0   Roll: 0.0"
                    self.setMapControlsBusy(
                        false,
                        status: String(format: "Map reset in %.1fs — live mapping", elapsed)
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.setMapControlsBusy(false, status: "Map reset failed", isError: true)
                    self.presentMapNotice(title: "Unable to reset map", error: error)
                }
            }
        }
    }

    private func loadMap(from url: URL) {
        setMapControlsBusy(true, status: "Loading \(url.lastPathComponent)…")

        queue.async { [weak self] in
            guard let self else { return }

            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let archive = try ROBOMap.decoded(from: Data(contentsOf: url))
                let map = try archive.makeRPMap()
                let pose = try archive.makeRPPose()
                guard let lidar = self.rpLidar else {
                    throw RPLidarControllerError.notConnected
                }

                try lidar.loadMapAndRecoverLocalization(map, pose: pose)
                self.currentMap = map
                self.currentCompositeMap = nil
                self.currentPose = pose
                self.currentLocation = pose.location
                self.currentLaserPoints = nil

                DispatchQueue.main.async {
                    let occupancyImage = self.mask(
                        from: archive.data.bytes,
                        dataWidth: map.dimension.width,
                        dataHeight: map.dimension.height
                    )
                    self.rpLidarImageView.image = occupancyImage
                    let mapFrame = self.mapFrame(from: map)
                    self.openStreetMapView.updateOccupancyMapImage(
                        occupancyImage,
                        worldSizeMeters: mapFrame?.worldSize
                    )
                    self.rpLidarPolarView.mapFrame = mapFrame
                    self.rpLidarPolarView.robotPose = RPLidarPose2D(
                        location: CGPoint(x: CGFloat(pose.location.x), y: CGFloat(pose.location.y)),
                        yaw: CGFloat(pose.yaw())
                    )
                    self.rpLidarPolarView.laserPoints = []
                    self.rpLidarPolarView.setNeedsDisplay()
                    self.beginRelocalizationMonitoring(mapName: url.deletingPathExtension().lastPathComponent)
                }
            } catch {
                DispatchQueue.main.async {
                    self.setMapControlsBusy(false, status: "Map load failed", isError: true)
                    self.presentMapNotice(title: "Unable to load map", error: error)
                }
            }
        }
    }

    private func confirmLoadMap(from url: URL) {
        let alert = UIAlertController(
            title: "Load \(url.lastPathComponent)?",
            message: "This replaces the current Slamware map and starts automatic relocalization. The droid may move or rotate while matching its position, so keep the area clear.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.setMapControlsBusy(false, status: "Map load cancelled")
        })
        alert.addAction(UIAlertAction(title: "Load & Relocalize", style: .default) { [weak self] _ in
            self?.loadMap(from: url)
        })
        present(alert, animated: true)
    }

    private func beginRelocalizationMonitoring(mapName: String) {
        relocalizationMonitorGeneration += 1
        let generation = relocalizationMonitorGeneration
        setMapControlsBusy(
            true,
            status: "Relocalizing on \(mapName)…",
            allowReset: true
        )
        scheduleRelocalizationPoll(generation: generation, mapName: mapName)
    }

    private func scheduleRelocalizationPoll(generation: Int, mapName: String) {
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }

            do {
                let state = try self.rpLidar?.relocalizationState() ?? .failed
                DispatchQueue.main.async {
                    guard generation == self.relocalizationMonitorGeneration else { return }

                    switch state {
                    case .waiting(let progress), .running(let progress):
                        let percent = Self.relocalizationPercent(progress)
                        self.setMapControlsBusy(
                            true,
                            status: "Relocalizing on \(mapName)… \(percent)%",
                            allowReset: true
                        )
                        self.scheduleRelocalizationPoll(generation: generation, mapName: mapName)
                    case .finished:
                        self.setMapControlsBusy(false, status: "Localized — \(mapName) locked")
                        self.passthroughServer.requestMapRefresh()
                    case .idle:
                        self.setMapControlsBusy(false, status: "Loaded \(mapName)")
                    case .stopped:
                        self.setMapControlsBusy(false, status: "Relocalization stopped", isError: true)
                        self.presentMapNotice(
                            title: "Relocalization stopped",
                            message: "The saved map is loaded, but the droid pose was not recovered. Retry Load Map or reset the map before navigating."
                        )
                    case .failed:
                        self.setMapControlsBusy(false, status: "Relocalization failed", isError: true)
                        self.presentMapNotice(
                            title: "Relocalization failed",
                            message: "The saved map is loaded, but Slamware could not match the droid to it. Move the droid into the mapped area and try Load Map again."
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.relocalizationMonitorGeneration else { return }
                    self.setMapControlsBusy(false, status: "Relocalization failed", isError: true)
                    self.presentMapNotice(title: "Unable to relocalize", error: error)
                }
            }
        }
    }

    private func setMapControlsBusy(
        _ busy: Bool,
        status: String,
        isError: Bool = false,
        allowReset: Bool = false
    ) {
        mapStatusLabel.text = status
        mapStatusLabel.textColor = isError ? .systemRed : .white
        loadMapButton.isEnabled = !busy
        saveMapButton.isEnabled = !busy
        destinationsButton.isEnabled = !busy
        // Reset remains available so a long or failed hardware recovery can
        // always be cancelled by starting a fresh map.
        resetMapButton.isEnabled = !busy || allowReset
    }

    private func presentMapNotice(title: String, error: Error) {
        presentMapNotice(title: title, message: error.localizedDescription)
    }

    private func presentMapNotice(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func makeTemporaryMapURL(named suggestedName: String, data: Data) throws -> URL {
        let invalidCharacters = CharacterSet.alphanumerics.inverted
        let sanitizedName = suggestedName
            .components(separatedBy: invalidCharacters)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let mapName = sanitizedName.isEmpty ? "RPLidar-Map" : sanitizedName
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RPLidarMapExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(mapName).appendingPathExtension("robomap")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func removeTemporaryMap(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private static var roboMapContentType: UTType {
        UTType(
            exportedAs: "com.orbitusrobotics.robomap",
            conformingTo: .json
        )
    }

    private static func relocalizationPercent(_ progress: Double) -> Int {
        guard progress.isFinite else { return 0 }
        let percentage = progress <= 1 ? progress * 100 : progress
        return Int(min(max(percentage, 0), 100).rounded())
    }

    private func installTransportControls() {
        transportStatusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        transportStatusLabel.textAlignment = .center
        transportStatusLabel.numberOfLines = 2

        transportRouteLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        transportRouteLabel.textAlignment = .center
        transportRouteLabel.numberOfLines = 2
        transportRouteLabel.adjustsFontSizeToFitWidth = true
        transportRouteLabel.minimumScaleFactor = 0.82
        transportRouteLabel.layer.cornerRadius = 8
        transportRouteLabel.clipsToBounds = true
        transportRouteLabel.accessibilityLabel = "Lidar telemetry transport"
        transportRouteLabel.accessibilityIdentifier = "RPLidarTransportRoute"
        transportRouteLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true

        pairButton.setTitle("Pair RPLidar…", for: .normal)
        pairButton.addTarget(self, action: #selector(showPairingPrompt), for: .touchUpInside)

        forgetPairingButton.setTitle("Forget Local Pairing", for: .normal)
        forgetPairingButton.addTarget(self, action: #selector(confirmForgetPairing), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            transportStatusLabel,
            transportRouteLabel,
            pairButton,
            forgetPairingButton
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        stack.layer.cornerRadius = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 230)
        ])
    }

    private func refreshPublisherIdentity() {
        passthroughServer.refreshPublisherIdentity()
    }

    @objc private func refreshTransportStatus() {
        let paired = autoNetClient.isPairingConfigured
        let stored = autoNetClient.hasStoredPairing
        let connected = autoNetClient.isConnected
        let route = ROBLidarTelemetryTransportRoute.resolve(
            publishingEnabled: paired && !autoNetClient.pairingNeedsReplacement,
            localIPCReady: passthroughServer.isLocalIPCReady,
            quicReady: connected
        )
        updateTransportRouteIndicator(route, quicStandbyReady: connected)
        if autoNetClient.pairingNeedsReplacement {
            transportStatusLabel.text = "Cerebro: re-pair required\nCertificate or code rejected"
            transportStatusLabel.textColor = .systemRed
        } else if paired && connected {
            transportStatusLabel.text = "Cerebro: authenticated\nRole: Lidar publisher"
            transportStatusLabel.textColor = .systemGreen
        } else if paired {
            transportStatusLabel.text = "Cerebro: reconnecting\nRole: Lidar publisher"
            transportStatusLabel.textColor = .systemYellow
        } else if stored {
            transportStatusLabel.text = "Cerebro: pairing invalid\nReplace or forget pairing"
            transportStatusLabel.textColor = .systemRed
        } else {
            transportStatusLabel.text = "Cerebro: not paired\nPublishing disabled"
            transportStatusLabel.textColor = .systemRed
        }
        pairButton.setTitle(stored ? "Replace Pairing…" : "Pair RPLidar…", for: .normal)
        forgetPairingButton.isEnabled = stored
    }

    private func updateTransportRouteIndicator(
        _ route: ROBLidarTelemetryTransportRoute,
        quicStandbyReady: Bool
    ) {
        switch route {
        case .localIPC:
            transportRouteLabel.text = quicStandbyReady
                ? "● LOCAL IPC • FAST\nQUIC standby ready"
                : "● LOCAL IPC • FAST\nQUIC standby reconnecting"
            transportRouteLabel.textColor = .white
            transportRouteLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.82)
            transportRouteLabel.accessibilityValue = quicStandbyReady
                ? "Local IPC fast path, QUIC standby ready"
                : "Local IPC fast path, QUIC standby reconnecting"
        case .quicFallback:
            transportRouteLabel.text = "● QUIC FALLBACK\nLocal IPC reconnecting"
            transportRouteLabel.textColor = .white
            transportRouteLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.88)
            transportRouteLabel.accessibilityValue = "QUIC network fallback"
        case .disconnected:
            transportRouteLabel.text = "● DISCONNECTED\nWaiting for Cerebro transports"
            transportRouteLabel.textColor = .white
            transportRouteLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.82)
            transportRouteLabel.accessibilityValue = "No active telemetry transport"
        case .publishingDisabled:
            transportRouteLabel.text = "● PUBLISHING DISABLED\nValid pairing required"
            transportRouteLabel.textColor = .secondaryLabel
            transportRouteLabel.backgroundColor = .secondarySystemBackground
            transportRouteLabel.accessibilityValue = "Publishing disabled"
        }
    }

    @objc private func showPairingPrompt() {
        let alert = UIAlertController(
            title: "Pair RPLidar with Cerebro",
            message: "In Cerebro, issue a new credential with the Lidar Publisher role, then paste the complete ROBCTL2 code here. Operator-controller credentials are rejected.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = AutoNetClient.pairingCodeFormat
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Pair", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let code = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !code.isEmpty else {
                self.presentTransportNotice(
                    title: "Pairing code required",
                    message: "Paste the complete ROBCTL2 code issued by Cerebro."
                )
                return
            }
            var error: NSError?
            guard self.autoNetClient.installPairingCode(code, error: &error) else {
                self.presentTransportNotice(
                    title: "Pairing rejected",
                    message: error?.localizedDescription ?? "Cerebro pairing credential was invalid."
                )
                return
            }
            self.refreshPublisherIdentity()
            self.refreshTransportStatus()
        })
        present(alert, animated: true)
    }

    @objc private func confirmForgetPairing() {
        let alert = UIAlertController(
            title: "Forget local pairing?",
            message: "This removes the credential from this app. To revoke it for every copy, revoke the device in Cerebro.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Forget", style: .destructive) { [weak self] _ in
            guard let self else { return }
            var error: NSError?
            guard self.autoNetClient.removePairingCode(&error) else {
                self.presentTransportNotice(
                    title: "Unable to forget pairing",
                    message: error?.localizedDescription ?? "The local Keychain entry could not be removed."
                )
                return
            }
            self.refreshPublisherIdentity()
            self.refreshTransportStatus()
        })
        present(alert, animated: true)
    }

    private func presentTransportNotice(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func getCurrentLocationName() -> String {
        if let networkStatus = rpLidar?.networkStatus,
           let ssid = networkStatus["ssid"], !ssid.isEmpty {
            return ssid
        }
        return "HOME"
    }
    
    func mask(from data: [UInt8], dataWidth: Int32, dataHeight: Int32) -> UIImage? {
        let width  = Int(dataWidth)
        let height = Int(dataHeight)
        guard let displayBytes = RPLidarMapRaster.displayBytes(
            from: data,
            width: width,
            height: height
        ) else {
            print("invalid map data or dimensions")
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        guard
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue),
            let buffer = context.data?.bindMemory(to: UInt8.self, capacity: width * height)
        else {
            return nil
        }
        
        for index in 0 ..< width * height {
            buffer[index] = displayBytes[index]
        }
        
        return context.makeImage().flatMap { UIImage(cgImage: $0) }
    }

    private func mapFrame(from map: RPMap) -> RPLidarMapFrame? {
        RPLidarMapFrame(
            origin: CGPoint(
                x: CGFloat(map.origin.x),
                y: CGFloat(map.origin.y)
            ),
            pixelDimensions: CGSize(
                width: CGFloat(map.dimension.width),
                height: CGFloat(map.dimension.height)
            ),
            resolution: CGSize(
                width: CGFloat(map.resolution.x),
                height: CGFloat(map.resolution.y)
            )
        )
    }
}

extension RPLidarViewController: RPLidarPassthroughServerDelegate {
    func passthroughServer(
        _ server: RPLidarPassthroughServer,
        didReceive scan: RPLidarScanSnapshot
    ) {
        currentLocation = scan.location
        currentPose = scan.pose
        currentLaserPoints = scan.laserPoints

        if let location = scan.location {
            locationLabel.text = String(
                format: "X: %.3f   Y: %.3f   Z: %.3f",
                location.x,
                location.y,
                location.z
            )
        }
        if let pose = scan.pose {
            rotationLabel.text = String(
                format: "Yaw: %.3f   Pitch: %.3f   Roll: %.3f",
                pose.yaw(),
                pose.pitch(),
                pose.roll()
            )
            rpLidarPolarView.robotPose = RPLidarPose2D(
                location: CGPoint(
                    x: CGFloat(pose.location.x),
                    y: CGFloat(pose.location.y)
                ),
                yaw: CGFloat(pose.yaw())
            )
        }
        rpLidarPolarView.laserPoints = scan.laserPoints
        rpLidarPolarView.setNeedsDisplay()

        let yaw = scan.pose.map { Double($0.yaw()) } ?? 0
        let headingRadians = abs(yaw) > Double.pi * 2
            ? yaw * Double.pi / 180
            : yaw
        let points = scan.laserPoints.map {
            String(format: "%.6f:%.6f", Double($0.distance), Double($0.angle))
        }
        openStreetMapView.updateLaserPoints(points, headingRadians: headingRadians)
    }

    func passthroughServer(
        _ server: RPLidarPassthroughServer,
        didReceive snapshot: RPLidarMapSnapshot
    ) {
        let map = snapshot.map
        currentMap = map
        currentCompositeMap = snapshot.compositeMap
        let occupancyImage = mask(
            from: Array(map.data),
            dataWidth: map.dimension.width,
            dataHeight: map.dimension.height
        )
        rpLidarImageView.image = occupancyImage
        let mapFrame = mapFrame(from: map)
        openStreetMapView.updateOccupancyMapImage(
            occupancyImage,
            worldSizeMeters: mapFrame?.worldSize
        )
        rpLidarPolarView.mapFrame = mapFrame
        rpLidarPolarView.setNeedsDisplay()
    }
}

extension RPLidarViewController: ROBOpenStreetMapViewDelegate {
    func openStreetMapViewDidRequestSearch(_ mapView: ROBOpenStreetMapView) {
        presentDestinationSearch()
    }

    func openStreetMapViewDidRequestCurrentLocation(_ mapView: ROBOpenStreetMapView) {
        if locationManager.authorizationStatus == .denied {
            let alert = UIAlertController(
                title: "Location access is off",
                message: "Allow RPLidar under Privacy & Security → Location Services, then try again.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
            present(alert, animated: true)
        } else {
            startLocationUpdatesIfAuthorized()
        }
    }

    func openStreetMapViewDidRequestOverlayCalibration(_ mapView: ROBOpenStreetMapView) {
        let editor = RPLidarOverlayCalibrationViewController(
            calibration: mapView.overlayCalibration,
            baseMapStyle: mapView.baseMapStyle
        )
        editor.onCalibrationChanged = { [weak self] calibration in
            self?.openStreetMapView.setOverlayCalibration(calibration)
        }
        editor.onBaseMapStyleChanged = { [weak self] style in
            self?.openStreetMapView.setBaseMapStyle(style)
        }
        let navigationController = UINavigationController(rootViewController: editor)
        navigationController.modalPresentationStyle = .pageSheet
        navigationController.preferredContentSize = CGSize(width: 480, height: 390)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    func openStreetMapView(
        _ mapView: ROBOpenStreetMapView,
        didSelectDestinationLatitude latitude: Double,
        longitude: Double
    ) {
        selectDestination(
            name: String(format: "%.6f, %.6f", latitude, longitude),
            latitude: latitude,
            longitude: longitude
        )
    }
}

private final class RPLidarOverlayCalibrationViewController: UIViewController {
    var onCalibrationChanged: ((ROBLidarOverlayCalibration) -> Void)?
    var onBaseMapStyleChanged: ((ROBLidarBaseMapStyle) -> Void)?

    private let mapStyleControl = UISegmentedControl(
        items: ROBLidarBaseMapStyle.allCases.map(\.title)
    )
    private let scaleSlider = UISlider(frame: .zero)
    private let rotationSlider = UISlider(frame: .zero)
    private let scaleValueLabel = UILabel(frame: .zero)
    private let rotationValueLabel = UILabel(frame: .zero)
    private var calibration: ROBLidarOverlayCalibration
    private var baseMapStyle: ROBLidarBaseMapStyle

    init(
        calibration: ROBLidarOverlayCalibration,
        baseMapStyle: ROBLidarBaseMapStyle
    ) {
        self.calibration = calibration
        self.baseMapStyle = baseMapStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lidar Overlay"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Reset",
            style: .plain,
            target: self,
            action: #selector(resetCalibration)
        )

        scaleSlider.minimumValue = 0.50
        scaleSlider.maximumValue = 1.50
        scaleSlider.value = Float(calibration.scale)
        scaleSlider.isContinuous = true
        scaleSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        rotationSlider.minimumValue = -180
        rotationSlider.maximumValue = 180
        rotationSlider.value = Float(calibration.northRotationDegrees)
        rotationSlider.isContinuous = true
        rotationSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        mapStyleControl.selectedSegmentIndex = ROBLidarBaseMapStyle.allCases.firstIndex(
            of: baseMapStyle
        ) ?? 0
        mapStyleControl.addTarget(self, action: #selector(mapStyleChanged), for: .valueChanged)

        [scaleValueLabel, rotationValueLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
            $0.textAlignment = .right
            $0.setContentHuggingPriority(.required, for: .horizontal)
        }

        let explanation = UILabel(frame: .zero)
        explanation.text = "The base bitmap size is calculated from Slamware map dimensions × cell resolution. Use Scale only as a correction. North rotation is clockwise."
        explanation.font = .preferredFont(forTextStyle: .footnote)
        explanation.textColor = .secondaryLabel
        explanation.numberOfLines = 0

        let mapStyleLabel = UILabel(frame: .zero)
        mapStyleLabel.text = "Base map"
        mapStyleLabel.font = .preferredFont(forTextStyle: .headline)
        let mapStyleRow = UIStackView(arrangedSubviews: [mapStyleLabel, mapStyleControl])
        mapStyleRow.axis = .vertical
        mapStyleRow.spacing = 8

        let scaleRow = calibrationRow(
            title: "Overlay scale",
            slider: scaleSlider,
            valueLabel: scaleValueLabel
        )
        let rotationRow = calibrationRow(
            title: "North rotation",
            slider: rotationSlider,
            valueLabel: rotationValueLabel
        )
        let stack = UIStackView(arrangedSubviews: [mapStyleRow, explanation, scaleRow, rotationRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 24
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
        refreshValueLabels()
    }

    private func calibrationRow(
        title: String,
        slider: UISlider,
        valueLabel: UILabel
    ) -> UIStackView {
        let titleLabel = UILabel(frame: .zero)
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        header.spacing = 12
        let row = UIStackView(arrangedSubviews: [header, slider])
        row.axis = .vertical
        row.spacing = 8
        return row
    }

    @objc private func sliderChanged() {
        calibration = ROBLidarOverlayCalibration(
            scale: Double((scaleSlider.value * 100).rounded() / 100),
            northRotationDegrees: Double(rotationSlider.value.rounded())
        )
        refreshValueLabels()
        onCalibrationChanged?(calibration)
    }

    @objc private func mapStyleChanged() {
        let styles = ROBLidarBaseMapStyle.allCases
        guard styles.indices.contains(mapStyleControl.selectedSegmentIndex) else { return }
        baseMapStyle = styles[mapStyleControl.selectedSegmentIndex]
        onBaseMapStyleChanged?(baseMapStyle)
    }

    private func refreshValueLabels() {
        scaleValueLabel.text = String(format: "%d%%", Int((calibration.scale * 100).rounded()))
        rotationValueLabel.text = String(format: "%+.0f°", calibration.northRotationDegrees)
    }

    @objc private func resetCalibration() {
        calibration = .default
        scaleSlider.setValue(Float(calibration.scale), animated: true)
        rotationSlider.setValue(Float(calibration.northRotationDegrees), animated: true)
        refreshValueLabels()
        onCalibrationChanged?(calibration)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension RPLidarViewController: CLLocationManagerDelegate {
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.reversed().first(where: {
            $0.horizontalAccuracy >= 0 && CLLocationCoordinate2DIsValid($0.coordinate)
        }) else {
            return
        }
        locationTimeoutWorkItem?.cancel()
        locationTimeoutWorkItem = nil
        latestDeviceLocation = location
        openStreetMapView.updateRobot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        mapStatusLabel.text = String(
            format: "Location locked (±%.0f m)",
            location.horizontalAccuracy
        )
        mapStatusLabel.textColor = .white
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startLocationUpdatesIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        if (error as? CLError)?.code == .denied {
            mapStatusLabel.text = "Location denied — allow RPLidar in System Settings"
        } else {
            mapStatusLabel.text = "Location failed: \(error.localizedDescription)"
        }
        mapStatusLabel.textColor = .systemYellow
    }
}

extension RPLidarViewController: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        switch mapDocumentOperation {
        case .importing:
            mapDocumentOperation = .none
            guard let url = urls.first else {
                setMapControlsBusy(false, status: "No map file selected")
                return
            }
            confirmLoadMap(from: url)

        case .exporting(let temporaryURL):
            mapDocumentOperation = .none
            removeTemporaryMap(at: temporaryURL)
            let savedName = urls.first?.lastPathComponent ?? temporaryURL.lastPathComponent
            setMapControlsBusy(false, status: "Saved \(savedName)")

        case .none:
            break
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if case .exporting(let temporaryURL) = mapDocumentOperation {
            removeTemporaryMap(at: temporaryURL)
        }
        mapDocumentOperation = .none
        setMapControlsBusy(false, status: "Map file operation cancelled")
    }
}

private enum MapDocumentOperation {
    case none
    case importing
    case exporting(URL)
}

public struct Pixel {
    public var value: UInt32
    
    public var red: UInt8 {
        get {
            return UInt8(value & 0xFF)
        } set {
            value = UInt32(newValue) | (value & 0xFFFFFF00)
        }
    }
    
    public var green: UInt8 {
        get {
            return UInt8((value >> 8) & 0xFF)
        } set {
            value = (UInt32(newValue) << 8) | (value & 0xFFFF00FF)
        }
    }
    
    public var blue: UInt8 {
        get {
            return UInt8((value >> 16) & 0xFF)
        } set {
            value = (UInt32(newValue) << 16) | (value & 0xFF00FFFF)
        }
    }
    
    public var alpha: UInt8 {
        get {
            return UInt8((value >> 24) & 0xFF)
        } set {
            value = (UInt32(newValue) << 24) | (value & 0x00FFFFFF)
        }
    }
}

extension Data {
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}

extension Array where Element == UInt8 {
    var data: Data {
        return Data(self)
    }
}

//if let origin = RPPointF(x: 0, andY: 0),
//let dimension = RPSize(width: 0, andHeight: 0),
//let resolution = RPPointF(x: 0, andY: 0) {
//    let timestamp = Int()
//    let data = Data()

struct ROBOMap: Codable {
    var origin: CGPoint
    let dimension: CGSize
    let resolution: CGPoint
    let timestamp: Int
    let data: Data
    
    let poseLocationX: Double
    let poseLocationY: Double
    let poseLocationZ: Double
    let poseYaw: Double
    let posePitch: Double
    let poseRoll: Double

    init(map: RPMap, pose: RPPose) {
        origin = CGPoint(x: Double(map.origin.x), y: Double(map.origin.y))
        dimension = CGSize(
            width: Double(map.dimension.width),
            height: Double(map.dimension.height)
        )
        resolution = CGPoint(
            x: Double(map.resolution.x),
            y: Double(map.resolution.y)
        )
        timestamp = map.timestamp
        data = map.data
        poseLocationX = Double(pose.location.x)
        poseLocationY = Double(pose.location.y)
        poseLocationZ = Double(pose.location.z)
        poseYaw = Double(pose.rotation.yaw)
        posePitch = Double(pose.rotation.pitch)
        poseRoll = Double(pose.rotation.roll)
    }

    static func decoded(from data: Data) throws -> ROBOMap {
        do {
            let archive = try JSONDecoder().decode(ROBOMap.self, from: data)
            try archive.validate()
            return archive
        } catch let error as RPLidarMapFileError {
            throw error
        } catch {
            throw RPLidarMapFileError.invalidFile(error)
        }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func makeRPMap() throws -> RPMap {
        let (width, height) = try validatedDimensions()
        guard let mapOrigin = RPPointF(x: Float(origin.x), andY: Float(origin.y)),
              let mapDimension = RPSize(width: width, andHeight: height),
              let mapResolution = RPPointF(
                x: Float(resolution.x),
                andY: Float(resolution.y)
              ) else {
            throw RPLidarMapFileError.invalidGeometry
        }
        return RPMap(
            origin: mapOrigin,
            andDimension: mapDimension,
            andResolution: mapResolution,
            andTimestamp: timestamp,
            andData: data
        )
    }

    func makeRPPose() throws -> RPPose {
        try validate()
        return RPPose(
            x: Float(poseLocationX),
            andY: Float(poseLocationY),
            andZ: Float(poseLocationZ),
            andYaw: Float(poseYaw),
            andPitch: Float(posePitch),
            andRoll: Float(poseRoll)
        )
    }

    private func validate() throws {
        let (width, height) = try validatedDimensions()
        let scalarValues = [
            origin.x, origin.y,
            resolution.x, resolution.y,
            poseLocationX, poseLocationY, poseLocationZ,
            poseYaw, posePitch, poseRoll
        ]
        let maximumFloat = CGFloat(Float.greatestFiniteMagnitude)
        guard scalarValues.allSatisfy({ $0.isFinite && abs($0) <= maximumFloat }),
              resolution.x > 0,
              resolution.y > 0 else {
            throw RPLidarMapFileError.invalidGeometry
        }

        let (expectedByteCount, overflow) = Int(width).multipliedReportingOverflow(by: Int(height))
        guard !overflow, data.count == expectedByteCount else {
            throw RPLidarMapFileError.invalidMapData(
                expected: overflow ? 0 : expectedByteCount,
                actual: data.count
            )
        }
    }

    private func validatedDimensions() throws -> (Int32, Int32) {
        guard dimension.width.isFinite,
              dimension.height.isFinite,
              dimension.width > 0,
              dimension.height > 0,
              dimension.width.rounded(.towardZero) == dimension.width,
              dimension.height.rounded(.towardZero) == dimension.height,
              dimension.width <= CGFloat(Int32.max),
              dimension.height <= CGFloat(Int32.max) else {
            throw RPLidarMapFileError.invalidGeometry
        }
        return (Int32(dimension.width), Int32(dimension.height))
    }
}

enum RPLidarMapFileError: LocalizedError {
    case mapUnavailable
    case poseUnavailable
    case invalidFile(Error)
    case invalidGeometry
    case invalidMapData(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .mapUnavailable:
            return "No map is available from the RPLidar yet."
        case .poseUnavailable:
            return "No droid pose is available from the RPLidar yet."
        case .invalidFile(let error):
            return "The file is not a valid RPLidar map: \(error.localizedDescription)"
        case .invalidGeometry:
            return "The map contains invalid dimensions, resolution, coordinates, or pose values."
        case .invalidMapData(let expected, let actual):
            return "The map contains \(actual) occupancy bytes; its dimensions require \(expected)."
        }
    }
}
