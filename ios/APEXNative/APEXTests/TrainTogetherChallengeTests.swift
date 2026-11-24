import XCTest
@testable import APEX

/// The challenge wheel: its library, the kit everyone has in common, the
/// spin every phone draws the same way, and the snapshot that carries it.
final class TrainTogetherChallengeTests: XCTestCase {
    private typealias Focus = TrainTogether.Focus
    private typealias Kit = TrainTogether.Kit
    private typealias Wheel = TrainTogether.Wheel

    private let library = TrainTogether.Challenge.library
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func main(_ item: ExerciseCatalogItem) -> Set<String> { Set(item.muscles.prefix(2)) }

    // MARK: - The library

    func testEveryChallengeIsBuiltFromTheCatalogueWithKitTheWheelAsksAbout() {
        XCTAssertEqual(Set(library.map(\.id)).count, library.count, "ids are unique")
        XCTAssertEqual(Set(library.map(\.name)).count, library.count, "names are unique")
        for challenge in library {
            XCTAssertEqual(challenge.items.count, challenge.moves.count, "\(challenge.id) uses a movement missing from the catalogue")
            XCTAssertNotNil(challenge.kit, "\(challenge.id) needs kit the wheel never asks about")
            XCTAssertLessThanOrEqual(challenge.name.count, 20, "\(challenge.id) does not fit on a slice")
            XCTAssert((3...6).contains(challenge.moves.count), "\(challenge.id) has \(challenge.moves.count) moves")
            XCTAssert((15...40).contains(challenge.estimatedMinutes), "\(challenge.id) takes \(challenge.estimatedMinutes) min")
            XCTAssertEqual(challenge.plan().exercises.count, challenge.moves.count)
            for item in challenge.items {
                XCTAssert(["reps", "seconds"].contains(item.unit), "\(challenge.id): \(item.movementID) is counted in \(item.unit)")
            }
        }
    }

    func testEveryFocusCanFillTheWheelWithNoKitAtAll() {
        let fewestWithoutKit: [Focus: Int] = [.fullBody: 5, .push: 4, .pull: 4, .upperBody: 4, .lowerBody: 4, .hiit: 5]
        for (focus, fewest) in fewestWithoutKit {
            XCTAssertGreaterThanOrEqual(Wheel.eligible(focus: focus, common: []).count, fewest, "\(focus) without kit")
        }
    }

    func testEachChallengeTrainsWhatItsFocusSays() {
        let upper: Set = ["chest", "lats", "upperBack", "frontDelts", "sideDelts", "rearDelts", "triceps", "biceps"]
        let lower: Set = ["quads", "hamstrings", "glutes", "calves", "adductors"]
        for challenge in library {
            let items = challenge.items
            switch challenge.focus {
            case .push:
                for item in items { XCTAssert(main(item).isDisjoint(with: ["lats", "upperBack", "biceps"]), "\(challenge.id): \(item.movementID) pulls") }
            case .pull:
                for item in items {
                    XCTAssert(main(item).isDisjoint(with: ["chest", "triceps"]), "\(challenge.id): \(item.movementID) pushes")
                    XCTAssertFalse(lower.contains(item.muscles.first ?? ""), "\(challenge.id): \(item.movementID) is a leg move")
                }
            case .upperBody:
                for item in items { XCTAssert(main(item).isDisjoint(with: ["quads", "hamstrings", "glutes"]), "\(challenge.id): \(item.movementID) is legs") }
            case .lowerBody:
                for item in items { XCTAssert(main(item).isDisjoint(with: upper), "\(challenge.id): \(item.movementID) is upper body") }
            case .fullBody:
                XCTAssert(items.contains { !main($0).isDisjoint(with: lower) }, "\(challenge.id) has no lower-body move")
                XCTAssert(items.contains { !main($0).isDisjoint(with: upper) }, "\(challenge.id) has no upper-body move")
            case .hiit:
                for pick in challenge.picks {
                    XCTAssertEqual(pick.item.unit, "seconds", "\(challenge.id): \(pick.item.movementID) is not timed")
                    XCTAssertGreaterThan(pick.rest, 0, "\(challenge.id): \(pick.item.movementID) has no rest")
                }
            }
        }
    }

    // MARK: - Kit

    func testCatalogueEquipmentBecomesKitToTick() {
        XCTAssertEqual(Kit.needs("Bodyweight"), [])
        XCTAssertEqual(Kit.needs("Mat · Floor Space"), [], "a mat helps but is never required")
        XCTAssertEqual(Kit.needs("Bench or Plyo Box or Step · Dumbbells"), [[.bench], [.dumbbells]])
        XCTAssertEqual(Kit.needs("Pull Up Bar or Rings"), [[.pullUpBar]], "options the wheel never asks about are dropped")
        XCTAssertNil(Kit.needs("Barbell · Plates"))
    }

    func testTheWheelOnlyHoldsWhatEveryoneHas() {
        XCTAssertEqual(Wheel.commonKit([[.dumbbells, .bands], [.dumbbells]], headcount: 2), [.dumbbells])
        XCTAssertEqual(Wheel.commonKit([[.dumbbells, .bands], nil], headcount: 2), [], "someone who has not answered has nothing yet")
        XCTAssertEqual(Wheel.commonKit([[.dumbbells], [.dumbbells]], headcount: 3), [], "someone not connected yet has nothing yet")
        let pullUps = library.filter { $0.kit?.contains([.pullUpBar]) == true }
        XCTAssertFalse(pullUps.isEmpty)
        for challenge in pullUps {
            XCTAssertFalse(challenge.fits(Wheel.commonKit([[.pullUpBar], [.dumbbells]], headcount: 2)), "\(challenge.id) needs a bar everyone has")
            XCTAssertTrue(challenge.fits(Wheel.commonKit([[.pullUpBar], [.pullUpBar, .dumbbells]], headcount: 2)))
        }
    }

