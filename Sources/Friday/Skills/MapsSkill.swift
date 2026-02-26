import Foundation
import MapKit

struct MapsSkill {
    static func findNearby(_ query: String) async -> String {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        guard let loc = await LocationSkill.fetchLocation() else {
            return "Unable to determine location for maps search."
        }
        
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lon),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        request.region = region
        
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            let items = response.mapItems.prefix(3)
            if items.isEmpty { return "I couldn't find any results for \(query) nearby." }
            
            var result = "I found a few places for \(query) near \(loc.city):\n"
            for item in items {
                let name = item.name ?? "Unknown"
                let address = item.placemark.title ?? ""
                result += "- \(name): \(address)\n"
            }
            return result
        } catch {
            return "I encountered an error searching maps: \(error.localizedDescription)"
        }
    }
}
