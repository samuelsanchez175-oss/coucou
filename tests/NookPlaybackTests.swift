import AVFoundation
import Foundation

@main
enum NookPlaybackTests {
    static func main() {
        testLauncherMarks()
        testPlayingCard()
        testPausedCardStays()
        testSourceFilter()
        testChromeShowsOnTheClosedNotch()
        testClosedNotchShowsArtworkAndWave()
        testChromeWireReachesTheNotch()
        testPictureInPictureChoosesTheVideo()
        testPictureStaysOnThisDesktop()
        testStemPipeline()
        testTapTempo()
        testSongFacts()
        testHomeAudioSitsUnderTheBlob()
        testTitleOpensThePlayingSource()
        print("Nook playback: 14 cases passed")
    }

    /// The home card shows the thumbnail under the blob only when a title exists.
    static func testHomeAudioSitsUnderTheBlob() {
        precondition(NookPlayback.showsHomeAudio(title: "Claude Opus 5.5") == true)
        precondition(NookPlayback.showsHomeAudio(title: "  ") == false)
        precondition(NookPlayback.showsHomeAudio(title: nil) == false)
        let overview = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandViewContent.swift", encoding: .utf8)
        guard let leftStart = overview.range(of: "Left card:"),
              let rightStart = overview.range(of: "Right card:") else {
            preconditionFailure("the home cards moved")
        }
        let left = String(overview[leftStart.lowerBound..<rightStart.lowerBound])
        precondition(left.contains("HomeAudioShelf"), "the thumbnail is not under the blob")
        guard let shelfStart = overview.range(of: "struct HomeAudioShelf"),
              let shelfEnd = overview.range(of: "struct EmptyStateView") else {
            preconditionFailure("the home audio shelf is missing")
        }
        let shelf = String(overview[shelfStart.lowerBound..<shelfEnd.lowerBound])
        precondition(shelf.contains("showsHomeAudio"), "the shelf shows without a title")
        precondition(shelf.contains("Now playing"), "the thumbnail has no name")
        precondition(!shelf.contains("No app seems to be running"), "an empty player sits under the blob")
    }

    /// The name under the white blob opens the app, or the browser tab, that is playing.
    static func testTitleOpensThePlayingSource() {
        precondition(NookPlayback.revealTarget(bundleID: "com.apple.Music", displayName: "Music") == .application("com.apple.Music"))
        precondition(NookPlayback.revealTarget(bundleID: "com.spotify.client", displayName: "Spotify") == .application("com.spotify.client"))
        precondition(NookPlayback.revealTarget(bundleID: "com.google.Chrome", displayName: "Google Chrome") == .browser("Google Chrome"))
        precondition(NookPlayback.revealTarget(bundleID: "com.google.Chrome", displayName: "YouTube") == .browser("Google Chrome"))
        precondition(NookPlayback.revealTarget(bundleID: "com.apple.Safari", displayName: "Safari") == .browser("Safari"))
        precondition(
            NookPlayback.revealTarget(
                bundleID: "com.google.Chrome.app.agimnkijcaahngcdmfeangaknmldooml",
                displayName: "YouTube"
            ) == .application("com.google.Chrome.app.agimnkijcaahngcdmfeangaknmldooml")
        )
        precondition(NookPlayback.revealTarget(bundleID: "com.apple.podcasts", displayName: "Podcasts") == .application("com.apple.podcasts"))
        precondition(NookPlayback.revealTarget(bundleID: "", displayName: "") == nil)
        precondition(NookPictureInPicture.prefersPlayingVideo("play", over: "have"))
        precondition(!NookPictureInPicture.prefersPlayingVideo("have", over: "play"))
        precondition(!NookPictureInPicture.prefersPlayingVideo("play", over: "play"))

        let overview = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandViewContent.swift", encoding: .utf8)
        guard let shelfStart = overview.range(of: "struct HomeAudioShelf"),
              let shelfEnd = overview.range(of: "struct EmptyStateView") else {
            preconditionFailure("the home audio shelf is missing")
        }
        let shelf = String(overview[shelfStart.lowerBound..<shelfEnd.lowerBound])
        precondition(shelf.contains("showPlayingSource"), "the name does not open what is playing")
        precondition(shelf.contains("Shows where this is playing."), "the name does not say what the click does")

        let board = try! String(contentsOfFile: "NotchBuddy/Sources/App/NookBoard.swift", encoding: .utf8)
        guard let boardStart = board.range(of: "func showPlayingSource"),
              let boardEnd = board.range(of: "func startTimer") else {
            preconditionFailure("opening the playing source is missing")
        }
        let open = String(board[boardStart.lowerBound..<boardEnd.lowerBound])
        precondition(open.contains("revealTarget"), "the click ignores which app is playing")
        precondition(open.contains("com.spotify.client"), "a missing Spotify is launched")
        precondition(open.contains("showPlaying"), "a browser video stays on the wrong tab")

        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/NookIslandView.swift", encoding: .utf8)
        guard let viewStart = view.range(of: "static func showPlaying"),
              let viewEnd = view.range(of: "private static func restoreFront") else {
            preconditionFailure("the browser is not brought to the video")
        }
        let show = String(view[viewStart.lowerBound..<viewEnd.lowerBound])
        precondition(show.contains("focusScript"), "the playing tab stays in the background")
        precondition(show.contains("activateIgnoringOtherApps"), "the browser stays behind this app")
        precondition(!show.contains("restoreFront"), "the click returns to the previous app")
    }

