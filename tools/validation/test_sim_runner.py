"""Fault-inject the actual Tcl runner without invoking a simulator or FPGA tools."""

from pathlib import Path
import tempfile
import tkinter
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "fpga/scripts/sim_all.tcl"


class RunnerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (ROOT / ".audit_verification").mkdir(exist_ok=True)

    def run_fixture(self, children, missing=()):
        with tempfile.TemporaryDirectory(
            prefix="runner_", dir=ROOT / ".audit_verification"
        ) as folder:
            root = Path(folder)
            scripts = root / "scripts"
            benches = root / "sim/testbenches"
            scripts.mkdir()
            benches.mkdir(parents=True)
            runner = scripts / "sim_all.tcl"
            runner.write_bytes(RUNNER.read_bytes())
            for name, body in children.items():
                (scripts / f"sim_{name}.tcl").write_text(body, encoding="utf-8")
                if name not in missing:
                    (benches / f"tb_{name}.sv").write_text(
                        "// fixture", encoding="utf-8"
                    )
            tcl = tkinter.Tcl()
            tcl.eval("proc puts {args} {}; set cleanup 0; set ran 0")
            tcl.eval(
                "proc close_sim {args} {incr ::cleanup}; proc close_project {} {incr ::cleanup}"
            )
            tcl.setvar("runner", runner.as_posix())
            code = int(tcl.eval("catch {source $runner} result"))
            return (
                code,
                str(tcl.getvar("result")),
                int(tcl.getvar("cleanup")),
                int(tcl.getvar("ran")),
            )

    def test_success(self):
        self.assertEqual(self.run_fixture({"ok": "return 0"})[0], 0)

    def test_empty_suite(self):
        self.assertEqual(self.run_fixture({})[0], 1)

    def test_missing_bench(self):
        self.assertEqual(
            self.run_fixture({"absent": "return 0"}, missing=("absent",))[0], 1
        )

    def test_failures_cleanup_and_continue(self):
        for body in (
            "return 1",
            'error "numerical mismatch"',
            'error "watchdog timeout"',
            'return ""',
        ):
            with self.subTest(body=body):
                code, _, cleanup, ran = self.run_fixture(
                    {"a_bad": body, "z_ok": "incr ::ran; return 0"}
                )
                self.assertEqual((code, cleanup, ran), (1, 2, 1))

    def test_child_variables_do_not_corrupt_parent(self):
        code, _, _, ran = self.run_fixture(
            {
                "a": "set results {}; set script_dir broken; return 0",
                "b": "incr ::ran; return 0",
            }
        )
        self.assertEqual((code, ran), (0, 1))

    def test_unregistered_bench(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".audit_verification") as folder:
            root = Path(folder)
            (root / "scripts").mkdir()
            (root / "sim/testbenches").mkdir(parents=True)
            (root / "scripts/sim_all.tcl").write_bytes(RUNNER.read_bytes())
            (root / "sim/testbenches/tb_forgotten.sv").write_text("// unregistered")
            tcl = tkinter.Tcl()
            tcl.setvar("runner", (root / "scripts/sim_all.tcl").as_posix())
            self.assertEqual(int(tcl.eval("catch {source $runner} result")), 1)
            self.assertIn("Unregistered active testbench", str(tcl.getvar("result")))

    def test_actual_child_requires_completion(self):
        # Execute the real child Tcl, with only Vivado commands mocked. This
        # proves a fixed-duration run cannot pass without test_done == 1.
        for done, expected in (("0", 1), ("X", 1), ("1", 0)):
            with self.subTest(done=done):
                tcl = tkinter.Tcl()
                for command in (
                    "puts",
                    "create_project",
                    "set_property",
                    "add_files",
                    "update_compile_order",
                    "launch_simulation",
                    "run",
                    "close_sim",
                    "close_project",
                ):
                    tcl.eval(f"proc {command} {{args}} {{}}")
                tcl.eval(
                    "proc get_filesets {args} {return dummy}; proc current_project {} {return dummy}"
                )
                tcl.setvar("completion", done)
                tcl.eval("proc get_value {args} {return $::completion}")
                fixture = ROOT / ".audit_verification/runner_log_fixture"
                log = fixture / "fixture.sim/sim_1/behav/xsim/simulate.log"
                log.parent.mkdir(parents=True, exist_ok=True)
                log.write_text("Simulation completed\n")
                tcl.setvar("fixture_dir", fixture.as_posix())
                tcl.eval(
                    'proc get_property {key object} {'
                    'if {$key eq "DIRECTORY"} {return $::fixture_dir}; return fixture}'
                )
                tcl.setvar(
                    "child", (ROOT / "fpga/scripts/sim_spectral_proc.tcl").as_posix()
                )
                code = int(tcl.eval("catch {source $child} result"))
                self.assertEqual(code, expected, str(tcl.getvar("result")))
                if expected:
                    self.assertEqual(
                        str(tcl.getvar("result")),
                        "Simulation did not reach successful completion",
                    )


if __name__ == "__main__":
    unittest.main(verbosity=2)
