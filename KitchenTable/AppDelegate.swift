//
//  AppDelegate.swift
//  KitchenTable
//
//  Created by Anders Hovmöller on 2024-04-20.
//

import Cocoa
import EventKit
import Swifter

let loc = CLLocation(latitude: 59.41789, longitude: 17.95551)

extension Date {
    var hour: Int {
        get {
            let components = Calendar.current.dateComponents([.hour], from: self)
            return components.hour!
        }
    }
    var minute: Int {
        get {
            let components = Calendar.current.dateComponents([.minute], from: self)
            return components.minute!
        }
    }
    var weekday: Int {
        get {
            let components = Calendar.current.dateComponents([.weekday], from: self)
            return components.weekday!
        }
    }
    var day: Int {
        get {
            let components = Calendar.current.dateComponents([.day], from: self)
            return components.day!
        }
    }
}

let server = HttpServer()


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
    var task: URLSessionDataTask?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        view.layer?.backgroundColor = .white
        
        dateUpdater()
        
        timer = Timer.scheduledTimer(
            withTimeInterval: 5,
            repeats: true,
            block: {_ in
                self.dateUpdater()
                self.readCalendar()
            }
        )
        
        timeFormatter.dateFormat = "HH:mm"
        
        server["/last_changed"] = { r in
            return HttpResponse.ok(.text("\(self.lastChanged.timeIntervalSince1970)"))
        }
        server["/image"] = { r in
            return HttpResponse.raw(200, "OK", [:], {
                try? $0.write(self.pngData!)
            })
        }
        do {
            try server.start(8123)
        }
        catch {
            setError("Failed to start server")
        }

        self.readWeather()
        if #available(macOS 14, *) {
            store.requestFullAccessToEvents { [self] granted, error in
                if granted {
                    DispatchQueue.main.async {
                        self.readCalendar()
                    }
                }
                else {
                    self.setError("Error getting calendar access")
                }
            }
        }
        else {
            store.requestAccess(to: .event, completion: { granted,_ in
                if granted {
                    self.readCalendar()
                }
                else {
                    self.setError("Error getting calendar access")
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
        
        let new_weekday_label = weekday_name_by_number[now.weekday]!
        if self.weekday_label.stringValue != new_weekday_label {
            self.weekday_label.stringValue = new_weekday_label
            self.dataChanged = Date()
        }
        let new_dateLabel = "\(now.day)"
        if self.date_label.stringValue != new_dateLabel {
            self.date_label.stringValue = new_dateLabel
            self.dataChanged = Date()
        }
        self.updateDisplay()
    }
    
    @MainActor
    func updateDisplay() {
        if self.dataChanged == self.lastChanged {
            return
        }
        
        NSLog("new image")

        guard let imgData = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            assert(false)
            return
        }
        
        view.cacheDisplay(in: view.bounds, to: imgData)
        pngData = imgData.representation(using: .png, properties: [:])
        self.lastChanged = dataChanged
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
        task = URLSession.shared.dataTask(with: request) { (data, response, error) in
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
                        
                        DispatchQueue.main.async {
                            NSLog("image set...")
                            // Sun icon = needs sunscreen
                            if result.daily.uv_index_max[0] >= 3 {
                                if self.rightImage.image == nil {
                                    self.rightImage.image = NSImage(systemSymbolName: "sun.max", variableValue: 0, accessibilityDescription: "")!
                                    self.dataChanged = Date()
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
                                    self.leftImage.image = NSImage(systemSymbolName: "cloud.heavyrain", variableValue: 0, accessibilityDescription: "")!
                                    self.dataChanged = Date()
                                }
                            }
                            else {
                                if self.leftImage.image != nil {
                                    self.leftImage.image = nil
                                    self.dataChanged = Date()
                                }
                            }
                            
                            while Date() == self.lastChanged {
                                Thread.sleep(forTimeInterval: 1)
                            }
                            NSLog("updateDisplay")
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
        task!.resume()
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
