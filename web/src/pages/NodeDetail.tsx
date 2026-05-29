import { Box, Typography } from '@mui/material'
import { useParams } from 'react-router-dom'

export default function NodeDetail() {
  const { id } = useParams<{ id: string }>()
  return <Box><Typography variant="h4" sx={{ fontWeight: 600, mb: 3 }}>节点详情 {id}</Typography></Box>
}