    // MARK: - The spin

    func testEveryPhoneStopsTheWheelOnTheSameSlot() {
        for slots in Wheel.fewestSlots...Wheel.mostSlots {
            for landing in 0..<slots {
                let end = Wheel.angle(slots: slots, landing: landing, elapsed: Wheel.spinSeconds + 5)
                XCTAssertEqual(Wheel.slotUnderPointer(angle: end, slots: slots), landing, "\(slots) slots, landing \(landing)")
            }
        }
        XCTAssertEqual(Wheel.angle(slots: 8, landing: 3, elapsed: 0), 0)
        XCTAssertLessThan(Wheel.angle(slots: 8, landing: 3, elapsed: 1), Wheel.angle(slots: 8, landing: 3, elapsed: 2))
        XCTAssertGreaterThan(Wheel.angle(slots: 8, landing: 3, elapsed: Wheel.spinSeconds), 5 * 360, "it turns at least five times")
    }

    /// The same seed always draws the same wheel, so a failure here can be replayed.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    func testADrawAlwaysLooksFullAndLandsOnTheWheel() throws {
        var generator = Seeded(state: 42)
        let two = Array(library.prefix(2))
        let short = try XCTUnwrap(Wheel.draw(from: two, using: &generator))
        XCTAssertEqual(short.slots.count, Wheel.fewestSlots)
        XCTAssertEqual(Set(short.slots), Set(two.map(\.id)))
        let long = try XCTUnwrap(Wheel.draw(from: library, using: &generator))
        XCTAssertEqual(long.slots.count, Wheel.mostSlots)
        XCTAssert(long.slots.indices.contains(long.landing))
        XCTAssertNil(Wheel.draw(from: [], using: &generator))
    }

    // MARK: - The snapshot

    func testTheWheelIsALobbyPressAndARoomWithoutAWorkoutCannotStart() throws {
        let empty = TrainTogether.Timeline(exercises: [], warmupText: "", warmupDuration: 0)
        let lobby = TrainTogether.State.lobby(at: t0)
        XCTAssertEqual(empty.apply(.start, to: lobby, at: t0), lobby, "nothing to start yet")

        let focused = empty.apply(.wheelFocus(.pull), to: lobby, at: t0)
        XCTAssertEqual(focused.wheel, Wheel(focus: .pull, spin: nil))
        let spun = empty.apply(.spin(slots: ["floor-pull", "posture-reset"], landing: 1), to: focused, at: t0.addingTimeInterval(1.2344))
        let spin = try XCTUnwrap(spun.wheel?.spin)
        XCTAssertEqual(spun.wheel?.focus, .pull)
        XCTAssertEqual(spin.landing, 1)
        XCTAssertEqual(spin.at.timeIntervalSince1970, t0.addingTimeInterval(1.234).timeIntervalSince1970, accuracy: 0.0001)
        XCTAssertEqual(empty.apply(.spin(slots: ["floor-pull"], landing: 4), to: focused, at: t0), focused, "a landing off the wheel is refused")
        XCTAssertNil(empty.apply(.wheelFocus(.push), to: spun, at: t0).wheel?.spin, "a new focus clears the last spin")

        let chosen = TrainTogether.Timeline(exercises: TrainTogether.Challenge.library[0].exercises(), warmupText: "", warmupDuration: 0)
        XCTAssertEqual(chosen.apply(.wheelFocus(.push), to: lobby, at: t0), lobby, "the wheel is gone once the room has its workout")
        XCTAssertEqual(chosen.apply(.spin(slots: ["floor-pull"], landing: 0), to: lobby, at: t0), lobby)

        var running = lobby
        running.phase = .rest
        XCTAssertEqual(empty.apply(.wheelFocus(.push), to: running, at: t0), running, "the wheel only turns in the lobby")
    }

    func testAWheelThisPhoneCanNotReadNeverCostsItTheRoom() throws {
        let json = #"{"phase":"lobby","position":0,"step":0,"extra_seconds":0,"sound":true,"voice":false,"anchor":"2026-11-24T08:00:00.000Z","wheel":{"focus":"legs"}}"#
        let state = try TrainTogetherCoding.decoder.decode(TrainTogether.State.self, from: Data(json.utf8))
        XCTAssertEqual(state.phase, .lobby)
        XCTAssertNil(state.wheel)

        var spun = TrainTogether.State.lobby(at: t0)
        spun.wheel = Wheel(focus: .hiit, spin: .init(at: t0.addingTimeInterval(2), slots: ["thirty-thirty"], landing: 0))
        let round = try TrainTogetherCoding.decoder.decode(TrainTogether.State.self, from: TrainTogetherCoding.encoder.encode(spun))
        XCTAssertEqual(round, spun)

        let offTheWheel = #"{"phase":"lobby","position":0,"step":0,"extra_seconds":0,"sound":true,"voice":false,"anchor":"2026-11-24T08:00:00.000Z","wheel":{"focus":"push","spin":{"at":"2026-11-24T08:01:00.000Z","slots":["push-up-ladder"],"landing":5}}}"#
        let refused = try TrainTogetherCoding.decoder.decode(TrainTogether.State.self, from: Data(offTheWheel.utf8))
        XCTAssertNil(refused.wheel, "a spin landing off its wheel is never drawn")
    }
}
