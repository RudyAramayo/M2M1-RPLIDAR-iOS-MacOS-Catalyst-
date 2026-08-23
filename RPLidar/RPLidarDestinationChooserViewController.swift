//
//  RPLidarDestinationChooserViewController.swift
//  RPLidar
//
//  Development-GUI destination selection backed by OpenStreetMap tiles and
//  Nominatim search. Selection history is intentionally local to RPLidar.
//

import Foundation
import CoreLocation
import MapKit
import UIKit

struct RPLidarDestination: Codable, Equatable {
    let id: UUID
    let displayName: String
    let latitude: Double
    let longitude: Double
    let selectedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
    }
}

final class RPLidarDestinationHistoryStore {
    static let maximumCount = 25

    private let defaults: UserDefaults
    private let key: String
    private(set) var destinations: [RPLidarDestination]

    init(
        defaults: UserDefaults = .standard,
        key: String = "RPLidar.DestinationHistory.v1"
    ) {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RPLidarDestination].self, from: data) {
            destinations = decoded.filter(\.isValid)
                .sorted { $0.selectedAt > $1.selectedAt }
                .prefix(Self.maximumCount)
                .map { $0 }
        } else {
            destinations = []
        }
    }

    @discardableResult
    func record(name: String, latitude: Double, longitude: Double) -> RPLidarDestination? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = RPLidarDestination(
            id: UUID(),
            displayName: trimmedName.isEmpty
                ? String(format: "%.6f, %.6f", latitude, longitude)
                : trimmedName,
            latitude: latitude,
            longitude: longitude,
            selectedAt: Date()
        )
        guard destination.isValid else { return nil }

        destinations.removeAll {
            abs($0.latitude - latitude) < 0.000_001 &&
                abs($0.longitude - longitude) < 0.000_001
        }
        destinations.insert(destination, at: 0)
        destinations = Array(destinations.prefix(Self.maximumCount))
        save()
        return destination
    }

    func remove(at index: Int) {
        guard destinations.indices.contains(index) else { return }
        destinations.remove(at: index)
        save()
    }

    func removeAll() {
        destinations.removeAll()
        defaults.removeObject(forKey: key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(destinations) else { return }
        defaults.set(data, forKey: key)
    }
}

final class RPLidarDestinationChooserViewController: UIViewController {
    var onDestinationSelected: ((RPLidarDestination) -> Void)?
    var initialDeviceLocation: CLLocation?

    private let historyStore = RPLidarDestinationHistoryStore()
    private let locationManager = CLLocationManager()
    private let mapView = MKMapView(frame: .zero)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let statusLabel = UILabel(frame: .zero)
    private let destinationAnnotation = MKPointAnnotation()
    private let baseMapStyle = ROBLidarBaseMapStyleStore.load()
    private var searchButton: UIBarButtonItem?
    private var locationButton: UIBarButtonItem?
    private var latestDeviceLocation: CLLocation?
    private var shouldCenterOnNextLocation = true
    private var locationTimeoutWorkItem: DispatchWorkItem?
    private var lastSearchUptime: TimeInterval = 0

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "OpenStreetMap Destination"
        view.backgroundColor = .systemBackground
        configureNavigationItems()
        configureMap()
        configureLocationServices()
        configureHistory()
        configureLayout()

