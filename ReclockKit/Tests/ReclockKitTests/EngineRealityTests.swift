import Foundation
import Testing
@testable import ReclockKit

@Suite("Reality constraints")
struct EngineRealityTests {

    @Test("All demo trips produce valid plans with arrival-day guidance")
    func allDemoTripsValid() throws {
        for (trip, profile) in DemoTrips.all(reference: TestSupport.reference) {
            let plan = try TestSupport.generateValidPlan(trip: trip, profile: profile)
            #expect(!plan.actions.isEmpty, "\(trip.name) plan has no actions")
            // At least one non-comfort recommendation on arrival day (validator enforces too).
            if let arrival = trip.outboundArrival {
                let window = TimeWindow(start: arrival.adding(hours: -2), end: arrival.adding(hours: 26))
                #expect(
                    plan.actions.contains { $0.window.overlaps(window) && !$0.type.isComfort },
                    "\(trip.name) has no arrival-day recommendation"
                )
            }
        }
    }

    @Test("No sleep scheduled during boarding, takeoff, or landing buffers")
    func noSleepInBlockedFlightPhases() throws {
        for (trip, profile) in DemoTrips.all(reference: TestSupport.reference) {
            let plan = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
            for action in plan.actions where action.type == .sleep || action.type == .nap {
                for segment in trip.segments {
                    let takeoff = TimeWindow(
                        start: segment.departure.adding(minutes: -45),
                        end: segment.departure.adding(minutes: 45)
                    )
                    let landing = TimeWindow(
                        start: segment.arrival.adding(minutes: -75),
                        end: segment.arrival
                    )
                    #expect(!action.window.overlaps(takeoff), "\(trip.name): sleep during boarding/takeoff")
                    #expect(!action.window.overlaps(landing), "\(trip.name): sleep during descent")
                }
            }
        }
    }

    @Test("Traveler who never sleeps on planes gets rest guidance, not sleep orders")
    func cantSleepOnPlanes() throws {
        let trip = DemoTrips.parisRedEye(reference: TestSupport.reference)
        let profile = DemoTrips.cantSleepOnPlanesProfile()
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: profile)
        let flightWindow = trip.segments[0].window
        for action in plan.actions where action.type == .sleep {
            if action.window.overlaps(flightWindow) {
                #expect(action.ruleReference.hasPrefix("v1/rest"), "in-flight sleep promised to a never-sleeper")
                #expect(action.priority != .mustDo)
            }
        }
    }

    @Test("In-flight sleep respects the stated realistic maximum")
    func inFlightSleepCap() throws {
        var profile = DemoTrips.defaultProfile(homeZone: "America/Los_Angeles")
        profile.maxInFlightSleep = .hours(3)
        let trip = DemoTrips.losAngelesToTokyo(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: profile)
        for action in plan.actions where action.type == .sleep && !action.ruleReference.hasPrefix("v1/rest") {
            for segment in trip.segments {
                if let overlap = action.window.intersection(segment.window) {
                    #expect(overlap.duration <= .hours(3) + .minutes(10))
                }
            }
        }
    }

    @Test("Caffeine opt-out removes all caffeine guidance")
    func caffeineOptOut() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.noStimulantsProfile())
        #expect(!plan.actions.contains { $0.type == .caffeineOK || $0.type == .caffeineCutoff })
    }

    @Test("Melatonin appears only for opted-in users, always with the disclaimer")
    func melatoninOptIn() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)

        let optedOut = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.noStimulantsProfile())
        #expect(!optedOut.actions.contains { $0.type == .melatoninOptional })

        let optedIn = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        let melatoninActions = optedIn.actions.filter { $0.type == .melatoninOptional }
        #expect(!melatoninActions.isEmpty, "advance trip with opt-in should offer reminders")
        for action in melatoninActions {
            #expect(action.priority == .optional)
            #expect(action.explanation.contains("not medical advice"))
        }
    }

    @Test("Wedding on arrival evening is protected: no sleep or nap overlaps it")
    func weddingCommitment() throws {
        let trip = DemoTrips.weddingTrip(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile(homeZone: "America/Los_Angeles")
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: profile)
        let wedding = trip.commitments[0].window
        for action in plan.actions where action.type == .sleep || action.type == .nap {
            #expect(!action.window.overlaps(wedding), "sleep/nap scheduled during the wedding")
        }
    }

    @Test("Short 2-night trip anchors to home time")
    func shortTripAnchors() throws {
        let trip = DemoTrips.shortLondonBusinessTrip(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        #expect(plan.strategy == .anchorToHome)
        #expect(plan.shiftDirection == ShiftDirection.none)
        // No light-shifting actions in anchor mode.
        #expect(!plan.actions.contains { $0.type == .seekLight || $0.type == .avoidLight })
        // But sleep protection still exists.
        #expect(plan.actions.contains { $0.type == .sleep })
    }

    @Test("User can force full adaptation on a short trip")
    func shortTripForcedAdaptation() throws {
        var trip = DemoTrips.shortLondonBusinessTrip(reference: TestSupport.reference)
        trip.adaptationStrategy = .fullyAdapt
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        #expect(plan.strategy == .fullyAdapt)
        #expect(plan.shiftDirection == .advance)
    }

    @Test("Red-eye arrival morning: avoid light first, seek light after the body's low point")
    func parisSunglassesCase() throws {
        let trip = DemoTrips.parisRedEye(reference: TestSupport.reference)
        // No pre-trip shifting: the classic case where the body lands fully on home time,
        // CBTmin sits mid-morning local, and early light would push the clock the wrong way.
        var profile = DemoTrips.defaultProfile()
        profile.preTripAdjustment = .none
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: profile)
        let arrival = trip.outboundArrival!
        let landingDay = TimeWindow(start: arrival, end: arrival.adding(hours: 14))

        let avoid = plan.actions.first { $0.type == .avoidLight && $0.window.overlaps(landingDay) }
        let seek = plan.actions.first { $0.type == .seekLight && $0.window.overlaps(landingDay) }
        #expect(avoid != nil, "landing morning after a red-eye should start with avoid-light")
        #expect(seek != nil, "seek-light should follow later the same day")
        if let avoid, let seek {
            #expect(avoid.window.start < seek.window.start)
            // Seek window must sit after the estimated CBTmin, i.e. not at 9 AM local.
            let seekStartHour = TestSupport.localHour(seek.window.start, "Europe/Paris")
            #expect(seekStartHour >= 10, "seek-light at \(seekStartHour):00 is before the body's low point")
        }
    }

    @Test("Westward arrival: stay-awake anchor until local bedtime")
    func westwardStayAwake() throws {
        let trip = DemoTrips.losAngelesToTokyo(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile(homeZone: "America/Los_Angeles")
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: profile)
        let arrival = trip.outboundArrival!
        let landingDay = TimeWindow(start: arrival, end: arrival.adding(hours: 14))
        #expect(
            plan.actions.contains { $0.type == .stayAwake && $0.window.overlaps(landingDay) },
            "Tokyo lands mid-afternoon with the body on 10 PM — needs an explicit stay-awake anchor"
        )
    }

    @Test("No caffeine window extends past its cutoff")
    func caffeineWindowsRespectCutoffs() throws {
        for (trip, profile) in DemoTrips.all(reference: TestSupport.reference) {
            guard profile.caffeine == .include else { continue }
            let plan = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
            for day in plan.days {
                let dayActions = plan.actions.filter { $0.dayIndex == day.index }
                guard let cutoff = dayActions.first(where: { $0.type == .caffeineCutoff }) else { continue }
                for ok in dayActions where ok.type == .caffeineOK {
                    #expect(ok.window.end <= cutoff.window.start.adding(minutes: 5))
                }
            }
        }
    }

    @Test("Every plan keeps a usable amount of sleep on flight nights")
    func protectsSleepQuantity() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        // The overnight JFK→HEL night should still schedule some sleep (in-flight).
        let flight = trip.segments[0]
        let sleepInFlight = plan.actions.filter {
            $0.type == .sleep && $0.window.overlaps(flight.window)
        }
        #expect(!sleepInFlight.isEmpty, "red-eye night lost all sleep")
    }

    @Test("Intensity changes plan density")
    func intensityDensity() throws {
        var easy = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        easy.intensity = .easy
        var maximum = easy
        maximum.intensity = .maximum
        let profile = DemoTrips.defaultProfile()
        let easyPlan = try TestSupport.generateValidPlan(trip: easy, profile: profile)
        let maxPlan = try TestSupport.generateValidPlan(trip: maximum, profile: profile)
        #expect(maxPlan.actions.count > easyPlan.actions.count)
        // Easy mode: no pre-trip shift days.
        let departure = easy.firstDeparture!
        let easyPre = easyPlan.days.filter { $0.estimatedBed < departure && $0.cumulativeShiftHours > 0.3 }
        #expect(easyPre.isEmpty, "easy mode should not shift sleep before departure")
    }
}