    /// Music keeps the app icon. Spotify is the wave circle. YouTube is the play tile.
    static func testLauncherMarks() {
        precondition(NookMediaPlatform.launcher == [.music, .spotify, .youtube])
        precondition(NookMediaPlatform.music.mark == "app-icon")
        precondition(NookMediaPlatform.spotify.mark == "wave-circle")
        precondition(NookMediaPlatform.youtube.mark == "play-tile")
        precondition(NookMediaPlatform.spotify.mark != "letter")
        precondition(NookMediaPlatform.youtube.mark != "letter")
    }

    /// A moving track or video replaces the launcher and shows Pause.
    static func testPlayingCard() {
        let card = NookPlayback.card(NookPlaybackFacts(
            title: "Estudando o samba",
            artist: "Tom Zé",
            bundleID: "com.spotify.client",
            displayName: "Spotify",
            rate: 1,
            position: 12,
            duration: 180
        ))
        precondition(card?.platform == .spotify)
        precondition(card?.playing == true)
        precondition(card?.transportSymbol == "pause.fill")
        let video = NookPlayback.card(NookPlaybackFacts(
            title: "A clip",
            artist: "",
            bundleID: "com.google.Chrome.app.agimnkijcaahngcdmfeangaknmldooml",
            displayName: "YouTube",
            rate: 1,
            position: 4,
            duration: 90
        ))
        precondition(video?.platform == .youtube)
        precondition(video?.transportSymbol == "pause.fill")
        precondition(NookPlayback.card(NookPlaybackFacts(
            title: "   ",
            artist: "",
            bundleID: "com.apple.Music",
            displayName: "Music",
            rate: 1,
            position: 0,
            duration: 0
        )) == nil)
    }

    /// Pause keeps the title up and switches the button to Play.
    static func testPausedCardStays() {
        let card = NookPlayback.card(NookPlaybackFacts(
            title: "Song",
            artist: "Artist",
            bundleID: "com.apple.Music",
            displayName: "Music",
            rate: 0,
            position: 40,
            duration: 200
        ))
        precondition(card != nil, "paused playback hid the player")
        precondition(card?.playing == false)
        precondition(card?.transportSymbol == "play.fill")
        precondition(card?.platform == .music)
    }

    /// System follows whichever app is playing. Music and Spotify stay on that app.
    static func testSourceFilter() {
        precondition(NookPlayback.accepts(platform: .youtube, preference: "system"))
        precondition(NookPlayback.accepts(platform: .music, preference: "music"))
        precondition(!NookPlayback.accepts(platform: .youtube, preference: "music"))
        precondition(NookPlayback.accepts(platform: .spotify, preference: "spotify"))
        precondition(!NookPlayback.accepts(platform: .music, preference: "spotify"))
        precondition(NookPlayback.accepts(platform: nil, preference: "system"))
        precondition(!NookPlayback.accepts(platform: nil, preference: "music"))
    }

    /// Chrome audio or video replaces the right-side faces even when the
    /// system reports the rate as stopped. A paused Music session stays faces.
    /// The shelf sits on the right, where those faces are.
    static func testChromeShowsOnTheClosedNotch() {
        precondition(NookPlayback.showsOnClosedNotch(
            bundleID: "com.google.Chrome",
            displayName: "Google Chrome",
            title: "A background clip",
            playing: false
        ), "chrome background video stayed off the closed notch")
        precondition(NookPlayback.showsOnClosedNotch(
            bundleID: "com.google.Chrome",
            displayName: "Google Chrome",
            title: "A background clip",
            playing: true
        ))
        precondition(!NookPlayback.showsOnClosedNotch(
            bundleID: "com.apple.Music",
            displayName: "Music",
            title: "Song",
            playing: false
        ), "paused music hid the terminal faces")
        precondition(NookPlayback.showsOnClosedNotch(
            bundleID: "com.apple.Music",
            displayName: "Music",
            title: "Song",
            playing: true
        ))
        precondition(!NookPlayback.showsOnClosedNotch(
            bundleID: "com.google.Chrome",
            displayName: "Google Chrome",
            title: "   ",
            playing: true
        ), "a blank chrome title replaced the faces")
        precondition(!NookPlayback.showsOnClosedNotch(
            bundleID: "com.google.Chrome.app.agimnkijcaahngcdmfeangaknmldooml",
            displayName: "YouTube",
            title: "A clip",
            playing: false
        ), "a paused youtube app hid the faces")
        let right = NookPlayback.closedShelfCenterX(islandWidth: 400, contentWidth: 48)
        precondition(right > 300, "media shelf stayed in the middle of the notch")
        precondition(abs(right - 360) < 0.5)
    }

