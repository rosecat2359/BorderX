import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { Box, Card, CardContent, TextField, Button, Typography, CircularProgress } from '@mui/material'
import { auth } from '../api'
import { useAuth } from '../store/auth'

export default function Login() {
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [needSetup, setNeedSetup] = useState(false)
  const { setToken } = useAuth()
  const navigate = useNavigate()

  useEffect(() => {
    auth.setupCheck().then(({ data }) => {
      setNeedSetup(data.need_setup)
      setLoading(false)
    }).catch(() => setLoading(false))
  }, [])

  const submit = async () => {
    if (password.length < 6) { setError('密码至少 6 位'); return }
    setError('')
    try {
      const fn = needSetup ? auth.setup : auth.login
      const { data } = await fn(password)
      setToken(data.token)
      navigate('/')
    } catch (err: any) {
      setError(err.response?.data?.error || '操作失败')
    }
  }

  if (loading) return <Box sx={{ display: 'flex', justifyContent: 'center', mt: 10 }}><CircularProgress /></Box>

  return (
    <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', bgcolor: 'background.default' }}>
      <Card sx={{ maxWidth: 400, width: '100%', mx: 2 }}>
        <CardContent sx={{ p: 4 }}>
          <Typography variant="h4" sx={{ fontWeight: 700, textAlign: 'center', mb: 1 }}>BorderX</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ textAlign: 'center', mb: 4 }}>
            {needSetup ? '首次使用，请设置管理员密码' : '请输入管理员密码'}
          </Typography>
          {error && <Typography color="error" sx={{ mb: 2, fontSize: 14 }}>{error}</Typography>}
          <TextField fullWidth type="password" label="密码" value={password}
            onChange={(e) => setPassword(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && submit()}
            sx={{ mb: 3 }} autoFocus />
          <Button fullWidth variant="contained" size="large" onClick={submit}>
            {needSetup ? '初始化' : '登录'}
          </Button>
        </CardContent>
      </Card>
    </Box>
  )
}
