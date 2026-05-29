import { create } from 'zustand'

interface AuthState {
  token: string | null
  needSetup: boolean
  setToken: (t: string) => void
  logout: () => void
}

export const useAuth = create<AuthState>((set) => ({
  token: localStorage.getItem('token'),
  needSetup: false,
  setToken: (t) => { localStorage.setItem('token', t); set({ token: t }) },
  logout: () => { localStorage.removeItem('token'); set({ token: null }) },
}))
