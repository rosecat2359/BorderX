package xray

import (
	"crypto/rand"
	"encoding/hex"
	"os/exec"
	"bytes"
)

// RealityKeys holds the X25519 keypair and short ID for Reality.
type RealityKeys struct {
	PrivateKey string `json:"private_key"`
	PublicKey  string `json:"public_key"`
	ShortID    string `json:"short_id"`
}

// GenerateRealityKeys runs "xray x25519" to generate a Reality keypair.
func GenerateRealityKeys(binaryPath string) (*RealityKeys, error) {
	cmd := exec.Command(binaryPath, "x25519")
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return nil, err
	}
	output := out.String()
	priv := extractLine(output, "Private key:")
	pub := extractLine(output, "Public key:")
	sid := generateShortID()
	return &RealityKeys{PrivateKey: priv, PublicKey: pub, ShortID: sid}, nil
}

func generateShortID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func extractLine(output, prefix string) string {
	for _, line := range bytes.Split([]byte(output), []byte("\n")) {
		if bytes.HasPrefix(line, []byte(prefix)) {
			s := string(bytes.TrimSpace(line))
			idx := len(prefix)
			for idx < len(s) && s[idx] == ' ' {
				idx++
			}
			if idx < len(s) {
				return s[idx:]
			}
		}
	}
	return ""
}
