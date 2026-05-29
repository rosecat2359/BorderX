import { useState, useEffect, useRef } from 'react'
import { Box, Typography, Card, CardContent, TextField, Button } from '@mui/material'
import api, { system } from '../api'

function formatSize(b: number): string {
  if (b >= 1e6) return (b / 1e6).toFixed(1) + ' MB'
  if (b >= 1e3) return (b / 1e3).toFixed(1) + ' KB'
  return b + ' B'
}

export default function Settings() {
  const [password, setPassword] = useState('')
  const [info, setInfo] = useState<any>({})
  const fileRef = useRef<HTMLInputElement>(null)

  useEffect(() => { system.info().then(({ data }) => setInfo(data)).catch(() => {}) }, [])

  const changePassword = async () => {
    if (password.length < 6) { alert('密码至少 6 位'); return }
    try { await system.password(password); alert('密码已更新'); setPassword('') }
    catch (err: any) { alert(err.response?.data?.error || '修改失败') }
  }

  const backup = async () => {
    try {
      const { data } = await system.backup()
      const url = URL.createObjectURL(new Blob([data], { type: 'application/octet-stream' }))
      const a = document.createElement('a'); a.href = url; a.download = 'borderx-backup.db'; a.click()
      URL.revokeObjectURL(url)
    } catch { alert('备份失败') }
  }

  const restore = async () => {
    const file = fileRef.current?.files?.[0]
    if (!file) { alert('请选择备份文件'); return }
    if (!confirm('恢复数据库将替换当前所有数据，面板将自动重启。确定继续？')) return
    try {
      const fd = new FormData(); fd.append('file', file)
      await api.post('/system/restore', fd)
      alert('数据库已恢复，面板即将重启')
      setTimeout(() => window.location.reload(), 3000)
    } catch (err: any) { alert(err.response?.data?.error || '恢复失败') }
  }

  return (
    <Box>
      <Typography variant="h4" sx={{ fontWeight: 600, mb: 3 }}>系统设置</Typography>
      <Card sx={{ mb: 3 }}><CardContent>
        <Typography variant="h6" sx={{ mb: 2 }}>系统信息</Typography>
        <Typography>版本: {info.version || '-'}</Typography>
        <Typography>系统: {info.os || '-'}</Typography>
        <Typography>活跃节点: {info.node_count ?? '-'}</Typography>
        <Typography>活跃客户端: {info.client_count ?? '-'}</Typography>
        <Typography>活跃入站: {info.inbound_count ?? '-'}</Typography>
        <Typography>数据库大小: {info.db_size ? formatSize(info.db_size) : '-'}</Typography>
      </CardContent></Card>
      <Card sx={{ mb: 3 }}><CardContent>
        <Typography variant="h6" sx={{ mb: 2 }}>修改密码</Typography>
        <Box sx={{ display: 'flex', gap: 2 }}>
          <TextField type="password" label="新密码" value={password} onChange={(e) => setPassword(e.target.value)} />
          <Button variant="contained" onClick={changePassword}>更新</Button>
        </Box>
      </CardContent></Card>
      <Card sx={{ mb: 3 }}><CardContent>
        <Typography variant="h6" sx={{ mb: 2 }}>数据备份</Typography>
        <Button variant="outlined" onClick={backup}>导出数据库</Button>
      </CardContent></Card>
      <Card><CardContent>
        <Typography variant="h6" sx={{ mb: 2 }}>数据恢复</Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          上传之前导出的 .db 备份文件，恢复后面板将自动重启。
        </Typography>
        <input type="file" accept=".db" ref={fileRef} style={{ marginBottom: 8 }} />
        <Button variant="contained" color="warning" onClick={restore}>恢复数据库</Button>
      </CardContent></Card>
    </Box>
  )
}
