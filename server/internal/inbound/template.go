package inbound

import "github.com/borderx/panel/internal/xray"

// Template represents a named inbound configuration preset.
type Template struct {
	Name        string `json:"name"`
	Protocol    string `json:"protocol"`
	Port        int    `json:"port"`
	Description string `json:"description"`
}

// BuiltinTemplates lists recommended inbound presets that cover common
// deployment patterns (Reality, WebSocket+TLS, CDN, Trojan).
var BuiltinTemplates = []Template{
	{Name: "VLESS + Reality", Protocol: "vless", Port: 443, Description: "推荐方案，Reality 抗封锁"},
	{Name: "VLESS + WebSocket + TLS", Protocol: "vless", Port: 443, Description: "WebSocket 分流，可搭配 Nginx"},
	{Name: "VMess + WebSocket + CDN", Protocol: "vmess", Port: 10001, Description: "适合套 CDN 隐藏 IP"},
	{Name: "Trojan + TCP + TLS", Protocol: "trojan", Port: 443, Description: "经典 Trojan 方案"},
}

// GetTemplates returns a copy of the built-in template list.
func GetTemplates() []Template { return BuiltinTemplates }

// GenerateSettings returns stock settings/stream JSON strings for the
// given protocol.  The caller is expected to replace Reality placeholders
// for vless before persisting the config.
func GenerateSettings(protocol string) (settingsJSON, streamJSON string) {
	switch protocol {
	case "vless":
		settingsJSON = `{"clients":[],"decryption":"none"}`
		streamJSON = `{"network":"tcp","security":"reality","realitySettings":{"dest":"www.microsoft.com:443","serverNames":["www.microsoft.com"],"privateKey":"PLACEHOLDER","shortIds":["PLACEHOLDER"]}}`
	case "vmess":
		settingsJSON = `{"clients":[]}`
		streamJSON = `{"network":"ws","security":"none","wsSettings":{"path":"/ws"}}`
	case "trojan":
		settingsJSON = `{"clients":[]}`
		streamJSON = `{"network":"tcp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/path/to/cert.pem","keyFile":"/path/to/key.pem"}]}}`
	default:
		settingsJSON = `{"clients":[],"decryption":"none"}`
		streamJSON = `{}`
	}
	return
}

// GenerateRealityKeys wraps xray.GenerateRealityKeys and returns the
// individual key components, or safe placeholders on failure.
func GenerateRealityKeys() (priv, pub, shortID string) {
	keys, err := xray.GenerateRealityKeys("xray")
	if err != nil {
		return "PLACEHOLDER_PRIV", "PLACEHOLDER_PUB", "abcdef01"
	}
	return keys.PrivateKey, keys.PublicKey, keys.ShortID
}

// ReplacePlaceholders substitutes the Reality PLACEHOLDER tokens in a
// stream-settings JSON string with real generated values.
func ReplacePlaceholders(stream, priv, shortID string) string {
	result := stream
	oldPriv := `"privateKey":"PLACEHOLDER"`
	newPriv := `"privateKey":"` + priv + `"`
	result = replaceStr(result, oldPriv, newPriv)
	oldSID := `"shortIds":["PLACEHOLDER"]`
	newSID := `"shortIds":["` + shortID + `"]`
	result = replaceStr(result, oldSID, newSID)
	return result
}

// replaceStr is a simple substring replacement helper.
func replaceStr(s, old, new string) string {
	if len(old) == 0 {
		return s
	}
	out := ""
	for i := 0; i < len(s); {
		if i+len(old) <= len(s) && s[i:i+len(old)] == old {
			out += new
			i += len(old)
		} else {
			out += string(s[i])
			i++
		}
	}
	return out
}
