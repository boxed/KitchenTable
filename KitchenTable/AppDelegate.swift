//
//  AppDelegate.swift
//  KitchenTable
//
//  Created by Anders Hovmöller on 2024-04-20.
//

import Cocoa
import EventKit
import Network

let loc = CLLocation(latitude: 59.41789, longitude: 17.95551)

extension Date {
    var hour: Int {
        get {
            let components = Calendar.current.dateComponents([.hour], from: self)
            guard let hour = components.hour else {
                NSLog("ERROR: Failed to get hour from date: \(self)")
                return 0
            }
            return hour
        }
    }
    var minute: Int {
        get {
            let components = Calendar.current.dateComponents([.minute], from: self)
            guard let minute = components.minute else {
                NSLog("ERROR: Failed to get minute from date: \(self)")
                return 0
            }
            return minute
        }
    }
    var weekday: Int {
        get {
            let components = Calendar.current.dateComponents([.weekday], from: self)
            guard let weekday = components.weekday else {
                NSLog("ERROR: Failed to get weekday from date: \(self)")
                return 1
            }
            return weekday
        }
    }
    var day: Int {
        get {
            let components = Calendar.current.dateComponents([.day], from: self)
            guard let day = components.day else {
                NSLog("ERROR: Failed to get day from date: \(self)")
                return 1
            }
            return day
        }
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet weak var view: NSView!
    @IBOutlet weak var am_label: NSTextField!
    @IBOutlet weak var pm_label: NSTextField!
    @IBOutlet weak var weekday_label: NSTextField!
    @IBOutlet weak var date_label: NSTextField!
    @IBOutlet weak var errors: NSTextField!
    @IBOutlet weak var leftImage: NSImageView!
    @IBOutlet weak var rightImage: NSImageView!
    var store = EKEventStore()
    let timeFormatter = DateFormatter()
    var lastChanged: Date = Date()
    var dataChanged: Date = Date()
    var pngData: Data?
    var timer: Timer?
    var timeOfWeatherData = Date.distantPast
    var timeOfCalendarRead = Date.distantPast
    var task: URLSessionDataTask?
    var listener: NWListener?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.isRestorable = false
        window.setFrameAutosaveName("MainWindow")
        view.layer?.backgroundColor = .white
        
        dateUpdater()
        
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true,
            block: { [weak self] _ in
                DispatchQueue.main.async {
                    autoreleasepool {
                        self?.dateUpdater()
                        self?.readCalendar()
                        self?.readWeather()
                    }
                }
            }
        )
        
        timeFormatter.dateFormat = "HH:mm"
        
        do {
            listener = try NWListener(using: .tcp, on: 8123)
        } catch {
            setError("Failed to start server")
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleHTTPConnection(connection)
        }
        listener?.start(queue: .global())

