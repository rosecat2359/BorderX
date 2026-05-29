import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Box, Typography, Card, CardContent, CardActions, Button, Grid, Chip, Fab, Dialog, DialogTitle, DialogContent, TextField, DialogActions } from '@mui/material'
import { Add, Computer, Cloud } from '@mui/icons-material'
import { nodes } from '../api'
import type { Node } from '../api'

export default function Nodes() {
  const [list, setList] = useState<Node[]>([])
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState({ name: '', host: '', ssh_port: 22, ssh_user: 'root', os: 'linux' })
  const navigate = useNavigate()

  const load = () => { nodes.list().then(({ data }) => setList(data)).catch(() => {}) }
  useEffect(() => { load() }, [])

  const create = async () => {
    await nodes.create(form)
    setOpen(false); setForm({ name: '', host: '', ssh_port: 22, ssh_user: 'root', os: 'linux' }); load()
  }

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h4" sx={{ fontWeight: 600 }}>节点</Typography>
        <Fab color="primary" size="small" onClick={() => setOpen(true)}><Add /></Fab>
      </Box>
      <Grid container spacing={2}>
        {list.map((n) => (
          <Grid size={{ xs: 12, sm: 6, md: 4 }} key={n.id}>
            <Card>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                  {n.os === 'windows' ? <Computer /> : <Cloud />}
                  <Typography variant="h6">{n.name}</Typography>
                  <Chip size="small" label={n.status || 'unknown'}
                    color={n.status === 'online' ? 'success' : n.status === 'offline' ? 'error' : 'default'} />
                </Box>
                <Typography variant="body2" color="text.secondary">{n.host}:{n.ssh_port}</Typography>
                {(n.region || n.os) && <Typography variant="body2" color="text.secondary">{n.region}{n.region && n.os ? ' · ' : ''}{n.os}</Typography>}
                <Typography variant="body2" sx={{ mt: 1 }}>{(n.inbound_count ?? 0)} 入站 · {(n.client_count ?? 0)} 客户端</Typography>
              </CardContent>
              <CardActions>
                <Button size="small" onClick={() => navigate(`/nodes/${n.id}`)}>详情</Button>
                <Button size="small" onClick={() => { nodes.test(n.id).then(({ data }) => alert(JSON.stringify(data))).catch(() => {}) }}>测试</Button>
                <Button size="small" color="error" onClick={() => { if(window.confirm('确定删除节点 "' + n.name + '"？关联的入站和客户端也会被删除。')) nodes.delete(n.id).then(load) }}>删除</Button>
              </CardActions>
            </Card>
          </Grid>
        ))}
        {list.length === 0 && (
          <Grid size={{ xs: 12 }}><Typography color="text.secondary">暂无节点，点击右下角 + 添加</Typography></Grid>
        )}
      </Grid>

      <Dialog open={open} onClose={() => setOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>添加节点</DialogTitle>
        <DialogContent>
          <TextField fullWidth label="名称" sx={{ mt: 1, mb: 2 }} value={form.name} onChange={(e) => setForm({...form, name: e.target.value})} />
          <TextField fullWidth label="IP 地址" sx={{ mb: 2 }} value={form.host} onChange={(e) => setForm({...form, host: e.target.value})} />
          <TextField fullWidth label="SSH 端口" type="number" sx={{ mb: 2 }} value={form.ssh_port} onChange={(e) => setForm({...form, ssh_port: +e.target.value})} />
          <TextField fullWidth label="用户名" sx={{ mb: 2 }} value={form.ssh_user} onChange={(e) => setForm({...form, ssh_user: e.target.value})} />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpen(false)}>取消</Button>
          <Button variant="contained" onClick={create}>添加</Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}
