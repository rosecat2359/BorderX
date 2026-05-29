import { useEffect, useState } from 'react'
import { Box, Typography, Card, CardContent, FormControl, InputLabel, Select, MenuItem } from '@mui/material'
import { LineChart } from '@mui/x-charts/LineChart'
import { clients, traffic } from '../api'
import type { Client } from '../api'

export default function Traffic() {
  const [clientList, setClientList] = useState<Client[]>([])
  const [selectedId, setSelectedId] = useState('')
  const [chartData, setChartData] = useState<{ hour: string; up: number; down: number }[]>([])

  useEffect(() => { clients.list().then(({ data }) => setClientList(data)).catch(() => {}) }, [])

  useEffect(() => {
    if (!selectedId) return
    traffic.clients(selectedId).then(({ data }) => {
      const series = (Array.isArray(data) ? data : []).map((d: any) => ({
        hour: d.hour ? d.hour.substring(11, 16) : '', // Just HH:MM
        up: +(d.up_bytes / 1e9).toFixed(2),
        down: +(d.down_bytes / 1e9).toFixed(2),
      }))
      setChartData(series)
    }).catch(() => {})
  }, [selectedId])

  return (
    <Box>
      <Typography variant="h4" sx={{ fontWeight: 600, mb: 3 }}>流量统计</Typography>
      <Card sx={{ mb: 3 }}>
        <CardContent>
          <FormControl fullWidth>
            <InputLabel>选择客户端</InputLabel>
            <Select value={selectedId} label="选择客户端" onChange={(e) => setSelectedId(e.target.value)}>
              {clientList.map((c) => (
                <MenuItem key={c.id} value={c.id}>{c.name || c.id.substring(0, 8)}</MenuItem>
              ))}
            </Select>
          </FormControl>
        </CardContent>
      </Card>
      {chartData.length > 0 && (
        <Card>
          <CardContent>
            <LineChart
              height={400}
              xAxis={[{ data: chartData.map((d) => d.hour), scaleType: 'band' as const }]}
              series={[
                { data: chartData.map((d) => d.up), label: '上行 (GB)', color: '#90caf9' },
                { data: chartData.map((d) => d.down), label: '下行 (GB)', color: '#f48fb1' },
              ]}
            />
          </CardContent>
        </Card>
      )}
    </Box>
  )
}
