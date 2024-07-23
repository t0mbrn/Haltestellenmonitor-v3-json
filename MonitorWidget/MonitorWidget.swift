//
//  MonitorWidget.swift
//  MonitorWidget
//
//  Created by Peter Lohse on 19.04.23.
//  Modiefied by Tom Braune on 03.11.23.
//  Credit to https://github.com/AKORA-Studios for helping with the LocationManager
//

import WidgetKit
import SwiftUI
import Intents
import CoreLocation
import MapKit

class Provider: IntentTimelineProvider {
    
    typealias Entry = MonitorEntry
    
    let widgetLocationManager = WidgetLocationManager()

    func placeholder(in context: Context) -> MonitorEntry {
        MonitorEntry(date: Date(), configuration: ConfigurationIntent(), stop: nil, stopEvents: nil)
    }

    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (MonitorEntry) -> ()) {
        // TODO: stopEvents
        let entry = MonitorEntry(date: Date(), configuration: configuration, stop: stops[0], stopEvents: [])
        completion(entry)
    }

    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        
        var stopID: String = "de:14612:28"
        var favoriteStops: [Int] = []
        
        if configuration.favoriteFilter == FavoriteFilter.true {
            if let data = UserDefaults(suiteName: "group.eu.hanashi.Haltestellenmonitor")?.data(forKey: "FavoriteStops") {
                if let decoded = try? JSONDecoder().decode([Int].self, from: data) {
                    favoriteStops = decoded
                }
            }
            
            // Retrieving stop data for marked favorites
            var favStops : [Stop] = stops.filter{favorite in
                return favoriteStops.contains(favorite.stopID)
            }
            
            if favStops.isEmpty {
                print("No favorites found.")
                stopID = "de:14612:28"
                
            } else {
                var favStopsLoc : [Stop] = []
                // Retrieving location data
                Task() {
                    await widgetLocationManager.fetchLocation { llocation in
                        print(">>>", llocation.coordinate)}
                }
                // Dresden town hall GPS coordinates as default
                let location = widgetLocationManager.llocation ?? CLLocation(latitude: +51.04750, longitude: +13.74035)
               
                // sorting by distance
                favStops.forEach {stop in
                    var newStop = stop
                    newStop.distance = location.distance(from: CLLocation(latitude: stop.coordinates.latitude, longitude: stop.coordinates.longitude))
                    favStopsLoc.append(newStop)
                }
                favStops = favStopsLoc.sorted{$0.getDistance() < $1.getDistance()}
                
                stopID = String(favStops[0].gid)
            }
        } else {
            stopID = configuration.stopType?.identifier ?? "de:14612:28"
        }
        
        let stop = Stop.getByGID(gid: stopID)
        
        let url = URL(string: "https://efa.vvo-online.de/std3/trias")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = DepartureRequest(stopPointRef: stopID, numberOfResults: 75).getXML()
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) {(data, response, error) in
            var entries: [MonitorEntry] = []
            var stopEvents: [StopEvent] = []
            guard error == nil else {
                print ("error: \(error!)")
                self.getTimeline(for: configuration, in: context, completion: completion)
                return
            }

            guard let content = data else {
                print("No data")
                self.getTimeline(for: configuration, in: context, completion: completion)
                return
            }

            DispatchQueue.main.async {
                let stopEventParser = StopEventResponseParser(data: content)
                stopEventParser.parse()
                stopEvents = stopEventParser.stopEvents
                
                let currentDate = Date()
                for i in 0 ..< 72 {
                    let entryDate = Calendar.current.date(byAdding: .second, value: 30 * i, to: currentDate)!
                    let entry = MonitorEntry(date: entryDate, configuration: configuration, stop: stop, stopEvents: stopEvents)
                    entries.append(entry)
                }
                
                let timeline = Timeline(entries: entries, policy: .atEnd)
                completion(timeline)
            }

        }
        task.resume()
    }
}

struct MonitorWidget: Widget {
    let kind: String = "MonitorWidget"
    
    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: Provider()) { entry in
            MonitorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Haltestellenmonitor")
        .description("Widget zur Anzeige der Abfahrten an einer Haltestelle.")
        .contentMarginsDisabledIfAvailable()
    }
}

extension WidgetConfiguration
{
    func contentMarginsDisabledIfAvailable() -> some WidgetConfiguration
    {
        if #available(iOSApplicationExtension 17.0, *)
        {
            return self.contentMarginsDisabled()
        }
        else
        {
            return self
        }
    }
}
