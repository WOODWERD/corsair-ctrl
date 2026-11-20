import Foundation
import EventKit

/// Weather and the next calendar event. Both keep their last good value and say when
/// it was read, so the panel never shows old data as live.
final class Glance {
    struct Place { var enabled: Bool; var label: String; var latitude: Double; var longitude: Double }
    private let place: Place
    private let events = EKEventStore()
    private var weather: [String: Any]?
    private var weatherAt: Double = 0
    private var weatherFailed = false
    private var next: [String: Any]?
    private let work = DispatchQueue(label: "com.woodwerd.corsairctrl.glance", qos: .utility)
    var onChange: () -> Void = {}

    init(place: Place) {
        self.place = place
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: events, queue: .main) { [weak self] _ in
            self?.refreshCalendar()
        }
    }

    // MARK: Calendar (Apple Calendar through EventKit)

    var calendarStatus: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "granted"
        case .notDetermined: return "unknown"
        default: return "denied"
        }
    }

    func requestCalendar() {
        events.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshCalendar() }
        }
    }

    /// Reads the next event on a background queue. The main thread must stay free: the touch
    /// driver gives the panel 50 ms to answer each Accessibility query and rejects the tap otherwise.
    func refreshCalendar() {
        guard calendarStatus == "granted" else { next = nil; onChange(); return }
        work.async { [weak self] in
            guard let self else { return }
            let found = self.nextEvent()
            DispatchQueue.main.async { self.next = found; self.onChange() }
        }
    }

    private func nextEvent() -> [String: Any]? {
        let now = Date()
        let pred = events.predicateForEvents(withStart: now, end: now.addingTimeInterval(7 * 86400), calendars: nil)
        let next = events.events(matching: pred)
            .filter { !$0.isAllDay && $0.startDate > now }
            .min { $0.startDate < $1.startDate }
        guard let e = next else { return nil }
        return ["title": e.title ?? "Event", "start": e.startDate.timeIntervalSince1970]
    }

    // MARK: Weather (Open-Meteo: no key, sends only the configured coordinates)

    private static func words(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorm"
        default: return "—"
        }
    }

    func refreshWeather() {
        guard place.enabled else { return }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(place.latitude)), .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,precipitation_probability_max"),
            .init(name: "temperature_unit", value: "fahrenheit"), .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]
        var req = URLRequest(url: c.url!, timeoutInterval: 15)
        req.setValue("CorsairCtrl", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            var parsed: [String: Any]?
            if let data, let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let cur = j["current"] as? [String: Any], let temp = cur["temperature_2m"] as? Double {
                var w: [String: Any] = ["temp": Int(temp.rounded()), "desc": Glance.words(cur["weather_code"] as? Int ?? -1)]
                if let daily = j["daily"] as? [String: Any] {
                    if let hi = (daily["temperature_2m_max"] as? [Double])?.first { w["high"] = Int(hi.rounded()) }
                    if let rain = (daily["precipitation_probability_max"] as? [Any])?.first as? Int { w["rain"] = rain }
                }
                parsed = w
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let parsed { self.weather = parsed; self.weatherAt = Date().timeIntervalSince1970; self.weatherFailed = false }
                else { self.weatherFailed = true }
                self.onChange()
            }
        }.resume()
    }

    func snapshot() -> [String: Any] {
        var out: [String: Any] = ["place": place.label, "weatherEnabled": place.enabled, "calendar": calendarStatus]
        if let weather {
            out["weather"] = weather
            out["weatherAt"] = weatherAt
            out["weatherStale"] = weatherFailed || Date().timeIntervalSince1970 - weatherAt > 45 * 60
        } else {
            out["weatherStale"] = weatherFailed
        }
        if let next { out["next"] = next }
        return out
    }
}
