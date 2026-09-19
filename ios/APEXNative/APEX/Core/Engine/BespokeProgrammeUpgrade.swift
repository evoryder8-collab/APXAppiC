import Foundation

/// Delivers the already-authored PDF update to native-only users. Old days and
/// every exercise/log remain stored; only their future selection is retired.
enum BespokeProgrammeUpgrade {
    enum WritePhase: CaseIterable, Sendable {
        case stagedDays, exercises, activeDays, program, settings, version
    }

    /// The completion marker cannot pass a failed definition write. Retrying
    /// repeats deterministic upserts, never destructive replacement or deletion.
    static func deliver(write: (WritePhase) async throws -> Void) async throws {
        for phase in WritePhase.allCases { try await write(phase) }
    }

    struct Manifest: Decodable {
        let version: Int
        let program: Program
        let days: [ProgramDay]
        let exercises: [Exercise]
    }

    struct Installation {
        let ownerID: UUID
        let program: Program
        let stagedDays: [ProgramDay]
        let days: [ProgramDay]
        let exercises: [Exercise]
        let settings: UserSettings
        let dashboard: DashboardData
    }

    static func prepare(in data: DashboardData, authenticatedOwnerID: UUID) throws -> Installation? {
        guard let profile = data.profile,
              profile.userID == authenticatedOwnerID,
              ProfileIntegrityPolicy.authorizedProtocol(for: profile) == .constantineV85,
              profile.seedVersion == 7,
              var settings = data.settings, settings.userID == authenticatedOwnerID,
              settings.addons["training_induction"]?.objectValue == nil,
              TrainingInduction.pendingDayIDs(settings).isEmpty,
              let main = data.programs.first(where: { $0.userID == authenticatedOwnerID && $0.slug == "main" })
        else { return nil }

        guard let url = Bundle.main.url(forResource: "constantine-v85", withExtension: "json") else {
            throw APEXServiceError.configurationMissing
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        guard manifest.version == 85, manifest.days.count == 18,
              Set(manifest.days.map(\.id)).count == 18,
              manifest.days.allSatisfy({ day in
                  manifest.exercises.contains { $0.programDayID == day.id && !$0.isLite }
              }) else { throw APEXServiceError.configurationMissing }

        func identifier(_ label: String) -> UUID {
            APEXStableID.scopedUUID(namespace: "bespoke-v85", date: label, userID: authenticatedOwnerID)
        }
        let dayMap = Dictionary(uniqueKeysWithValues: manifest.days.map { day in
            (day.id, identifier("day:\(day.weekday):\(day.sortOrder % 10)"))
        })
        let newDays = manifest.days.map { day in
            ProgramDay(id: dayMap[day.id]!, userID: authenticatedOwnerID, programID: main.id,
                       weekday: day.weekday, name: day.name, dayType: day.dayType,
                       estimatedMinutes: day.estimatedMinutes, warmupNote: day.warmupNote,
                       sortOrder: day.sortOrder, sessionMode: WorkoutSessionMode.guided.rawValue)
        }
        let newIDs = Set(newDays.map(\.id))
        let protected = TrainingInduction.protectedOriginalDayIDs(settings)
        let archived = TrainingInduction.archivedDayIDs(settings).subtracting(protected)
        let oldDays = data.programDays.filter { day in
            day.userID == authenticatedOwnerID && day.programID == main.id && day.isActive
                && !newIDs.contains(day.id) && !archived.contains(day.id)
                && (protected.isEmpty || protected.contains(day.id))
                && day.coachPlanVersionID == nil && day.recoveryPlanID == nil && day.scheduledDate == nil
        }
        let retired = oldDays.map { day in var copy = day; copy.isActive = false; return copy }
        let newExercises = manifest.exercises.map { row in
            let dayID = dayMap[row.programDayID]!
            return Exercise(
                id: identifier("exercise:\(dayID.uuidString.lowercased()):\(row.isLite):\(row.sortOrder)"),
                userID: authenticatedOwnerID, programDayID: dayID, name: row.name,
                movementID: row.movementID,
                workGroupID: row.workGroupID == nil ? nil : dayID,
                workGroupPosition: row.workGroupPosition,
                sets: row.sets, repMin: row.repMin, repMax: row.repMax, repUnit: row.repUnit,
                perSide: row.perSide, restSeconds: row.restSeconds,
                tempoUp: row.tempoUp, tempoDown: row.tempoDown, tempoPause: row.tempoPause,
                tempoNote: row.tempoNote, notes: row.notes, incrementKG: row.incrementKG,
                isLite: row.isLite, optional: row.optional, sortOrder: row.sortOrder
            )
        }
        var program = main
        program.name = manifest.program.name
        program.description = manifest.program.description
        var protocolMetadata = settings.addons["training_protocol"]?.objectValue ?? [:]
        protocolMetadata["version"] = .number(85)
        // Do not restart a training block or its deload schedule on installation.
        if protocolMetadata["start_date"] == nil {
            protocolMetadata["start_date"] = .string(profile.baselineDate)
        }
        settings.addons["training_protocol"] = .object(protocolMetadata)
        settings.addons[TrainingInduction.protectedOriginalDayIDsKey] = .array(
            protected.subtracting(oldDays.map(\.id)).union(newIDs)
                .map { $0.uuidString.lowercased() }.sorted().map(JSONValue.string)
        )
        var next = data
        next.programs = data.programs.map { $0.id == main.id ? program : $0 }
        let replacementDays = Dictionary(uniqueKeysWithValues: (retired + newDays).map { ($0.id, $0) })
        next.programDays = data.programDays.map { replacementDays[$0.id] ?? $0 }
        next.programDays += newDays.filter { day in !data.programDays.contains { $0.id == day.id } }
        let replacementExercises = Dictionary(uniqueKeysWithValues: newExercises.map { ($0.id, $0) })
        next.exercises = data.exercises.map { replacementExercises[$0.id] ?? $0 }
        next.exercises += newExercises.filter { row in !data.exercises.contains { $0.id == row.id } }
        next.settings = settings
        next.profile?.seedVersion = 8
        return Installation(
            ownerID: authenticatedOwnerID, program: program,
            stagedDays: newDays.filter { day in !data.programDays.contains { $0.id == day.id } }
                .map { day in var copy = day; copy.isActive = false; return copy },
            days: retired + newDays, exercises: newExercises, settings: settings, dashboard: next
        )
    }
}
