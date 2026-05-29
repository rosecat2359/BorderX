package node

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

// SSHManager manages SSH connection pool and remote command execution.
type SSHManager struct {
	mu     sync.RWMutex
	config map[string]*ssh.ClientConfig
	pool   map[string]*ssh.Client
}

// NewSSHManager creates a new SSHManager.
func NewSSHManager() *SSHManager {
	return &SSHManager{
		config: make(map[string]*ssh.ClientConfig),
		pool:   make(map[string]*ssh.Client),
	}
}

// Register stores the SSH config for a given node.
func (m *SSHManager) Register(nodeID, user, keyContent string, port int) error {
	signer, err := ssh.ParsePrivateKey([]byte(keyContent))
	if err != nil {
		return fmt.Errorf("解析 SSH 私钥失败: %w", err)
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.config[nodeID] = &ssh.ClientConfig{
		User: user,
		Auth: []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: func(hostname string, remote net.Addr, key ssh.PublicKey) error {
			return nil // Trust on first use
		},
		Timeout: 10 * time.Second,
	}
	return nil
}

// Connect establishes an SSH connection to the node.
func (m *SSHManager) Connect(nodeID, host string, port int) error {
	m.mu.RLock()
	cfg, ok := m.config[nodeID]
	m.mu.RUnlock()
	if !ok {
		return fmt.Errorf("节点 %s 未注册 SSH 配置", nodeID)
	}
	addr := fmt.Sprintf("%s:%d", host, port)
	client, err := ssh.Dial("tcp", addr, cfg)
	if err != nil {
		return fmt.Errorf("SSH 连接失败: %w", err)
	}
	m.mu.Lock()
	// Close old connection if exists
	if old, exists := m.pool[nodeID]; exists {
		old.Close()
	}
	m.pool[nodeID] = client
	m.mu.Unlock()
	return nil
}

// Exec runs a command on the remote node and returns stdout.
func (m *SSHManager) Exec(nodeID, command string) (string, error) {
	m.mu.RLock()
	client := m.pool[nodeID]
	m.mu.RUnlock()
	if client == nil {
		return "", fmt.Errorf("节点 %s 未连接", nodeID)
	}
	session, err := client.NewSession()
	if err != nil {
		return "", err
	}
	defer session.Close()
	var buf bytes.Buffer
	session.Stdout = &buf
	session.Stderr = &buf
	if err := session.Run(command); err != nil {
		return buf.String(), err
	}
	return buf.String(), nil
}

// CopyFile copies a local file to the remote node using SCP.
func (m *SSHManager) CopyFile(nodeID, localContent, remotePath string) error {
	m.mu.RLock()
	client := m.pool[nodeID]
	m.mu.RUnlock()
	if client == nil {
		return fmt.Errorf("节点 %s 未连接", nodeID)
	}
	session, err := client.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()
	w, _ := session.StdinPipe()
	go func() {
		defer w.Close()
		fmt.Fprintf(w, "C0644 %d %s\n", len(localContent), remotePath)
		io.WriteString(w, localContent)
		fmt.Fprint(w, "\x00")
	}()
	return session.Run("scp -t " + remotePath)
}

// Close disconnects a single node.
func (m *SSHManager) Close(nodeID string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if c, ok := m.pool[nodeID]; ok {
		c.Close()
		delete(m.pool, nodeID)
	}
}

// CloseAll disconnects all nodes.
func (m *SSHManager) CloseAll() {
	m.mu.Lock()
	defer m.mu.Unlock()
	for id, c := range m.pool {
		c.Close()
		delete(m.pool, id)
	}
}
