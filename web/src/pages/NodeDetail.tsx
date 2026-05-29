import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Box, Typography, Card, CardContent, Grid, Chip } from '@mui/material'
import { nodes, inbounds } from '../api'
import type { Node, Inbound } from '../api'

export default function NodeDetail() {
  const { id } = useParams<{ id: string }>()
  const [node, setNode] = useState<Node | null>(null)
  const [ibList, setIbList] = useState<Inbound[]>([])

  useEffect(() => {
    if (!id) return
    nodes.get(id).then(({ data }) => setNode(data)).catch(() => {})
    inbounds.list(id).then(({ data }) => setIbList(Array.isArray(data) ? data : [])).catch(() => {})
  }, [id])

  if (!node) return null

  return (
    <Box>
      <Typography variant="h4" sx={{ fontWeight: 600, mb: 1 }}>{node.name}</Typography>
      <Typography color="text.secondary" sx={{ mb: 3 }}>{node.host} · {node.os} · {node.region}</Typography>

      <Typography variant="h6" sx={{ mb: 2 }}>入站规则</Typography>
      <Grid container spacing={2}>
        {ibList.map((ib) => (
          <Grid size={{ xs: 12, sm: 6 }} key={ib.id}>
            <Card>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                  <Chip label={ib.protocol.toUpperCase()} color="primary" size="small" />
                  <Typography sx={{ fontWeight: 600 }}>:{ib.port}</Typography>
                  <Chip label={ib.is_active ? '启用' : '停用'} size="small" color={ib.is_active ? 'success' : 'default'} />
                </Box>
                <Typography variant="body2" color="text.secondary">{ib.tag}</Typography>
                <Typography variant="body2">{(ib as any).client_count ?? 0} 个客户端</Typography>
              </CardContent>
            </Card>
          </Grid>
        ))}
        {ibList.length === 0 && <Grid size={{ xs: 12 }}><Typography color="text.secondary">暂无入站规则</Typography></Grid>}
      </Grid>
    </Box>
  )
}
