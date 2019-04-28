//
//  AppDelegate.swift
//  Persephone
//
//  Created by Daniel Barber on 2018/7/31.
//  Copyright © 2018 Dan Barber. All rights reserved.
//

import Cocoa
import ReSwift
import MediaKeyTap

@NSApplicationMain
class AppDelegate: NSObject,
                   NSApplicationDelegate,
                   MediaKeyTapDelegate {
  var preferences = Preferences()
  var mediaKeyTap: MediaKeyTap?
  var userNotificationsController: UserNotificationsController?

  static let mpdClient = MPDClient(
    withDelegate: NotificationsController()
  )

  static let trackTimer = TrackTimer()

  static let store = Store<AppState>(reducer: appReducer, state: nil)

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    connect()

    preferences.addObserver(self, forKeyPath: "mpdHost")
    preferences.addObserver(self, forKeyPath: "mpdPort")

    mediaKeyTap = MediaKeyTap(delegate: self)
    mediaKeyTap?.start()

    AppDelegate.store.subscribe(self) {
      $0.select { $0.playerState }
    }

    userNotificationsController = UserNotificationsController()
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    disconnect()
  }

  override func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey : Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    switch keyPath {
    case "mpdHost", "mpdPort":
      disconnect()
      connect()
    default:
      break
    }
  }

  func handle(mediaKey: MediaKey, event: KeyEvent) {
    switch mediaKey {
    case .playPause:
      AppDelegate.mpdClient.playPause()
    case .next, .fastForward:
      AppDelegate.mpdClient.nextTrack()
    case .previous, .rewind:
      AppDelegate.mpdClient.prevTrack()
    }
  }

  func connect() {
    AppDelegate.mpdClient.connect(
      host: preferences.mpdHostOrDefault,
      port: preferences.mpdPortOrDefault
    )
  }

  func disconnect() {
    AppDelegate.mpdClient.disconnect()
  }

  @IBAction func updateDatabase(_ sender: NSMenuItem) {
    AppDelegate.mpdClient.updateDatabase()
  }

  @IBOutlet weak var updateDatabaseMenuItem: NSMenuItem!
}

extension AppDelegate: StoreSubscriber {
  typealias StoreSubscriberStateType = PlayerState

  func newState(state: PlayerState) {
    updateDatabaseMenuItem.isEnabled = !state.databaseUpdating
  }
}