    /// A playing session grows a right wing for the play button only.
    /// The matching left wing keeps the housing centered. The app icon,
    /// the waveform, and the song name stay off that closed notch.
    static func testClosedNotchShowsArtworkAndWave() {
        precondition(NookPlayback.mediaWingWidth(showing: false) == 0)
        let wing = NookPlayback.mediaWingWidth(showing: true)
        precondition(wing == 36, "the play button does not need the chrome icon and the wave")
        let notch: CGFloat = 251
        let width = notch + wing * 2
        let center = NookPlayback.mediaShelfCenterX(islandWidth: width, wing: wing)
        precondition(center > width / 2, "the play button stayed off the right wing")
        precondition(abs(center - (width - wing / 2)) < 0.5)
        let housing = NookPlayback.housingEdges(islandWidth: width, notchWidth: notch)
        let title = NookPlayback.mediaTitlePlacement(islandWidth: width, notchWidth: notch)
        precondition(title.maxWidth == 0, "the closed notch still shows the track name")
        let shelfLeft = center - NookPlayback.shelfContentWidth / 2
        precondition(NookPlayback.shelfContentWidth == 18, "the play button is still as wide as the old shelf")
        precondition(shelfLeft + 0.5 >= housing.trailing, "the play button crosses the camera")
        let blocked = NookPlayback.mediaTitlePlacement(islandWidth: notch, notchWidth: notch)
        precondition(blocked.maxWidth == 0, "a title with no wing still uses the camera")
        let root = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandRootView.swift", encoding: .utf8)
        precondition(root.contains("mediaTitlePlacement"), "the title still sits on the camera")
        precondition(root.contains("edge.id == \"media\""), "the song line still uses the center")
        precondition(!NookPlayback.waveIsMoving(reportedPlaying: false, outputRunning: false))
        precondition(NookPlayback.waveIsMoving(reportedPlaying: true, outputRunning: false))
        precondition(NookPlayback.waveIsMoving(reportedPlaying: false, outputRunning: true), "a loud Chrome tab left the waveform still")
        let moving = NookPlayback.barHeights(phase: 0.4, moving: true)
        precondition(moving.count == 7)
        precondition(moving.allSatisfy { $0 >= 0.28 && $0 <= 1 })
        precondition(Set(moving.map { Int($0 * 100) }).count > 1, "the waveform was a flat line")
        let resting = NookPlayback.barHeights(phase: 0.4, moving: false)
        precondition(resting == Array(repeating: 0.22, count: 7))
        let lifted = NookPlayback.waveTint(red: 0, green: 0, blue: 0)
        precondition(lifted.0 >= 0.7 && lifted.1 >= 0.7 && lifted.2 >= 0.7, "a black cover disappeared on the notch")
        let cover = NookPlayback.waveTint(red: 0.40, green: 0.54, blue: 0.50)
        precondition(abs(max(cover.0, cover.1, cover.2) - 0.78) < 0.02)
        let shelf = try! String(contentsOfFile: "NotchBuddy/Sources/App/NookIslandView.swift", encoding: .utf8)
        guard let start = shelf.range(of: "struct NotchMediaShelf"),
              let end = shelf.range(of: "struct LiveActivityPill") else {
            preconditionFailure("the closed notch player is missing")
        }
        let body = String(shelf[start.lowerBound..<end.lowerBound])
        precondition(body.contains("mediaShelfCenterX"), "the play button is not on the right wing")
        precondition(body.contains("togglePlayback"), "the closed notch has no play button")
        precondition(!body.contains("Audio waveform"), "the wave is still beside the play button")
        precondition(!body.contains("barHeights"), "the wave is still drawn on the closed notch")
        precondition(!body.contains("func artwork"), "the chrome thumbnail is still beside the play button")
        precondition(!body.contains("mediaTitle"), "the closed notch shows the track name")
    }

    /// A now-playing line from the system reader reaches the closed notch.
    /// Chrome stays visible when the rate is stopped. A broken line does not.
    static func testChromeWireReachesTheNotch() {
        let line = "{\"ok\":true,\"bundle\":\"com.google.Chrome\",\"name\":\"Google Chrome\",\"title\":\"A background clip\",\"artist\":\"\",\"playing\":false,\"rate\":0,\"position\":3,\"duration\":20,\"art\":\"/tmp/coucou-now-playing.jpg\",\"stamp\":12}"
        let wire = NowPlayingWireLine.decode(line)
        precondition(wire?.bundleID == "com.google.Chrome", "chrome bundle was dropped")
        precondition(wire?.displayName == "Google Chrome")
        precondition(wire?.title == "A background clip")
        precondition(wire?.playing == false, "a stopped chrome rate was treated as moving")
        precondition(wire?.position == 3)
        precondition(wire?.duration == 20)
        precondition(wire?.artworkPath == "/tmp/coucou-now-playing.jpg")
        precondition(wire?.artworkStamp == 12)
        precondition(NookPlayback.showsOnClosedNotch(
            bundleID: wire?.bundleID ?? "",
            displayName: wire?.displayName ?? "",
            title: wire?.title,
            playing: wire?.playing ?? false
        ), "a decoded chrome session stayed off the closed notch")
        let moving = NowPlayingWireLine.decode("{\"ok\":true,\"bundle\":\"com.apple.Music\",\"name\":\"Music\",\"title\":\"Song\",\"playing\":false,\"rate\":1}")
        precondition(moving?.playing == true, "a moving rate stayed paused")
        precondition(moving?.artworkPath == nil)
        precondition(NowPlayingWireLine.decode("{\"ok\":false}") == nil)
        precondition(NowPlayingWireLine.decode("not json") == nil)
        precondition(NowPlayingWireLine.decode("{\"ok\":true,\"title\":\"  \",\"bundle\":\"com.google.Chrome\"}") == nil)
    }

