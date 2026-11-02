import Foundation
import Testing
@testable import Herdcats

struct SpacesRefreshPolicyTests {
    @Test func tuiPollsEveryFiveSeconds() {
        #expect(SpacesRefreshPolicy.interval(isCoreMode: false, eventsOpen: false) == 5)
        #expect(SpacesRefreshPolicy.interval(isCoreMode: false, eventsOpen: true) == 5)
    }

    @Test func coreWithOpenEventsFallsBackToSlowSafetyRefresh() {
        #expect(SpacesRefreshPolicy.interval(isCoreMode: true, eventsOpen: true) == 60)
    }

    @Test func coreWithClosedEventsPollsEveryFiveSeconds() {
        #expect(SpacesRefreshPolicy.interval(isCoreMode: true, eventsOpen: false) == 5)
    }

    @Test func intervalIsDueOnceElapsedReachesIt() {
        #expect(SpacesRefreshPolicy.isDue(elapsed: 5, interval: 5))
        #expect(!SpacesRefreshPolicy.isDue(elapsed: 55, interval: 60))
        #expect(SpacesRefreshPolicy.isDue(elapsed: 60, interval: 60))
        // Events dropped mid-wait: the shorter interval is due immediately.
        #expect(SpacesRefreshPolicy.isDue(elapsed: 10, interval: 5))
    }

    @Test func tuiStaysDueOnEveryTickEvenAfterAnotherRefresh() {
        var clock = SpacesAutoRefreshClock(epoch: 0)
        for epoch in [0, 1, 1, 5] {
            clock.advance(epoch: epoch)
            #expect(clock.isDue(interval: 5))
            clock.didRefresh(epoch: epoch)
        }
    }

    @Test func coreSafetyRefreshRestartsAfterAnotherRefresh() {
        var clock = SpacesAutoRefreshClock(epoch: 0)
        for _ in 0..<11 {
            clock.advance(epoch: 0)
            #expect(!clock.isDue(interval: 60))
        }
        // An event-driven refresh lands: the 60 s countdown starts over.
        clock.advance(epoch: 1)
        #expect(!clock.isDue(interval: 60))
        for _ in 0..<10 { clock.advance(epoch: 1) }
        #expect(!clock.isDue(interval: 60))
        clock.advance(epoch: 1)
        #expect(clock.isDue(interval: 60))
    }

    @Test func freshConnectionReportsCoreEventsClosed() async {
        #expect(await HerdrConnection().coreEventsOpen == false)
    }
}
