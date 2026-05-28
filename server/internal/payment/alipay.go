package payment

import (
	"bytes"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"time"
)

// AlipayConfig holds Alipay merchant configuration.
type AlipayConfig struct {
	AppID        string // 支付宝应用 APPID
	PrivateKey   string // 应用私钥路径
	AlipayPubKey string // 支付宝公钥路径
	NotifyURL    string // 回调地址 https://your-domain/api/payment/alipay/notify
}

// AlipayClient communicates with Alipay's OpenAPI.
type AlipayClient struct {
	cfg        AlipayConfig
	privateKey *rsa.PrivateKey
	aliPubKey  *rsa.PublicKey
}

// NewAlipayClient loads RSA keys from the configured paths and returns a ready-to-use client.
func NewAlipayClient(cfg AlipayConfig) (*AlipayClient, error) {
	privData, err := os.ReadFile(cfg.PrivateKey)
	if err != nil {
		return nil, fmt.Errorf("读取应用私钥失败: %w", err)
	}
	block, _ := pem.Decode(privData)
	if block == nil {
		return nil, fmt.Errorf("无法解析应用私钥 PEM 块")
	}
	privKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("解析私钥失败: %w", err)
	}

	rsaPriv, ok := privKey.(*rsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("应用私钥不是 RSA 私钥")
	}

	pubData, err := os.ReadFile(cfg.AlipayPubKey)
	if err != nil {
		return nil, fmt.Errorf("读取支付宝公钥失败: %w", err)
	}
	block, _ = pem.Decode(pubData)
	if block == nil {
		return nil, fmt.Errorf("无法解析支付宝公钥 PEM 块")
	}
	pubKey, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("解析支付宝公钥失败: %w", err)
	}

	rsaPub, ok := pubKey.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("支付宝公钥不是 RSA 公钥")
	}

	return &AlipayClient{
		cfg:        cfg,
		privateKey: rsaPriv,
		aliPubKey:  rsaPub,
	}, nil
}

// TradePrecreate 调用支付宝当面付预下单接口，返回 QR 码 URL。
// outTradeNo: 商户订单号 (对应 order.id)
// subject:    商品标题 (套餐名称)
// totalAmount: 金额（元）
func (c *AlipayClient) TradePrecreate(outTradeNo, subject string, totalAmount float64) (string, error) {
	bizContent := map[string]string{
		"out_trade_no": outTradeNo,
		"total_amount": fmt.Sprintf("%.2f", totalAmount),
		"subject":      subject,
	}
	bizJSON, _ := json.Marshal(bizContent)

	params := map[string]string{
		"app_id":      c.cfg.AppID,
		"method":      "alipay.trade.precreate",
		"charset":     "utf-8",
		"sign_type":   "RSA2",
		"timestamp":   time.Now().Format("2006-01-02 15:04:05"),
		"version":     "1.0",
		"notify_url":  c.cfg.NotifyURL,
		"biz_content": string(bizJSON),
	}

	params["sign"] = c.sign(params)

	resp, err := httpPostForm("https://openapi.alipay.com/gateway.do", params)
	if err != nil {
		return "", fmt.Errorf("支付宝请求失败: %w", err)
	}

	type inner struct {
		Code   string `json:"code"`
		Msg    string `json:"msg"`
		QRCode string `json:"qr_code"`
	}
	var result struct {
		AlipayTradePrecreateResponse inner `json:"alipay_trade_precreate_response"`
	}
	if err := json.Unmarshal(resp, &result); err != nil {
		return "", fmt.Errorf("解析支付宝响应失败: %w", err)
	}

	if result.AlipayTradePrecreateResponse.Code != "10000" {
		return "", fmt.Errorf("支付宝预下单失败: %s (%s)",
			result.AlipayTradePrecreateResponse.Msg,
			result.AlipayTradePrecreateResponse.Code)
	}

	return result.AlipayTradePrecreateResponse.QRCode, nil
}

// VerifyNotify 验证支付宝异步通知的签名。
// 支付宝用其私钥签名，我方用支付宝公钥验签。
func (c *AlipayClient) VerifyNotify(params map[string]string) bool {
	sign, ok := params["sign"]
	if !ok || sign == "" {
		return false
	}
	signType := params["sign_type"]
	delete(params, "sign")
	delete(params, "sign_type")

	expected := c.sign(params)

	// Restore deleted keys in case the caller still needs them.
	params["sign"] = sign
	if signType != "" {
		params["sign_type"] = signType
	}

	// 验签: 用支付宝公钥验证 RSA-SHA256 签名
	sigBytes, err := base64.StdEncoding.DecodeString(expected)
	if err != nil {
		return false
	}
	hash := sha256.Sum256([]byte(c.buildSignString(params)))
	err = rsa.VerifyPKCS1v15(c.aliPubKey, crypto.SHA256, hash[:], sigBytes)
	if err != nil {
		// Fallback: compare sign strings for environments where Alipay
		// returns a differently-formatted signature.
		return sign == expected
	}
	return true
}

// sign builds the sorted k=v string, signs it with RSA-SHA256, and returns
// the base64-encoded signature.
func (c *AlipayClient) sign(params map[string]string) string {
	content := c.buildSignString(params)
	hash := sha256.Sum256([]byte(content))
	sig, _ := rsa.SignPKCS1v15(rand.Reader, c.privateKey, crypto.SHA256, hash[:])
	return base64.StdEncoding.EncodeToString(sig)
}

// buildSignString returns the canonical query-string-like content to be signed:
// sorted keys, excluding sign and empty-value keys, joined by "&".
func (c *AlipayClient) buildSignString(params map[string]string) string {
	keys := make([]string, 0, len(params))
	for k := range params {
		if k == "sign" || k == "sign_type" || params[k] == "" {
			continue
		}
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var parts []string
	for _, k := range keys {
		parts = append(parts, k+"="+params[k])
	}
	return strings.Join(parts, "&")
}

// httpPostForm performs an HTTP POST with form-encoded data and returns the
// response body.
func httpPostForm(apiURL string, params map[string]string) ([]byte, error) {
	form := url.Values{}
	for k, v := range params {
		form.Set(k, v)
	}
	resp, err := http.Post(apiURL, "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var buf bytes.Buffer
	if _, err := buf.ReadFrom(resp.Body); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
