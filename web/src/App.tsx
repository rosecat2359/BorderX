import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { ThemeProvider, CssBaseline, Box, Typography } from '@mui/material'
import { darkTheme } from './theme'

export default function App() {
  return (
    <ThemeProvider theme={darkTheme}>
      <CssBaseline />
      <BrowserRouter>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '100vh' }}>
          <Routes>
            <Route path="/" element={<Typography variant="h4">BorderX v2</Typography>} />
          </Routes>
        </Box>
      </BrowserRouter>
    </ThemeProvider>
  )
}
