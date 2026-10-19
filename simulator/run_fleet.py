
import argparse
import json

from simulator.fleet import MachineFleet


def main():
    parser = argparse.ArgumentParser(
        description="Husky 12-machine IoT simulator"
    )

    parser.add_argument(
        "--machines",
        type=int,
        default=12
    )

    parser.add_argument(
        "--ticks",
        type=int,
        default=10
    )

    parser.add_argument(
        "--interval",
        type=float,
        default=30
    )

    parser.add_argument(
        "--hours-per-step",
        type=float,
        default=None,
        help="Simulated operating hours per tick"
    )

    parser.add_argument(
        "--output-dir",
        default="data"
    )

    parser.add_argument(
        "--realtime",
        action="store_true",
        help="Wait between ticks"
    )

    args = parser.parse_args()

    fleet = MachineFleet(
        machine_count=args.machines,
        interval_seconds=args.interval,
        operating_hours_per_step=args.hours_per_step
    )

    # Schedule example fault scenarios.
    fault_scenarios = [
        (2, "IMM-001", "bearing_wear"),
        (3, "IMM-002", "overheating"),
        (4, "IMM-003", "seal_leak"),
        (5, "IMM-004", "stuck_sensor"),
        (6, "IMM-005", "spike")
    ]

    for tick, machine_id, fault_type in fault_scenarios:
        if tick <= args.ticks and machine_id in fleet.machines:
            fleet.schedule_fault(
                tick,
                machine_id,
                fault_type
            )

    result = fleet.run(
        ticks=args.ticks,
        output_dir=args.output_dir,
        sleep_between_ticks=args.realtime
    )

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
