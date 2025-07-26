//
//  RPAppKitController.swift
//  RPAppKitController
//
//  Created by Rob Makina on 7/25/25.
//  Copyright © 2025 OrbitusRobotics. All rights reserved.
//

import Foundation

final class RPAppKitController: Sendable {
    static let shared = RPAppKitController()

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    func writeMapToFile(location: String, data: Data) {
        let filename = getDocumentsDirectory().appendingPathComponent("\(location).robomap")
        do {
            try data.write(to: filename, options: .atomic)
            print("Data saved successfully to \(filename)")
        } catch {
            print("Error saving data: \(error)")
        }
    }
    
    func allMaps() -> [String] {
        var maps: [String] = []
        let fileManager = FileManager.default
        do {
            let fileUrls = try fileManager.contentsOfDirectory(at: getDocumentsDirectory(), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for fileUrl in fileUrls {
                if fileUrl.pathExtension == "robomap" {
                    maps.append(fileUrl.lastPathComponent)
                }
            }
        } catch {
            print("Error while enumerating files: \(error)")
        }
        
        return maps
    }
    
    func loadMap(_ mapName: String) -> Data? {
        let fileManager = FileManager.default
        do {
            let fileUrls = try fileManager.contentsOfDirectory(at: getDocumentsDirectory(), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for fileUrl in fileUrls {
                print("comparing \(fileUrl.lastPathComponent) to \(mapName.appending(".robomap"))")
                if fileUrl.pathExtension == "robomap" && fileUrl.lastPathComponent == mapName.appending(".robomap") {
                    return try Data(contentsOf: fileUrl)
                }
            }
        } catch {
            print("Error while enumerating files: \(error)")
        }
        
        return nil
    }
}
