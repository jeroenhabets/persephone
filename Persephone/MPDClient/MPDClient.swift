//
//  MPDClient.swift
//  Persephone
//
//  Created by Daniel Barber on 2019/1/25.
//  Copyright © 2019 Dan Barber. All rights reserved.
//

import Foundation
import mpdclient

class MPDClient {
  var delegate: MPDClientDelegate?

  let HOST = "localhost"
  let PORT: UInt32 = 6600

  private var connection: OpaquePointer?
  private var status: Status?
  private var queue: [Song] = []

  private let commandQueue = DispatchQueue(label: "commandQueue")

  enum Command {
    case prevTrack, nextTrack, playPause, stop, fetchStatus, fetchQueue,
      fetchAllAlbums
  }

  struct Idle: OptionSet {
    let rawValue: UInt32

    static let database = Idle(rawValue: 0x1)
    static let storedPlaylist = Idle(rawValue: 0x2)
    static let queue = Idle(rawValue: 0x4)
    static let player = Idle(rawValue: 0x8)
    static let mixer = Idle(rawValue: 0x10)
    static let output = Idle(rawValue: 0x20)
    static let options = Idle(rawValue: 0x40)
    static let update = Idle(rawValue: 0x80)
    static let sticker = Idle(rawValue: 0x100)
    static let subscription = Idle(rawValue: 0x200)
    static let message = Idle(rawValue: 0x400)
  }

  init(withDelegate delegate: MPDClientDelegate?) {
    self.delegate = delegate
  }

  func connect() {
    guard let connection = mpd_connection_new(HOST, PORT, 0)
      else { return }

    guard let status = mpd_run_status(connection)
      else { return }

    self.connection = connection
    self.status = Status(status)

    fetchQueue()

    fetchAllAlbums()

    self.delegate?.didUpdateState(mpdClient: self, state: self.status!.state)
    self.delegate?.didUpdateQueue(mpdClient: self, queue: self.queue)
    self.delegate?.didUpdateQueuePos(mpdClient: self, song: self.status!.song)
    idle()
  }

  func disconnect() {
    noIdle()
    commandQueue.async { [unowned self] in
      mpd_connection_free(self.connection)
    }
  }

  func fetchStatus() {
    sendCommand(command: .fetchStatus)
  }

  func fetchQueue() {
    sendCommand(command: .fetchQueue)
  }

  func fetchAllAlbums() {
    sendCommand(command: .fetchAllAlbums)
  }

  func playPause() {
    queueCommand(command: .playPause)
  }

  func stop() {
    queueCommand(command: .stop)
  }

  func prevTrack() {
    queueCommand(command: .prevTrack)
  }

  func nextTrack() {
    queueCommand(command: .nextTrack)
  }

  func queueCommand(command: Command) {
    noIdle()
    commandQueue.async { [unowned self] in
      self.sendCommand(command: command)
    }
    idle()
  }

  func sendCommand(command: Command) {
    print("Command:", command)
    switch command {

    // Transport commands
    case .prevTrack:
      sendPreviousTrack()
    case .nextTrack:
      sendNextTrack()
    case .stop:
      sendStop()
    case .playPause:
      sendPlay()
    case .fetchStatus:
      sendRunStatus()
    case .fetchQueue:
      sendFetchQueue()
    case .fetchAllAlbums:
      allAlbums()
    }
  }

  func sendNextTrack() {
    guard let state = status?.state,
      state.isOneOf([.playing, .paused])
      else { return }

    mpd_run_next(connection)
  }

  func sendPreviousTrack() {
    guard let state = status?.state,
      state.isOneOf([.playing, .paused])
      else { return }

    mpd_run_previous(connection)
  }

  func sendStop() {
    mpd_run_stop(connection)
  }

  func sendPlay() {
    if status?.state == .stopped {
      mpd_run_play(connection)
    } else {
      mpd_run_toggle_pause(connection)
    }
  }

