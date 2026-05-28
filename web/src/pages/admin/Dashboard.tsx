import { useState, useEffect } from 'react'
import { admin } from '../../api'

interface DashboardData {
  total_users: number
  active_accounts: number
  today_income_cents: number
}

export default function AdminDashboard() {
  const [data, setData] = useState<DashboardData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    admin.dashboard()
      .then((res) => setData(res.data))
      .catch((err) => setError(err.response?.data?.error || '加载失败'))
      .finally(() => setLoading(false))
  }, [])

  if (loading) {
    return <div className="text-center text-gray-500 py-12">加载中...</div>
  }

  if (error) {
    return <div className="text-center text-red-500 py-12">{error}</div>
  }

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 mb-8">仪表盘</h1>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-white rounded-2xl shadow-md p-6 border border-gray-100">
          <p className="text-gray-500 text-sm mb-2">总用户</p>
          <p className="text-4xl font-bold text-gray-900">{data?.total_users ?? 0}</p>
        </div>

        <div className="bg-white rounded-2xl shadow-md p-6 border border-gray-100">
          <p className="text-gray-500 text-sm mb-2">活跃账号</p>
          <p className="text-4xl font-bold text-gray-900">{data?.active_accounts ?? 0}</p>
        </div>

        <div className="bg-white rounded-2xl shadow-md p-6 border border-gray-100">
          <p className="text-gray-500 text-sm mb-2">今日收入</p>
          <p className="text-4xl font-bold text-green-600">
            ¥{((data?.today_income_cents ?? 0) / 100).toFixed(2)}
          </p>
        </div>
      </div>
    </div>
  )
}
