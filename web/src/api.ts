import axios from 'axios'

const api = axios.create({ baseURL: '/api' })
api.interceptors.request.use((cfg) => {
  const token = localStorage.getItem('token')
  if (token) cfg.headers.Authorization = `Bearer ${token}`
  return cfg
})
api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('token')
      if (window.location.pathname !== '/login') window.location.href = '/login'
    }
    return Promise.reject(err)
  },
)

export const auth = {
  setupCheck: () => api.get('/auth/setup'),
  setup: (password: string) => api.post('/auth/setup', { password }),
  login: (password: string) => api.post('/auth/login', { password }),
}

export interface Node {
  id: string; name: string; host: string; ssh_port: number; os: string
  region: string; is_active: boolean; status?: string
  inbound_count?: number; client_count?: number; last_seen_at?: string
}
export interface Inbound {
  id: string; node_id: string; tag: string; protocol: string; port: number
  listen: string; sniffing: boolean; is_active: boolean
  node_name?: string; client_count?: number
}
export interface Client {
  id: string; name: string; uuid: string; flow: string
  total_limit: number; total_used?: number
  expiry_at?: string; is_active: boolean
  inbounds?: ClientInbound[]
}
export interface ClientInbound {
  client_id: string; inbound_id: string; is_visible: boolean
  node_name?: string; protocol?: string; port?: number; host?: string
}

export const nodes = {
  list: () => api.get<Node[]>('/nodes'),
  get: (id: string) => api.get<Node>(`/nodes/${id}`),
  create: (data: any) => api.post('/nodes', data),
  update: (id: string, data: any) => api.put(`/nodes/${id}`, data),
  delete: (id: string) => api.delete(`/nodes/${id}`),
  test: (id: string) => api.post(`/nodes/${id}/test`),
  status: (id: string) => api.get(`/nodes/${id}/status`),
}

export const inbounds = {
  list: (nodeId?: string) => api.get<Inbound[]>('/inbounds', { params: nodeId ? { node_id: nodeId } : {} }),
  create: (data: any) => api.post('/inbounds', data),
  update: (id: string, data: any) => api.put(`/inbounds/${id}`, data),
  delete: (id: string) => api.delete(`/inbounds/${id}`),
  deploy: (id: string) => api.post(`/inbounds/${id}/deploy`),
}

export const clients = {
  list: () => api.get<Client[]>('/clients'),
  create: (data: any) => api.post('/clients', data),
  update: (id: string, data: any) => api.put(`/clients/${id}`, data),
  delete: (id: string) => api.delete(`/clients/${id}`),
  reset: (id: string) => api.post(`/clients/${id}/reset`),
  updateInbounds: (id: string, data: any) => api.put(`/clients/${id}/inbounds`, data),
}

export const traffic = {
  overview: () => api.get('/traffic/overview'),
  clients: (id: string) => api.get(`/traffic/clients/${id}`),
  nodes: (id: string) => api.get(`/traffic/nodes/${id}`),
}

export const system = {
  info: () => api.get('/system/info'),
  password: (password: string) => api.put('/system/password', { password }),
  backup: () => api.post('/system/backup', {}, { responseType: 'blob' }),
}

export default api
