import { useState, useEffect } from 'react'
import { Box, Typography, Card, CardContent, TextField, Button } from '@mui/material'
import { system } from '../api'

export default function Settings() {
  const [password, setPassword] = useState('')
  const [info, setInfo] = useState<any>({})

  useEffect(() => { system.info().then(({ data }) => setInfo(data)).catch(() => {}) }, [])

  const changePassword = async () => {
    if (password.length < 6) { alert('密码至少 6 位'); return }
    try {
      await system.password(password)
      alert('密码已更新')
      setPassword('')
    } catch (err: any) {
      alert(err.response?.data?.error || '修改失败')
    }
  }

  const backup = async () => {
    try {
      const { data } = await system.backup()
      const url = URL.createObjectURL(new Blob([data], { type: 'application/octet-stream' }))
      const a = document.createElement('a')
      a.href = url; a.download = 'borderx-backup.db'; a.click()
      URL.revokeObjectURL(url)
    } catch {
      alert('备份失败')
    }
  }

  return (
    <Box>
      <Typography variant="h4" sx={{ fontWeight: 600, mb: 3 }}>系统设置</Typography>

      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Typography variant="h6" sx={{ mb: 2 }}>系统信息</Typography>
          <Typography>版本: {info.version || '-'}</Typography>
          <Typography>系统: {info.os || '-'}</Typography>
        </CardContent>
      </Card>

      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Typography variant="h6" sx={{ mb: 2 }}>修改密码</Typography>
          <Box sx={{ display: 'flex', gap: 2 }}>
            <TextField type="password" label="新密码" value={password} onChange={(e) => setPassword(e.target.value)} />
            <Button variant="contained" onClick={changePassword}>更新</Button>
          </Box>
        </CardContent>
      </Card>

      <Card>
        <CardContent>
          <Typography variant="h6" sx={{ mb: 2 }}>数据备份</Typography>
          <Button variant="outlined" onClick={backup}>导出数据库</Button>
        </CardContent>
      </Card>
    </Box>
  )
}
