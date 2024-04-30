//
//  AppDelegate.swift
//  KitchenTable
//
//  Created by Anders Hovmöller on 2024-04-20.
//

import Cocoa
import EventKit
import Swifter

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
    var store = EKEventStore()
    let timeFormatter = DateFormatter()
    var lastChanged: Date = Date()
    var pngData: Data?
    var timer: Timer?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        timer = Timer.scheduledTimer(
            withTimeInterval: 5,
            repeats: true,
            block: {_ in
                self.updateDisplay()
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
            NSLog("Failed to start server")
            assert(false)
        }

        if #available(macOS 14, *) {
            store.requestFullAccessToEvents { [self] granted, error in
                if granted {
                    DispatchQueue.main.async {
                        self.readCalendar()
                        self.updateDisplay()
                    }
                }
                else {
                    let alert = NSAlert()
                    alert.messageText = "Error getting calendar access"
                    alert.addButton(withTitle: "OK")
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
        else {
            store.requestAccess(to: .event, completion: { granted,_ in
                if granted {
                    self.readCalendar()
                    self.updateDisplay()
                }
                else {
                    let alert = NSAlert()
                    alert.messageText = "Error getting calendar access"
                    alert.addButton(withTitle: "OK")
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            })
        }
    }
    
    @MainActor
    func updateDisplay() {
        let prev_changed = lastChanged
        readCalendar()
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
        if weekday_label.stringValue != new_weekday_label {
            weekday_label.stringValue = new_weekday_label
            lastChanged = Date()
        }
        let new_dateLabel = "\(now.day)"
        if date_label.stringValue != new_dateLabel {
            date_label.stringValue = new_dateLabel
            lastChanged = Date()
        }
        
        if lastChanged != prev_changed {
            NSLog("new image")

            guard let imgData = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                assert(false)
                return
            }
            
            view.cacheDisplay(in: view.bounds, to: imgData)
            view.unlockFocus()
            pngData = imgData.representation(using: .png, properties: [:])
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
            lastChanged = Date()
        }
        self.am_label.stringValue = new_am_label
        
        let new_pm_label = pm_events.joined(separator: "\n")
        if new_pm_label != self.pm_label.stringValue {
            lastChanged = Date()
        }
        self.pm_label.stringValue = new_pm_label
    }

   
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


}

