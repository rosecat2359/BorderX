// 跨平台 Xray 操作抽象 — Linux systemctl / Windows Service。
package xray

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// PlatformManager abstracts OS-specific Xray operations.
type PlatformManager interface {
	DetectXray() (installed bool, version string, err error)
	InstallXray() error
	ConfigPath() string
	ReloadService() error
	ServiceStatus() (running bool, err error)
}

// NewPlatformManager returns the correct implementation for the given OS.
// Acceptable values for os: "linux", "windows". Defaults to linux.
func NewPlatformManager(osName, binaryPath, configPath string) PlatformManager {
	switch strings.ToLower(osName) {
	case "windows":
		return &windowsManager{binaryPath: binaryPath, configPath: configPath}
	default:
		return &linuxManager{binaryPath: binaryPath, configPath: configPath}
	}
}

// HostPlatformManager returns a PlatformManager for the current OS.
func HostPlatformManager(binaryPath, configPath string) PlatformManager {
	return NewPlatformManager(runtime.GOOS, binaryPath, configPath)
}

// ---- Linux ----

type linuxManager struct {
	binaryPath string
	configPath string
}

func (m *linuxManager) DetectXray() (bool, string, error) {
	if _, err := os.Stat(m.binaryPath); os.IsNotExist(err) {
		return false, "", nil
	}
	out, err := exec.Command(m.binaryPath, "version").CombinedOutput()
	if err != nil {
		return false, "", nil
	}
	version := strings.TrimSpace(string(out))
	// xray version prints multiline, take first line
	if idx := strings.Index(version, "\n"); idx > 0 {
		version = version[:idx]
	}
	return true, version, nil
}

func (m *linuxManager) InstallXray() error {
	script := `bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install`
	return exec.Command("bash", "-c", script).Run()
}

func (m *linuxManager) ConfigPath() string {
	return m.configPath
}

func (m *linuxManager) ReloadService() error {
	// Try systemctl first, then fall back to restarting the process
	if err := exec.Command("systemctl", "reload", "xray").Run(); err != nil {
		return exec.Command("systemctl", "restart", "xray").Run()
	}
	return nil
}

func (m *linuxManager) ServiceStatus() (bool, error) {
	err := exec.Command("systemctl", "is-active", "--quiet", "xray").Run()
	return err == nil, nil
}

// ---- Windows ----

type windowsManager struct {
	binaryPath string
	configPath string
}

func (m *windowsManager) DetectXray() (bool, string, error) {
	if _, err := os.Stat(m.binaryPath); os.IsNotExist(err) {
		return false, "", nil
	}
	out, err := exec.Command(m.binaryPath, "version").CombinedOutput()
	if err != nil {
		return false, "", nil
	}
	version := strings.TrimSpace(string(out))
	if idx := strings.Index(version, "\n"); idx > 0 {
		version = version[:idx]
	}
	return true, version, nil
}

func (m *windowsManager) InstallXray() error {
	return fmt.Errorf("Windows 自动安装 Xray 暂不支持，请手动下载: https://github.com/XTLS/Xray-core/releases")
}

func (m *windowsManager) ConfigPath() string {
	return m.configPath
}

func (m *windowsManager) ReloadService() error {
	return exec.Command("powershell", "-Command", "Restart-Service", "Xray").Run()
}

func (m *windowsManager) ServiceStatus() (bool, error) {
	err := exec.Command("powershell", "-Command", "Get-Service", "Xray", "-ErrorAction", "SilentlyContinue").Run()
	return err == nil, nil
}
