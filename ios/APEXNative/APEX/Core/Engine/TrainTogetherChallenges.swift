import Foundation

/*
 * The challenges the wheel can land on. Each one is built only from exercise
 * catalogue movements, carries exactly one focus, and needs no kit beyond
 * what its movements list in the catalogue. TrainTogetherChallengeTests
 * checks all of that, and that every focus can always fill the wheel.
 *
 * For a timed movement, `reps` is its seconds.
 */
extension TrainTogether.Challenge {

    static let library: [TrainTogether.Challenge] = [
        // MARK: Full body

        .init(id: "bodyweight-burner", name: "Bodyweight burner", focus: .fullBody, moves: [
            Move(movementID: "bodyweight_squat", sets: 3, reps: 15, rest: 45),
            Move(movementID: "push_up", sets: 3, reps: 10, rest: 45),
            Move(movementID: "mountain_climber", sets: 3, reps: 30, rest: 30),
            Move(movementID: "glute_bridge", sets: 3, reps: 15, rest: 45),
            Move(movementID: "plank", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "animal-circuit", name: "Animal circuit", focus: .fullBody, moves: [
            Move(movementID: "bear_crawl", sets: 3, reps: 30, rest: 30),
            Move(movementID: "crab_walk", sets: 3, reps: 30, rest: 30),
            Move(movementID: "spiderman_push_up", sets: 3, reps: 8, rest: 45),
            Move(movementID: "frog_pump", sets: 3, reps: 20, rest: 45),
            Move(movementID: "inchworm_walkout", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "total-body-tune-up", name: "Total body tune-up", focus: .fullBody, moves: [
            Move(movementID: "lateral_lunge", sets: 3, reps: 10, rest: 45),
            Move(movementID: "wide_grip_push_up", sets: 3, reps: 10, rest: 45),
            Move(movementID: "hip_thrust_bodyweight", sets: 3, reps: 15, rest: 45),
            Move(movementID: "bird_dog", sets: 3, reps: 10, rest: 30),
            Move(movementID: "side_plank", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "strong-all-over", name: "Strong all over", focus: .fullBody, moves: [
            Move(movementID: "squat_jump", sets: 3, reps: 10, rest: 60),
            Move(movementID: "close_grip_push_up", sets: 3, reps: 10, rest: 60),
            Move(movementID: "glute_ham_walkout", sets: 3, reps: 10, rest: 45),
            Move(movementID: "plank_with_shoulder_tap", sets: 3, reps: 20, rest: 30),
            Move(movementID: "wall_sit", sets: 3, reps: 40, rest: 45),
        ]),
        .init(id: "power-yoga-flow", name: "Power yoga flow", focus: .fullBody, moves: [
            Move(movementID: "chair_pose", sets: 3, reps: 30, rest: 30),
            Move(movementID: "warrior_two", sets: 3, reps: 30, rest: 20),
            Move(movementID: "chaturanga", sets: 3, reps: 6, rest: 45),
            Move(movementID: "downward_dog", sets: 3, reps: 30, rest: 20),
            Move(movementID: "boat_pose", sets: 3, reps: 30, rest: 30),
            Move(movementID: "locust_pose", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "backpack-100", name: "Backpack 100", focus: .fullBody, moves: [
            Move(movementID: "backpack_rdl", sets: 4, reps: 10, rest: 60),
            Move(movementID: "backpack_row", sets: 4, reps: 10, rest: 60),
            Move(movementID: "weighted_push_up", sets: 4, reps: 5, rest: 60),
            Move(movementID: "backpack_carry", sets: 4, reps: 40, rest: 45),
        ]),
        .init(id: "dumbbell-complex", name: "Dumbbell complex", focus: .fullBody, moves: [
            Move(movementID: "dumbbell_romanian_deadlift", sets: 4, reps: 10, rest: 60),
            Move(movementID: "bent_over_dumbbell_row", sets: 4, reps: 10, rest: 60),
            Move(movementID: "goblet_squat", sets: 4, reps: 10, rest: 60),
            Move(movementID: "dumbbell_floor_press", sets: 4, reps: 10, rest: 60),
        ]),
        .init(id: "kettlebell-rounds", name: "Kettlebell rounds", focus: .fullBody, moves: [
            Move(movementID: "kettlebell_swing", sets: 4, reps: 15, rest: 60),
            Move(movementID: "kettlebell_squat_to_press", sets: 4, reps: 10, rest: 60),
            Move(movementID: "kettlebell_row", sets: 4, reps: 10, rest: 60),
            Move(movementID: "kettlebell_floor_press", sets: 4, reps: 10, rest: 60),
        ]),

        // MARK: Push

        .init(id: "push-up-ladder", name: "Push-up ladder", focus: .push, moves: [
            Move(movementID: "knee_push_up", sets: 3, reps: 12, rest: 45),
            Move(movementID: "push_up", sets: 3, reps: 10, rest: 60),
            Move(movementID: "wide_grip_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "diamond_push_up", sets: 3, reps: 6, rest: 60),
            Move(movementID: "pike_push_up", sets: 3, reps: 6, rest: 60),
        ]),
        .init(id: "push-and-plank", name: "Push and plank", focus: .push, moves: [
            Move(movementID: "hindu_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "plank_with_shoulder_tap", sets: 3, reps: 20, rest: 45),
            Move(movementID: "close_grip_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "rkc_plank", sets: 3, reps: 20, rest: 40),
            Move(movementID: "mountain_climber", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "shoulder-burner", name: "Shoulder burner", focus: .push, moves: [
            Move(movementID: "pike_push_up", sets: 4, reps: 8, rest: 60),
            Move(movementID: "bear_crawl", sets: 3, reps: 30, rest: 30),
            Move(movementID: "divebomber_push_up", sets: 3, reps: 6, rest: 60),
            Move(movementID: "clock_push_up", sets: 3, reps: 30, rest: 45),
            Move(movementID: "plank", sets: 3, reps: 45, rest: 30),
        ]),
        .init(id: "chest-and-triceps", name: "Chest and triceps", focus: .push, moves: [
            Move(movementID: "wide_grip_push_up", sets: 3, reps: 10, rest: 60),
            Move(movementID: "diamond_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "spiderman_push_up", sets: 3, reps: 6, rest: 60),
            Move(movementID: "chaturanga", sets: 3, reps: 5, rest: 60),
            Move(movementID: "hollow_body_hold", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "bench-push-ups", name: "Bench push-ups", focus: .push, moves: [
            Move(movementID: "incline_push_up", sets: 3, reps: 12, rest: 60),
            Move(movementID: "feet_elevated_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "elevated_pike_push_up", sets: 3, reps: 6, rest: 60),
            Move(movementID: "diamond_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "plank", sets: 3, reps: 40, rest: 30),
        ]),
        .init(id: "dumbbell-press-day", name: "Dumbbell press day", focus: .push, moves: [
            Move(movementID: "dumbbell_floor_press", sets: 4, reps: 10, rest: 75),
            Move(movementID: "single_arm_dumbbell_press", sets: 3, reps: 8, rest: 60),
            Move(movementID: "lateral_raise", sets: 3, reps: 12, rest: 45),
            Move(movementID: "overhead_triceps_extension", sets: 3, reps: 12, rest: 45),
            Move(movementID: "dumbbell_floor_fly", sets: 3, reps: 10, rest: 45),
        ]),

        // MARK: Pull

        .init(id: "floor-pull", name: "Floor pull", focus: .pull, moves: [
            Move(movementID: "prone_floor_row", sets: 4, reps: 12, rest: 45),
            Move(movementID: "locust_pose", sets: 3, reps: 30, rest: 30),
            Move(movementID: "pilates_swimming", sets: 3, reps: 30, rest: 30),
            Move(movementID: "bird_dog", sets: 3, reps: 10, rest: 30),
            Move(movementID: "hollow_body_hold", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "table-row-pull", name: "Table row pull", focus: .pull, moves: [
            Move(movementID: "table_row", sets: 4, reps: 10, rest: 60),
            Move(movementID: "prone_floor_row", sets: 3, reps: 12, rest: 45),
            Move(movementID: "pilates_swimming", sets: 3, reps: 30, rest: 30),
            Move(movementID: "dead_bug", sets: 3, reps: 10, rest: 30),
            Move(movementID: "locust_pose", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "back-and-core", name: "Back and core", focus: .pull, moves: [
            Move(movementID: "pilates_swimming", sets: 3, reps: 40, rest: 30),
            Move(movementID: "wall_slide", sets: 3, reps: 12, rest: 30),
            Move(movementID: "bird_dog", sets: 3, reps: 10, rest: 30),
            Move(movementID: "hollow_rock", sets: 3, reps: 12, rest: 45),
            Move(movementID: "locust_pose", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "posture-reset", name: "Posture reset", focus: .pull, moves: [
            Move(movementID: "wall_slide", sets: 3, reps: 12, rest: 30),
            Move(movementID: "prone_floor_row", sets: 3, reps: 12, rest: 45),
            Move(movementID: "locust_pose", sets: 3, reps: 30, rest: 30),
            Move(movementID: "bird_dog", sets: 3, reps: 10, rest: 30),
            Move(movementID: "dead_bug", sets: 3, reps: 10, rest: 30),
            Move(movementID: "thread_the_needle_stretch", sets: 2, reps: 30, rest: 15),
        ]),
        .init(id: "pull-up-bar-basics", name: "Pull-up bar basics", focus: .pull, moves: [
            Move(movementID: "scapular_pull_up", sets: 3, reps: 8, rest: 45),
            Move(movementID: "chin_up", sets: 4, reps: 5, rest: 90),
            Move(movementID: "dead_hang", sets: 3, reps: 30, rest: 45),
            Move(movementID: "hanging_knee_raise", sets: 3, reps: 10, rest: 60),
            Move(movementID: "prone_floor_row", sets: 3, reps: 12, rest: 45),
        ]),
        .init(id: "towel-door-rows", name: "Towel door rows", focus: .pull, moves: [
            Move(movementID: "towel_door_row", sets: 4, reps: 12, rest: 60),
            Move(movementID: "towel_door_pulldown", sets: 3, reps: 12, rest: 60),
            Move(movementID: "pilates_swimming", sets: 3, reps: 30, rest: 30),
            Move(movementID: "prone_floor_row", sets: 3, reps: 12, rest: 45),
            Move(movementID: "locust_pose", sets: 3, reps: 30, rest: 30),
        ]),

        // MARK: Upper body

        .init(id: "upper-body-basics", name: "Upper body basics", focus: .upperBody, moves: [
            Move(movementID: "push_up", sets: 3, reps: 10, rest: 60),
            Move(movementID: "prone_floor_row", sets: 3, reps: 12, rest: 45),
            Move(movementID: "pike_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "plank", sets: 3, reps: 30, rest: 30),
            Move(movementID: "dead_bug", sets: 3, reps: 10, rest: 30),
        ]),
        .init(id: "bear-and-crab", name: "Bear and crab", focus: .upperBody, moves: [
            Move(movementID: "bear_crawl", sets: 3, reps: 30, rest: 30),
            Move(movementID: "crab_walk", sets: 3, reps: 30, rest: 30),
            Move(movementID: "walkout_to_push_up", sets: 3, reps: 30, rest: 45),
            Move(movementID: "wide_grip_push_up", sets: 3, reps: 10, rest: 60),
            Move(movementID: "prone_floor_row", sets: 3, reps: 12, rest: 45),
        ]),
        .init(id: "arms-and-abs", name: "Arms and abs", focus: .upperBody, moves: [
            Move(movementID: "diamond_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "close_grip_push_up", sets: 3, reps: 10, rest: 60),
            Move(movementID: "plank_with_shoulder_tap", sets: 3, reps: 20, rest: 30),
            Move(movementID: "bicycle_crunch", sets: 3, reps: 20, rest: 30),
            Move(movementID: "hollow_body_hold", sets: 3, reps: 30, rest: 30),
        ]),
        .init(id: "floor-push-pull", name: "Floor push-pull", focus: .upperBody, moves: [
            Move(movementID: "push_up", sets: 3, reps: 10, rest: 60),
            Move(movementID: "prone_floor_row", sets: 3, reps: 12, rest: 45),
            Move(movementID: "pike_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "wall_slide", sets: 3, reps: 12, rest: 30),
            Move(movementID: "hindu_push_up", sets: 3, reps: 8, rest: 60),
            Move(movementID: "rkc_plank", sets: 3, reps: 20, rest: 40),
        ]),
        .init(id: "bench-and-dumbbells", name: "Bench and dumbbells", focus: .upperBody, moves: [
            Move(movementID: "dumbbell_bench_press", sets: 4, reps: 10, rest: 75),
            Move(movementID: "one_arm_dumbbell_row", sets: 3, reps: 10, rest: 60),
            Move(movementID: "dumbbell_overhead_press", sets: 3, reps: 10, rest: 60),
            Move(movementID: "chest_supported_row", sets: 3, reps: 10, rest: 60),
            Move(movementID: "overhead_triceps_extension", sets: 3, reps: 12, rest: 45),
        ]),
        .init(id: "band-upper-body", name: "Band upper body", focus: .upperBody, moves: [
            Move(movementID: "band_row", sets: 4, reps: 15, rest: 45),
            Move(movementID: "band_overhead_press", sets: 3, reps: 12, rest: 60),
            Move(movementID: "band_pull_apart", sets: 3, reps: 15, rest: 30),
            Move(movementID: "band_curl", sets: 3, reps: 12, rest: 45),
            Move(movementID: "push_up", sets: 3, reps: 10, rest: 60),
        ]),

        // MARK: Lower body

        .init(id: "legs-on-fire", name: "Legs on fire", focus: .lowerBody, moves: [
            Move(movementID: "bodyweight_squat", sets: 4, reps: 15, rest: 45),
            Move(movementID: "glute_bridge", sets: 3, reps: 15, rest: 45),
            Move(movementID: "squat_jump", sets: 3, reps: 10, rest: 60),
            Move(movementID: "wall_sit", sets: 3, reps: 40, rest: 45),
            Move(movementID: "wall_calf_raise", sets: 3, reps: 20, rest: 30),
        ]),
        .init(id: "glute-builder", name: "Glute builder", focus: .lowerBody, moves: [
            Move(movementID: "hip_thrust_bodyweight", sets: 4, reps: 15, rest: 45),
            Move(movementID: "frog_pump", sets: 3, reps: 20, rest: 45),
            Move(movementID: "pilates_clam", sets: 3, reps: 15, rest: 30),
            Move(movementID: "pilates_side_kick", sets: 3, reps: 12, rest: 30),
            Move(movementID: "lateral_lunge", sets: 3, reps: 10, rest: 45),
        ]),
        .init(id: "lunge-it-out", name: "Lunge it out", focus: .lowerBody, moves: [
            Move(movementID: "reverse_lunge_to_knee_drive", sets: 3, reps: 30, rest: 30),
            Move(movementID: "curtsy_lunge_bodyweight", sets: 3, reps: 10, rest: 45),
            Move(movementID: "cossack_squat", sets: 3, reps: 8, rest: 45),
            Move(movementID: "step_back_lunge_with_twist", sets: 3, reps: 30, rest: 30),
            Move(movementID: "jumping_lunge", sets: 3, reps: 8, rest: 60),
        ]),
        .init(id: "posterior-chain", name: "Posterior chain", focus: .lowerBody, moves: [
            Move(movementID: "glute_ham_walkout", sets: 3, reps: 8, rest: 60),
            Move(movementID: "single_leg_glute_bridge", sets: 3, reps: 10, rest: 45),
            Move(movementID: "single_leg_reach", sets: 3, reps: 8, rest: 30),
            Move(movementID: "locust_pose", sets: 3, reps: 30, rest: 30),
            Move(movementID: "bridge_pose", sets: 3, reps: 30, rest: 30),
            Move(movementID: "dead_bug", sets: 3, reps: 10, rest: 30),
        ]),
        .init(id: "dumbbell-legs", name: "Dumbbell legs", focus: .lowerBody, moves: [
            Move(movementID: "goblet_squat", sets: 4, reps: 10, rest: 75),
            Move(movementID: "dumbbell_romanian_deadlift", sets: 4, reps: 10, rest: 75),
            Move(movementID: "reverse_lunge", sets: 3, reps: 8, rest: 60),
            Move(movementID: "dumbbell_sumo_squat", sets: 3, reps: 12, rest: 60),
            Move(movementID: "wall_calf_raise", sets: 3, reps: 20, rest: 30),
        ]),
        .init(id: "chair-legs", name: "Chair legs", focus: .lowerBody, moves: [
            Move(movementID: "sit_to_stand", sets: 4, reps: 12, rest: 45),
            Move(movementID: "chair_step_up", sets: 3, reps: 10, rest: 60),
            Move(movementID: "step_down_control", sets: 3, reps: 8, rest: 45),
            Move(movementID: "wall_sit", sets: 3, reps: 40, rest: 45),
            Move(movementID: "glute_bridge", sets: 3, reps: 15, rest: 45),
        ]),

        // MARK: HIIT, timed work only

        .init(id: "thirty-thirty", name: "Thirty-thirty", focus: .hiit, moves: [
            Move(movementID: "burpee", sets: 4, reps: 30, rest: 30),
            Move(movementID: "jumping_jack", sets: 4, reps: 30, rest: 30),
            Move(movementID: "high_knees", sets: 4, reps: 30, rest: 30),
            Move(movementID: "mountain_climber", sets: 4, reps: 30, rest: 30),
            Move(movementID: "step_back_lunge_with_twist", sets: 4, reps: 30, rest: 30),
        ]),
        .init(id: "forty-twenty", name: "Forty-twenty", focus: .hiit, moves: [
            Move(movementID: "squat_thrust", sets: 4, reps: 40, rest: 20),
            Move(movementID: "high_knees", sets: 4, reps: 40, rest: 20),
            Move(movementID: "walkout_to_push_up", sets: 4, reps: 40, rest: 20),
            Move(movementID: "reverse_lunge_to_knee_drive", sets: 4, reps: 40, rest: 20),
            Move(movementID: "pogo_hop", sets: 4, reps: 40, rest: 20),
        ]),
        .init(id: "core-and-cardio", name: "Core and cardio", focus: .hiit, moves: [
            Move(movementID: "mountain_climber", sets: 4, reps: 30, rest: 20),
            Move(movementID: "plank", sets: 4, reps: 40, rest: 20),
            Move(movementID: "jumping_jack", sets: 4, reps: 30, rest: 20),
            Move(movementID: "hollow_body_hold", sets: 4, reps: 30, rest: 20),
            Move(movementID: "high_knees", sets: 4, reps: 30, rest: 20),
            Move(movementID: "bear_crawl", sets: 4, reps: 30, rest: 20),
        ]),
        .init(id: "burpee-and-friends", name: "Burpee and friends", focus: .hiit, moves: [
            Move(movementID: "burpee", sets: 4, reps: 30, rest: 30),
            Move(movementID: "crab_walk", sets: 4, reps: 30, rest: 30),
            Move(movementID: "lateral_hop", sets: 4, reps: 30, rest: 30),
            Move(movementID: "inchworm_walkout", sets: 4, reps: 30, rest: 30),
            Move(movementID: "wall_sit", sets: 4, reps: 30, rest: 30),
        ]),
        .init(id: "low-impact-sweat", name: "Low-impact sweat", focus: .hiit, moves: [
            Move(movementID: "marching_in_place", sets: 4, reps: 45, rest: 15),
            Move(movementID: "step_back_lunge_with_twist", sets: 4, reps: 40, rest: 20),
            Move(movementID: "inchworm_walkout", sets: 4, reps: 30, rest: 30),
            Move(movementID: "rkc_plank", sets: 4, reps: 20, rest: 25),
            Move(movementID: "wall_sit", sets: 4, reps: 30, rest: 30),
        ]),
        .init(id: "rope-and-burpees", name: "Rope and burpees", focus: .hiit, moves: [
            Move(movementID: "single_under", sets: 5, reps: 60, rest: 30),
            Move(movementID: "burpee", sets: 4, reps: 30, rest: 30),
            Move(movementID: "mountain_climber", sets: 4, reps: 30, rest: 30),
            Move(movementID: "plank", sets: 4, reps: 40, rest: 20),
        ]),
        .init(id: "kettlebell-intervals", name: "Kettlebell intervals", focus: .hiit, moves: [
            Move(movementID: "kettlebell_swing_to_squat", sets: 5, reps: 30, rest: 30),
            Move(movementID: "kettlebell_figure_8", sets: 4, reps: 30, rest: 30),
            Move(movementID: "kettlebell_walking_lunge", sets: 4, reps: 30, rest: 30),
            Move(movementID: "mountain_climber", sets: 4, reps: 30, rest: 30),
            Move(movementID: "front_rack_carry", sets: 4, reps: 40, rest: 20),
        ]),
        .init(id: "dumbbell-intervals", name: "Dumbbell intervals", focus: .hiit, moves: [
            Move(movementID: "devils_press", sets: 4, reps: 30, rest: 30),
            Move(movementID: "farmers_carry", sets: 4, reps: 40, rest: 20),
            Move(movementID: "squat_thrust", sets: 4, reps: 30, rest: 30),
            Move(movementID: "overhead_carry", sets: 3, reps: 30, rest: 30),
            Move(movementID: "high_knees", sets: 4, reps: 30, rest: 30),
        ]),
    ]
}
