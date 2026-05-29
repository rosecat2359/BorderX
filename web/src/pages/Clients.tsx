import { useEffect, useState } from 'react'
import { Box, Typography, Table, TableHead, TableBody, TableRow, TableCell, Button, Chip, Dialog, DialogTitle, DialogContent, TextField, DialogActions, IconButton, Tooltip } from '@mui/material'
import { ContentCopy, QrCode2, Add } from '@mui/icons-material'
import { clients, inbounds } from '../api'
import type { Client, Inbound } from '../api'
import { QRCodeSVG } from 'qrcode.react'

export default function Clients() {
  const [list, setList] = useState<Client[]>([])
  const [open, setOpen] = useState(false)
  const [ibList, setIbList] = useState<Inbound[]>([])
  const [form, setForm] = useState({ name: '', total_limit: 0, expiry_at: '', inbound_ids: [] as string[] })
  const [qrData, setQrData] = useState('')

  const load = () => { clients.list().then(({ data }) => setList(data)).catch(() => {}) }
  useEffect(() => {
    load()
    inbounds.list().then(({ data }) => setIbList(Array.isArray(data) ? data : [])).catch(() => {})
  }, [])

  const create = async () => {
    await clients.create(form)
    setOpen(false); setForm({ name: '', total_limit: 0, expiry_at: '', inbound_ids: [] }); load()
  }

  const getSubUrl = (clientId: string) => `/api/sub?client=${clientId}`

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4" sx={{ fontWeight: 600 }}>客户端</Typography>
        <Button variant="contained" startIcon={<Add />} onClick={() => setOpen(true)}>添加</Button>
      </Box>
      <Table>
        <TableHead>
          <TableRow>
            <TableCell>备注</TableCell>
            <TableCell>UUID</TableCell>
            <TableCell>流量</TableCell>
            <TableCell>到期</TableCell>
            <TableCell>节点</TableCell>
            <TableCell>操作</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {list.map((c) => (
            <TableRow key={c.id}>
              <TableCell>{c.name || '-'}</TableCell>
              <TableCell><Typography component="code">{c.uuid.substring(0, 12)}...</Typography></TableCell>
              <TableCell>{formatBytes(c.total_used ?? 0)} / {c.total_limit > 0 ? c.total_limit + ' GB' : '不限'}</TableCell>
              <TableCell>{c.expiry_at ? new Date(c.expiry_at).toLocaleDateString() : '永不过期'}</TableCell>
              <TableCell>{(c.inbounds ?? []).map(ci => ci.node_name).join(', ') || '-'}</TableCell>
              <TableCell>
                <Tooltip title="复制订阅链接"><IconButton onClick={() => { navigator.clipboard.writeText(window.location.origin + getSubUrl(c.id)) }}><ContentCopy /></IconButton></Tooltip>
                <Tooltip title="QR 码"><IconButton onClick={() => setQrData(window.location.origin + getSubUrl(c.id))}><QrCode2 /></IconButton></Tooltip>
                <Button size="small" color="error" onClick={() => { if(window.confirm('确定删除？')) clients.delete(c.id).then(load) }}>删除</Button>
              </TableCell>
            </TableRow>
          ))}
          {list.length === 0 && (
            <TableRow><TableCell colSpan={6}><Typography color="text.secondary" sx={{ textAlign: 'center' }}>暂无客户端</Typography></TableCell></TableRow>
          )}
        </TableBody>
      </Table>

      <Dialog open={open} onClose={() => setOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>添加客户端</DialogTitle>
        <DialogContent>
          <TextField fullWidth label="备注" sx={{ mt: 1, mb: 2 }} value={form.name} onChange={(e) => setForm({...form, name: e.target.value})} />
          <TextField fullWidth label="流量限制 (GB, 0=不限)" type="number" sx={{ mb: 2 }} value={form.total_limit} onChange={(e) => setForm({...form, total_limit: +e.target.value})} />
          <TextField fullWidth label="到期时间" type="date" sx={{ mb: 2 }} value={form.expiry_at} onChange={(e) => setForm({...form, expiry_at: e.target.value})} slotProps={{ inputLabel: { shrink: true } }} />
          <Typography variant="body2" sx={{ mb: 1 }}>部署到入站:</Typography>
          <Box>
            {ibList.map((ib) => (
              <Chip key={ib.id}
                label={`${(ib as any).node_name || ib.node_id} - ${ib.protocol}:${ib.port}`}
                color={form.inbound_ids.includes(ib.id) ? 'primary' : 'default'}
                onClick={() => setForm({...form, inbound_ids: form.inbound_ids.includes(ib.id) ? form.inbound_ids.filter(i => i !== ib.id) : [...form.inbound_ids, ib.id]})}
                sx={{ mr: 1, mb: 1 }} />
            ))}
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpen(false)}>取消</Button>
          <Button variant="contained" onClick={create} disabled={form.inbound_ids.length === 0}>创建</Button>
        </DialogActions>
      </Dialog>

      <Dialog open={!!qrData} onClose={() => setQrData('')}>
        <DialogContent sx={{ textAlign: 'center' }}>
          <QRCodeSVG value={qrData} size={256} />
          <Typography variant="body2" sx={{ mt: 1, wordBreak: 'break-all' }}>{qrData}</Typography>
        </DialogContent>
      </Dialog>
    </Box>
  )
}

function formatBytes(b: number): string {
  if (b === 0) return '0 B'
  if (b >= 1e9) return (b / 1e9).toFixed(1) + ' GB'
  if (b >= 1e6) return (b / 1e6).toFixed(1) + ' MB'
  if (b >= 1e3) return (b / 1e3).toFixed(1) + ' KB'
  return b + ' B'
}
