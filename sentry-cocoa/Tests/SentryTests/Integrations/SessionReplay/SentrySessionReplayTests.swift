import Foundation
import Nimble
@testable import Sentry
import SentryTestUtils
import XCTest

#if os(iOS) || os(tvOS)
class SentrySessionReplayTests: XCTestCase {
    
    private class ScreenshotProvider: NSObject, SentryViewScreenshotProvider {
        func image(view: UIView, options: Sentry.SentryRedactOptions, onComplete: @escaping Sentry.ScreenshotCallback) {
            onComplete(UIImage.add)
        }
    }
     
    private class TestReplayMaker: NSObject, SentryReplayVideoMaker {
        
        var videoWidth: Int = 0
        var videoHeight: Int = 0
        
        struct CreateVideoCall {
            var duration: TimeInterval
            var beginning: Date
            var outputFileURL: URL
            var completion: ((Sentry.SentryVideoInfo?, Error?) -> Void)
        }
        
        var lastCallToCreateVideo: CreateVideoCall?
        func createVideoWith(duration: TimeInterval, beginning: Date, outputFileURL: URL, completion: @escaping (Sentry.SentryVideoInfo?, (Error)?) -> Void) throws {
            lastCallToCreateVideo = CreateVideoCall(duration: duration,
                                                        beginning: beginning,
                                                        outputFileURL: outputFileURL,
                                                        completion: completion)
            
            try? "Video Data".write(to: outputFileURL, atomically: true, encoding: .utf8)
            
            let videoInfo = SentryVideoInfo(path: outputFileURL, height: 1_024, width: 480, duration: duration, frameCount: 5, frameRate: 1, start: beginning, end: beginning.addingTimeInterval(duration), fileSize: 10)
            
            completion(videoInfo, nil)
        }
        
        var lastFrame: UIImage?
        func addFrameAsync(image: UIImage) {
            lastFrame = image
        }
        
        var lastReleaseUntil: Date?
        func releaseFramesUntil(_ date: Date) {
            lastReleaseUntil = date
        }
    }
    
    private class ReplayHub: SentryHub {
        var lastEvent: SentryReplayEvent?
        var lastRecording: SentryReplayRecording?
        var lastVideo: URL?
        
        override func capture(_ replayEvent: SentryReplayEvent, replayRecording: SentryReplayRecording, video videoURL: URL) {
            lastEvent = replayEvent
            lastRecording = replayRecording
            lastVideo = videoURL
        }
    }
    
    private class Fixture {
        let dateProvider = TestCurrentDateProvider()
        let random = TestRandom(value: 0)
        let screenshotProvider = ScreenshotProvider()
        let displayLink = TestDisplayLinkWrapper()
        let rootView = UIView()
        let hub = ReplayHub(client: SentryClient(options: Options()), andScope: nil)
        let replayMaker = TestReplayMaker()
        let cacheFolder = FileManager.default.temporaryDirectory
        