    /// The player button floats a browser video, and an album when there is no video.
    /// The click lands in the page, clear of the title bar. A blank session has no button.
    static func testPictureInPictureChoosesTheVideo() {
        precondition(NookPictureInPicture.kind(
            bundleID: "com.google.Chrome", displayName: "Google Chrome", hasTitle: true
        ) == .browser("Google Chrome"))
        precondition(NookPictureInPicture.kind(
            bundleID: "com.apple.Safari", displayName: "Safari", hasTitle: true
        ) == .browser("Safari"))
        precondition(NookPictureInPicture.kind(
            bundleID: "com.google.Chrome.app.agimnkijcaahngcdmfeangaknmldooml",
            displayName: "YouTube",
            hasTitle: true
        ) == .browser("Google Chrome"))
        precondition(NookPictureInPicture.kind(
            bundleID: "com.apple.Music", displayName: "Music", hasTitle: true
        ) == .artwork)
        precondition(NookPictureInPicture.kind(
            bundleID: "com.spotify.client", displayName: "Spotify", hasTitle: true
        ) == .artwork)
        precondition(NookPictureInPicture.kind(
            bundleID: "com.google.Chrome", displayName: "Google Chrome", hasTitle: false
        ) == .unavailable)

        let point = NookPictureInPicture.click(left: 190, top: 45, right: 1844, bottom: 1330)
        precondition(point?.x == 1017)
        precondition(point?.y == 45 + 360)
        precondition(NookPictureInPicture.click(left: 0, top: 0, right: 40, bottom: 30) == nil)

        precondition(NookPictureInPicture.outcome("in-pip entered") == .entered)
        precondition(NookPictureInPicture.outcome("in-pip") == .entered)
        // A leftover "entered" mark is not a floating picture.
        precondition(NookPictureInPicture.outcome("not-pip entered") == .failed)
        precondition(NookPictureInPicture.outcome("not-pip exited") == .exited)
        precondition(NookPictureInPicture.outcome("not-pip err-NotAllowedError") == .failed)
        precondition(NookPictureInPicture.outcome("") == .failed)
        precondition(NookPictureInPicture.hookScript().contains("window.__coucouPip=''"))

        precondition(NookPictureInPicture.buttonSymbol(active: false) == "pip.enter")
        precondition(NookPictureInPicture.buttonSymbol(active: true) == "pip.exit")
        precondition(NookPictureInPicture.buttonLabel(active: false) == "Picture in picture")
        precondition(NookPictureInPicture.buttonLabel(active: true) == "Exit picture in picture")
        precondition(NookPictureInPicture.hookScript().contains("requestPictureInPicture"))
        precondition(NookPictureInPicture.hookScript().contains("isTrusted"))
        precondition(NookPictureInPicture.hookScript().contains("preventDefault"))
        precondition(NookPictureInPicture.hookScript().contains("querySelectorAll"))
        precondition(!NookPictureInPicture.hookScript().contains("document.title"))
    }

