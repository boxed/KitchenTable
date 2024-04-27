//
//  AppDelegate.swift
//  KitchenTable
//
//  Created by Anders Hovmöller on 2024-04-20.
//

import Cocoa
import EventKit

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


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        timeFormatter.dateFormat = "HH:mm"

        if #available(macOS 14, *) {
            store.requestFullAccessToEvents { [self] granted, error in
                if granted {
                    DispatchQueue.main.async { [self]
                        self.readCalendar()
                        self.updateDisplay()
                    }
                }
            }
        }
        else {
            readCalendar()
            updateDisplay()
        }
    }
    
    @MainActor
    func updateDisplay() {
        let now = Date()
        let weekday_name_by_number = [
            2: "Måndag",
            3: "Tisdag",
            4: "Onsdag",
            5: "Torsdag",
            6: "Fredag",
            7: "Lördag",
            0: "Söndag",
        ]
        
        weekday_label.stringValue = weekday_name_by_number[now.weekday]!
        date_label.stringValue = "\(now.day)"
        
        guard let imgData = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            assert(false)
        }
        
        view.cacheDisplay(in: view.bounds, to: imgData)
        view.unlockFocus()
        let pngData = imgData.representation(using: .png, properties: [:])
        do {
            let path = URL.init(fileURLWithPath: "output.png")
            NSLog(path.absoluteString)
            try pngData!.write(to: path, options: .atomic)
        }
        catch {
            assert(false)
        }
        NSLog("bar")
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
        
        self.am_label.stringValue = am_events.joined(separator: "\n")
        self.pm_label.stringValue = pm_events.joined(separator: "\n")
        NSLog("foo")
    }

   
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


}

