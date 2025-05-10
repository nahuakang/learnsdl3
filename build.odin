package build

import "core:fmt"
import "core:log"
import os "core:os/os2"
import "core:path/filepath"
import "core:slice"
import "core:strings"

main :: proc() {
	context.logger = log.create_console_logger()

	EXE :: "learnsdl3"
	OUT :: EXE + ".exe" when ODIN_OS == .Windows else EXE
	run_str("odin build src -debug -out:" + OUT)

	files, err := os.read_all_directory_by_path("content/shaders/src", context.temp_allocator)
	if err != nil {
		log.errorf("Error reading shader sources: {}", err)
		os.exit(1)
	}
	for file in files {
		shadercross(file, "spv")
		shadercross(file, "dxil")
		shadercross(file, "msl")
		shadercross(file, "json")
	}

	if slice.contains(os.args, "run") do run({OUT})
}

shadercross :: proc(file: os.File_Info, format: string) {
	basename := filepath.stem(file.name)
	outfile := filepath.join({"content/shaders/out", strings.concatenate({basename, ".", format})})
	run({"shadercross", file.fullpath, "-o", outfile})
}

run_str :: proc(cmd: string) {
	run(strings.split(cmd, " "))
}

run :: proc(cmd: []string) {
	log.infof("Running {}", cmd)
	code, err := exec(cmd)
	if err != nil {
		log.errorf("Error executing process: {}", err)
		os.exit(1)
	}
	if code != 0 {
		log.errorf("Process exited with non-zero code {}", code)
		os.exit(1)
	}
}

exec :: proc(cmd: []string) -> (code: int, error: os.Error) {
	process := os.process_start(
		{command = cmd, stdin = os.stdin, stdout = os.stdout, stderr = os.stderr},
	) or_return
	state := os.process_wait(process) or_return
	os.process_close(process) or_return
	return state.exit_code, nil
}
