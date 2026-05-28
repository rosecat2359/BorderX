package auth

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"net/http"
	"strings"
	"time"

	"github.com/borderx/panel/internal/mail"
	"github.com/borderx/panel/internal/model"
	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type Handler struct {
	DB         *sql.DB
	JWT        *JWTManager
	MailSender *mail.Sender
}

type RegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6,max=64"`
}

type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type AdminLoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *Handler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "服务器错误"})
		return
	}
	var user model.User
	err = h.DB.QueryRow(
		`INSERT INTO users (email, password_hash) VALUES ($1, $2)
		 RETURNING id, email, status, created_at`,
		req.Email, string(hash),
	).Scan(&user.ID, &user.Email, &user.Status, &user.CreatedAt)
	if err != nil {
		if isDuplicate(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "该邮箱已注册"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "注册失败"})
		return
	}
	token, _ := h.JWT.GenerateUserToken(user.ID, user.Email)
	c.JSON(http.StatusCreated, gin.H{"token": token, "user": user})
}

func (h *Handler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	var user model.User
	err := h.DB.QueryRow(
		`SELECT id, email, password_hash, status FROM users WHERE email = $1`, req.Email,
	).Scan(&user.ID, &user.Email, &user.PasswordHash, &user.Status)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "邮箱或密码错误"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "登录失败"})
		return
	}
	if user.Status != "active" {
		c.JSON(http.StatusForbidden, gin.H{"error": "账号已被禁用"})
		return
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "邮箱或密码错误"})
		return
	}
	token, _ := h.JWT.GenerateUserToken(user.ID, user.Email)
	c.JSON(http.StatusOK, gin.H{"token": token, "user": user})
}

func (h *Handler) AdminLogin(c *gin.Context) {
	var req AdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	var admin model.Admin
	err := h.DB.QueryRow(
		`SELECT id, username, password_hash, role FROM admins WHERE username = $1`, req.Username,
	).Scan(&admin.ID, &admin.Username, &admin.PasswordHash, &admin.Role)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "登录失败"})
		return
	}
	if err := bcrypt.CompareHashAndPassword([]byte(admin.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
		return
	}
	token, _ := h.JWT.GenerateAdminToken(admin.ID, admin.Username, admin.Role)
	c.JSON(http.StatusOK, gin.H{
		"token": token,
		"admin": gin.H{"id": admin.ID, "username": admin.Username, "role": admin.Role},
	})
}

func isDuplicate(err error) bool {
	return err != nil && strings.Contains(err.Error(), "duplicate key")
}

func generateToken() string {
	b := make([]byte, 32)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// SendVerifyEmail sends a verification email to the user
func (h *Handler) SendVerifyEmail(c *gin.Context) {
	userID := c.GetString("user_id")
	token := generateToken()
	h.DB.Exec("UPDATE users SET verify_token=$1 WHERE id=$2", token, userID)

	var email string
	h.DB.QueryRow("SELECT email FROM users WHERE id=$1", userID).Scan(&email)

	link := c.Request.Host + "/api/auth/verify-email?token=" + token
	if h.MailSender != nil {
		h.MailSender.Send(email, "BorderX 邮箱验证", "请点击链接验证邮箱: "+link)
	}

	c.JSON(http.StatusOK, gin.H{"message": "验证邮件已发送", "verify_link": link})
}

// VerifyEmail confirms a user's email address
func (h *Handler) VerifyEmail(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		c.String(http.StatusBadRequest, "缺少 token")
		return
	}
	result, _ := h.DB.Exec("UPDATE users SET email_verified=true, verify_token='' WHERE verify_token=$1 AND verify_token!=''", token)
	n, _ := result.RowsAffected()
	if n == 0 {
		c.String(http.StatusBadRequest, "无效或已过期的验证链接")
		return
	}
	c.String(http.StatusOK, "邮箱验证成功，请返回登录")
}

// ForgotPassword sends a password reset email
func (h *Handler) ForgotPassword(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}

	var userID string
	err := h.DB.QueryRow("SELECT id FROM users WHERE email=$1", req.Email).Scan(&userID)
	if err != nil {
		// Don't reveal whether email exists
		c.JSON(http.StatusOK, gin.H{"message": "如果邮箱已注册，重置邮件已发送"})
		return
	}

	token := generateToken()
	expires := time.Now().Add(1 * time.Hour)
	h.DB.Exec("UPDATE users SET reset_token=$1, reset_token_expires=$2 WHERE id=$3", token, expires, userID)

	link := c.Request.Host + "/reset-password?token=" + token
	if h.MailSender != nil {
		h.MailSender.Send(req.Email, "BorderX 密码重置", "请点击链接重置密码（1小时内有效）: "+link)
	}

	c.JSON(http.StatusOK, gin.H{"message": "如果邮箱已注册，重置邮件已发送"})
}

// ResetPassword changes password using a reset token
func (h *Handler) ResetPassword(c *gin.Context) {
	var req struct {
		Token    string `json:"token" binding:"required"`
		Password string `json:"password" binding:"required,min=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}

	var userID string
	err := h.DB.QueryRow(
		"SELECT id FROM users WHERE reset_token=$1 AND reset_token_expires > now()",
		req.Token,
	).Scan(&userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效或已过期的重置链接"})
		return
	}

	hash, _ := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	h.DB.Exec("UPDATE users SET password_hash=$1, reset_token='', reset_token_expires=NULL WHERE id=$2",
		string(hash), userID)

	c.JSON(http.StatusOK, gin.H{"message": "密码已重置，请重新登录"})
}
