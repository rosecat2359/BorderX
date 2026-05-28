package xray

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"
)

// ReloadService signals Xray to reload its configuration.
// On Linux, it calls "systemctl reload xray".
// On Windows, it restarts the Xray Windows service.
func ReloadService() error {
	switch runtime.GOOS {
	case "linux":
		return run("systemctl", "reload", "xray")
	case "windows":
		// Windows: use sc or net stop/start
		if err := run("sc", "stop", "Xray"); err != nil {
			return fmt.Errorf("stop xray service: %w", err)
		}
		return run("sc", "start", "Xray")
	default:
		return fmt.Errorf("unsupported OS: %s", runtime.GOOS)
	}
}

// StartService starts the Xray service.
func StartService() error {
	switch runtime.GOOS {
	case "linux":
		return run("systemctl", "start", "xray")
	case "windows":
		return run("sc", "start", "Xray")
	default:
		return fmt.Errorf("unsupported OS: %s", runtime.GOOS)
	}
}

// StopService stops the Xray service.
func StopService() error {
	switch runtime.GOOS {
	case "linux":
		return run("systemctl", "stop", "xray")
	case "windows":
		return run("sc", "stop", "Xray")
	default:
		return fmt.Errorf("unsupported OS: %s", runtime.GOOS)
	}
}

// IsServiceRunning checks whether the Xray service is active.
func IsServiceRunning() bool {
	switch runtime.GOOS {
	case "linux":
		return run("systemctl", "is-active", "--quiet", "xray") == nil
	case "windows":
		out, err := exec.Command("sc", "query", "Xray").CombinedOutput()
		if err != nil {
			return false
		}
		return strings.Contains(string(out), "RUNNING")
	default:
		return false
	}
}

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%s %s: %w\n%s", name, strings.Join(args, " "), err, string(out))
	}
	return nil
}