        func getSut(options: SentryReplayOptions = .init(sessionSampleRate: 0, errorSampleRate: 0) ) -> SentrySessionReplay {
            return SentrySessionReplay(settings: options,
                                       replayFolderPath: cacheFolder,
                                       screenshotProvider: screenshotProvider,
                                       replay: replayMaker,
                                       breadcrumbConverter: SentrySRDefaultBreadcrumbConverter(),
                                       touchTracker: SentryTouchTracker(dateProvider: dateProvider, scale: 0),
                                       dateProvider: dateProvider,
                                       random: random,
                                       displayLinkWrapper: displayLink)
        }
    }
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
        clearTestState()
    }
    
    private func startFixture() -> Fixture {
        let fixture = Fixture()
        SentrySDK.setCurrentHub(fixture.hub)
        return fixture
    }
    
    func testDontSentReplay_NoFullSession() {
        let fixture = startFixture()
        let sut = fixture.getSut()
        sut.start(fixture.rootView, fullSession: false)
        
        fixture.dateProvider.advance(by: 1)
        Dynamic(sut).newFrame(nil)
        fixture.dateProvider.advance(by: 5)
        Dynamic(sut).newFrame(nil)
        
        expect(fixture.hub.lastEvent) == nil
    }
    
    func testVideoSize() {
        let fixture = startFixture()
        let options = SentryReplayOptions(sessionSampleRate: 1, errorSampleRate: 1)
        let sut = fixture.getSut(options: options)
        let view = fixture.rootView
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 900)
        sut.start(fixture.rootView, fullSession: true)
        
        XCTAssertEqual(Int(320 * options.sizeScale), fixture.replayMaker.videoWidth)
        XCTAssertEqual(Int(900 * options.sizeScale), fixture.replayMaker.videoHeight)
    }
    
    func testSentReplay_FullSession() {
        let fixture = startFixture()
        
        let sut = fixture.getSut(options: SentryReplayOptions(sessionSampleRate: 1, errorSampleRate: 1))
        sut.start(fixture.rootView, fullSession: true)
        expect(fixture.hub.scope.replayId) == sut.sessionReplayId.sentryIdString
        
        fixture.dateProvider.advance(by: 1)
        
        let startEvent = fixture.dateProvider.date()
        
        Dynamic(sut).newFrame(nil)
        fixture.dateProvider.advance(by: 5)
        Dynamic(sut).newFrame(nil)
        
        guard let videoArguments = fixture.replayMaker.lastCallToCreateVideo else {
            fail("Replay maker create video was not called")
            return
        }
        
        expect(videoArguments.duration) == 5
        expect(videoArguments.beginning) == startEvent
        expect(videoArguments.outputFileURL) == fixture.cacheFolder.appendingPathComponent("segments/0.mp4")
        
        expect(fixture.hub.lastRecording) != nil
        expect(fixture.hub.lastVideo) == videoArguments.outputFileURL
        assertFullSession(sut, expected: true)
    }
    
    func testDontSentReplay_NotFullSession() {
        let fixture = startFixture()
        let sut = fixture.getSut(options: SentryReplayOptions(sessionSampleRate: 1, errorSampleRate: 1))
        sut.start(fixture.rootView, fullSession: false)
        
        expect(fixture.hub.scope.replayId) == nil
        
        fixture.dateProvider.advance(by: 1)
        
        Dynamic(sut).newFrame(nil)
        fixture.dateProvider.advance(by: 5)
        Dynamic(sut).newFrame(nil)
        
        let videoArguments = fixture.replayMaker.lastCallToCreateVideo
        
        expect(videoArguments) == nil
        assertFullSession(sut, expected: false)
    }
    
    func testChangeReplayMode_forErrorEvent() {
        let fixture = startFixture()
        let sut = fixture.getSut(options: SentryReplayOptions(sessionSampleRate: 1, errorSampleRate: 1))
        sut.start(fixture.rootView, fullSession: false)
        expect(fixture.hub.scope.replayId) == nil
        let event = Event(error: NSError(domain: "Some error", code: 1))
        
        sut.capture(for: event)
        expect(fixture.hub.scope.replayId) == sut.sessionReplayId.sentryIdString
        expect(event.context?["replay"]?["replay_id"] as? String) == sut.sessionReplayId.sentryIdString
        assertFullSession(sut, expected: true)
    }
    
    func testDontChangeReplayMode_forNonErrorEvent() {
        let fixture = startFixture()
        let sut = fixture.getSut(options: SentryReplayOptions(sessionSampleRate: 1, errorSampleRate: 1))
        sut.start(fixture.rootView, fullSession: false)
        
        let event = Event(level: .info)
        
        sut.capture(for: event)
        
        assertFullSession(sut, expected: false)
    }
    
    @available(iOS 16.0, tvOS 16, *)
    func testChangeReplayMode_forHybridSDKEvent() {
        let fixture = startFixture()
        let sut = fixture.getSut(options: SentryReplayOptions(sessionSampleRate: 1, errorSampleRate: 1))
        sut.start(fixture.rootView, fullSession: false)

        sut.capture()

        expect(fixture.hub.scope.replayId) == sut.sessionReplayId.sentryIdString
        assertFullSession(sut, expected: true)
    }

    @available(iOS 16.0, tvOS 16, *)
    func testSessionReplayMaximumDuration() {
        let fixture = startFixture()
        let sut = fixture.getSut(options: SentryReplayOptions(sessionSampleRate: 1, errorSampleRate: 1))
        sut.start(fixture.rootView, fullSession: true)
        
        Dynamic(sut).newFrame(nil)
        fixture.dateProvider.advance(by: 5)
        Dynamic(sut).newFrame(nil)
        expect(Dynamic(sut).isRunning) == true
        fixture.dateProvider.advance(by: 3_600)
        Dynamic(sut).newFrame(nil)
        
        expect(Dynamic(sut).isRunning) == false
    }
    
    @available(iOS 16.0, tvOS 16, *)
    func testDealloc_CallsStop() {
        let fixture = startFixture()
        func sutIsDeallocatedAfterCallingMe() {
            _ = fixture.getSut(options: SentryReplayOptions(sessionSampleRate: 1, errorSampleRate: 1))
        }
        sutIsDeallocatedAfterCallingMe()
        
        expect(fixture.displayLink.invalidateInvocations.count) == 1
    }

    func assertFullSession(_ sessionReplay: SentrySessionReplay, expected: Bool) {
        expect(Dynamic(sessionReplay).isFullSession) == expected
    }
}

#endif