    /// The home button floats the picture on the desktop the person is already using.
    /// It must not activate the browser before it knows a new picture has to be opened.
    static func testPictureStaysOnThisDesktop() {
        precondition(NookPictureInPicture.step(buttonIsOn: false, videoState: "play") == .enterWithoutLeaving)
        precondition(NookPictureInPicture.step(buttonIsOn: false, videoState: "have") == .enterWithoutLeaving)
        precondition(NookPictureInPicture.step(buttonIsOn: false, videoState: "in") == .showExisting)
        precondition(NookPictureInPicture.step(buttonIsOn: true, videoState: "in") == .exitWithoutLeaving)
        precondition(NookPictureInPicture.step(buttonIsOn: false, videoState: "none") == .unavailable)
        precondition(NookPictureInPicture.step(buttonIsOn: true, videoState: "none") == .unavailable)

        let frame = NookPictureInPicture.parseVideo("play 16 68 1451 726 190 45")
        precondition(frame?.state == "play")
        precondition(frame?.width == 1451)
        let point = NookPictureInPicture.videoClick(
            frame!,
            windowLeft: 190, windowTop: 45, windowRight: 1844, windowBottom: 1330
        )
        precondition(point?.x == 931.5)
        precondition(point?.y == 393)
        // The open notch covers this spot on every desktop, so the press must move below it.
        let notch = NookPictureInPicture.ScreenRect(left: 604, top: 0, right: 1443, bottom: 400)
        let below = NookPictureInPicture.videoClick(
            frame!,
            windowLeft: 190, windowTop: 45, windowRight: 1844, windowBottom: 1330,
            coveredBy: notch
        )
        precondition(below?.x == 931.5)
        precondition(below?.y == 424)
        precondition(!notch.contains(below!.x, below!.y))
        let hidden = NookPictureInPicture.parseVideo("have 0 0 0 0 190 45 hidden")
        precondition(hidden?.state == "have")
        precondition(!NookPictureInPicture.frameIsLaidOut(hidden!))
        precondition(NookPictureInPicture.frameIsLaidOut(frame!))
        precondition(!NookPictureInPicture.pageIsVisible("have 0 0 0 0 190 45 hidden"))
        precondition(NookPictureInPicture.pageIsVisible("play 16 68 1451 726 190 45 visible"))
        let pushed = NookPictureInPicture.videoClick(
            hidden!,
            windowLeft: 190, windowTop: 45, windowRight: 1844, windowBottom: 1330,
            coveredBy: NookPictureInPicture.ScreenRect(left: 604, top: 0, right: 1443, bottom: 450)
        )
        precondition(pushed?.y == 474)
        let covered = NookPictureInPicture.videoClick(
            frame!,
            windowLeft: 190, windowTop: 45, windowRight: 1844, windowBottom: 1330,
            coveredBy: NookPictureInPicture.ScreenRect(left: 0, top: 0, right: 2048, bottom: 1330)
        )
        precondition(covered?.x == 931.5)
        precondition(covered?.y == 393)
        precondition(NookPictureInPicture.isPictureWindow(
            width: 921, height: 461, browserWidth: 1654, browserHeight: 1285
        ))
        precondition(!NookPictureInPicture.isPictureWindow(
            width: 1654, height: 1285, browserWidth: 1654, browserHeight: 1285
        ))
        precondition(!NookPictureInPicture.isPictureWindow(
            width: 149, height: 21, browserWidth: 1654, browserHeight: 1285
        ))
        precondition(NookPictureInPicture.keepWaiting(read: "not-pip ", tries: 0, limit: 8))
        precondition(NookPictureInPicture.keepWaiting(read: "not-pip entered", tries: 0, limit: 12))
        precondition(!NookPictureInPicture.keepWaiting(read: "in-pip entered", tries: 0, limit: 8))
        precondition(!NookPictureInPicture.keepWaiting(read: "not-pip ", tries: 8, limit: 8))
        precondition(NookPictureInPicture.pictureReady(read: "in-pip entered", pictureOnScreen: true))
        precondition(!NookPictureInPicture.pictureReady(read: "in-pip entered", pictureOnScreen: false))
        precondition(!NookPictureInPicture.pictureReady(read: "not-pip entered", pictureOnScreen: true))
        precondition(NookPictureInPicture.route(browserOnThisDesktop: true) == .enterHere)
        precondition(NookPictureInPicture.route(browserOnThisDesktop: false) == .mirrorHere)
        // A picture that already exists on another desktop is brought here.
        // A second event from the same press is ignored.
        precondition(NookPictureInPicture.place(
            step: .showExisting, browserOnThisDesktop: false, pictureOnThisDesktop: false
        ) == .mirrorHere)
        precondition(NookPictureInPicture.place(
            step: .showExisting, browserOnThisDesktop: false, pictureOnThisDesktop: true
        ) == .raiseHere)
        precondition(NookPictureInPicture.place(
            step: .enterWithoutLeaving, browserOnThisDesktop: false, pictureOnThisDesktop: false
        ) == .mirrorHere)
        precondition(NookPictureInPicture.place(
            step: .enterWithoutLeaving, browserOnThisDesktop: true, pictureOnThisDesktop: false
        ) == .enterHere)
        precondition(!NookPictureInPicture.acceptsPress(secondsSinceLast: 0))
        precondition(!NookPictureInPicture.acceptsPress(secondsSinceLast: 0.2))
        precondition(NookPictureInPicture.acceptsPress(secondsSinceLast: 0.35))
        let crop = NookPictureInPicture.mirrorCrop(
            frame: frame!, windowWidth: 1654, windowHeight: 1285
        )
        precondition(crop?.left == 16)
        precondition(crop?.top == 68)
        precondition(crop?.right == 1467)
        precondition(crop?.bottom == 794)
        let fallback = NookPictureInPicture.mirrorCrop(
            frame: hidden!, windowWidth: 1654, windowHeight: 1285
        )
        precondition(fallback?.top == 92)
        precondition(fallback?.left == 0)
        precondition(fallback?.right == 1654)
        precondition(fallback?.bottom == 1285)
        precondition(NookPictureInPicture.videoFrameScript().contains("screenX"))
        precondition(NookPictureInPicture.videoFrameScript().contains("visibilityState"))
        precondition(NookPictureInPicture.hookScript().contains("videoWidth"))
        // One press may click more than once. A miss must leave the listener in place.
        let hook = NookPictureInPicture.hookScript()
        let noVideo = hook.range(of: "no-video")!.lowerBound
        let requestAt = hook.range(of: "requestPictureInPicture")!.lowerBound
        let removeAt = hook.range(of: "removeEventListener")!.lowerBound
        precondition(noVideo < removeAt, "a miss must leave the hook in place")
        precondition(requestAt < removeAt, "the hook stays until the picture is requested")
        // The notch has to be gone before the first click. Later clicks stay in the same press.
        precondition(!NookPictureInPicture.notchIsClear(cover: notch, x: 931.5, y: 393))
        precondition(NookPictureInPicture.notchIsClear(cover: notch, x: 931.5, y: 424))
        precondition(NookPictureInPicture.notchIsClear(cover: nil, x: 931.5, y: 393))
        precondition(NookPictureInPicture.nextPress(read: "", clicksSent: 0, pollsSinceClick: 0) == .click)
        precondition(NookPictureInPicture.nextPress(read: "not-pip ", clicksSent: 1, pollsSinceClick: 0) == .wait)
        precondition(NookPictureInPicture.nextPress(read: "not-pip err-NotAllowedError", clicksSent: 1, pollsSinceClick: 3) == .click)
        precondition(NookPictureInPicture.nextPress(read: "not-pip ", clicksSent: 6, pollsSinceClick: 3) == .stop)
        precondition(NookPictureInPicture.nextPress(read: "in-pip entered", clicksSent: 1, pollsSinceClick: 0) == .stop)
        precondition(NookPictureInPicture.nextPress(read: "not-pip exited", clicksSent: 1, pollsSinceClick: 0) == .stop)
        let spots = NookPictureInPicture.clickSpots(
            primary: NookPictureInPictureClick(x: 931.5, y: 424),
            windowLeft: 190, windowTop: 45, windowRight: 1844, windowBottom: 1330
        )
        precondition(spots.count >= 4)
        precondition(spots.first?.x == 931.5)
        precondition(spots.first?.y == 424)
        // A picture that already exists on another desktop is the window to show.
        let listed = [
            NookPictureInPicture.ListedWindow(id: 21907, owner: "Google Chrome", width: 1654, height: 1285, onScreen: false, layer: 0),
            NookPictureInPicture.ListedWindow(id: 22955, owner: "Google Chrome", width: 457, height: 257, onScreen: false, layer: 3),
            NookPictureInPicture.ListedWindow(id: 9, owner: "Coucou", width: 312, height: 237, onScreen: false, layer: 101)
        ]
        let picture = NookPictureInPicture.offscreenPicture(among: listed, browserWidth: 1654, browserHeight: 1285)
        precondition(picture?.id == 22955)
        let full = NookPictureInPicture.pictureCrop(width: 457, height: 257)
        precondition(full.left == 0)
        precondition(full.top == 0)
        precondition(full.right == 457)
        precondition(full.bottom == 257)
        precondition(NookPictureInPicture.captureAsk(alreadyAllowed: true, alreadyAsked: false) == .allowed)
        precondition(NookPictureInPicture.captureAsk(alreadyAllowed: false, alreadyAsked: false) == .ask)
        precondition(NookPictureInPicture.captureAsk(alreadyAllowed: false, alreadyAsked: true) == .skip)

        let text = try! String(contentsOfFile: "NotchBuddy/Sources/App/NookIslandView.swift", encoding: .utf8)
        let toggle = sourceSlice(text, from: "static func toggle(application:", until: "private struct Choice")
        precondition(toggle.contains("NookPictureInPicture.step"))
        precondition(toggle.contains(".showExisting"))
        precondition(toggle.contains(".mirror("))
        precondition(toggle.contains("route(browserOnThisDesktop:"))
        precondition(toggle.contains("place(step:"))
        let mirrorStart = sourceSlice(text, from: "func startMirror", until: "func stopMirror")
        precondition(mirrorStart.contains("CGRequestScreenCaptureAccess"))
        precondition(text.contains("hidesOnDeactivate = false"))
        precondition(text.contains("acceptsPress(secondsSinceLast:"))
        precondition(!toggle.contains("activate("))
        precondition(!toggle.contains("revealBrowser"))
        let enter = sourceSlice(text, from: "func enterWithoutLeaving", until: "private struct Choice")
        precondition(!enter.contains("revealBrowser"))
        precondition(enter.contains("waitForFrame"))
        precondition(enter.contains("coveredBy:"))
        precondition(enter.contains("setClicksPassThrough(true)"))
        precondition(enter.contains("setNotchHidden(true)"))
        precondition(enter.contains("waitForPicture"))
        precondition(text.contains("ignoresMouseEvents"))
        precondition(text.contains("desktopIndependentWindow"))
        let passAt = enter.range(of: "setClicksPassThrough(true)")!.lowerBound
        let hideAt = enter.range(of: "setNotchHidden(true)")!.lowerBound
        let clickAt = enter.range(of: "click(x:")!.lowerBound
        let pictureAt = enter.range(of: "waitForPicture")!.lowerBound
        let restoreMouse = enter.range(of: "setClicksPassThrough(false)")!.lowerBound
        let showAt = enter.range(of: "setNotchHidden(false)")!.lowerBound
        let backAt = enter.range(of: "restoreFront", options: .backwards)!.lowerBound
        precondition(hideAt < clickAt)
        precondition(passAt < clickAt)
        precondition(clickAt < pictureAt)
        precondition(pictureAt < restoreMouse)
        precondition(restoreMouse < showAt)
        precondition(showAt < backAt)
        let clearAt = enter.range(of: "notchIsClear")!.lowerBound
        precondition(hideAt < clearAt)
        precondition(clearAt < clickAt)
        precondition(enter.contains("nextPress(read:"))
        precondition(enter.contains("clickSpots("))
        precondition(toggle.contains("offscreenPicture("))
        precondition(toggle.contains("pictureCrop("))
        precondition(mirrorStart.contains("captureAsk("))
        precondition(!text.contains("nook.pipMirrorProbe"))
        precondition(!text.contains("coucou-pip-frames.txt"))
        let begin = sourceSlice(text, from: "private func begin()", until: "private func showPanel")
        precondition(!begin.contains("CGRequestScreenCaptureAccess"))
        precondition(begin.contains("CGPreflightScreenCaptureAccess"))
    }

