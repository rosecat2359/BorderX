import { useEffect, useState } from 'react'
import { Box, Card, CardContent, Typography, Grid } from '@mui/material'
import { Dns, People, CloudUpload, CloudDownload } from '@mui/icons-material'
import { traffic } from '../api'

export default function Dashboard() {
  const [data, setData] = useState<any>({})
  useEffect(() => { traffic.overview().then(({ data }) => setData(data)).catch(() => {}) }, [])

  const cards = [
    { label: '活跃节点', value: data.node_count ?? '-', icon: <Dns />, color: '#90caf9' },
    { label: '活跃客户端', value: data.active_clients ?? '-', icon: <People />, color: '#a5d6a7' },
    { label: '今日上行', value: formatBytes(data.today_up_bytes ?? 0), icon: <CloudUpload />, color: '#ef9a9a' },
    { label: '今日下行', value: formatBytes(data.today_down_bytes ?? 0), icon: <CloudDownload />, color: '#ffcc80' },
  ]

  return (
    <Box>
      <Typography variant="h4" sx={{ fontWeight: 600, mb: 3 }}>仪表盘</Typography>
      <Grid container spacing={3}>
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
