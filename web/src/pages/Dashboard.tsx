import { useEffect, useState, useCallback } from 'react'
import { Box, Card, CardContent, Typography, Grid, Chip } from '@mui/material'
import { Dns, People, CloudUpload, CloudDownload } from '@mui/icons-material'
import { traffic, nodes } from '../api'
import type { Node } from '../api'

function formatBytes(b: number): string {
  if (b === 0) return '0 B'
  if (b >= 1e9) return (b / 1e9).toFixed(1) + ' GB'
  if (b >= 1e6) return (b / 1e6).toFixed(1) + ' MB'
  if (b >= 1e3) return (b / 1e3).toFixed(1) + ' KB'
  return b + ' B'
}

export default function Dashboard() {
  const [data, setData] = useState<any>({})
  const [nodeList, setNodeList] = useState<Node[]>([])
  const [uptime, setUptime] = useState(0)

  const load = useCallback(() => {
    traffic.overview().then(({ data }) => setData(data)).catch(() => {})
    nodes.list().then(({ data }) => setNodeList(Array.isArray(data) ? data : [])).catch(() => {})
    setUptime((u) => u + 30)
  }, [])

  useEffect(() => {
    load()
    const timer = setInterval(load, 30000) // refresh every 30s
    return () => clearInterval(timer)
  }, [load])

  const cards = [
    { label: '活跃节点', value: data.node_count ?? '-', icon: <Dns />, color: '#90caf9' },
    { label: '活跃客户端', value: data.active_clients ?? '-', icon: <People />, color: '#a5d6a7' },
    { label: '今日上行', value: formatBytes(data.today_up_bytes ?? 0), icon: <CloudUpload />, color: '#ef9a9a' },
    { label: '今日下行', value: formatBytes(data.today_down_bytes ?? 0), icon: <CloudDownload />, color: '#ffcc80' },
  ]

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h4" sx={{ fontWeight: 600 }}>仪表盘</Typography>
        <Typography variant="body2" color="text.secondary">每 30 秒自动刷新 · 运行 {Math.floor(uptime / 60)} 分 {uptime % 60} 秒</Typography>
      </Box>
      <Grid container spacing={3} sx={{ mb: 4 }}>
        {cards.map((card) => (
          <Grid size={{ xs: 12, sm: 6, md: 3 }} key={card.label}>
            <Card>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                  <Box sx={{ color: card.color }}>{card.icon}</Box>
                  <Box>
                    <Typography variant="h5" sx={{ fontWeight: 700 }}>{card.value}</Typography>
                    <Typography variant="body2" color="text.secondary">{card.label}</Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      <Typography variant="h6" sx={{ mb: 2 }}>节点状态</Typography>
      <Grid container spacing={2}>
        {nodeList.map((n) => (
          <Grid size={{ xs: 12, sm: 6, md: 4 }} key={n.id}>
            <Card>
              <CardContent>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                  <Typography sx={{ fontWeight: 600 }}>{n.name || n.host}</Typography>
                  <Chip size="small" label={n.status || 'unknown'}
                    color={n.status === 'online' ? 'success' : n.status === 'offline' ? 'error' : 'default'} />
                </Box>
                <Typography variant="body2" color="text.secondary">{n.host} · {n.os}</Typography>
                <Box sx={{ mt: 1, display: 'flex', gap: 2 }}>
                  <Typography variant="body2">{n.inbound_count ?? 0} 入站</Typography>
                  <Typography variant="body2">{n.client_count ?? 0} 客户端</Typography>
                </Box>
              </CardContent>
            </Card>
          </Grid>
        ))}
        {nodeList.length === 0 && (
          <Grid size={{ xs: 12 }}><Typography color="text.secondary">暂无节点，前往"节点"页面添加</Typography></Grid>
        )}
      </Grid>
    </Box>
  )
}