    static func sourceSlice(_ text: String, from start: String, until end: String) -> String {
        guard let from = text.range(of: start),
              let to = text.range(of: end, range: from.upperBound..<text.endIndex) else {
            preconditionFailure("missing \(start)")
        }
        return String(text[from.lowerBound..<to.lowerBound])
    }

    /// A song uses Logic's stem splitter. Other files stay on AirDrop.
    /// The pipeline stays off the AirDrop path when Logic is missing.
    static func testStemPipeline() {
        precondition(NookStemPipeline.isSong("/tmp/song.wav"))
        precondition(NookStemPipeline.isSong("/tmp/Song.MP3"))
        precondition(NookStemPipeline.isSong("/tmp/take.aiff"))
        precondition(NookStemPipeline.isSong("/tmp/voice.m4a"))
        precondition(!NookStemPipeline.isSong("/tmp/notes.pdf"))
        precondition(!NookStemPipeline.isSong("/tmp/clip.mp4"))
        precondition(NookStemPipeline.route(
            paths: ["/tmp/song.wav"], enabled: true, logicInstalled: true, appleSilicon: true
        ) == .stems)
        precondition(NookStemPipeline.route(
            paths: ["/tmp/song.wav"], enabled: false, logicInstalled: true, appleSilicon: true
        ) == .airDrop)
        precondition(NookStemPipeline.route(
            paths: ["/tmp/notes.pdf"], enabled: true, logicInstalled: true, appleSilicon: true
        ) == .airDrop)
        precondition(NookStemPipeline.route(
            paths: ["/tmp/song.wav", "/tmp/notes.pdf"], enabled: true, logicInstalled: false, appleSilicon: true
        ) == .needsLogic)
        precondition(NookStemPipeline.route(
            paths: ["/tmp/song.aiff"], enabled: true, logicInstalled: true, appleSilicon: false
        ) == .needsAppleSilicon)
        precondition(NookStemPipeline.songPaths(["/tmp/a.wav", "/tmp/b.pdf"]) == ["/tmp/a.wav"])
        precondition(NookStemPipeline.otherPaths(["/tmp/a.wav", "/tmp/b.pdf"]) == ["/tmp/b.pdf"])
        precondition(NookStemPipeline.songName("/tmp/Demo.wav") == "Demo")
        precondition(NookStemPipeline.note(route: .needsLogic, songName: "Demo").contains("not installed"))
        precondition(NookStemPipeline.note(route: .stems, songName: "Demo").contains("Logic Pro"))
        precondition(NookStemPipeline.finishedNote(songName: "Demo", result: "ok").contains("muted"))
    }

