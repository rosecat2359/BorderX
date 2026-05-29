import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { Box, Drawer, List, ListItemButton, ListItemIcon, ListItemText, Typography, IconButton } from '@mui/material'
import {
  Dashboard as DashboardIcon,
  Dns as DnsIcon,
  People as PeopleIcon,
  BarChart as BarChartIcon,
  Settings as SettingsIcon,
  Logout as LogoutIcon,
} from '@mui/icons-material'
import { useAuth } from '../store/auth'

const DRAWER_WIDTH = 240

const navItems = [
  { path: '/', label: '仪表盘', icon: <DashboardIcon /> },
  { path: '/nodes', label: '节点', icon: <DnsIcon /> },
  { path: '/clients', label: '客户端', icon: <PeopleIcon /> },
  { path: '/traffic', label: '流量', icon: <BarChartIcon /> },
  { path: '/settings', label: '设置', icon: <SettingsIcon /> },
]

export default function Layout() {
  const navigate = useNavigate()
  const location = useLocation()
  const { logout } = useAuth()

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh' }}>
      <Drawer variant="permanent" sx={{
        width: DRAWER_WIDTH,
        '& .MuiDrawer-paper': {
          width: DRAWER_WIDTH,
          bgcolor: 'background.paper',
          borderRight: '1px solid',
          borderColor: 'divider',
        },
      }}>
        <Box sx={{ p: 2 }}>
          <Typography variant="h6" sx={{ fontWeight: 700 }}>BorderX</Typography>
        </Box>
        <List>
          {navItems.map((item) => (
            <ListItemButton key={item.path} selected={location.pathname === item.path}
              onClick={() => navigate(item.path)} sx={{ mx: 1, borderRadius: 2 }}>
              <ListItemIcon>{item.icon}</ListItemIcon>
              <ListItemText primary={item.label} />
            </ListItemButton>
          ))}
        </List>
        <Box sx={{ mt: 'auto', p: 2 }}>
          <IconButton onClick={() => { logout(); navigate('/login') }}><LogoutIcon /></IconButton>
        </Box>
      </Drawer>
      <Box component="main" sx={{ flex: 1, p: 3, bgcolor: 'background.default', overflow: 'auto' }}>
        <Outlet />
      </Box>
    </Box>
  )
}
