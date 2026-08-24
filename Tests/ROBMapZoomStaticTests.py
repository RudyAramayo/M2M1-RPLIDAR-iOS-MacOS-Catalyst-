#!/usr/bin/env python3
"""Regression checks for preserving maximum map zoom across base-map styles."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAP_VIEW = ROOT / "RPLidar" / "ROBOpenStreetMapView.swift"
VIEW_CONTROLLER = ROOT / "RPLidar" / "RPLidarViewController.swift"


class MapZoomTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = MAP_VIEW.read_text(encoding="utf-8")
        cls.controller = VIEW_CONTROLLER.read_text(encoding="utf-8")

    def test_all_styles_enable_closest_mapkit_zoom(self) -> None:
        self.assertIn("private static let closestCameraDistance: CLLocationDistance = 1", self.source)
        self.assertIn("MKMapView.CameraZoomRange(", self.source)
        self.assertIn("minCenterCoordinateDistance: Self.closestCameraDistance", self.source)
        self.assertIn("mapView.setCameraZoomRange(zoomRange, animated: false)", self.source)
        self.assertIn("enableClosestMapZoom()", self.source)

    def test_style_switch_preserves_camera_after_renderer_replacement(self) -> None:
        self.assertIn("mapView.camera.copy() as? MKMapCamera", self.source)
        self.assertIn("restoreCameraAfterStyleChange(preservedCamera)", self.source)
        self.assertIn("DispatchQueue.main.async", self.source)
        self.assertGreaterEqual(
            self.source.count("setCamera("),
            2,
            "Camera should be restored immediately and after MapKit replaces its renderer",
        )

    def test_live_lidar_stays_visible_with_or_without_gps(self) -> None:
        self.assertIn("insertSubview(lidarView, aboveSubview: mapView)", self.source)
        self.assertIn("drawingAnchorCoordinate(in: mapView)", self.source)
        self.assertIn("!samples.isEmpty || occupancyMapImage != nil", self.source)
        self.assertIn("let centerCoordinate = mapView.centerCoordinate", self.source)
        self.assertIn('robotCoordinate == nil ? "MAP CENTER" : "GPS"', self.source)

    def test_perceived_location_can_be_aligned_and_reset(self) -> None:
        self.assertIn("UILongPressGestureRecognizer(", self.source)
        self.assertIn("setPerceivedRobotCoordinate", self.source)
        self.assertIn("ROBLidarLocationOffsetStore.save(locationOffset)", self.source)
        self.assertIn("alignRobotToMapCenter()", self.source)
        self.assertIn("resetPerceivedRobotLocation()", self.source)
        self.assertIn('anchorState = "ADJUSTED"', self.source)
        self.assertIn('"Set ROB to Map Center"', self.controller)
        self.assertIn('"Use Device GPS"', self.controller)

    def test_tapping_a_destination_preserves_the_current_camera(self) -> None:
        tap_handler = self.source.split("@objc private func mapTapped", 1)[1].split(
            "@objc private func mapLocationPressed", 1
        )[0]
        self.assertNotIn("setRegion(", tap_handler)
        self.assertNotIn("selectAnnotation(", tap_handler)
        self.assertIn("focusOnMap: false", self.controller)

    def test_named_mission_paths_are_persisted_and_rendered(self) -> None:
        self.assertIn("private final class ROBMissionPathStore", self.source)
        self.assertIn('title: "New Mission…"', self.source)
        self.assertIn('? "Finish Adding Stops" : "Add Stops"', self.source)
        self.assertIn("missionStore.appendWaypoint(coordinate)", self.source)
        self.assertIn("MKPolyline(coordinates:", self.source)
        self.assertIn('UIMenu(title: "Open Mission"', self.source)


if __name__ == "__main__":
    unittest.main()