  func sendRunStatus() {
    guard let status = mpd_run_status(connection) else { return }
    self.status = Status(status)
  }

  func sendFetchQueue() {
    self.queue = []
    mpd_send_list_queue_meta(connection)

    while let mpdSong = mpd_recv_song(connection) {
      let song = Song(mpdSong)
      self.queue.append(song)
    }
  }

  func allAlbums() {
    var albums: [Album] = []
    var artist: String = ""

    mpd_search_db_tags(self.connection, MPD_TAG_ALBUM)
    mpd_search_add_group_tag(self.connection, MPD_TAG_ALBUM_ARTIST)
    mpd_search_commit(self.connection)
    while let mpdPair = mpd_recv_pair(self.connection) {
      let name = String(cString: mpdPair.pointee.name)
      let value = String(cString: mpdPair.pointee.value)

      switch name {
      case "AlbumArtist":
        artist = value
      case "Album":
        albums.append(Album(title: value, artist: artist))
      default:
        break
      }
      
      mpd_return_pair(self.connection, mpdPair)
    }

    delegate?.didLoadAlbums(mpdClient: self, albums: albums)
  }

  func albumsForArtist(_ artist: String) -> [Album] {
    var albums: [Album] = []

    mpd_search_db_tags(self.connection, MPD_TAG_ALBUM)
    mpd_search_add_tag_constraint(self.connection, MPD_OPERATOR_DEFAULT, MPD_TAG_ARTIST, artist)
    mpd_search_commit(self.connection)
    while let mpdAlbumPair = mpd_recv_pair_tag(self.connection, MPD_TAG_ALBUM) {
      print(artist, "-", String(cString: mpdAlbumPair.pointee.value))
      albums.append(Album(title: String(cString: mpdAlbumPair.pointee.value), artist: artist))
      mpd_return_pair(self.connection, mpdAlbumPair)
    }

    return albums
  }

  func allArtists() -> [String] {
    var artists: [String] = []

    mpd_search_db_tags(self.connection, MPD_TAG_ARTIST)
    mpd_search_commit(self.connection)
    while let mpdArtistPair = mpd_recv_pair_tag(self.connection, MPD_TAG_ARTIST) {
      artists.append(String(cString: mpdArtistPair.pointee.value))
      mpd_return_pair(self.connection, mpdArtistPair)
    }

    return artists
  }

  func sendSearchDbTags(_ tagType: mpd_tag_type) {
    mpd_search_db_tags(self.connection, tagType)
    mpd_search_commit(self.connection)
    while let mpdPair = mpd_recv_pair_tag(self.connection, tagType) {
      print(String(cString: mpdPair.pointee.value))
      mpd_return_pair(self.connection, mpdPair)
    }
  }

  func noIdle() {
    mpd_send_noidle(connection)
  }

  func idle() {
    commandQueue.async { [unowned self] in
      mpd_send_idle(self.connection)
      let result = mpd_recv_idle(self.connection, true)

      self.handleIdleResult(result)
    }
  }

  func handleIdleResult(_ result: mpd_idle) {
    let mpdIdle = Idle(rawValue: result.rawValue)

    if mpdIdle.contains(.queue) {
      self.fetchQueue()
      self.delegate?.didUpdateQueue(mpdClient: self, queue: self.queue)
    }
    if mpdIdle.contains(.player) {
      self.fetchStatus()
      self.delegate?.didUpdateState(mpdClient: self, state: self.status!.state)
      self.delegate?.didUpdateQueuePos(mpdClient: self, song: self.status!.song)
    }
    if !mpdIdle.isEmpty {
      print("Status")
      self.idle()
    }
  }

  func getLastErrorMessage() -> String! {
    if mpd_connection_get_error(connection) == MPD_ERROR_SUCCESS {
      return "no error"
    }

    if let errorMessage = mpd_connection_get_error_message(connection) {
      return String(cString: errorMessage)
    }

    return "no error"
  }
}