        self.readWeather()
        if #available(macOS 14, *) {
            store.requestFullAccessToEvents { [weak self] granted, error in
                if granted {
                    DispatchQueue.main.async {
                        self?.readCalendar()
                    }
                }
                else {
                    self?.setError("Error getting calendar access")
                }
            }
        }
        else {
            store.requestAccess(to: .event, completion: { [weak self] granted,_ in
                if granted {
                    DispatchQueue.main.async {
                        self?.readCalendar()
                    }
                }
                else {
                    self?.setError("Error getting calendar access")
                }
            })
        }
    }
    
    @MainActor
    func dateUpdater() {
        let now = Date()
        let weekday_name_by_number = [
            2: "Måndag",
            3: "Tisdag",
            4: "Onsdag",
            5: "Torsdag",
            6: "Fredag",
            7: "Lördag",
            1: "Söndag",
        ]
        
        guard let new_weekday_label = weekday_name_by_number[now.weekday] else {
            NSLog("ERROR: Failed to get weekday name for weekday number: \(now.weekday)")
            return
        }
        if self.weekday_label.stringValue != new_weekday_label {
            self.weekday_label.stringValue = new_weekday_label
            self.dataChanged = Date()
        }
        let new_dateLabel = "\(now.day)"
        if self.date_label.stringValue != new_dateLabel {
            self.date_label.stringValue = new_dateLabel
            self.dataChanged = Date()
            self.timeOfCalendarRead = Date.distantPast
            self.timeOfWeatherData = Date.distantPast
        }
        self.updateDisplay()
    }
    
    @MainActor
    func updateDisplay() {
        if self.dataChanged == self.lastChanged {
            return
        }

        NSLog("new image")

        // Always render at exactly 960x540 pixels regardless of screen scale
        let targetWidth = 960
        let targetHeight = 540

        guard let imgData = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            NSLog("ERROR: Failed to create NSBitmapImageRep for image rendering")
            return
        }

        imgData.size = view.bounds.size

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: imgData) else {
            NSLog("ERROR: Failed to create NSGraphicsContext from bitmap")
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        NSGraphicsContext.current = context
        view.displayIgnoringOpacity(view.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()

        // Move PNG compression to background thread to avoid blocking main thread
        let currentDataChanged = dataChanged
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            autoreleasepool {
                let startTime = Date()
                guard let png = imgData.representation(using: .png, properties: [:]) else {
                    NSLog("ERROR: Failed to create PNG representation from bitmap")
                    return
                }
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 1.0 {
                    NSLog("WARNING: PNG compression took \(elapsed) seconds")
                }
                DispatchQueue.main.async {
                    self?.pngData = png
                    self?.lastChanged = currentDataChanged
                }
            }
        }
        /*
        do {
            let path = URL.init(fileURLWithPath: "output.png")
            NSLog(path.absoluteString)
            try pngData!.write(to: path, options: .atomic)
        }
        catch {
            assert(false)
        }
         */
    }
    
    @MainActor
    func readCalendar() {
        guard Date().timeIntervalSince(timeOfCalendarRead) > 60*60 else { return }
        timeOfCalendarRead = Date()
        var am_events: [String] = []
        var pm_events: [String] = []
        let startOfToday = Calendar.current.startOfDay(for: Date())
        for event in store.events(matching: store.predicateForEvents(withStart: startOfToday, end: startOfToday.addingTimeInterval(60*60*24), calendars: nil)) {
            if event.calendar.title == "Delad" {
                if event.isAllDay {
                    am_events.append(event.title)
                }
                else {
                    let s = "\(timeFormatter.string(from: event.startDate))  \(event.title ?? "")"
                    if event.startDate.hour < 12 {
                        am_events.append(s)
                    }
                    else {
                        pm_events.append(s)
                    }
                }
            }
        }
        
        let new_am_label = am_events.joined(separator: "\n")
        if new_am_label != self.am_label.stringValue {
            dataChanged = Date()
        }
        self.am_label.stringValue = new_am_label
        
        let new_pm_label = pm_events.joined(separator: "\n")
        if new_pm_label != self.pm_label.stringValue {
            dataChanged = Date()
        }
        self.pm_label.stringValue = new_pm_label
        self.updateDisplay()
    }
    
    func readWeather() {
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(loc.coordinate.latitude)&longitude=\(loc.coordinate.longitude)&daily=weather_code,temperature_2m_max,temperature_2m_min,rain_sum,snowfall_sum,wind_speed_10m_max,uv_index_max&forecast_days=1&timezone=Europe%2FBerlin"
        guard (Date().timeIntervalSince1970 - timeOfWeatherData.timeIntervalSince1970) > 60*60 else {  // don't update more than once an hour
            return
        }
        guard let url = URL(string: s) else {
            setError("invalid url")
            return
        }
        
        NSLog("getting: \(url)")
        let request = URLRequest(url: url)
        task = URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
            guard let self = self else { return }
            defer { DispatchQueue.main.async { self.task = nil } }
            if let response = response as? HTTPURLResponse {
                NSLog("got response")

                if response.statusCode == 503 {
                    self.setError("failed to get data, \(response.statusCode)")
                    return
                }

                if error != nil {
                    self.setError("\(error.debugDescription)")
                    return
                }

                do {
                    if let data = data {
                        let string1 = String(data: data, encoding: String.Encoding.utf8) ?? "Data could not be printed"
                        NSLog(string1)
                        let decoder = JSONDecoder()

                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

                        decoder.dateDecodingStrategy = JSONDecoder.DateDecodingStrategy.secondsSince1970
                        let result = try decoder.decode(OMWeatherData.self, from: data)
                        NSLog("Parsed!")

                        self.timeOfWeatherData = Date()

                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            NSLog("image set...")
                            // Sun icon = needs sunscreen
                            if result.daily.uv_index_max[0] >= 3 {
                                if self.rightImage.image == nil {
                                    if let sunImage = NSImage(systemSymbolName: "sun.max", variableValue: 0, accessibilityDescription: "") {
                                        self.rightImage.image = sunImage
                                        self.dataChanged = Date()
                                    } else {
                                        NSLog("ERROR: Failed to create sun.max system symbol image")
                                    }
                                }
                            }
                            else {
                                if self.leftImage.image != nil {
                                    self.rightImage.image = nil
                                    self.dataChanged = Date()
                                }
                            }
                            // Rain icon == needs rain gear
                            if result.daily.rain_sum[0] >= 10 {
                                if self.leftImage.image == nil {
                                    if let rainImage = NSImage(systemSymbolName: "cloud.heavyrain", variableValue: 0, accessibilityDescription: "") {
                                        self.leftImage.image = rainImage
                                        self.dataChanged = Date()
                                    } else {
                                        NSLog("ERROR: Failed to create cloud.heavyrain system symbol image")
                                    }
                                }
                            }
                            else {
                                if self.leftImage.image != nil {
                                    self.leftImage.image = nil
                                    self.dataChanged = Date()
                                }
                            }

                            self.updateDisplay()
                        }
                        NSLog("Parsed! 5")

                    }
                }
                catch let error {
                    self.setError("Error parsing (\(error))")
                }
            }
            else {
                self.setError("\(error.debugDescription)")
            }

        }
        NSLog("start task")
        guard let task = task else {
            NSLog("ERROR: Failed to create URLSessionDataTask")
            return
        }
        task.resume()
    }

   
    func handleHTTPConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self = self else {
                connection.cancel()
                return
            }

            guard let data = data,
                  let request = String(data: data, encoding: .utf8),
                  let requestLine = request.split(separator: "\r\n").first else {
                connection.cancel()
                return
            }

            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }

            let fullPath = String(parts[1])
            let pathAndQuery = fullPath.split(separator: "?", maxSplits: 1)
            let path = String(pathAndQuery[0])
            let query = pathAndQuery.count > 1 ? String(pathAndQuery[1]) : ""

            switch path {
            case "/last_changed":
                let battery = query.split(separator: "&").compactMap { p -> String? in
                    let kv = p.split(separator: "=", maxSplits: 1)
                    return kv.count == 2 && kv[0] == "battery" ? String(kv[1]) : nil
                }.first

                DispatchQueue.main.async {
                    if let battery = battery {
                        self.window.title = "\(Date().description) - Battery: \(battery)"
                    } else {
                        self.window.title = "\(Date().description)"
                    }
                }

                let now = Date()
                let calendar = Calendar.current
                var targetComponents = calendar.dateComponents([.year, .month, .day], from: now)
                targetComponents.hour = 0
                targetComponents.minute = 10
                targetComponents.second = 0

                var secondsUntilTarget = 0
                if var target = calendar.date(from: targetComponents) {
                    if now >= target {
                        if let nextDay = calendar.date(byAdding: .day, value: 1, to: target) {
                            target = nextDay
                        }
                    }
                    secondsUntilTarget = Int(target.timeIntervalSince(now))
                }

                let body = "\(self.lastChanged.timeIntervalSince1970)\n\(secondsUntilTarget)"
                self.sendHTTPResponse(connection: connection, contentType: "text/plain", body: Data(body.utf8))

            case "/image":
                DispatchQueue.main.async {
                    self.window.title = "\(Date().description)"
                }
                self.sendHTTPResponse(connection: connection, contentType: "image/png", body: self.pngData ?? Data())

            default:
                self.sendHTTPResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
            }
        }
    }

    func sendHTTPResponse(connection: NWConnection, status: String = "200 OK", contentType: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func setError(_ s: String) {
        NSLog(s)
        DispatchQueue.main.async {
            self.errors.stringValue = s
        }
    }
}


struct OMWeatherData : Decodable {
    let daily: OMDaily
}

struct OMDaily : Decodable {
    let weather_code: [Int]
    let temperature_2m_max: [Float]
    let temperature_2m_min: [Float]
    let rain_sum: [Float]
    let snowfall_sum: [Float]
    let wind_speed_10m_max: [Float]
    let uv_index_max: [Float]
}
