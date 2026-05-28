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
      window.location.href = '/login'
    }
    return Promise.reject(err)
  }
)

export interface User { id: string; email: string; status: string; created_at: string }
export interface Plan { id: string; name: string; price_cents: number; duration_days: number; traffic_limit_gb: number; max_devices: number; is_active: boolean }

export const auth = {
  register: (email: string, password: string) => api.post('/auth/register', { email, password }),
  login: (email: string, password: string) => api.post('/auth/login', { email, password }),
  adminLogin: (username: string, password: string) => api.post('/auth/admin-login', { username, password }),
}

export const plans = { list: () => api.get<Plan[]>('/plans') }

export const orders = {
  create: (planID: string, protocol?: string) =>
    api.post('/orders', { plan_id: planID, protocol }),
  list: () => api.get('/orders'),
  status: (id: string) => api.get<{ status: string }>(`/orders/${id}/status`),
}

export const admin = {
  dashboard: () => api.get('/admin/dashboard'),
  listUsers: (params?: any) => api.get('/admin/users', { params }),
  getUser: (id: string) => api.get(`/admin/users/${id}`),
  disableUser: (id: string) => api.post(`/admin/users/${id}/disable`),
  enableUser: (id: string) => api.post(`/admin/users/${id}/enable`),
  listPlans: () => api.get<Plan[]>('/admin/plans'),
  createPlan: (data: Partial<Plan>) => api.post('/admin/plans', data),
  updatePlan: (id: string, data: Partial<Plan>) => api.put(`/admin/plans/${id}`, data),
  deletePlan: (id: string) => api.delete(`/admin/plans/${id}`),
  listOrders: (params?: any) => api.get('/admin/orders', { params }),
  cancelOrder: (id: string) => api.post(`/admin/orders/${id}/cancel`),
  getTrafficSummary: () => api.get('/admin/traffic/summary'),
  getTrafficAccounts: (days: number) => api.get('/admin/traffic/accounts', { params: { days } }),
  getTrafficTimeline: () => api.get('/admin/traffic/timeline'),
  getAuditLogs: (page: number) => api.get('/admin/audit-logs', { params: { page } }),
}

export default api