    /// Two taps set the tempo. A pause longer than the gap starts a new count.
    static func testTapTempo() {
        precondition(TapTempo.bpm(tapTimes: []) == nil)
        precondition(TapTempo.bpm(tapTimes: [10]) == nil)
        precondition(TapTempo.bpm(tapTimes: [0, 0.5]) == 120)
        precondition(TapTempo.bpm(tapTimes: [0, 0.5, 1.0, 1.5]) == 120)
        precondition(TapTempo.bpm(tapTimes: [0, 0.5, 4.0]) == nil)
        precondition(TapTempo.bpm(tapTimes: [0, 0.5, 4.0, 4.5]) == 120)
        precondition(TapTempo.resetAfter == 2.2)
    }

    /// A local reading reports BPM, key, Camelot, and energy without a browser.
    static func testSongFacts() {
        precondition(SongFacts.camelot(pitchClass: 9, minor: true) == "8A")
        precondition(SongFacts.camelot(pitchClass: 0, minor: false) == "8B")
        precondition(SongFacts.camelot(pitchClass: 6, minor: true) == "11A")
        precondition(SongFacts.keyName(pitchClass: 9, minor: false) == "A major")
        precondition(SongFacts.energy(of: []) == 0)
        precondition(SongFacts.energy(of: [Float](repeating: 0, count: 2000)) == 0)

        let rate = 22050.0
        let clicks = clickTrain(sampleRate: rate, bpm: 120, seconds: 8)
        let clickRead = SongFacts.analyze(samples: clicks, sampleRate: rate)
        let clickTempo = clickRead?.bpm ?? -1
        precondition(clickTempo >= 118 && clickTempo <= 123, "click tempo \(clickTempo)")

        let chord = majorChord(sampleRate: rate, seconds: 4)
        let chordRead = SongFacts.analyze(samples: chord, sampleRate: rate)
        precondition(chordRead?.keyName == "A major", chordRead?.keyName ?? "no key")
        precondition(chordRead?.camelot == "11B", chordRead?.camelot ?? "no camelot")
        precondition(chordRead?.bpm == nil, "a held chord reported \(chordRead?.bpm ?? -1) BPM")

        precondition(SongFacts.scaleNotes(keyName: "A minor") == ["A", "B", "C", "D", "E", "F", "G"])
        precondition(SongFacts.scaleNotes(keyName: "A major") == ["A", "B", "C♯", "D", "E", "F♯", "G♯"])
        precondition(SongFacts.scaleNotes(keyName: "C major") == ["C", "D", "E", "F", "G", "A", "B"])
        precondition(SongFacts.scaleNotes(keyName: "F major") == ["F", "G", "A", "B♭", "C", "D", "E"])
        precondition(SongFacts.scaleNotes(keyName: "F♯ minor") == ["F♯", "G♯", "A", "B", "C♯", "D", "E"])
        precondition(SongFacts.keyColorHex(keyName: "A minor") == SongFacts.noteColorHex("A"))
        precondition(SongFacts.keyColorHex(keyName: "C major") == "#5CA3EB")
        precondition(SongFacts.noteColorHex("A") == "#EB5CEB")
        precondition(SongFacts.noteColorHex("B") == "#EB5C5C")
        precondition(SongFacts.noteColorHex("C♯") == SongFacts.noteColorHex("D♭"))
        let wheel = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        precondition(Set(wheel.map { SongFacts.noteColorHex($0) }).count == 12)

        let line = SongReadout(bpm: 120, keyName: "A minor", camelot: "8A", energy: 40).line
        precondition(line.contains("120 BPM"))
        precondition(line.contains("8A"))
        precondition(line.contains("A B C D E F G"))
        precondition(line.contains("Energy 40"))

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("coucou-song-facts-\(UUID().uuidString).wav")
        writeWav(chord, sampleRate: rate, to: url)
        let fromFile = SongFacts.read(url: url)
        try? FileManager.default.removeItem(at: url)
        precondition(fromFile?.keyName == "A major", fromFile?.keyName ?? "file had no key")
        precondition(fromFile?.camelot == "11B")
        precondition(SongFacts.read(url: URL(fileURLWithPath: "/tmp/notes.pdf")) == nil)
    }