        if let location = usableDeviceLocation(initialDeviceLocation ?? locationManager.location) {
            latestDeviceLocation = location
            centerOnDeviceLocation(location, animated: false)
        } else if let recent = historyStore.destinations.first {
            show(recent, animated: false, notify: false)
        } else {
            mapView.setRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 180)
                ),
                animated: false
            )
            statusLabel.text = "Finding current location…"
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startLocationUpdatesIfAuthorized()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        locationManager.stopUpdatingLocation()
    }

    deinit {
        locationTimeoutWorkItem?.cancel()
        locationManager.stopUpdatingLocation()
    }

    private func configureNavigationItems() {
        let search = UIBarButtonItem(
            title: "Search",
            style: .plain,
            target: self,
            action: #selector(presentDestinationSearch)
        )
        searchButton = search
        let locate = UIBarButtonItem(
            image: UIImage(systemName: "location.fill"),
            style: .plain,
            target: self,
            action: #selector(showCurrentLocation)
        )
        locate.accessibilityLabel = "Show current location"
        locationButton = locate
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(close)
            ),
            search,
            locate
        ]
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Clear History",
            style: .plain,
            target: self,
            action: #selector(confirmClearHistory)
        )
    }

    private func configureMap() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.accessibilityLabel = "OpenStreetMap destination map"

        _ = ROBLidarBaseMapLayer.install(baseMapStyle, on: mapView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)
    }

    private func configureLocationServices() {
        locationManager.delegate = self
        locationManager.distanceFilter = 2
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private func startLocationUpdatesIfAuthorized() {
        guard CLLocationManager.locationServicesEnabled() else {
            statusLabel.text = "Location Services are disabled in System Settings."
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            statusLabel.text = "Finding current location…"
            scheduleLocationTimeoutIfNeeded()
            locationManager.requestLocation()
            locationManager.startUpdatingLocation()
        case .notDetermined:
            statusLabel.text = "Allow location access to center the map near ROB."
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            statusLabel.text = "Location access is off. Enable it in Settings, or search for a destination."
        @unknown default:
            break
        }
    }

    private func scheduleLocationTimeoutIfNeeded() {
        guard latestDeviceLocation == nil else { return }
        locationTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.latestDeviceLocation == nil else { return }
            self.statusLabel.text = "No Mac location fix. Check Location Services and keep Wi-Fi enabled."
        }
        locationTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }

    private func usableDeviceLocation(_ location: CLLocation?) -> CLLocation? {
        guard let location,
              location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate) else {
            return nil
        }
        return location
    }

    private func centerOnDeviceLocation(_ location: CLLocation, animated: Bool) {
        shouldCenterOnNextLocation = false
        mapView.setRegion(
            MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 1_000,
                longitudinalMeters: 1_000
            ),
            animated: animated
        )
        statusLabel.text = location.horizontalAccuracy.isFinite
            ? String(format: "Centered on current location (±%.0f m).", location.horizontalAccuracy)
            : "Centered on current location."
    }

    private func configureHistory() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 58
        tableView.accessibilityLabel = "Recent destinations"

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.text = "Search or tap the map to choose a destination."
    }

    private func configureLayout() {
        let attribution = UILabel(frame: .zero)
        attribution.translatesAutoresizingMaskIntoConstraints = false
        attribution.text = baseMapStyle.attribution
        attribution.isHidden = baseMapStyle.attribution == nil
        attribution.font = .preferredFont(forTextStyle: .caption2)
        attribution.textColor = .secondaryLabel
        attribution.textAlignment = .right

        let mapContainer = UIView(frame: .zero)
        mapContainer.translatesAutoresizingMaskIntoConstraints = false
        mapContainer.addSubview(mapView)
        mapContainer.addSubview(attribution)

        let historyTitle = UILabel(frame: .zero)
        historyTitle.text = "Recent Destinations"
        historyTitle.font = .preferredFont(forTextStyle: .headline)

        let historyContainer = UIStackView(arrangedSubviews: [
            historyTitle,
            tableView,
            statusLabel
        ])
        historyContainer.axis = .vertical
        historyContainer.spacing = 4
        historyContainer.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        historyContainer.isLayoutMarginsRelativeArrangement = true

        let content = UIStackView(arrangedSubviews: [mapContainer, historyContainer])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 0
        view.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            mapView.leadingAnchor.constraint(equalTo: mapContainer.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: mapContainer.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: mapContainer.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: mapContainer.bottomAnchor),
            mapContainer.heightAnchor.constraint(
                greaterThanOrEqualTo: view.heightAnchor,
                multiplier: 0.48
            ),

            attribution.trailingAnchor.constraint(equalTo: mapContainer.trailingAnchor, constant: -6),
            attribution.bottomAnchor.constraint(equalTo: mapContainer.bottomAnchor, constant: -4),
            tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func showCurrentLocation() {
        shouldCenterOnNextLocation = true
        if let location = usableDeviceLocation(latestDeviceLocation ?? locationManager.location) {
            latestDeviceLocation = location
            centerOnDeviceLocation(location, animated: true)
        } else {
            statusLabel.text = "Finding current location…"
            startLocationUpdatesIfAuthorized()
        }
    }

    @objc private func confirmClearHistory() {
        guard !historyStore.destinations.isEmpty else { return }
        let alert = UIAlertController(
            title: "Clear recent destinations?",
            message: "This removes only RPLidar's local destination history.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.historyStore.removeAll()
            self?.tableView.reloadData()
            self?.statusLabel.text = "Recent destination history cleared."
        })
        present(alert, animated: true)
    }

    @objc private func mapTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        shouldCenterOnNextLocation = false
        let point = recognizer.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }

        let coordinateName = String(
            format: "%.6f, %.6f",
            coordinate.latitude,
            coordinate.longitude
        )
        let alert = UIAlertController(
            title: "Choose this destination?",
            message: coordinateName,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Choose", style: .default) { [weak self] _ in
            self?.recordAndShow(
                name: coordinateName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        })
        present(alert, animated: true)
    }

    @objc private func presentDestinationSearch() {
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
                self?.presentNotice(
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
        guard now - lastSearchUptime >= 1 else {
            presentNotice(
                title: "Please wait",
                message: "OpenStreetMap search is limited to one submitted request per second."
            )
            return
        }
        lastSearchUptime = now

        let configuredEndpoint = UserDefaults.standard.string(forKey: "ROBNominatimEndpoint")
        let endpoint = configuredEndpoint?.isEmpty == false
            ? configuredEndpoint!
            : "https://nominatim.openstreetmap.org/search"
        guard var components = URLComponents(string: endpoint) else {
            presentNotice(
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
            presentNotice(
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
        searchButton?.isEnabled = false
        statusLabel.text = "Searching OpenStreetMap…"

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.searchButton?.isEnabled = true
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard error == nil,
                      (200 ... 299).contains(statusCode),
                      let data,
                      data.count <= 500_000 else {
                    self.statusLabel.text = "OpenStreetMap search failed."
                    self.presentNotice(
                        title: "OpenStreetMap search failed",
                        message: error?.localizedDescription ??
                            "The search service did not return a usable response."
                    )
                    return
                }

                let results = (try? JSONDecoder().decode([RPLidarNominatimPlace].self, from: data))?
                    .filter(\.isValid) ?? []
                guard !results.isEmpty else {
                    self.statusLabel.text = "No destinations found."
                    self.presentNotice(
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
                self?.recordAndShow(
                    name: result.displayName,
                    latitude: result.latitude,
                    longitude: result.longitude
                )
            })
        }
        chooser.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(chooser, animated: true)
    }

    private func recordAndShow(name: String, latitude: Double, longitude: Double) {
        shouldCenterOnNextLocation = false
        guard let destination = historyStore.record(
            name: name,
            latitude: latitude,
            longitude: longitude
        ) else {
            presentNotice(title: "Invalid destination", message: "That coordinate is not usable.")
            return
        }
        tableView.reloadData()
        show(destination, animated: true, notify: true)
    }

    private func show(_ destination: RPLidarDestination, animated: Bool, notify: Bool) {
        destinationAnnotation.coordinate = destination.coordinate
        destinationAnnotation.title = destination.displayName
        if !mapView.annotations.contains(where: { $0 === destinationAnnotation }) {
            mapView.addAnnotation(destinationAnnotation)
        }
        mapView.selectAnnotation(destinationAnnotation, animated: animated)
        mapView.setRegion(
            MKCoordinateRegion(
                center: destination.coordinate,
                latitudinalMeters: 250,
                longitudinalMeters: 250
            ),
            animated: animated
        )
        statusLabel.text = "Selected \(destination.displayName)"
        if notify {
            onDestinationSelected?(destination)
        }
    }

    private func presentNotice(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension RPLidarDestinationChooserViewController: CLLocationManagerDelegate {
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.reversed().compactMap(usableDeviceLocation).first else {
            return
        }
        locationTimeoutWorkItem?.cancel()
        locationTimeoutWorkItem = nil
        latestDeviceLocation = location
        locationButton?.isEnabled = true
        if shouldCenterOnNextLocation {
            centerOnDeviceLocation(location, animated: true)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startLocationUpdatesIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        if (error as? CLError)?.code == .denied {
            statusLabel.text = "Location denied. Allow RPLidar in System Settings, or search manually."
        } else {
            statusLabel.text = "Location failed: \(error.localizedDescription)"
        }
    }
}

extension RPLidarDestinationChooserViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        historyStore.destinations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseIdentifier = "RPLidarDestinationHistoryCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier) ??
            UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
        let destination = historyStore.destinations[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = destination.displayName
        content.secondaryText = String(
            format: "%.6f, %.6f  •  %@",
            destination.latitude,
            destination.longitude,
            dateFormatter.string(from: destination.selectedAt)
        )
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard historyStore.destinations.indices.contains(indexPath.row) else { return }
        let destination = historyStore.destinations[indexPath.row]
        recordAndShow(
            name: destination.displayName,
            latitude: destination.latitude,
            longitude: destination.longitude
        )
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else { return }
        historyStore.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }
}

extension RPLidarDestinationChooserViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let tileOverlay = overlay as? MKTileOverlay else {
            return MKOverlayRenderer(overlay: overlay)
        }
        return MKTileOverlayRenderer(tileOverlay: tileOverlay)
    }
}

extension RPLidarDestinationChooserViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

struct RPLidarNominatimPlace: Decodable {
    let displayName: String
    let latitude: Double
    let longitude: Double

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case latitude = "lat"
        case longitude = "lon"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        let latitudeString = try container.decode(String.self, forKey: .latitude)
        let longitudeString = try container.decode(String.self, forKey: .longitude)
        latitude = Double(latitudeString) ?? .nan
        longitude = Double(longitudeString) ?? .nan
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
    }
}