    private static func clickTrain(sampleRate: Double, bpm: Double, seconds: Double) -> [Float] {
        let count = Int(sampleRate * seconds)
        var samples = [Float](repeating: 0, count: count)
        let period = Int(sampleRate * 60.0 / bpm)
        let burst = 220
        var start = 0
        while start < count {
            let end = min(count, start + burst)
            for index in start..<end {
                let time = Double(index - start) / sampleRate
                samples[index] = Float(sin(2 * Double.pi * 1000 * time) * 0.8)
            }
            start += period
        }
        return samples
    }

    private static func majorChord(sampleRate: Double, seconds: Double) -> [Float] {
        let count = Int(sampleRate * seconds)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let a = sin(2 * Double.pi * 440 * time)
            let sharp = sin(2 * Double.pi * 554.37 * time)
            let e = sin(2 * Double.pi * 659.25 * time)
            samples[index] = Float((a + sharp + e) / 3 * 0.5)
        }
        return samples
    }

    private static func writeWav(_ samples: [Float], sampleRate: Double, to url: URL) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let file = try? AVAudioFile(forWriting: url, settings: format.settings) else {
            preconditionFailure("could not write \(url.path)")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let address = source.baseAddress, let channel = buffer.floatChannelData else { return }
            channel[0].update(from: address, count: samples.count)
        }
        do { try file.write(from: buffer) } catch {
            preconditionFailure("could not write wav: \(error)")
        }
    }
}
